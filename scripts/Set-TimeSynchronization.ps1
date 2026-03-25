<#
.SYNOPSIS
    Configures time synchronization on a Domain Controller after a restore.

.DESCRIPTION
    After restoring from backup, the DC's clock may be at the backup timestamp. Kerberos
    authentication fails if the clock difference exceeds 5 minutes. This script:
      1. Sets MaxNegPhaseCorrection and MaxPosPhaseCorrection (default: 172800 = 48 hours)
      2. Configures the time source type (NTP for forest root PDC, NT5DS for all others)
      3. Optionally sets an external NTP server
      4. Restarts the W32Time service and forces a resync

    Corresponds to:
      - Domain Recovery  Step 10
      - Forest Recovery  Step 2.10 / Step 3.12

.PARAMETER IsForestRootPDC
    Set this switch if this DC is the PDC Emulator of the forest root domain.
    Configures NTP as the time source type.

.PARAMETER NTPServer
    External NTP server to configure (only used with -IsForestRootPDC).
    Default: time.windows.com.

.PARAMETER MaxCorrectionSeconds
    Maximum phase correction in seconds. Default: 172800 (48 hours).

.EXAMPLE
    # Child DC or non-PDC — uses NT5DS (domain hierarchy)
    .\Set-TimeSynchronization.ps1

.EXAMPLE
    # Forest root PDC Emulator — uses external NTP
    .\Set-TimeSynchronization.ps1 -IsForestRootPDC -NTPServer "time.windows.com"

.NOTES
    Author : Jan Tiedemann
    Version: 1.0.0
    Requires: Administrative privileges
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [switch]$IsForestRootPDC,

    [Parameter()]
    [string]$NTPServer = 'time.windows.com',

    [Parameter()]
    [ValidateRange(3600, 604800)]
    [int]$MaxCorrectionSeconds = 172800
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$timeSourceType = if ($IsForestRootPDC) { 'NTP' } else { 'NT5DS' }

Write-Host "`n=== Time Synchronization Configuration ===" -ForegroundColor Cyan
Write-Host "Computer     : $env:COMPUTERNAME"
Write-Host "Source Type  : $timeSourceType"
if ($IsForestRootPDC) { Write-Host "NTP Server   : $NTPServer" }
Write-Host "Max Correction: $MaxCorrectionSeconds seconds ($([math]::Round($MaxCorrectionSeconds / 3600, 1)) hours)`n"

$w32timeConfigPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config'
$w32timeParamsPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'

if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Configure time synchronization ($timeSourceType)")) {
    # Set phase correction limits
    Write-Host "Setting MaxNegPhaseCorrection = $MaxCorrectionSeconds..." -ForegroundColor Green
    Set-ItemProperty -Path $w32timeConfigPath -Name 'MaxNegPhaseCorrection' -Value $MaxCorrectionSeconds -Type DWord
    Write-Host "Setting MaxPosPhaseCorrection = $MaxCorrectionSeconds..." -ForegroundColor Green
    Set-ItemProperty -Path $w32timeConfigPath -Name 'MaxPosPhaseCorrection' -Value $MaxCorrectionSeconds -Type DWord

    # Set time source type
    Write-Host "Setting time source type = $timeSourceType..." -ForegroundColor Green
    Set-ItemProperty -Path $w32timeParamsPath -Name 'Type' -Value $timeSourceType -Type String

    # Configure NTP server for forest root PDC
    if ($IsForestRootPDC) {
        Write-Host "Setting NTP server = $NTPServer..." -ForegroundColor Green
        Set-ItemProperty -Path $w32timeParamsPath -Name 'NtpServer' -Value "$NTPServer,0x9" -Type String
    }

    # Restart W32Time service and resync
    Write-Host "`nRestarting Windows Time service..." -ForegroundColor Green
    Stop-Service -Name 'W32Time' -Force -ErrorAction SilentlyContinue
    Start-Service -Name 'W32Time'
    Write-Host "Forcing time resync..." -ForegroundColor Green
    & w32tm /resync 2>&1 | Out-Null

    Write-Host "`n[OK] Time synchronization configured." -ForegroundColor Green
    Write-Host "     Current system time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
}
