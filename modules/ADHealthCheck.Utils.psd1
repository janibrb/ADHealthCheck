#
# Modul-Manifest: ADHealthCheck.Utils.psd1
#
@{
    # Modul-Identität
    ModuleVersion     = '2.1.0'
    GUID              = 'a1b2c3d4-0001-4e5f-8a9b-000000000001'
    Author            = 'LAKE Solutions AG'
    CompanyName       = 'LAKE Solutions AG'
    Copyright         = '(c) 2025 LAKE Solutions AG. All rights reserved.'
    Description       = 'Utility functions for ADHealthCheck: config loading, i18n, logging and HTML helpers.'

    # PowerShell-Anforderungen
    PowerShellVersion = '5.1'

    # Root-Modul
    RootModule        = 'ADHealthCheck.Utils.psm1'

    # Exportierte Funktionen (explizit — kein Wildcard)
    FunctionsToExport = @(
        'Get-ADHCConfig',
        'Get-ADHCI18n',
        'Get-ADHCMapping',
        'Write-ADHCLog',
        'New-HTMLTable'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # Privates Daten / PSGallery-Metadaten
    PrivateData = @{
        PSData = @{
            Tags        = @('ActiveDirectory', 'HealthCheck', 'Utils', 'LAKE')
            ProjectUri  = 'https://github.com/janibrb/ADHealthCheck'
        }
    }
}
