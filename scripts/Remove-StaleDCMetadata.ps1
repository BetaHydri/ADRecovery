<#
.SYNOPSIS
    Removes stale Domain Controller metadata from Active Directory, DNS, and Sites & Services.

.DESCRIPTION
    After restoring a DC from backup, all non-restored DCs must be cleaned up. This script:
      1. Queries current FSMO role holders
      2. Lists all DCs and lets you choose which to remove
      3. Removes computer accounts from AD (with metadata cleanup)
      4. Removes server entries from AD Sites and Services
      5. Deregisters DNS SRV records via nltest
      6. Seizes FSMO roles if needed

    Corresponds to:
      - Domain Recovery  Step 5
      - Forest Recovery  Step 2.5 / Step 3.5

.PARAMETER SurvivorDCName
    The name of the restored (surviving) Domain Controller that should keep all roles.

.PARAMETER DomainFQDN
    The FQDN of the domain. Auto-detected if omitted.

.EXAMPLE
    .\Remove-StaleDCMetadata.ps1 -SurvivorDCName "DC01"

.NOTES
    Author : Jan Tiedemann (Microsoft)
    Version: 1.0.0
    Requires: ActiveDirectory module, Domain Admin privileges
#>

#Requires -Modules ActiveDirectory

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$SurvivorDCName,

    [Parameter()]
    [string]$DomainFQDN = (Get-ADDomain).DNSRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n=== Remove Stale DC Metadata ===" -ForegroundColor Cyan
Write-Host "Survivor DC : $SurvivorDCName"
Write-Host "Domain      : $DomainFQDN`n"

# --- 1. Show current FSMO role holders ---
Write-Host "--- Current FSMO Role Holders ---" -ForegroundColor Yellow
try {
    $domainRoles = Get-ADDomain -Server $SurvivorDCName
    $forestRoles = Get-ADForest -Server $SurvivorDCName
    Write-Host "  PDC Emulator          : $($domainRoles.PDCEmulator)"
    Write-Host "  RID Master            : $($domainRoles.RIDMaster)"
    Write-Host "  Infrastructure Master : $($domainRoles.InfrastructureMaster)"
    Write-Host "  Schema Master         : $($forestRoles.SchemaMaster)"
    Write-Host "  Domain Naming Master  : $($forestRoles.DomainNamingMaster)"
}
catch {
    Write-Warning "Could not query FSMO roles: $_"
}
Write-Host ""

# --- 2. Get all DCs, identify stale ones ---
$allDCs = Get-ADDomainController -Filter * -Server $SurvivorDCName
$staleDCs = $allDCs | Where-Object { $_.Name -ne $SurvivorDCName }

if ($staleDCs.Count -eq 0) {
    Write-Host "No other Domain Controllers found. Nothing to remove." -ForegroundColor Green
    return
}

Write-Host "--- DCs to Remove ---" -ForegroundColor Yellow
$staleDCs | ForEach-Object {
    Write-Host "  $($_.Name)  ($($_.IPv4Address))  Site: $($_.Site)  GC: $($_.IsGlobalCatalog)"
}
Write-Host ""

# --- 3. Remove each stale DC ---
foreach ($dc in $staleDCs) {
    Write-Host "Processing: $($dc.Name)" -ForegroundColor Cyan

    if ($PSCmdlet.ShouldProcess($dc.Name, "Remove DC metadata from AD")) {
        # 3a. Remove the computer account from AD (triggers metadata cleanup)
        try {
            $dcComputerDN = (Get-ADComputer -Identity $dc.Name -Server $SurvivorDCName).DistinguishedName
            Remove-ADObject -Identity $dcComputerDN -Server $SurvivorDCName -Recursive -Confirm:$false
            Write-Host "  [OK] Computer account removed: $dcComputerDN" -ForegroundColor Green
        }
        catch {
            Write-Warning "  Could not remove computer account for $($dc.Name): $_"
        }

        # 3b. Remove server entry from Sites and Services
        try {
            $serverDN = "CN=$($dc.Name),CN=Servers,CN=$($dc.Site),CN=Sites,CN=Configuration,$((Get-ADDomain -Server $SurvivorDCName).DistinguishedName -replace '^.*?,(?=DC=)', '')"
            # Use the forest config DN
            $configDN = (Get-ADRootDSE -Server $SurvivorDCName).configurationNamingContext
            $serverObj = Get-ADObject -Filter "Name -eq '$($dc.Name)'" -SearchBase "CN=Sites,$configDN" -SearchScope Subtree -Server $SurvivorDCName
            if ($serverObj) {
                Remove-ADObject -Identity $serverObj.DistinguishedName -Server $SurvivorDCName -Recursive -Confirm:$false
                Write-Host "  [OK] Server entry removed from Sites and Services" -ForegroundColor Green
            }
        }
        catch {
            Write-Warning "  Could not remove Sites & Services entry for $($dc.Name): $_"
        }

        # 3c. Deregister DNS SRV records
        try {
            $null = & nltest /dsderegdns:"$($dc.Name).$DomainFQDN" 2>&1
            Write-Host "  [OK] DNS SRV deregistration initiated for $($dc.Name).$DomainFQDN" -ForegroundColor Green
        }
        catch {
            Write-Warning "  nltest /dsderegdns failed for $($dc.Name): $_"
        }
    }
}

