#
# Modul-Manifest: ADHealthCheck.EntraSync.psd1
#
@{
    ModuleVersion     = '2.1.0'
    GUID              = 'a1b2c3d4-0005-4e5f-8a9b-000000000005'
    Author            = 'LAKE Solutions AG'
    CompanyName       = 'LAKE Solutions AG'
    Copyright         = '(c) 2025 LAKE Solutions AG. All rights reserved.'
    Description       = 'Entra ID / Azure AD Connect sync status checks for ADHealthCheck.'

    PowerShellVersion = '5.1'

    RequiredModules   = @(
        @{ ModuleName = 'ADHealthCheck.Utils'; ModuleVersion = '2.1.0' }
    )

    RootModule        = 'ADHealthCheck.EntraSync.psm1'

    FunctionsToExport = @(
        'Get-EntraSyncStatus'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('ActiveDirectory', 'HealthCheck', 'EntraID', 'AzureAD', 'LAKE')
            ProjectUri = 'https://github.com/janibrb/ADHealthCheck'
        }
    }
}
