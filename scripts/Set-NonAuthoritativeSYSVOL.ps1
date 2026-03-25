<#
.SYNOPSIS
    Marks all Domain Controllers (except the authoritative one) as non-authoritative for SYSVOL DFS-R.

.DESCRIPTION
    Sets msDFSR-Enabled=FALSE on every DC's SYSVOL Subscription object except the specified
    authoritative DC. This is required before performing an authoritative SYSVOL sync.

    After DFS-R is restarted on the authoritative DC, run this script's companion
    (Set-AuthoritativeSYSVOLRestore.ps1) first, then set msDFSR-Enabled back to TRUE
    on non-authoritative DCs and restart their DFS-R service.

    Corresponds to:
      - SYSVOL Recovery  Steps 3, 5, 7, 9

.PARAMETER AuthoritativeDCName
    Name of the DC that is the authoritative SYSVOL source (will be excluded).

.PARAMETER DomainDN
    Distinguished name of the domain. Auto-detected if omitted.

.PARAMETER ReEnable
    Switch to re-enable DFS-R on non-authoritative DCs (Step 7/9 of SYSVOL Recovery).

.EXAMPLE
    # Disable DFS-R on all non-authoritative DCs
    .\Set-NonAuthoritativeSYSVOL.ps1 -AuthoritativeDCName "DC01"

.EXAMPLE
    # Re-enable DFS-R on all non-authoritative DCs after authoritative sync
    .\Set-NonAuthoritativeSYSVOL.ps1 -AuthoritativeDCName "DC01" -ReEnable

.NOTES
    Author : Jan Tiedemann
    Version: 1.0.0
    Requires: ActiveDirectory module, Domain Admin privileges
#>

#Requires -Modules ActiveDirectory

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$AuthoritativeDCName,

    [Parameter()]
    [string]$DomainDN = (Get-ADDomain).DistinguishedName,

    [Parameter()]
    [switch]$ReEnable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$action = if ($ReEnable) { "Re-enabling" } else { "Disabling" }
Write-Host "`n=== $action DFS-R on Non-Authoritative DCs ===" -ForegroundColor Cyan
Write-Host "Authoritative DC : $AuthoritativeDCName"
Write-Host "Domain            : $DomainDN`n"

# Get all DCs in the domain except the authoritative one
$allDCs = @(Get-ADDomainController -Filter * | Where-Object { $_.Name -ne $AuthoritativeDCName })

if ($allDCs.Count -eq 0) {
    Write-Host "No other Domain Controllers found. Nothing to do." -ForegroundColor Yellow
    return
}

Write-Host "Target DCs:" -ForegroundColor Yellow
$allDCs | ForEach-Object { Write-Host "  - $($_.Name)" }
Write-Host ""

foreach ($dc in $allDCs) {
    $sysvolDN = "CN=SYSVOL Subscription,CN=Domain System Volume,CN=DFSR-LocalSettings,CN=$($dc.Name),OU=Domain Controllers,$DomainDN"

    try {
        $obj = Get-ADObject -Identity $sysvolDN -Properties 'msDFSR-Enabled'
    }
    catch {
        Write-Warning "Cannot find SYSVOL Subscription for $($dc.Name) — skipping. Error: $_"
        continue
    }

    $targetValue = if ($ReEnable) { $true } else { $false }

    if ($PSCmdlet.ShouldProcess($dc.Name, "Set msDFSR-Enabled=$targetValue")) {
        Set-ADObject -Identity $sysvolDN -Replace @{ 'msDFSR-Enabled' = $targetValue }
        Write-Host "[OK] $($dc.Name): msDFSR-Enabled = $targetValue" -ForegroundColor Green

        if (-not $ReEnable) {
            # Stop DFS-R on non-authoritative DCs
            Write-Host "     Stopping DFSR service on $($dc.Name)..."
            try {
                Invoke-Command -ComputerName $dc.HostName -ScriptBlock { Stop-Service -Name 'DFSR' -Force } -ErrorAction Stop
                Write-Host "     DFSR service stopped." -ForegroundColor Green
            }
            catch {
                Write-Warning "     Could not stop DFSR on $($dc.Name): $_"
            }
        }
        else {
            # Restart DFS-R on non-authoritative DCs
            Write-Host "     Starting DFSR service on $($dc.Name)..."
            try {
                Invoke-Command -ComputerName $dc.HostName -ScriptBlock {
                    Start-Service -Name 'DFSR'
                    & DFSRDIAG POLLAD 2>$null
                } -ErrorAction Stop
                Write-Host "     DFSR service started." -ForegroundColor Green
            }
            catch {
                Write-Warning "     Could not start DFSR on $($dc.Name): $_"
            }
        }
    }
}

Write-Host ""
if ($ReEnable) {
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Force AD replication: repadmin /syncall /d /e /P $AuthoritativeDCName $DomainDN"
    Write-Host "  2. On each DC, check DFS Replication log for Event IDs 4614 and 4604"
    Write-Host "  3. Verify SYSVOL/NETLOGON shares on each DC: net share`n"
}
else {
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Restart DFS-R on the authoritative DC ($AuthoritativeDCName)"
    Write-Host "  2. Force AD replication: repadmin /syncall /d /e /P $AuthoritativeDCName $DomainDN"
    Write-Host "  3. Re-enable DFS-R: .\Set-NonAuthoritativeSYSVOL.ps1 -AuthoritativeDCName $AuthoritativeDCName -ReEnable`n"
}
