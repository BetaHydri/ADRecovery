Describe 'Invoke-ADRecoveryDiagnostics.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Invoke-ADRecoveryDiagnostics.ps1'

        Mock Get-WmiObject {
            [PSCustomObject]@{ Domain = 'contoso.com' }
        }
        # Mock all external commands
        Mock repadmin { 'Replication summary' }
        Mock nltest { 'DC list' }
        Mock dcdiag { 'All tests passed' }
        # net share returns lines
        Mock net {
            @(
                'Share name   Resource',
                'SYSVOL       C:\Windows\SYSVOL\sysvol',
                'NETLOGON     C:\Windows\SYSVOL\sysvol\contoso.com\SCRIPTS'
            )
        }
        Mock Write-Host { }
    }

    It 'Should run without errors' {
        { & $scriptPath -DomainFQDN 'contoso.com' } | Should -Not -Throw
    }

    It 'Should invoke repadmin commands' {
        & $scriptPath -DomainFQDN 'contoso.com'
        Should -Invoke repadmin -Times 2  # /viewlist and /showrepl
    }

    It 'Should invoke nltest for DC list' {
        & $scriptPath -DomainFQDN 'contoso.com'
        Should -Invoke nltest -Times 1 -Exactly
    }

    It 'Should invoke dcdiag' {
        & $scriptPath -DomainFQDN 'contoso.com'
        Should -Invoke dcdiag -Times 2  # /e /q and /e /test:dns
    }

    It 'Should verify trusts when -VerifyTrust is specified' {
        & $scriptPath -DomainFQDN 'contoso.com' -VerifyTrust 'corp.contoso.com'
        # nltest called for dclist + sc_verify
        Should -Invoke nltest -Times 2
    }
}
