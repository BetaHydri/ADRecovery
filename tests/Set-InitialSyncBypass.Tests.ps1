Describe 'Set-InitialSyncBypass.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Set-InitialSyncBypass.ps1'

        Mock Get-ItemProperty { $null }
        Mock Set-ItemProperty { }
        Mock Remove-ItemProperty { }
        Mock Write-Host { }
    }

    Context 'Bypass mode (default — during recovery)' {
        It 'Should set registry value to 0' {
            & $scriptPath -Confirm:$false
            Should -Invoke Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Repl Perform Initial Synchronizations' -and $Value -eq 0
            }
        }

        It 'Should not call Remove-ItemProperty' {
            & $scriptPath -Confirm:$false
            Should -Invoke Remove-ItemProperty -Times 0
        }
    }

    Context 'Enable mode (after recovery)' {
        It 'Should remove the registry value to restore default behavior' {
            & $scriptPath -Enable -Confirm:$false
            Should -Invoke Remove-ItemProperty -Times 1 -Exactly
        }
    }

    It 'Should not modify anything with -WhatIf' {
        & $scriptPath -WhatIf
        Should -Invoke Set-ItemProperty -Times 0
        Should -Invoke Remove-ItemProperty -Times 0
    }
}
