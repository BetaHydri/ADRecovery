<#
.SYNOPSIS
    Resets the krbtgt account password twice to invalidate all existing Kerberos tickets.

.DESCRIPTION
    After an Active Directory security incident, the krbtgt account password must be reset
    twice because AD keeps both the current and previous password hashes. Resetting twice
    ensures both are replaced, fully invalidating any stolen tickets (Golden Ticket attack).

    Corresponds to:
      - Domain Recovery  Step 3
      - Forest Recovery  Step 2.3 / Step 3.3

.PARAMETER DomainFQDN
    The fully qualified domain name (e.g., contoso.com). Defaults to the current domain.

.PARAMETER DelaySeconds
    Seconds to wait between the two password resets. Default: 10.

    During a domain/forest recovery (single restored DC, no replication partners),
    10 seconds is sufficient. In a live environment with multiple DCs, Microsoft
    recommends waiting at least the maximum TGT lifetime (default: 10 hours = 36000
    seconds) between resets to allow replication and avoid domain-wide authentication
    disruption.

.EXAMPLE
    .\Reset-KrbtgtPassword.ps1

.EXAMPLE
    .\Reset-KrbtgtPassword.ps1 -DomainFQDN "corp.contoso.com" -DelaySeconds 15

.EXAMPLE
    # Live environment with multiple DCs — wait 10 hours between resets
    .\Reset-KrbtgtPassword.ps1 -DelaySeconds 36000

.NOTES
    Author : Jan Tiedemann (Microsoft)
    Version: 1.0.0
    Requires: ActiveDirectory module, Domain Admin privileges
#>

#Requires -Modules ActiveDirectory

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [string]$DomainFQDN = (Get-ADDomain).DNSRoot,

    [Parameter()]
    [ValidateRange(5, 36000)]
    [int]$DelaySeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n=== krbtgt Password Reset ===" -ForegroundColor Cyan
Write-Host "Domain : $DomainFQDN"
Write-Host "Delay  : $DelaySeconds seconds between resets`n"

# Retrieve the krbtgt account
$krbtgt = Get-ADUser -Identity 'krbtgt' -Server $DomainFQDN -Properties PasswordLastSet
Write-Host "Current krbtgt PasswordLastSet: $($krbtgt.PasswordLastSet)" -ForegroundColor Yellow

if ($PSCmdlet.ShouldProcess("krbtgt@$DomainFQDN", "Reset password twice")) {
    # First reset
    Write-Host "`n[1/2] Resetting krbtgt password (first time)..." -ForegroundColor Green
    $bytes1 = [byte[]]::new(48)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes1)
    $pw1 = [Convert]::ToBase64String($bytes1)
    Set-ADAccountPassword -Identity 'krbtgt' -Server $DomainFQDN -Reset -NewPassword (ConvertTo-SecureString $pw1 -AsPlainText -Force)
    Write-Host "      First reset completed." -ForegroundColor Green

    # Wait before second reset
    Write-Host "      Waiting $DelaySeconds seconds before second reset..."
    Start-Sleep -Seconds $DelaySeconds

    # Second reset
    Write-Host "[2/2] Resetting krbtgt password (second time)..." -ForegroundColor Green
    $bytes2 = [byte[]]::new(48)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes2)
    $pw2 = [Convert]::ToBase64String($bytes2)
    Set-ADAccountPassword -Identity 'krbtgt' -Server $DomainFQDN -Reset -NewPassword (ConvertTo-SecureString $pw2 -AsPlainText -Force)
    Write-Host "      Second reset completed." -ForegroundColor Green

    # Verify
    $krbtgtAfter = Get-ADUser -Identity 'krbtgt' -Server $DomainFQDN -Properties PasswordLastSet
    Write-Host "`nNew krbtgt PasswordLastSet: $($krbtgtAfter.PasswordLastSet)" -ForegroundColor Cyan
    Write-Host "`n[OK] krbtgt password has been reset twice. All existing Kerberos tickets are now invalid." -ForegroundColor Green
    Write-Host "     Clients will need to re-authenticate.`n"
}
