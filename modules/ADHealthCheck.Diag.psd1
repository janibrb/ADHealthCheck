#
# Modul-Manifest: ADHealthCheck.Diag.psd1
#
@{
    ModuleVersion     = '2.1.0'
    GUID              = 'a1b2c3d4-0002-4e5f-8a9b-000000000002'
    Author            = 'LAKE Solutions AG'
    CompanyName       = 'LAKE Solutions AG'
    Copyright         = '(c) 2025 LAKE Solutions AG. All rights reserved.'
    Description       = 'AD diagnostics: DC discovery, DCDIAG, security analysis, FSMO, sites, backup, ACL audit.'

    PowerShellVersion = '5.1'

    # Abhängigkeit: Utils muss zuerst geladen sein (Write-ADHCLog)
    RequiredModules   = @(
        @{ ModuleName = 'ADHealthCheck.Utils'; ModuleVersion = '2.1.0' }
    )

    RootModule        = 'ADHealthCheck.Diag.psm1'

    FunctionsToExport = @(
        'Get-ADHealthDiscovery',
        'Get-ADServiceStatus',
        'Invoke-DetailedDcdiag',
        'Get-ADSecurityInfo',
        'Get-ADFSMORoles',
        'Get-ADDomainStats',
        'Get-ADSitesInfo',
        'Get-ADBackupStatus',
        'Get-ADOUAndAccountSecurity',
        'Get-ADHCMockData'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('ActiveDirectory', 'HealthCheck', 'Diagnostics', 'LAKE')
            ProjectUri = 'https://github.com/janibrb/ADHealthCheck'
        }
    }
}
