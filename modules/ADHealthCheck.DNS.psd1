#
# Modul-Manifest: ADHealthCheck.DNS.psd1
#
@{
    ModuleVersion     = '2.1.0'
    GUID              = 'a1b2c3d4-0004-4e5f-8a9b-000000000004'
    Author            = 'LAKE Solutions AG'
    CompanyName       = 'LAKE Solutions AG'
    Copyright         = '(c) 2025 LAKE Solutions AG. All rights reserved.'
    Description       = 'DNS zone health checks, SRV record validation and nameserver status for ADHealthCheck.'

    PowerShellVersion = '5.1'

    RequiredModules   = @(
        @{ ModuleName = 'ADHealthCheck.Utils'; ModuleVersion = '2.1.0' }
    )

    RootModule        = 'ADHealthCheck.DNS.psm1'

    FunctionsToExport = @(
        'Get-ADDNSHealthStatus'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('ActiveDirectory', 'HealthCheck', 'DNS', 'LAKE')
            ProjectUri = 'https://github.com/janibrb/ADHealthCheck'
        }
    }
}
