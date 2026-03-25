<#
.SYNOPSIS
    Detects USN rollback on the local Domain Controller.

.DESCRIPTION
    Checks for symptoms of a USN rollback:
      1. Event ID 2095 in the Directory Services event log
      2. Registry value "Dsa Not Writable" = 0x4
      3. Net Logon service paused state

    Corresponds to:
      - USN Rollback Recovery  Steps 1–3 (Detection)

.EXAMPLE
    .\Detect-USNRollback.ps1

.NOTES
    Author : Jan Tiedemann
    Version: 1.0.0
    Requires: Run on the suspected DC, administrative privileges
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "`n=== USN Rollback Detection ===" -ForegroundColor Cyan
Write-Host "Computer : $env:COMPUTERNAME"
Write-Host "Time     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

$rollbackDetected = $false

# --- 1. Check for Event ID 2095 ---
Write-Host "--- Check 1: Event ID 2095 (Directory Services log) ---" -ForegroundColor Yellow
try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName   = 'Directory Service'
        Id        = 2095
    } -MaxEvents 5 -ErrorAction SilentlyContinue

    if ($events) {
        $rollbackDetected = $true
        Write-Host "  [ALERT] Event ID 2095 FOUND — USN rollback detected!" -ForegroundColor Red
        foreach ($evt in $events) {
            Write-Host "    Time: $($evt.TimeCreated)  Message: $($evt.Message.Substring(0, [math]::Min(200, $evt.Message.Length)))..." -ForegroundColor Red
        }
    }
    else {
        Write-Host "  [OK] No Event ID 2095 found." -ForegroundColor Green
    }
}
catch {
    Write-Host "  [INFO] Could not query Directory Service log: $_" -ForegroundColor Yellow
}
Write-Host ""

# --- 2. Check Registry: Dsa Not Writable ---
Write-Host "--- Check 2: Registry 'Dsa Not Writable' ---" -ForegroundColor Yellow
$ntdsParamsPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters'
try {
    $dsaNotWritable = Get-ItemProperty -Path $ntdsParamsPath -Name 'Dsa Not Writable' -ErrorAction SilentlyContinue
    if ($dsaNotWritable -and $dsaNotWritable.'Dsa Not Writable' -eq 4) {
        $rollbackDetected = $true
        Write-Host "  [ALERT] 'Dsa Not Writable' = 0x4 — USN rollback quarantine is active!" -ForegroundColor Red
        Write-Host "  WARNING: Do NOT manually delete or modify this value." -ForegroundColor Red
    }
    elseif ($dsaNotWritable) {
        Write-Host "  [INFO] 'Dsa Not Writable' = $($dsaNotWritable.'Dsa Not Writable') (not 0x4, so not USN rollback)." -ForegroundColor Yellow
    }
    else {
        Write-Host "  [OK] 'Dsa Not Writable' value not present." -ForegroundColor Green
    }
}
catch {
    Write-Host "  [OK] Registry key not found (normal)." -ForegroundColor Green
}
Write-Host ""

# --- 3. Check Net Logon Service ---
Write-Host "--- Check 3: Net Logon Service Status ---" -ForegroundColor Yellow
try {
    $netlogon = Get-Service -Name 'Netlogon' -ErrorAction Stop
    if ($netlogon.Status -eq 'Paused') {
        $rollbackDetected = $true
        Write-Host "  [ALERT] Net Logon service is PAUSED — USN rollback quarantine confirmed!" -ForegroundColor Red
    }
    elseif ($netlogon.Status -eq 'Running') {
        Write-Host "  [OK] Net Logon service is running." -ForegroundColor Green
    }
    else {
        Write-Host "  [WARN] Net Logon service status: $($netlogon.Status)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  [WARN] Could not query Net Logon service: $_" -ForegroundColor Yellow
}
Write-Host ""

# --- Summary ---
Write-Host "=== Summary ===" -ForegroundColor Cyan
if ($rollbackDetected) {
    Write-Host "[ALERT] USN ROLLBACK DETECTED on $env:COMPUTERNAME!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Recovery options:" -ForegroundColor Yellow
    Write-Host "  Option A (Recommended): Force-demote and re-promote the DC"
    Write-Host "    -> Run: .\Repair-USNRollback.ps1 -Method ForceDemote"
    Write-Host "  Option B: Restore from a valid system state backup"
    Write-Host "  Option C: Reset the Invocation ID (virtual DCs only)"
    Write-Host ""
    Write-Host "See docs/05-USN-Rollback-Recovery.md for full details.`n"
}
else {
    Write-Host "[OK] No USN rollback detected on $env:COMPUTERNAME.`n" -ForegroundColor Green
}
