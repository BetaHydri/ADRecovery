BeforeAll {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
        New-Module -Name ActiveDirectory -ScriptBlock {
            function Get-ADDomain { }
            function Get-ADObject { }
            function Set-ADObject { }
            Export-ModuleMember -Function *
        } | Import-Module -Force
    }
}

Describe 'Set-AuthoritativeSYSVOLRestore.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Set-AuthoritativeSYSVOLRestore.ps1'

        Mock Get-ADDomain {
            [PSCustomObject]@{ DistinguishedName = 'DC=contoso,DC=com' }
        }
        Mock Get-ADObject {
            [PSCustomObject]@{
                DistinguishedName = 'CN=SYSVOL Subscription,CN=Domain System Volume,CN=DFSR-LocalSettings,CN=DC01,OU=Domain Controllers,DC=contoso,DC=com'
                'msDFSR-Options'  = 0
                'msDFSR-Enabled'  = $false
            }
        }
        Mock Set-ADObject { }
        Mock Stop-Service { }
        Mock Start-Service { }
        Mock Invoke-Command { }
        Mock Write-Host { }
    }

    It 'Should retrieve the SYSVOL Subscription object' {
        & $scriptPath -DCName 'DC01' -DomainDN 'DC=contoso,DC=com' -Confirm:$false
        Should -Invoke Get-ADObject -Times 1 -Exactly
    }

    It 'Should set msDFSR-Options and msDFSR-Enabled via Set-ADObject' {
        & $scriptPath -DCName 'DC01' -DomainDN 'DC=contoso,DC=com' -Confirm:$false
        Should -Invoke Set-ADObject -Times 1 -Exactly
    }

    It 'Should restart DFSR service on remote DC' {
        & $scriptPath -DCName 'REMOTEDC' -DomainDN 'DC=contoso,DC=com' -Confirm:$false
        Should -Invoke Invoke-Command -Times 1 -Exactly
    }

    It 'Should restart DFSR service locally when DCName matches COMPUTERNAME' {
        $env:COMPUTERNAME_BACKUP = $env:COMPUTERNAME
        $env:COMPUTERNAME = 'DC01'
        try {
            & $scriptPath -DCName 'DC01' -DomainDN 'DC=contoso,DC=com' -Confirm:$false
            Should -Invoke Stop-Service -Times 1 -Exactly
            Should -Invoke Start-Service -Times 1 -Exactly
        }
        finally {
            $env:COMPUTERNAME = $env:COMPUTERNAME_BACKUP
        }
    }
}