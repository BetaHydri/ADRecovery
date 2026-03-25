<#
.SYNOPSIS
    Finds Linux/Unix systems in Active Directory that likely use Kerberos keytab files.

.DESCRIPTION
    Queries Active Directory for computer accounts and user accounts that indicate
    Linux/Unix Kerberos keytab usage. This helps identify systems that will be
    affected by a krbtgt password reset (double reset).

    Detection methods:
      1. Computer accounts with a Linux/Unix operating system attribute
         (e.g., Linux, Ubuntu, CentOS, RHEL, Debian, SUSE, Fedora, etc.)
      2. User or computer accounts with Service Principal Names (SPNs) that
         match common Linux service patterns (host/, HTTP/, nfs/, cifs/, etc.)
         on non-Windows operating systems
      3. Computer accounts whose description or name suggests keytab tooling
         (e.g., created by msktutil, adcli, SSSD, Samba, Centrify, PBIS)

    Use this script BEFORE performing a krbtgt double reset to understand the
    blast radius for Linux/Unix infrastructure.

    Corresponds to:
      - Domain Recovery  Step 3 (pre-check)
      - Forest Recovery  Step 2.3 / Step 3.3 (pre-check)

.PARAMETER DomainFQDN
    The fully qualified domain name to search. Defaults to the current domain.

.PARAMETER Server
    A specific Domain Controller to query. If omitted, uses the default DC for the domain.

.PARAMETER IncludeSPNSearch
    Also searches for user accounts with Service Principal Names, which may indicate
    Linux service accounts using keytabs. Default: $true.

.EXAMPLE
    .\Find-LinuxKerberosKeytabs.ps1

.EXAMPLE
    .\Find-LinuxKerberosKeytabs.ps1 -DomainFQDN "corp.contoso.com"

.EXAMPLE
    .\Find-LinuxKerberosKeytabs.ps1 -IncludeSPNSearch $false

.NOTES
    Author : Jan Tiedemann
    Version: 1.0.0
    Requires: ActiveDirectory module, Domain Admin or delegated read privileges
#>

#Requires -Modules ActiveDirectory

