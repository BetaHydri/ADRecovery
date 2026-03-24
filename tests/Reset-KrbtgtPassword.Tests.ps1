BeforeAll {
    # Stub the ActiveDirectory module so the script can be dot-sourced without it installed
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
        New-Module -Name ActiveDirectory -Scriptblock {
            function Get-ADDomain { }
            function Get-ADUser { }
            function Set-ADAccountPassword { }
            Export-ModuleMember -Function *
        } | Import-Module -Force
    }

    # Ensure System.Web assembly is loaded for [System.Web.Security.Membership]::GeneratePassword()
    try {
        Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    }
    catch {
        # On PowerShell Core / non-Windows, create a stub type
        if (-not ([System.Management.Automation.PSTypeName]'System.Web.Security.Membership').Type) {
            Add-Type -TypeDefinition @'
public static class MembershipStub {
    public static string GeneratePassword(int length, int numberOfNonAlphanumericCharacters) {
        return new string('A', length);
    }
}
'@ -ErrorAction SilentlyContinue
            # Create the namespace/class via a wrapper so the script's type reference resolves
            $code = @'
namespace System.Web.Security {
    public static class Membership {
        public static string GeneratePassword(int length, int numberOfNonAlphanumericCharacters) {
            return new string('P', length);
        }
    }
}
'@
            Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Reset-KrbtgtPassword.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Reset-KrbtgtPassword.ps1'

        Mock Get-ADDomain {
            [PSCustomObject]@{ DNSRoot = 'contoso.com' }
        }
        Mock Get-ADUser {
            [PSCustomObject]@{
                SamAccountName  = 'krbtgt'
                PasswordLastSet = (Get-Date).AddDays(-30)
            }
        }
        Mock Set-ADAccountPassword { }
        Mock Start-Sleep { }
        Mock Write-Host { }
    }

    It 'Should call Set-ADAccountPassword exactly twice' {
        & $scriptPath -DomainFQDN 'contoso.com' -DelaySeconds 5 -Confirm:$false
        Should -Invoke Set-ADAccountPassword -Times 2 -Exactly
    }

    It 'Should call Get-ADUser to retrieve the krbtgt account' {
        & $scriptPath -DomainFQDN 'contoso.com' -DelaySeconds 5 -Confirm:$false
        Should -Invoke Get-ADUser -Times 2 -Exactly  # once before, once after
    }

    It 'Should wait between resets' {
        & $scriptPath -DomainFQDN 'contoso.com' -DelaySeconds 5 -Confirm:$false
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 5 }
    }

    It 'Should not proceed with -WhatIf' {
        & $scriptPath -DomainFQDN 'contoso.com' -DelaySeconds 5 -WhatIf
        Should -Invoke Set-ADAccountPassword -Times 0
    }
}
