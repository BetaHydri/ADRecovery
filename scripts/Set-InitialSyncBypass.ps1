<#
.SYNOPSIS
    Configures or resets the "Repl Perform Initial Synchronizations" registry value.

.DESCRIPTION
    During recovery, the restored DC should not wait for initial replication before
    advertising as a DC (since no replication partners may be available). This script
    sets the registry value to 0 (bypass) or 1 (normal).

    After the forest is fully recovered and replication is healthy, run this script
    with -Enable to restore normal behavior.

    Corresponds to:
      - Domain Recovery  Step 4.7
      - Forest Recovery  Step 2.4.6 / Step 3.4.6

.PARAMETER Enable
    Set to restore normal initial sync behavior (value = 1).
    Without this switch, the bypass is set (value = 0).

.EXAMPLE
    # During recovery — bypass initial sync wait
    .\Set-InitialSyncBypass.ps1

.EXAMPLE
    # After recovery — restore normal behavior
    .\Set-InitialSyncBypass.ps1 -Enable

.NOTES
    Author : Jan Tiedemann
    Version: 1.0.0
    Requires: Administrative privileges
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [switch]$Enable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters'
$regName = 'Repl Perform Initial Synchronizations'
$targetValue = if ($Enable) { 1 } else { 0 }
$description = if ($Enable) { "Restoring normal initial sync (value=1)" } else { "Bypassing initial sync wait (value=0)" }

Write-Host "`n=== Initial Synchronization Configuration ===" -ForegroundColor Cyan
Write-Host "Computer : $env:COMPUTERNAME"
Write-Host "Action   : $description`n"

# Show current value
try {
    $current = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
    if ($current) {
        Write-Host "Current value: $($current.$regName)" -ForegroundColor Yellow
    }
    else {
        Write-Host "Current value: (not set — default behavior)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "Current value: (not set)" -ForegroundColor Yellow
}

if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, $description)) {
    if ($Enable) {
        # Restore normal behavior — set to 1 or remove the key
        try {
            Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
            Write-Host "[OK] Registry value removed (default behavior restored)." -ForegroundColor Green
        }
        catch {
            Set-ItemProperty -Path $regPath -Name $regName -Value 1 -Type DWord
            Write-Host "[OK] Value set to 1 (normal initial sync)." -ForegroundColor Green
        }
    }
    else {
        Set-ItemProperty -Path $regPath -Name $regName -Value 0 -Type DWord
        Write-Host "[OK] Value set to 0 (initial sync bypassed)." -ForegroundColor Green
        Write-Host ""
        Write-Host "IMPORTANT: After forest recovery is complete and replication is healthy," -ForegroundColor Red
        Write-Host "run this script with -Enable to restore normal behavior:" -ForegroundColor Red
        Write-Host "  .\Set-InitialSyncBypass.ps1 -Enable" -ForegroundColor Red
    }
    Write-Host ""
}
