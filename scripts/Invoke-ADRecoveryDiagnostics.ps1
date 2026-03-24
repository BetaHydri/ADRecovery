<#
.SYNOPSIS
    Runs AD recovery diagnostics to verify replication, DNS, SYSVOL, and trust health.

.DESCRIPTION
    Executes common diagnostic commands after a domain or forest recovery to confirm
    the environment is healthy:
      - repadmin /viewlist, /showrepl
      - nltest /dclist
      - dcdiag /e /q, dcdiag /e /test:dns
      - net share (SYSVOL/NETLOGON)
      - nltest /sc_verify (trust verification)

    Corresponds to:
      - Domain Recovery  Step 11
      - Forest Recovery  Phase 4

.PARAMETER DomainFQDN
    The FQDN of the domain to diagnose. Auto-detected if omitted.

.PARAMETER VerifyTrust
    Additional domain names to verify trust relationships with (e.g., parent or child domains).

.EXAMPLE
    .\Invoke-ADRecoveryDiagnostics.ps1

.EXAMPLE
    .\Invoke-ADRecoveryDiagnostics.ps1 -DomainFQDN "contoso.com" -VerifyTrust "corp.contoso.com"

.NOTES
    Author : Jan Tiedemann (Microsoft)
    Version: 1.0.0
    Requires: Run on a Domain Controller, Domain Admin privileges
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$DomainFQDN = (Get-WmiObject Win32_ComputerSystem).Domain,

    [Parameter()]
    [string[]]$VerifyTrust
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Write-Host "`n=== AD Recovery Diagnostics ===" -ForegroundColor Cyan
Write-Host "Domain : $DomainFQDN"
Write-Host "Time   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

# --- 1. Replication Partners ---
Write-Host "--- repadmin /viewlist * ---" -ForegroundColor Yellow
& repadmin /viewlist * 2>&1 | ForEach-Object { Write-Host "  $_" }
Write-Host ""

# --- 2. Replication Status ---
Write-Host "--- repadmin /showrepl ---" -ForegroundColor Yellow
& repadmin /showrepl 2>&1 | ForEach-Object { Write-Host "  $_" }
Write-Host ""

# --- 3. DC List ---
Write-Host "--- nltest /dclist:$DomainFQDN ---" -ForegroundColor Yellow
& nltest /dclist:$DomainFQDN 2>&1 | ForEach-Object { Write-Host "  $_" }
Write-Host ""

# --- 4. SYSVOL/NETLOGON Shares ---
Write-Host "--- SYSVOL / NETLOGON Shares ---" -ForegroundColor Yellow
$shares = & net share 2>&1
$sysvolShares = $shares | Select-String -Pattern 'SYSVOL|NETLOGON'
if ($sysvolShares) {
    $sysvolShares | ForEach-Object { Write-Host "  $_" -ForegroundColor Green }
}
else {
    Write-Host "  WARNING: SYSVOL/NETLOGON shares NOT found!" -ForegroundColor Red
}
Write-Host ""

# --- 5. DCDiag ---
Write-Host "--- dcdiag /e /q ---" -ForegroundColor Yellow
$dcdiagOutput = & dcdiag /e /q 2>&1
if ($dcdiagOutput) {
    $dcdiagOutput | ForEach-Object { Write-Host "  $_" }
}
else {
    Write-Host "  All tests passed (no errors)." -ForegroundColor Green
}
Write-Host ""

# --- 6. DNS Diagnostics ---
Write-Host "--- dcdiag /e /test:dns ---" -ForegroundColor Yellow
& dcdiag /e /test:dns 2>&1 | ForEach-Object { Write-Host "  $_" }
Write-Host ""

# --- 7. Trust Verification ---
if ($VerifyTrust) {
    Write-Host "--- Trust Verification ---" -ForegroundColor Yellow
    foreach ($trustDomain in $VerifyTrust) {
        Write-Host "  Verifying trust with: $trustDomain"
        $result = & nltest /sc_verify:$trustDomain 2>&1
        $result | ForEach-Object { Write-Host "    $_" }
    }
    Write-Host ""
}

Write-Host "=== Diagnostics Complete ===" -ForegroundColor Cyan
Write-Host "Review output above for any errors or warnings.`n"
