BeforeAll {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
        New-Module -Name ActiveDirectory -Scriptblock {
            function Get-ADDomain { }
            function Get-ADObject { }
            function Set-ADObject { }
            Export-ModuleMember -Function *
        } | Import-Module -Force
    }
}

Describe 'Reset-RIDPool.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Reset-RIDPool.ps1'

        Mock Get-ADDomain {
            [PSCustomObject]@{ DistinguishedName = 'DC=contoso,DC=com' }
        }
        Mock Get-ADObject {
            [PSCustomObject]@{
                DistinguishedName = 'CN=RID Manager$,CN=System,DC=contoso,DC=com'
                rIDAvailablePool  = [Int64]4611686014132422708
            }
        }
        Mock Set-ADObject { }
        Mock Write-Host { }
        Mock Write-Warning { }
    }

    It 'Should read the current rIDAvailablePool value' {
        & $scriptPath -Increment 100000 -DomainDN 'DC=contoso,DC=com' -Confirm:$false
        Should -Invoke Get-ADObject -Times 1 -Exactly
    }

    It 'Should update rIDAvailablePool via Set-ADObject' {
        & $scriptPath -Increment 100000 -DomainDN 'DC=contoso,DC=com' -Confirm:$false
        Should -Invoke Set-ADObject -Times 1 -Exactly
    }
}
