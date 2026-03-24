<#
.SYNOPSIS
    Marks a Domain Controller as the authoritative source for SYSVOL DFS-R replication.

.DESCRIPTION
    Sets msDFSR-Options=1 and msDFSR-Enabled=TRUE on the specified DC's SYSVOL Subscription
    object, then restarts the DFS Replication service. This makes the DC the authoritative
    SYSVOL source so all other DCs replicate from it.

    Corresponds to:
      - Domain Recovery  Step 4
      - Forest Recovery  Step 2.4 / Step 3.4
      - SYSVOL Recovery  Step 2

.PARAMETER DCName
    The name of the Domain Controller to mark as authoritative (e.g., DC01).

.PARAMETER DomainDN
    The distinguished name of the domain (e.g., DC=contoso,DC=com). Auto-detected if omitted.

.EXAMPLE
    .\Set-AuthoritativeSYSVOLRestore.ps1 -DCName "DC01"

.EXAMPLE
    .\Set-AuthoritativeSYSVOLRestore.ps1 -DCName "DC-ROOT01" -DomainDN "DC=contoso,DC=com"

.NOTES
    Author : Jan Tiedemann (Microsoft)
    Version: 1.0.0
    Requires: ActiveDirectory module, Domain Admin privileges
#>

#Requires -Modules ActiveDirectory

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$DCName,

    [Parameter()]
    [string]$DomainDN = (Get-ADDomain).DistinguishedName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n=== Authoritative SYSVOL Restore (DFS-R) ===" -ForegroundColor Cyan
Write-Host "DC     : $DCName"
Write-Host "Domain : $DomainDN`n"

# Build the path to the SYSVOL Subscription object
$sysvolSubscriptionDN = "CN=SYSVOL Subscription,CN=Domain System Volume,CN=DFSR-LocalSettings,CN=$DCName,OU=Domain Controllers,$DomainDN"

Write-Host "Target object:"
Write-Host "  $sysvolSubscriptionDN`n"

# Verify the object exists
try {
    $obj = Get-ADObject -Identity $sysvolSubscriptionDN -Properties 'msDFSR-Options', 'msDFSR-Enabled'
}
catch {
    Write-Error "Cannot find SYSVOL Subscription object at: $sysvolSubscriptionDN. Verify the DC name and domain DN."
    return
}

Write-Host "Current values:" -ForegroundColor Yellow
Write-Host "  msDFSR-Options : $($obj.'msDFSR-Options')"
Write-Host "  msDFSR-Enabled : $($obj.'msDFSR-Enabled')`n"

if ($PSCmdlet.ShouldProcess($sysvolSubscriptionDN, "Set msDFSR-Options=1 and msDFSR-Enabled=TRUE")) {
    # Set authoritative flag
    Set-ADObject -Identity $sysvolSubscriptionDN -Replace @{
        'msDFSR-Options' = 1
        'msDFSR-Enabled' = $true
    }
    Write-Host "[OK] msDFSR-Options set to 1 (authoritative)" -ForegroundColor Green
    Write-Host "[OK] msDFSR-Enabled set to TRUE" -ForegroundColor Green

    # Restart DFS Replication service
    Write-Host "`nRestarting DFS Replication service on $DCName..."
    if ($DCName -eq $env:COMPUTERNAME) {
        Stop-Service -Name 'DFSR' -Force
        Start-Service -Name 'DFSR'
    }
    else {
        Invoke-Command -ComputerName $DCName -ScriptBlock {
            Stop-Service -Name 'DFSR' -Force
            Start-Service -Name 'DFSR'
        }
    }
    Write-Host "[OK] DFS Replication service restarted." -ForegroundColor Green

    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "  1. Check Event Viewer -> DFS Replication log for Event ID 4602 (SYSVOL initialized)"
    Write-Host "  2. Event ID 5008 (no replication partner) is expected if other DCs are offline"
    Write-Host "  3. Mark all OTHER DCs as non-authoritative using Set-NonAuthoritativeSYSVOL.ps1`n"
}
