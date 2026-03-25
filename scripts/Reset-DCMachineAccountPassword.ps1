<#
.SYNOPSIS
    Resets the Domain Controller machine account password twice.

.DESCRIPTION
    After restoring a DC from backup, the machine account password stored locally may not
    match what AD expects. AD keeps the current and previous password — resetting twice
    ensures both slots are updated, preventing secure channel (Kerberos) failures.

    Corresponds to:
      - Domain Recovery  Step 7
      - Forest Recovery  Step 2.7 / Step 3.9

.PARAMETER DelaySeconds
    Seconds to wait between the two resets. Default: 5.

.EXAMPLE
    .\Reset-DCMachineAccountPassword.ps1

.NOTES
    Author : Jan Tiedemann
    Version: 1.0.0
    Requires: Run locally on the restored DC, Domain Admin privileges
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateRange(3, 60)]
    [int]$DelaySeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n=== DC Machine Account Password Reset ===" -ForegroundColor Cyan
Write-Host "Computer : $env:COMPUTERNAME"
Write-Host "Delay    : $DelaySeconds seconds between resets`n"

if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Reset machine account password twice")) {
    Write-Host "[1/2] Resetting machine account password (first time)..." -ForegroundColor Green
    Reset-ComputerMachinePassword
    Write-Host "      First reset completed." -ForegroundColor Green

    Write-Host "      Waiting $DelaySeconds seconds..."
    Start-Sleep -Seconds $DelaySeconds

    Write-Host "[2/2] Resetting machine account password (second time)..." -ForegroundColor Green
    Reset-ComputerMachinePassword
    Write-Host "      Second reset completed." -ForegroundColor Green

    Write-Host "`n[OK] Machine account password has been reset twice." -ForegroundColor Green
    Write-Host "     The secure channel is now re-established.`n"
}
