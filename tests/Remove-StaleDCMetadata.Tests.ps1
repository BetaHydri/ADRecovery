BeforeAll {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue)) {
        New-Module -Name ActiveDirectory -ScriptBlock {
            function Get-ADDomain { }
            function Get-ADForest { }
            function Get-ADDomainController { }
            function Get-ADComputer { }
            function Get-ADObject { }
            function Get-ADRootDSE { }
            function Remove-ADObject { }
            function Move-ADDirectoryServerOperationMasterRole { }
            Export-ModuleMember -Function *
        } | Import-Module -Force
    }
}

Describe 'Remove-StaleDCMetadata.ps1' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'Remove-StaleDCMetadata.ps1'

        Mock Get-ADDomain {
            [PSCustomObject]@{
                DNSRoot               = 'contoso.com'
                DistinguishedName     = 'DC=contoso,DC=com'
                PDCEmulator           = 'DC01.contoso.com'
                RIDMaster             = 'DC01.contoso.com'
                InfrastructureMaster  = 'DC01.contoso.com'
            }
        }
        Mock Get-ADForest {
            [PSCustomObject]@{
                SchemaMaster       = 'DC01.contoso.com'
                DomainNamingMaster = 'DC01.contoso.com'
            }
        }
        Mock Get-ADDomainController {
            @(
                [PSCustomObject]@{ Name = 'DC01'; IPv4Address = '10.0.0.1'; Site = 'Default'; IsGlobalCatalog = $true },
                [PSCustomObject]@{ Name = 'DC02'; IPv4Address = '10.0.0.2'; Site = 'Default'; IsGlobalCatalog = $false }
            )
        }
        Mock Get-ADComputer {
            [PSCustomObject]@{ DistinguishedName = 'CN=DC02,OU=Domain Controllers,DC=contoso,DC=com' }
        }
        Mock Get-ADRootDSE {
            [PSCustomObject]@{ configurationNamingContext = 'CN=Configuration,DC=contoso,DC=com' }
        }
        Mock Get-ADObject {
            [PSCustomObject]@{ DistinguishedName = 'CN=DC02,CN=Servers,CN=Default,CN=Sites,CN=Configuration,DC=contoso,DC=com' }
        }
        Mock Remove-ADObject { }
        Mock Move-ADDirectoryServerOperationMasterRole { }
        Mock Write-Host { }
        Mock Write-Warning { }
        Mock nltest { 'Command completed successfully.' }
    }

    It 'Should query current FSMO role holders' {
        & $scriptPath -SurvivorDCName 'DC01' -DomainFQDN 'contoso.com' -Confirm:$false
        Should -Invoke Get-ADDomain -Times 1 -Exactly
    }

    It 'Should enumerate all domain controllers' {
        & $scriptPath -SurvivorDCName 'DC01' -DomainFQDN 'contoso.com' -Confirm:$false
        Should -Invoke Get-ADDomainController -Times 1 -Exactly
    }

    It 'Should remove stale DC computer accounts' {
        & $scriptPath -SurvivorDCName 'DC01' -DomainFQDN 'contoso.com' -Confirm:$false
        Should -Invoke Remove-ADObject -Times 1 -Exactly
    }
}