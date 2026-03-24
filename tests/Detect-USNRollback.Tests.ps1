Describe 'Detect-USNRollback.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Detect-USNRollback.ps1'
        Mock Write-Host { }
    }

    Context 'No USN rollback' {
        BeforeAll {
            Mock Get-WinEvent { $null }
            Mock Get-ItemProperty { $null }
            Mock Get-Service {
                [PSCustomObject]@{ Status = 'Running'; Name = 'Netlogon' }
            }
        }

        It 'Should complete without errors' {
            { & $scriptPath } | Should -Not -Throw
        }

        It 'Should check Event ID 2095' {
            & $scriptPath
            Should -Invoke Get-WinEvent -Times 1
        }

        It 'Should check the registry for Dsa Not Writable' {
            & $scriptPath
            Should -Invoke Get-ItemProperty -Times 1
        }

        It 'Should check Net Logon service status' {
            & $scriptPath
            Should -Invoke Get-Service -Times 1
        }
    }

    Context 'USN rollback detected' {
        BeforeAll {
            Mock Get-WinEvent {
                @([PSCustomObject]@{
                    TimeCreated = (Get-Date)
                    Message     = 'USN rollback was detected on this domain controller.'
                    Id          = 2095
                })
            }
            Mock Get-ItemProperty {
                [PSCustomObject]@{ 'Dsa Not Writable' = 4 }
            }
            Mock Get-Service {
                [PSCustomObject]@{ Status = 'Paused'; Name = 'Netlogon' }
            }
        }

        It 'Should detect Event ID 2095' {
            & $scriptPath
            Should -Invoke Get-WinEvent -Times 1
        }

        It 'Should detect Dsa Not Writable = 0x4' {
            & $scriptPath
            Should -Invoke Get-ItemProperty -Times 1
        }

        It 'Should detect paused Net Logon service' {
            & $scriptPath
            Should -Invoke Get-Service -Times 1
        }
    }
}
