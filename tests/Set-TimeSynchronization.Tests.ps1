Describe 'Set-TimeSynchronization.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Set-TimeSynchronization.ps1'

        Mock Set-ItemProperty { }
        Mock Stop-Service { }
        Mock Start-Service { }
        Mock w32tm { 'Sending resync command to local computer' }
        Mock Write-Host { }
    }

    It 'Should set MaxNegPhaseCorrection and MaxPosPhaseCorrection' {
        & $scriptPath -MaxCorrectionSeconds 172800 -Confirm:$false
        Should -Invoke Set-ItemProperty -Times 3 -Exactly  # MaxNeg + MaxPos + Type
    }

    It 'Should set time source to NT5DS for non-PDC DCs' {
        & $scriptPath -Confirm:$false
        Should -Invoke Set-ItemProperty -ParameterFilter {
            $Name -eq 'Type' -and $Value -eq 'NT5DS'
        } -Times 1
    }

    It 'Should set time source to NTP for forest root PDC' {
        & $scriptPath -IsForestRootPDC -Confirm:$false
        Should -Invoke Set-ItemProperty -ParameterFilter {
            $Name -eq 'Type' -and $Value -eq 'NTP'
        } -Times 1
    }

    It 'Should configure NTP server when -IsForestRootPDC is set' {
        & $scriptPath -IsForestRootPDC -NTPServer 'time.windows.com' -Confirm:$false
        Should -Invoke Set-ItemProperty -ParameterFilter {
            $Name -eq 'NtpServer'
        } -Times 1
    }

    It 'Should restart the W32Time service' {
        & $scriptPath -Confirm:$false
        Should -Invoke Stop-Service -Times 1 -Exactly
        Should -Invoke Start-Service -Times 1 -Exactly
    }

    It 'Should not modify anything with -WhatIf' {
        & $scriptPath -WhatIf
        Should -Invoke Set-ItemProperty -Times 0
    }
}