# --- 4. Seize FSMO roles if needed ---
Write-Host "`n--- Verifying FSMO Roles After Cleanup ---" -ForegroundColor Yellow
try {
    $domainRoles = Get-ADDomain -Server $SurvivorDCName
    $forestRoles = Get-ADForest -Server $SurvivorDCName

    $allRolesOnSurvivor = $true
    $rolesToSeize = @()

    if ($domainRoles.PDCEmulator -notmatch "^$SurvivorDCName\.") { $allRolesOnSurvivor = $false; $rolesToSeize += 0 }
    if ($domainRoles.RIDMaster -notmatch "^$SurvivorDCName\.") { $allRolesOnSurvivor = $false; $rolesToSeize += 1 }
    if ($domainRoles.InfrastructureMaster -notmatch "^$SurvivorDCName\.") { $allRolesOnSurvivor = $false; $rolesToSeize += 2 }
    if ($forestRoles.SchemaMaster -notmatch "^$SurvivorDCName\.") { $allRolesOnSurvivor = $false; $rolesToSeize += 3 }
    if ($forestRoles.DomainNamingMaster -notmatch "^$SurvivorDCName\.") { $allRolesOnSurvivor = $false; $rolesToSeize += 4 }

    if ($allRolesOnSurvivor) {
        Write-Host "All FSMO roles are on $SurvivorDCName. No seizure needed." -ForegroundColor Green
    }
    else {
        Write-Host "The following roles need to be seized:" -ForegroundColor Red
        $roleNames = @('PDCEmulator', 'RIDMaster', 'InfrastructureMaster', 'SchemaMaster', 'DomainNamingMaster')
        foreach ($r in $rolesToSeize) { Write-Host "  - $($roleNames[$r]) ($r)" }

        if ($PSCmdlet.ShouldProcess($SurvivorDCName, "Seize FSMO roles: $($rolesToSeize -join ', ')")) {
            Move-ADDirectoryServerOperationMasterRole -Identity $SurvivorDCName -OperationMasterRole $rolesToSeize -Force
            Write-Host "[OK] FSMO roles seized." -ForegroundColor Green
        }
    }
}
catch {
    Write-Warning "Could not verify/seize FSMO roles: $_"
}

Write-Host "`n--- Final FSMO Role Holders ---" -ForegroundColor Yellow
try {
    $domainRoles = Get-ADDomain -Server $SurvivorDCName
    $forestRoles = Get-ADForest -Server $SurvivorDCName
    Write-Host "  PDC Emulator          : $($domainRoles.PDCEmulator)"
    Write-Host "  RID Master            : $($domainRoles.RIDMaster)"
    Write-Host "  Infrastructure Master : $($domainRoles.InfrastructureMaster)"
    Write-Host "  Schema Master         : $($forestRoles.SchemaMaster)"
    Write-Host "  Domain Naming Master  : $($forestRoles.DomainNamingMaster)"
}
catch {
    Write-Warning "Could not re-query FSMO roles: $_"
}

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "  1. In DNS Manager, remove remaining A/AAAA/SRV/PTR records for deleted DCs"
Write-Host "  2. Remove deleted DCs from the Name Servers tab of all DNS zones"
Write-Host "  3. Proceed with RID pool reset (Reset-RIDPool.ps1)`n"
