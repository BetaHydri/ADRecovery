BeforeAll {
    if (-not (Get-Command -Name Uninstall-ADDSDomainController -ErrorAction SilentlyContinue)) {
        function global:Uninstall-ADDSDomainController { }
    }
}

Describe 'Repair-USNRollback.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Repair-USNRollback.ps1'

        Mock Uninstall-ADDSDomainController { }
        Mock Write-Host { }
    }

    It 'Should call Uninstall-ADDSDomainController with -ForceRemoval' {
        & $scriptPath -Method ForceDemote -Confirm:$false
        Should -Invoke Uninstall-ADDSDomainController -Times 1 -Exactly -ParameterFilter {
            $ForceRemoval -eq $true -and $DemoteOperationMasterRole -eq $true
        }
    }

    It 'Should not proceed with -WhatIf' {
        & $scriptPath -Method ForceDemote -WhatIf
        Should -Invoke Uninstall-ADDSDomainController -Times 0
    }
}
