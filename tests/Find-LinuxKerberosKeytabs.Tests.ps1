BeforeAll {
    # Stub the ActiveDirectory module so the script can be dot-sourced without it installed
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
        New-Module -Name ActiveDirectory -ScriptBlock {
            function Get-ADDomain { }
            function Get-ADComputer { }
            function Get-ADUser { }
            Export-ModuleMember -Function *
        } | Import-Module -Force
    }
}

Describe 'Find-LinuxKerberosKeytabs.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Find-LinuxKerberosKeytabs.ps1'

        Mock Get-ADDomain {
            [PSCustomObject]@{ DNSRoot = 'contoso.com' }
        }
        Mock Write-Host { }
    }

    Context 'When Linux computer accounts exist' {
        BeforeAll {
            Mock Get-ADComputer {
                @(
                    [PSCustomObject]@{
                        Name                   = 'LINUX-WEB01'
                        DNSHostName            = 'linux-web01.contoso.com'
                        OperatingSystem        = 'Ubuntu 22.04 LTS'
                        OperatingSystemVersion  = '22.04'
                        ServicePrincipalName   = @('host/linux-web01.contoso.com', 'HTTP/linux-web01.contoso.com')
                        Description            = 'Web server'
                        WhenCreated            = (Get-Date).AddDays(-90)
                        PasswordLastSet        = (Get-Date).AddDays(-30)
                    },
                    [PSCustomObject]@{
                        Name                   = 'LINUX-DB01'
                        DNSHostName            = 'linux-db01.contoso.com'
                        OperatingSystem        = 'Red Hat Enterprise Linux 9'
                        OperatingSystemVersion  = '9.0'
                        ServicePrincipalName   = @('host/linux-db01.contoso.com')
                        Description            = 'Database server'
                        WhenCreated            = (Get-Date).AddDays(-180)
                        PasswordLastSet        = (Get-Date).AddDays(-15)
                    }
                )
            }
            Mock Get-ADUser { @() }
        }

        It 'Should query AD for Linux/Unix computer accounts' {
            & $scriptPath -DomainFQDN 'contoso.com'
            Should -Invoke Get-ADComputer -Times 1 -Exactly
        }

        It 'Should use an LDAP filter targeting Linux/Unix operating systems' {
            & $scriptPath -DomainFQDN 'contoso.com'
            Should -Invoke Get-ADComputer -Times 1 -Exactly -ParameterFilter {
                $LDAPFilter -match 'operatingSystem=\*Linux\*' -and
                $LDAPFilter -match 'operatingSystem=\*Ubuntu\*' -and
                $LDAPFilter -match 'operatingSystem=\*Red Hat\*'
            }
        }
    }

    Context 'When no Linux computer accounts exist' {
        BeforeAll {
            Mock Get-ADComputer { @() }
            Mock Get-ADUser { @() }
        }

        It 'Should complete without error' {
            { & $scriptPath -DomainFQDN 'contoso.com' } | Should -Not -Throw
        }

        It 'Should still query AD' {
            & $scriptPath -DomainFQDN 'contoso.com'
            Should -Invoke Get-ADComputer -Times 1 -Exactly
        }
    }

    Context 'When user accounts with SPNs exist' {
        BeforeAll {
            Mock Get-ADComputer { @() }
            Mock Get-ADUser {
                @(
                    [PSCustomObject]@{
                        Name                = 'svc-hadoop'
                        SamAccountName      = 'svc-hadoop'
                        ServicePrincipalName = @('HTTP/hadoop-master.contoso.com')
                        Description         = 'Hadoop service account'
                        WhenCreated         = (Get-Date).AddDays(-60)
                        PasswordLastSet     = (Get-Date).AddDays(-10)
                        Enabled             = $true
                    }
                )
            }
        }

        It 'Should search for user accounts with SPNs by default' {
            & $scriptPath -DomainFQDN 'contoso.com'
            Should -Invoke Get-ADUser -Times 1 -Exactly
        }

        It 'Should use an LDAP filter for servicePrincipalName' {
            & $scriptPath -DomainFQDN 'contoso.com'
            Should -Invoke Get-ADUser -Times 1 -Exactly -ParameterFilter {
                $LDAPFilter -eq '(servicePrincipalName=*)'
            }
        }
    }

    Context 'When IncludeSPNSearch is disabled' {
        BeforeAll {
            Mock Get-ADComputer { @() }
            Mock Get-ADUser { }
        }

        It 'Should not query user accounts with SPNs' {
            & $scriptPath -DomainFQDN 'contoso.com' -IncludeSPNSearch $false
            Should -Invoke Get-ADUser -Times 0
        }
    }

    Context 'When -Server parameter is specified' {
        BeforeAll {
            Mock Get-ADComputer { @() }
            Mock Get-ADUser { @() }
        }

        It 'Should pass the Server parameter to AD cmdlets' {
            & $scriptPath -DomainFQDN 'contoso.com' -Server 'DC01.contoso.com'
            Should -Invoke Get-ADComputer -Times 1 -Exactly -ParameterFilter {
                $Server -eq 'DC01.contoso.com'
            }
        }
    }
}
