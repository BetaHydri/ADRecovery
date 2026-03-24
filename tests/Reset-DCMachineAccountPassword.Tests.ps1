Describe 'Reset-DCMachineAccountPassword.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Reset-DCMachineAccountPassword.ps1'

        Mock Reset-ComputerMachinePassword { }
        Mock Start-Sleep { }
        Mock Write-Host { }
    }

    It 'Should call Reset-ComputerMachinePassword exactly twice' {
        & $scriptPath -DelaySeconds 3 -Confirm:$false
        Should -Invoke Reset-ComputerMachinePassword -Times 2 -Exactly
    }

    It 'Should wait between resets' {
        & $scriptPath -DelaySeconds 3 -Confirm:$false
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 3 }
    }

    It 'Should not proceed with -WhatIf' {
        & $scriptPath -DelaySeconds 3 -WhatIf
        Should -Invoke Reset-ComputerMachinePassword -Times 0
    }
}
