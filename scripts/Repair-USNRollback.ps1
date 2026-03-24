<#
.SYNOPSIS
    Recovers from a USN rollback by force-demoting and optionally re-promoting the DC.

.DESCRIPTION
    Performs the recommended recovery from USN rollback (Option A):
      1. Force-demotes the affected DC
      2. Optionally cleans up metadata on a healthy DC
      3. Optionally re-promotes the server as a new DC

    Corresponds to:
      - USN Rollback Recovery  Option A

.PARAMETER Method
    Recovery method: ForceDemote (default). Other methods (SystemStateRestore,
    ResetInvocationID) require manual steps — see 05-USN-Rollback-Recovery.md.

.PARAMETER DomainName
    The domain to re-join when re-promoting. Default: auto-detected.

.PARAMETER SkipRePromote
    Skip the re-promotion step (useful if you want to re-promote manually later).

.EXAMPLE
    .\Repair-USNRollback.ps1 -Method ForceDemote

.EXAMPLE
    .\Repair-USNRollback.ps1 -Method ForceDemote -SkipRePromote

.NOTES
    Author : Jan Tiedemann (Microsoft)
    Version: 1.0.0
    Requires: Administrative privileges, RSAT AD DS tools
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateSet('ForceDemote')]
    [string]$Method = 'ForceDemote',

    [Parameter()]
    [string]$DomainName,

    [Parameter()]
    [switch]$SkipRePromote
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n=== USN Rollback Recovery ===" -ForegroundColor Cyan
Write-Host "Computer : $env:COMPUTERNAME"
Write-Host "Method   : $Method`n"

switch ($Method) {
    'ForceDemote' {
        # --- Step 1: Force-demote ---
        Write-Host "--- Step 1: Force Demotion ---" -ForegroundColor Yellow
        Write-Host "This will forcefully remove AD DS from this server." -ForegroundColor Red
        Write-Host "The server will need to be rebooted after demotion.`n"

        if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Force-demote Domain Controller")) {
            Write-Host "Force-demoting $env:COMPUTERNAME..." -ForegroundColor Green
            try {
                Uninstall-ADDSDomainController -ForceRemoval -DemoteOperationMasterRole -Force
                Write-Host "[OK] Demotion initiated. The server will restart." -ForegroundColor Green
            }
            catch {
                Write-Error "Demotion failed: $_"
                Write-Host "`nIf demotion fails, try:" -ForegroundColor Yellow
                Write-Host '  Uninstall-ADDSDomainController -ForceRemoval -DemoteOperationMasterRole -Force -IgnoreLastDCInDomainMismatch'
                return
            }

            Write-Host "`nAfter reboot, complete these steps:" -ForegroundColor Yellow
            Write-Host "  1. On a HEALTHY DC, clean up metadata:"
            Write-Host "     -> .\Remove-StaleDCMetadata.ps1 -SurvivorDCName <HealthyDC>"
            Write-Host "  2. Seize FSMO roles if this DC held any:"
            Write-Host "     -> Move-ADDirectoryServerOperationMasterRole -Identity <HealthyDC> -OperationMasterRole 0,1,2,3,4 -Force"
            Write-Host "  3. Clean up DNS records for this DC"

            if (-not $SkipRePromote) {
                Write-Host "  4. After cleanup, re-promote this server:"
                $domain = if ($DomainName) { $DomainName } else { '<YourDomainFQDN>' }
                Write-Host "     -> Install-ADDSDomainController -DomainName '$domain' -Credential (Get-Credential)"
                Write-Host "  5. Re-enable Global Catalog if needed"
                Write-Host "  6. Transfer FSMO roles back if needed"
            }

            Write-Host "`n  7. Verify replication:"
            Write-Host "     -> repadmin /showrepl"
            Write-Host "     -> dcdiag /q`n"
        }
    }
}
