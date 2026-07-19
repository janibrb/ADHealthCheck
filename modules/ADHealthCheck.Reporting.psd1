#
# Modul-Manifest: ADHealthCheck.Reporting.psd1
#
@{
    ModuleVersion     = '2.1.0'
    GUID              = 'a1b2c3d4-0003-4e5f-8a9b-000000000003'
    Author            = 'LAKE Solutions AG'
    CompanyName       = 'LAKE Solutions AG'
    Copyright         = '(c) 2025 LAKE Solutions AG. All rights reserved.'
    Description       = 'HTML report generation and recommendation engine for ADHealthCheck.'

    PowerShellVersion = '5.1'

    RequiredModules   = @(
        @{ ModuleName = 'ADHealthCheck.Utils'; ModuleVersion = '2.1.0' }
    )

    RootModule        = 'ADHealthCheck.Reporting.psm1'

    FunctionsToExport = @(
        'New-ADHCReport'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('ActiveDirectory', 'HealthCheck', 'Reporting', 'HTML', 'LAKE')
            ProjectUri = 'https://github.com/janibrb/ADHealthCheck'
        }
    }
}
