BeforeAll {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
        New-Module -Name ActiveDirectory -ScriptBlock {
            function Get-ADDomain { }
            function Get-ADDomainController { }
            Export-ModuleMember -Function *
        } | Import-Module -Force
    }
}

Describe 'Find-AuthoritativeDC.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Find-AuthoritativeDC.ps1'

        Mock Get-ADDomain {
            [PSCustomObject]@{
                DNSRoot             = 'contoso.com'
                DistinguishedName   = 'DC=contoso,DC=com'
                PDCEmulator         = 'DC01.contoso.com'
            }
        }

        Mock Get-ADDomainController {
            @(
                [PSCustomObject]@{ HostName = 'DC01.contoso.com' },
                [PSCustomObject]@{ HostName = 'DC02.contoso.com' },
                [PSCustomObject]@{ HostName = 'DC03.contoso.com' }
            )
        }

        Mock Get-Service {
            [PSCustomObject]@{ Status = 'Running' }
        }

        Mock Test-Path { $true }

        Mock Get-ChildItem {
            @(
                [PSCustomObject]@{ Length = 1024; LastWriteTime = (Get-Date '2026-03-20 10:00:00') },
                [PSCustomObject]@{ Length = 2048; LastWriteTime = (Get-Date '2026-03-24 14:30:00') },
                [PSCustomObject]@{ Length = 512;  LastWriteTime = (Get-Date '2026-03-22 08:15:00') }
            )
        }

        Mock Write-Host { }
    }

    It 'Should query all Domain Controllers' {
        & $scriptPath
        Should -Invoke Get-ADDomainController -Times 1 -Exactly
    }

    It 'Should check DFSR service on each DC' {
        & $scriptPath
        Should -Invoke Get-Service -Times 3 -Exactly
    }

    It 'Should test SYSVOL path accessibility for each DC' {
        & $scriptPath
        Should -Invoke Test-Path -Times 3 -Exactly
    }

    It 'Should enumerate SYSVOL content for reachable DCs' {
        & $scriptPath
        Should -Invoke Get-ChildItem -Times 3 -Exactly
    }

    It 'Should return results for all DCs' {
        $output = & $scriptPath
        $output.Count | Should -Be 3
    }

    It 'Should rank PDC Emulator highest when all else is equal' {
        $output = & $scriptPath
        $output[0].DC | Should -Be 'DC01.contoso.com'
        $output[0].IsPDCEmulator | Should -BeTrue
    }

    It 'Should report DFSR service status' {
        $output = & $scriptPath
        $output | ForEach-Object {
            $_.DFSRService | Should -Be 'Running'
        }
    }

    It 'Should compute file count and total size' {
        $output = & $scriptPath
        $output[0].PolicyFiles | Should -Be 3
        $output[0].TotalSizeKB | Should -BeGreaterThan 0
    }

    It 'Should handle unreachable SYSVOL gracefully' {
        Mock Test-Path { $false }
        Mock Get-ChildItem { }
        $output = & $scriptPath
        $output | ForEach-Object {
            $_.SYSVOLReachable | Should -BeFalse
            $_.PolicyFiles     | Should -Be 0
        }
    }

    It 'Should handle DFSR service query failure gracefully' {
        Mock Get-Service { throw 'RPC unavailable' }
        $output = & $scriptPath
        $output | ForEach-Object {
            $_.DFSRService | Should -Be 'Unknown'
        }
    }

    It 'Should accept DomainFQDN parameter' {
        $output = & $scriptPath -DomainFQDN 'contoso.com'
        $output.Count | Should -Be 3
    }
}
