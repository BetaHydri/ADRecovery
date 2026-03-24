BeforeAll {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
        New-Module -Name ActiveDirectory -ScriptBlock {
            function Get-ADDomain { }
            function Get-ADDomainController { }
            function Get-ADObject { }
            function Set-ADObject { }
            Export-ModuleMember -Function *
        } | Import-Module -Force
    }
}

Describe 'Set-NonAuthoritativeSYSVOL.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Set-NonAuthoritativeSYSVOL.ps1'

        Mock Get-ADDomain {
            [PSCustomObject]@{ DistinguishedName = 'DC=contoso,DC=com' }
        }
        Mock Get-ADDomainController {
            @(
                [PSCustomObject]@{ Name = 'DC01'; HostName = 'DC01.contoso.com' },
                [PSCustomObject]@{ Name = 'DC02'; HostName = 'DC02.contoso.com' },
                [PSCustomObject]@{ Name = 'DC03'; HostName = 'DC03.contoso.com' }
            )
        }
        Mock Get-ADObject {
            [PSCustomObject]@{ 'msDFSR-Enabled' = $true }
        }
        Mock Set-ADObject { }
        Mock Invoke-Command { }
        Mock Write-Host { }
    }

    It 'Should skip the authoritative DC and process only others' {
        & $scriptPath -AuthoritativeDCName 'DC01' -DomainDN 'DC=contoso,DC=com' -Confirm:$false
        # DC02 and DC03 should be processed (2 calls to Set-ADObject)
        Should -Invoke Set-ADObject -Times 2 -Exactly
    }

    It 'Should stop DFSR on non-authoritative DCs when disabling' {
        & $scriptPath -AuthoritativeDCName 'DC01' -DomainDN 'DC=contoso,DC=com' -Confirm:$false
        Should -Invoke Invoke-Command -Times 2 -Exactly
    }

    It 'Should start DFSR on non-authoritative DCs when re-enabling' {
        & $scriptPath -AuthoritativeDCName 'DC01' -DomainDN 'DC=contoso,DC=com' -ReEnable -Confirm:$false
        Should -Invoke Invoke-Command -Times 2 -Exactly
    }
}