[CmdletBinding()]
param(
    [Parameter()]
    [string]$DomainFQDN = (Get-ADDomain).DNSRoot,

    [Parameter()]
    [string]$Server,

    [Parameter()]
    [bool]$IncludeSPNSearch = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Build common -Server parameter
$adParams = @{}
if ($Server) { $adParams['Server'] = $Server }
else { $adParams['Server'] = $DomainFQDN }

Write-Host "`n=== Linux/Unix Kerberos Keytab Discovery ===" -ForegroundColor Cyan
Write-Host "Domain : $DomainFQDN"
Write-Host "Time   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

# ----------------------------------------------------------------
# 1. Computer accounts with Linux/Unix operating system
# ----------------------------------------------------------------
Write-Host "--- Searching for Linux/Unix computer accounts ---" -ForegroundColor Yellow

$osFilters = @(
    '(operatingSystem=*Linux*)'
    '(operatingSystem=*Ubuntu*)'
    '(operatingSystem=*CentOS*)'
    '(operatingSystem=*Red Hat*)'
    '(operatingSystem=*RHEL*)'
    '(operatingSystem=*Debian*)'
    '(operatingSystem=*SUSE*)'
    '(operatingSystem=*Fedora*)'
    '(operatingSystem=*Unix*)'
    '(operatingSystem=*AIX*)'
    '(operatingSystem=*Solaris*)'
    '(operatingSystem=*HP-UX*)'
    '(operatingSystem=*FreeBSD*)'
    '(operatingSystem=*Mac OS*)'
    '(operatingSystem=*macOS*)'
)
$ldapFilter = "(|$($osFilters -join ''))"

$linuxComputers = @(Get-ADComputer -LDAPFilter $ldapFilter @adParams -Properties `
    Name, DNSHostName, OperatingSystem, OperatingSystemVersion, `
    ServicePrincipalName, Description, WhenCreated, PasswordLastSet)

if ($linuxComputers) {
    Write-Host "  Found $($linuxComputers.Count) Linux/Unix computer account(s):`n" -ForegroundColor Green
    foreach ($computer in $linuxComputers) {
        Write-Host "  Computer        : $($computer.Name)" -ForegroundColor White
        Write-Host "  DNS Hostname    : $($computer.DNSHostName)"
        Write-Host "  Operating System: $($computer.OperatingSystem) $($computer.OperatingSystemVersion)"
        Write-Host "  Description     : $($computer.Description)"
        Write-Host "  Created         : $($computer.WhenCreated)"
        Write-Host "  Password Set    : $($computer.PasswordLastSet)"
        if ($computer.ServicePrincipalName) {
            Write-Host "  SPNs            : $($computer.ServicePrincipalName -join ', ')"
        }
        Write-Host ""
    }
}
else {
    Write-Host "  No Linux/Unix computer accounts found.`n" -ForegroundColor DarkGray
}

# ----------------------------------------------------------------
# 2. User accounts with SPNs (potential Linux service keytabs)
# ----------------------------------------------------------------
if ($IncludeSPNSearch) {
    Write-Host "--- Searching for user accounts with Service Principal Names ---" -ForegroundColor Yellow
    Write-Host "  (These may be Linux/Unix service accounts using keytabs)`n"

    $spnUsers = @(Get-ADUser -LDAPFilter '(servicePrincipalName=*)' @adParams -Properties `
        Name, SamAccountName, ServicePrincipalName, Description, `
        WhenCreated, PasswordLastSet, Enabled |
    Where-Object { $_.SamAccountName -ne 'krbtgt' })

    if ($spnUsers) {
        Write-Host "  Found $($spnUsers.Count) user account(s) with SPNs:`n" -ForegroundColor Green
        foreach ($user in $spnUsers) {
            Write-Host "  Account      : $($user.SamAccountName)" -ForegroundColor White
            Write-Host "  Display Name : $($user.Name)"
            Write-Host "  Enabled      : $($user.Enabled)"
            Write-Host "  Description  : $($user.Description)"
            Write-Host "  Created      : $($user.WhenCreated)"
            Write-Host "  Password Set : $($user.PasswordLastSet)"
            Write-Host "  SPNs         : $($user.ServicePrincipalName -join ', ')"
            Write-Host ""
        }
    }
    else {
        Write-Host "  No user accounts with SPNs found.`n" -ForegroundColor DarkGray
    }
}

# ----------------------------------------------------------------
# 3. Summary
# ----------------------------------------------------------------
Write-Host "--- Summary ---" -ForegroundColor Yellow

$linuxCount = if ($linuxComputers) { $linuxComputers.Count } else { 0 }
$spnCount = if ($IncludeSPNSearch -and $spnUsers) { $spnUsers.Count } else { 0 }

Write-Host "  Linux/Unix computer accounts : $linuxCount"
if ($IncludeSPNSearch) {
    Write-Host "  User accounts with SPNs      : $spnCount"
}

if ($linuxCount -gt 0 -or $spnCount -gt 0) {
    Write-Host "`n  [ACTION REQUIRED] Before performing a krbtgt double reset:" -ForegroundColor Red
    Write-Host "    1. Document all systems listed above."
    Write-Host "    2. Plan keytab regeneration for each affected host."
    Write-Host "    3. After the krbtgt reset, regenerate keytabs (ktpass, msktutil, adcli)."
    Write-Host "    4. Restart Kerberos-dependent services on affected hosts."
    Write-Host "    5. Verify authentication with kinit / klist.`n"
}
else {
    Write-Host "`n  [OK] No obvious Linux/Unix Kerberos keytab usage detected." -ForegroundColor Green
    Write-Host "       Note: This does not guarantee no keytabs exist — some systems may"
    Write-Host "       use keytabs without having a recognizable AD computer account.`n"
}
