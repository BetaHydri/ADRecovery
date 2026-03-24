BeforeAll {
    # Stub the ActiveDirectory module so the script can be dot-sourced without it installed
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
        New-Module -Name ActiveDirectory -ScriptBlock {
            function Get-ADDomain { }
            function Get-ADUser { }
            function Set-ADAccountPassword { }
            Export-ModuleMember -Function *
        } | Import-Module -Force
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
