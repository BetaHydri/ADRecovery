<#
.SYNOPSIS
    Restores deleted Active Directory objects from the AD Recycle Bin.

.DESCRIPTION
    Searches for deleted AD objects by display name, SAM account name, or OU name and
    restores them. Supports restoring individual objects, entire OUs, and nested OU
    structures (parent OU first, then children).

    Corresponds to:
      - Object Recovery  Method 2 (PowerShell)

.PARAMETER DisplayName
    Display name (or partial) of the deleted object to search for.

.PARAMETER SAMAccountName
    SAM account name of the deleted user or group.

.PARAMETER OUName
    Name of a deleted OU to restore (including child objects).

.PARAMETER TargetOU
    Optional alternative OU to restore objects into (distinguished name).

.PARAMETER DomainDN
    Distinguished name of the domain. Auto-detected if omitted.

.EXAMPLE
    # Restore a single user by display name
    .\Restore-DeletedADObjects.ps1 -DisplayName "John Doe"

.EXAMPLE
    # Restore by SAM account name
    .\Restore-DeletedADObjects.ps1 -SAMAccountName "jdoe"

.EXAMPLE
    # Restore an OU and all its contents
    .\Restore-DeletedADObjects.ps1 -OUName "Sales"

.NOTES
    Author : Jan Tiedemann
    Version: 1.0.0
    Requires: ActiveDirectory module, AD Recycle Bin enabled, Domain Admin privileges
#>

#Requires -Modules ActiveDirectory

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [Parameter(ParameterSetName = 'ByDisplayName')]
    [string]$DisplayName,

    [Parameter(ParameterSetName = 'BySAM')]
    [string]$SAMAccountName,

    [Parameter(ParameterSetName = 'ByOU')]
    [string]$OUName,

    [Parameter()]
    [string]$TargetOU,

    [Parameter()]
    [string]$DomainDN = (Get-ADDomain).DistinguishedName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "`n=== AD Object Recovery (Recycle Bin) ===" -ForegroundColor Cyan
Write-Host "Domain : $DomainDN`n"

$deletedObjectsDN = "CN=Deleted Objects,$DomainDN"

switch ($PSCmdlet.ParameterSetName) {
    'ByDisplayName' {
        Write-Host "Searching for deleted objects with DisplayName: '$DisplayName'..." -ForegroundColor Yellow
        $objects = Get-ADObject -Filter { displayName -eq $DisplayName } -IncludeDeletedObjects -Properties displayName, lastKnownParent, whenChanged
        if (-not $objects) {
            # Try wildcard
            $objects = Get-ADObject -Filter { displayName -like $DisplayName } -IncludeDeletedObjects -Properties displayName, lastKnownParent, whenChanged
        }
    }
    'BySAM' {
        Write-Host "Searching for deleted objects with SAMAccountName: '$SAMAccountName'..." -ForegroundColor Yellow
        $objects = Get-ADObject -Filter { SAMAccountName -eq $SAMAccountName } -IncludeDeletedObjects -Properties SAMAccountName, lastKnownParent, whenChanged
    }
    'ByOU' {
        Write-Host "Searching for deleted OU: '$OUName'..." -ForegroundColor Yellow
        # Step 1: Restore the OU itself
        $ouObject = Get-ADObject -LDAPFilter "(msDS-LastKnownRDN=$OUName)" -IncludeDeletedObjects -Properties msDS-LastKnownRDN, lastKnownParent, whenChanged |
            Where-Object { $_.ObjectClass -eq 'organizationalUnit' }

        if (-not $ouObject) {
            Write-Host "No deleted OU named '$OUName' found." -ForegroundColor Red
            return
        }

        Write-Host "Found deleted OU:" -ForegroundColor Green
        Write-Host "  DN: $($ouObject.DistinguishedName)"
        Write-Host "  Deleted: $($ouObject.whenChanged)`n"

        if ($PSCmdlet.ShouldProcess($ouObject.DistinguishedName, "Restore OU '$OUName'")) {
            Restore-ADObject -Identity $ouObject.DistinguishedName
            Write-Host "[OK] OU '$OUName' restored." -ForegroundColor Green

            # Step 2: Restore child objects
            $restoredOUDN = "OU=$OUName,$($ouObject.lastKnownParent)"
            Write-Host "`nSearching for child objects with lastKnownParent = $restoredOUDN..."
            $children = Get-ADObject -SearchBase $deletedObjectsDN `
                -Filter { lastKnownParent -eq $restoredOUDN } `
                -IncludeDeletedObjects -Properties lastKnownParent, msDS-LastKnownRDN, whenChanged

            if ($children) {
                Write-Host "Found $($children.Count) child object(s):" -ForegroundColor Yellow
                foreach ($child in $children) {
                    Write-Host "  - $($child.'msDS-LastKnownRDN') ($($child.ObjectClass))"
                    Restore-ADObject -Identity $child.DistinguishedName
                    Write-Host "    [OK] Restored." -ForegroundColor Green
                }
            }
            else {
                Write-Host "No child objects found." -ForegroundColor Yellow
            }
        }
        Write-Host "`n[OK] OU recovery complete. Verify in Active Directory Users and Computers.`n"
        return
    }
}

# Handle single-object results (DisplayName / SAM)
if (-not $objects) {
    Write-Host "No deleted objects found matching the search criteria." -ForegroundColor Red
    return
}

Write-Host "Found $(@($objects).Count) deleted object(s):" -ForegroundColor Green
foreach ($obj in $objects) {
    Write-Host "  - $($obj.Name) | Class: $($obj.ObjectClass) | Deleted: $($obj.whenChanged) | From: $($obj.lastKnownParent)"
}
Write-Host ""

foreach ($obj in $objects) {
    $restoreTarget = if ($TargetOU) { "Restore to '$TargetOU'" } else { "Restore to original location" }
    if ($PSCmdlet.ShouldProcess($obj.Name, $restoreTarget)) {
        if ($TargetOU) {
            Restore-ADObject -Identity $obj.DistinguishedName -TargetPath $TargetOU
        }
        else {
            Restore-ADObject -Identity $obj.DistinguishedName
        }
        Write-Host "[OK] Restored: $($obj.Name)" -ForegroundColor Green
    }
}

Write-Host "`n[OK] Recovery complete. Verify in Active Directory Users and Computers."
Write-Host "     Check group memberships — back-links may need time to replicate.`n"
