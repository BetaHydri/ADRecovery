BeforeAll {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
        New-Module -Name ActiveDirectory -ScriptBlock {
            function Get-ADDomain { }
            function Get-ADObject { }
            function Restore-ADObject { }
            Export-ModuleMember -Function *
        } | Import-Module -Force
    }
}

Describe 'Restore-DeletedADObjects.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Restore-DeletedADObjects.ps1'

        Mock Get-ADDomain {
            [PSCustomObject]@{ DistinguishedName = 'DC=contoso,DC=com' }
        }
        Mock Restore-ADObject { }
        Mock Write-Host { }
    }

    Context 'ByDisplayName' {
        BeforeEach {
            Mock Get-ADObject {
                [PSCustomObject]@{
                    Name              = 'John Doe\0ADEL:abc123'
                    ObjectClass       = 'user'
                    DistinguishedName = 'CN=John Doe\0ADEL:abc123,CN=Deleted Objects,DC=contoso,DC=com'
                    whenChanged       = (Get-Date).AddDays(-1)
                    lastKnownParent   = 'OU=Users,DC=contoso,DC=com'
                    displayName       = 'John Doe'
                }
            }
        }

        It 'Should find and restore a deleted user by DisplayName' {
            & $scriptPath -DisplayName 'John Doe' -Confirm:$false
            Should -Invoke Restore-ADObject -Times 1 -Exactly
        }

        It 'Should restore to alternative OU when -TargetOU is specified' {
            & $scriptPath -DisplayName 'John Doe' -TargetOU 'OU=Recovered,DC=contoso,DC=com' -Confirm:$false
            Should -Invoke Restore-ADObject -Times 1 -Exactly -ParameterFilter {
                $TargetPath -eq 'OU=Recovered,DC=contoso,DC=com'
            }
        }
    }

    Context 'BySAM' {
        BeforeEach {
            Mock Get-ADObject {
                [PSCustomObject]@{
                    Name              = 'jdoe\0ADEL:abc123'
                    ObjectClass       = 'user'
                    DistinguishedName = 'CN=jdoe\0ADEL:abc123,CN=Deleted Objects,DC=contoso,DC=com'
                    whenChanged       = (Get-Date).AddDays(-1)
                    lastKnownParent   = 'OU=Users,DC=contoso,DC=com'
                    SAMAccountName    = 'jdoe'
                }
            }
        }

        It 'Should find and restore a deleted user by SAMAccountName' {
            & $scriptPath -SAMAccountName 'jdoe' -Confirm:$false
            Should -Invoke Restore-ADObject -Times 1 -Exactly
        }
    }

    Context 'ByOU' {
        BeforeAll {
            # First call returns the OU, second call returns children
            $script:callCount = 0
        }
        BeforeEach {
            $script:callCount = 0
            Mock Get-ADObject {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    # Return the OU object
                    [PSCustomObject]@{
                        Name                = 'Sales\0ADEL:abc123'
                        ObjectClass         = 'organizationalUnit'
                        DistinguishedName   = 'CN=Sales\0ADEL:abc123,CN=Deleted Objects,DC=contoso,DC=com'
                        'msDS-LastKnownRDN' = 'Sales'
                        lastKnownParent     = 'DC=contoso,DC=com'
                        whenChanged         = (Get-Date).AddDays(-1)
                    }
                }
                else {
                    # Return child objects
                    @(
                        [PSCustomObject]@{
                            Name                = 'Alice\0ADEL:def456'
                            ObjectClass         = 'user'
                            DistinguishedName   = 'CN=Alice\0ADEL:def456,CN=Deleted Objects,DC=contoso,DC=com'
                            'msDS-LastKnownRDN' = 'Alice'
                            lastKnownParent     = 'OU=Sales,DC=contoso,DC=com'
                            whenChanged         = (Get-Date).AddDays(-1)
                        }
                    )
                }
            }
        }

        It 'Should restore the OU and its child objects' {
            & $scriptPath -OUName 'Sales' -Confirm:$false
            Should -Invoke Restore-ADObject -Times 2  # OU + 1 child
        }
    }

    Context 'No results' {
        BeforeEach {
            Mock Get-ADObject { $null }
        }

        It 'Should report when no deleted objects are found' {
            & $scriptPath -DisplayName 'NonExistent' -Confirm:$false
            Should -Invoke Restore-ADObject -Times 0
        }
    }
}
