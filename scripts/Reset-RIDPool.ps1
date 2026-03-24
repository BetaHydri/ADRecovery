<#
.SYNOPSIS
    Resets the RID pool after a Domain Controller restore to prevent duplicate SID creation.

.DESCRIPTION
    After restoring a DC from backup, the RID pool may overlap with RIDs already issued.
    This script:
      1. Reads the current rIDAvailablePool value
      2. Calculates a new value with the upper 32 bits raised by a configurable increment
      3. Updates the rIDAvailablePool attribute
      4. Invalidates the local DC's RID cache

    Corresponds to:
      - Domain Recovery  Step 6
      - Forest Recovery  Step 2.6 / Step 3.8

.PARAMETER Increment
    How much to increase the upper 32-bit ceiling. Microsoft recommends at least 100,000.
    Default: 100000.

.PARAMETER DomainDN
    Distinguished name of the domain. Auto-detected if omitted.

.EXAMPLE
    .\Reset-RIDPool.ps1

.EXAMPLE
    .\Reset-RIDPool.ps1 -Increment 200000

.NOTES
    Author : Jan Tiedemann (Microsoft)
    Version: 1.0.0
    Requires: ActiveDirectory module, Domain Admin privileges
#>

#Requires -Modules ActiveDirectory

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateRange(10000, 1000000)]
    [int]$Increment = 100000,

    [Parameter()]
    [string]$DomainDN = (Get-ADDomain).DistinguishedName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n=== RID Pool Reset ===" -ForegroundColor Cyan
Write-Host "Domain    : $DomainDN"
Write-Host "Increment : $Increment`n"

# Locate the RID Manager object
$ridManagerDN = "CN=RID Manager`$,CN=System,$DomainDN"
Write-Host "RID Manager: $ridManagerDN`n"

try {
    $ridManager = Get-ADObject -Identity $ridManagerDN -Properties rIDAvailablePool
}
catch {
    Write-Error "Cannot find RID Manager at: $ridManagerDN. Verify the domain DN."
    return
}

$currentPool = [Int64]$ridManager.rIDAvailablePool
$currentUpper = [math]::Floor($currentPool / [math]::Pow(2, 32))
$currentLower = $currentPool % [math]::Pow(2, 32)

Write-Host "Current rIDAvailablePool : $currentPool" -ForegroundColor Yellow
Write-Host "  Upper 32 bits (ceiling): $currentUpper"
Write-Host "  Lower 32 bits (next RID): $currentLower`n"

$incrementValue = [Int64]$Increment * [Int64][math]::Pow(2, 32)
$newPool = $currentPool + $incrementValue
$newUpper = [math]::Floor($newPool / [math]::Pow(2, 32))

Write-Host "New rIDAvailablePool    : $newPool" -ForegroundColor Green
Write-Host "  New upper 32 bits     : $newUpper"
Write-Host "  Increase              : +$Increment`n"

if ($PSCmdlet.ShouldProcess($ridManagerDN, "Update rIDAvailablePool from $currentPool to $newPool")) {
    # Update the RID pool ceiling
    Set-ADObject -Identity $ridManagerDN -Replace @{ rIDAvailablePool = $newPool }
    Write-Host "[OK] rIDAvailablePool updated." -ForegroundColor Green

    # Invalidate the local DC's RID cache
    Write-Host "Invalidating local RID pool cache..."
    try {
        $domain = New-Object System.DirectoryServices.DirectoryEntry
        $domainSid = $domain.objectSid
        $rootDSE = New-Object System.DirectoryServices.DirectoryEntry("LDAP://RootDSE")
        $rootDSE.UsePropertyCache = $false
        $rootDSE.Put("invalidateRidPool", $domainSid.Value)
        $rootDSE.SetInfo()
        Write-Host "[OK] Local RID pool cache invalidated." -ForegroundColor Green
    }
    catch {
        Write-Warning "Could not invalidate local RID pool: $_"
        Write-Host "You can manually invalidate via ADSI as described in the documentation."
    }

    Write-Host "`nVerification:" -ForegroundColor Yellow
    Write-Host "  1. Open Active Directory Users and Computers"
    Write-Host "  2. Create a test user — an initial error is EXPECTED (new pool allocation)"
    Write-Host "  3. Try creating the user again — it should succeed"
    Write-Host "  4. Delete the test user afterwards`n"
}
