#Requires -Module Pester
<#
.SYNOPSIS
    Pester-Tests für ADHealthCheck Module.

.NOTES
    Ausführen:    Invoke-Pester -Path .\tests\pester\ADHealthCheck.Tests.ps1 -Output Detailed
    Voraussetzung: Pester v5+   (Install-Module Pester -Force)
#>

# ---------------------------------------------------------------------------
# Pfade — relativ zur Testdatei, damit CI und lokales Ausführen funktionieren
# ---------------------------------------------------------------------------
$repoRoot   = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$diagPath   = Join-Path $repoRoot "modules\ADHealthCheck.Diag.psm1"
$repPath    = Join-Path $repoRoot "modules\ADHealthCheck.Reporting.psm1"
$i18nDePath = Join-Path $repoRoot "config\i18n.de.json"
$i18nEnPath = Join-Path $repoRoot "config\i18n.en.json"

# ---------------------------------------------------------------------------
# Hilfs-Objekte die mehrere Test-Blöcke brauchen
# ---------------------------------------------------------------------------
$mockSettings = [PSCustomObject]@{
    Thresholds = [PSCustomObject]@{
        InactiveAccountDays      = 90
        DiskFreePercentWarning   = 20
        DiskFreePercentCritical  = 10
        KrbtgtPasswordAgeDays    = 180
    }
    EntraID = [PSCustomObject]@{ ExpectedAgentVersion = "2.4.0.0" }
    Paths   = [PSCustomObject]@{ Output = "$env:TEMP\ADHCTest"; Data = "$env:TEMP\ADHCTest\data" }
    Company = [PSCustomObject]@{ Name = "TestCo"; Address = ""; LogoUrl = "" }
    ShowRecommendations = @{ DNS = $false; Security = $false; FSMO = $false }
}

# ---------------------------------------------------------------------------
BeforeAll {
    # Module laden — korrekte Erweiterung .psm1
    if (Test-Path $diagPath) {
        Import-Module $diagPath -Force -DisableNameChecking
    } else {
        throw "Diag-Modul nicht gefunden: $diagPath"
    }

    if (Test-Path $repPath) {
        Import-Module $repPath -Force -DisableNameChecking
    } else {
        throw "Reporting-Modul nicht gefunden: $repPath"
    }
}

AfterAll {
    Remove-Module ADHealthCheck.Diag      -ErrorAction SilentlyContinue
    Remove-Module ADHealthCheck.Reporting -ErrorAction SilentlyContinue
    if (Test-Path "$env:TEMP\ADHCTest") { Remove-Item "$env:TEMP\ADHCTest" -Recurse -Force }
}

# ===========================================================================
# BLOCK 1: i18n JSON-Dateien
# ===========================================================================
Describe "i18n JSON Struktur" {

    Context "Deutsch (i18n.de.json)" {
        BeforeAll { $script:de = Get-Content $i18nDePath -Raw -Encoding UTF8 | ConvertFrom-Json }

        It "Datei existiert" { Test-Path $i18nDePath | Should -Be $true }
        It "Title vorhanden"                    { $script:de.Title                    | Should -Not -BeNullOrEmpty }
        It "Labels.NoneFound vorhanden"         { $script:de.Labels.NoneFound         | Should -Not -BeNullOrEmpty }
        It "Labels.AllUpToDate vorhanden"       { $script:de.Labels.AllUpToDate       | Should -Not -BeNullOrEmpty }
        It "Labels.AllServersOnline vorhanden"  { $script:de.Labels.AllServersOnline  | Should -Not -BeNullOrEmpty }
        It "Labels.CheckAndClean vorhanden"     { $script:de.Labels.CheckAndClean     | Should -Not -BeNullOrEmpty }
        It "Labels.OUName vorhanden"            { $script:de.Labels.OUName            | Should -Not -BeNullOrEmpty }
        It "Labels.DNPath vorhanden"            { $script:de.Labels.DNPath            | Should -Not -BeNullOrEmpty }
        It "Labels.UserLabel vorhanden"         { $script:de.Labels.UserLabel         | Should -Not -BeNullOrEmpty }
        It "Labels.OrphanedSIDsDetailHeader vorhanden" { $script:de.Labels.OrphanedSIDsDetailHeader | Should -Not -BeNullOrEmpty }
        It "Labels.ScavengingCheckedIn vorhanden"      { $script:de.Labels.ScavengingCheckedIn      | Should -Not -BeNullOrEmpty }
        It "Reasons.Inactive vorhanden"         { $script:de.Reasons.Inactive         | Should -Not -BeNullOrEmpty }
        It "Reasons.Inactive enthält Platzhalter {0}"  { $script:de.Reasons.Inactive  | Should -Match '\{0\}' }
        It "CsvHeaders.Surname vorhanden"       { $script:de.CsvHeaders.Surname       | Should -Not -BeNullOrEmpty }
    }

    Context "Englisch (i18n.en.json)" {
        BeforeAll { $script:en = Get-Content $i18nEnPath -Raw -Encoding UTF8 | ConvertFrom-Json }

        It "Datei existiert" { Test-Path $i18nEnPath | Should -Be $true }
        It "Title vorhanden"                    { $script:en.Title                    | Should -Not -BeNullOrEmpty }
        It "Labels.NoneFound vorhanden"         { $script:en.Labels.NoneFound         | Should -Not -BeNullOrEmpty }
        It "Labels.AllUpToDate vorhanden"       { $script:en.Labels.AllUpToDate       | Should -Not -BeNullOrEmpty }
        It "Labels.AllServersOnline vorhanden"  { $script:en.Labels.AllServersOnline  | Should -Not -BeNullOrEmpty }
        It "Labels.CheckAndClean vorhanden"     { $script:en.Labels.CheckAndClean     | Should -Not -BeNullOrEmpty }
        It "Labels.OUName vorhanden"            { $script:en.Labels.OUName            | Should -Not -BeNullOrEmpty }
        It "Labels.DNPath vorhanden"            { $script:en.Labels.DNPath            | Should -Not -BeNullOrEmpty }
        It "Labels.UserLabel vorhanden"         { $script:en.Labels.UserLabel         | Should -Not -BeNullOrEmpty }
        It "Reasons.Inactive enthält Platzhalter {0}"  { $script:en.Reasons.Inactive  | Should -Match '\{0\}' }
    }

    Context "DE und EN Schlüssel-Parität" {
        BeforeAll {
            $script:deKeys = (Get-Content $i18nDePath -Raw -Encoding UTF8 | ConvertFrom-Json).Labels.PSObject.Properties.Name
            $script:enKeys = (Get-Content $i18nEnPath -Raw -Encoding UTF8 | ConvertFrom-Json).Labels.PSObject.Properties.Name
        }
        It "Alle DE Labels auch in EN vorhanden" {
            $missing = $script:deKeys | Where-Object { $_ -notin $script:enKeys }
            $missing | Should -BeNullOrEmpty -Because "Jeder DE-Label-Key muss auch in EN existieren: $($missing -join ', ')"
        }
    }
}

# ===========================================================================
# BLOCK 2: Get-ADHCMockData
# ===========================================================================
Describe "Get-ADHCMockData" {

    BeforeAll {
        $script:i18n = Get-Content $i18nDePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:mockData = Get-ADHCMockData -I18n $script:i18n -Settings $mockSettings
    }

    It "Gibt ein Objekt zurück"        { $script:mockData        | Should -Not -BeNullOrEmpty }
    It "DomainStats vorhanden"         { $script:mockData.DomainStats   | Should -Not -BeNullOrEmpty }
    It "FSMO vorhanden"                { $script:mockData.FSMO          | Should -Not -BeNullOrEmpty }
    It "Discovery vorhanden"           { $script:mockData.Discovery     | Should -Not -BeNullOrEmpty }
    It "Security vorhanden"            { $script:mockData.Security      | Should -Not -BeNullOrEmpty }
    It "OUAccountSecurity vorhanden"   { $script:mockData.OUAccountSecurity | Should -Not -BeNullOrEmpty }

    It "RawExportData nutzt lokalisierte Spaltenbezeichnungen" {
        $firstRow = $script:mockData.Security.RawExportData | Select-Object -First 1
        $cols = $firstRow.PSObject.Properties.Name
        # Spalten dürfen NICHT hartcodiert Deutsch sein wenn EN geladen wird
        # Mit DE i18n: Spalte heisst "Nachname"
        $cols | Should -Contain $script:i18n.CsvHeaders.Surname
    }
}

# ===========================================================================
# BLOCK 3: Get-ADSecurityInfo — Parameter-Signatur
# ===========================================================================
Describe "Get-ADSecurityInfo Signatur" {

    It "Funktion ist exportiert" {
        Get-Command -Name Get-ADSecurityInfo -Module ADHealthCheck.Diag | Should -Not -BeNullOrEmpty
    }

    It "Besitzt Parameter I18n" {
        $cmd = Get-Command -Name Get-ADSecurityInfo -Module ADHealthCheck.Diag
        $cmd.Parameters.Keys | Should -Contain "I18n"
    }

    It "Besitzt Parameter LangCode" {
        $cmd = Get-Command -Name Get-ADSecurityInfo -Module ADHealthCheck.Diag
        $cmd.Parameters.Keys | Should -Contain "LangCode"
    }

    It "LangCode hat Standardwert 'de'" {
        $cmd = Get-Command -Name Get-ADSecurityInfo -Module ADHealthCheck.Diag
        $cmd.Parameters["LangCode"].DefaultValue | Should -Be "de"
    }
}

# ===========================================================================
# BLOCK 4: Get-ADOUAndAccountSecurity — Async Runspace
# ===========================================================================
Describe "Get-ADOUAndAccountSecurity Async-Parameter" {

    It "Funktion ist exportiert" {
        Get-Command -Name Get-ADOUAndAccountSecurity -Module ADHealthCheck.Diag | Should -Not -BeNullOrEmpty
    }

    It "Besitzt Parameter ProgressCallback" {
        $cmd = Get-Command -Name Get-ADOUAndAccountSecurity -Module ADHealthCheck.Diag
        $cmd.Parameters.Keys | Should -Contain "ProgressCallback"
    }

    It "ProgressCallback ist vom Typ ScriptBlock" {
        $cmd = Get-Command -Name Get-ADOUAndAccountSecurity -Module ADHealthCheck.Diag
        $cmd.Parameters["ProgressCallback"].ParameterType | Should -Be ([scriptblock])
    }
}

# ===========================================================================
# BLOCK 5: Reporting — $htmlOUSec Initialisierung
# ===========================================================================
Describe "New-ADHCReport — htmlOUSec Null-Safety" {

    BeforeAll {
        $script:i18n = Get-Content $i18nDePath -Raw -Encoding UTF8 | ConvertFrom-Json

        # Minimales Template damit New-ADHCReport nicht über fehlendes File crasht
        $tmpDir  = "$env:TEMP\ADHCTestTemplate"
        New-Item $tmpDir -ItemType Directory -Force | Out-Null
        $tplPath = Join-Path $tmpDir "report.template.html"
        @"
<html><head><style>{{CSS_CONTENT}}</style></head>
<body lang='{{LANG_CODE}}'>
{{SECTION_OU_ACCOUNT_SECURITY}}
{{SECTION_DOMAIN_STATS}}{{SECTION_FSMO}}{{SECTION_DCDIAG}}{{SECTION_DCS}}
{{SECTION_BACKUP}}{{SECTION_SERVICES}}{{SECTION_SITES}}{{SECTION_SECURITY}}
{{SECTION_ENTRA}}{{SECTION_DNS}}{{SECTION_RECOMMENDATIONS}}
<footer>{{FOOTER_TEXT}}</footer>
</body></html>
"@ | Out-File $tplPath -Encoding UTF8
        Set-Content (Join-Path $tmpDir "report.style.css") "body{}" -Encoding UTF8

        $script:tplPath = $tplPath

        # Data-Objekt OHNE OUAccountSecurity -> htmlOUSec muss leer sein, kein Crash
        $script:minimalData = @{
            DomainStats        = $null
            FSMO               = $null
            Discovery          = $null
            DCDiag             = @()
            Backup             = $null
            Services           = $null
            Sites              = $null
            Security           = $null
            OUAccountSecurity  = $null   # <-- absichtlich null
            Entra              = $null
            DNS                = $null
        }
    }

    AfterAll {
        Remove-Item "$env:TEMP\ADHCTestTemplate" -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "New-ADHCReport wirft keine Exception wenn OUAccountSecurity null ist" {
        {
            $localSettings = $mockSettings.PSObject.Copy()
            $localSettings | Add-Member -NotePropertyName Paths -NotePropertyValue ([PSCustomObject]@{
                Output = "$env:TEMP\ADHCTest\out"
                Data   = "$env:TEMP\ADHCTest\data"
            }) -Force
            New-Item "$env:TEMP\ADHCTest\out"  -ItemType Directory -Force | Out-Null
            New-Item "$env:TEMP\ADHCTest\data" -ItemType Directory -Force | Out-Null

            New-ADHCReport `
                -Data        $script:minimalData `
                -Settings    $localSettings `
                -I18n        $script:i18n `
                -Mapping     @{} `
                -TemplatePath $script:tplPath `
                -LangCode    "de"
        } | Should -Not -Throw
    }

    It "Generierter Report enthält keinen nicht-ersetzten Platzhalter für OU-Sektion" {
        $localSettings = $mockSettings.PSObject.Copy()
        $localSettings | Add-Member -NotePropertyName Paths -NotePropertyValue ([PSCustomObject]@{
            Output = "$env:TEMP\ADHCTest\out"
            Data   = "$env:TEMP\ADHCTest\data"
        }) -Force

        $htmlFile = New-ADHCReport `
            -Data        $script:minimalData `
            -Settings    $localSettings `
            -I18n        $script:i18n `
            -Mapping     @{} `
            -TemplatePath $script:tplPath `
            -LangCode    "de"

        $content = Get-Content $htmlFile -Raw
        $content | Should -Not -Match '\{\{SECTION_OU_ACCOUNT_SECURITY\}\}'
    }
}

# ===========================================================================
# BLOCK 6: Reporting — HTML-Output enthält keine hartcodierten DE-Strings
# ===========================================================================
Describe "New-ADHCReport — Keine hartcodierten DE-Strings im EN-Modus" {

    BeforeAll {
        $script:i18nEn = Get-Content $i18nEnPath -Raw -Encoding UTF8 | ConvertFrom-Json

        $tmpDir  = "$env:TEMP\ADHCTestTemplateEN"
        New-Item $tmpDir -ItemType Directory -Force | Out-Null
        $tplPath = Join-Path $tmpDir "report.template.html"
        @"
<html><head><style>{{CSS_CONTENT}}</style></head><body lang='{{LANG_CODE}}'>
{{SECTION_SECURITY}}{{SECTION_OU_ACCOUNT_SECURITY}}{{SECTION_DNS}}
{{SECTION_DOMAIN_STATS}}{{SECTION_FSMO}}{{SECTION_DCDIAG}}{{SECTION_DCS}}
{{SECTION_BACKUP}}{{SECTION_SERVICES}}{{SECTION_SITES}}{{SECTION_ENTRA}}
{{SECTION_RECOMMENDATIONS}}<footer>{{FOOTER_TEXT}}</footer></body></html>
"@ | Out-File $tplPath -Encoding UTF8
        Set-Content (Join-Path $tmpDir "report.style.css") "body{}" -Encoding UTF8
        $script:enTplPath = $tplPath

        # Security-Daten mit bekannten Werten: inaktiveCount = 0 -> darf "None found" zeigen
        $script:secData = [PSCustomObject]@{
            InactiveUsers         = 0
            DisabledUsers         = 0
            NoPwdExpiryUsers      = 0
            ExpiredPwdUsers       = 0
            DomAdminCount         = 1
            EntAdminCount         = 1
            SchAdminCount         = 1
            Complexity            = $true
            MinPwdLength          = 10
            MinPwdAge             = 1
            MaxPwdAge             = 90
            PwdHistory            = 10
            LockoutThresh         = 5
            LockoutDuration       = 30
            ResetLockoutCount     = 30
            InactiveThresholdDays = 90
            RawExportData         = @()
        }

        $script:ouData = [PSCustomObject]@{
            UniqueOrphanCount        = 2
            TotalOrphanCount         = 5
            TopOrphanedSIDs          = @([PSCustomObject]@{ Name = "S-1-5-21-999-1"; Count = 3 })
            DisabledInheritanceOU    = @([PSCustomObject]@{ Name = "TestOU"; DN = "OU=TestOU,DC=test,DC=com" })
            DisabledInheritanceUser  = @([PSCustomObject]@{ Name = "TestUser"; DN = "CN=TestUser,DC=test,DC=com" })
        }

        $dataWithSec = @{
            DomainStats       = $null; FSMO = $null; Discovery = $null; DCDiag = @()
            Backup            = $null; Services = $null; Sites = $null
            Security          = $script:secData
            OUAccountSecurity = $script:ouData
            Entra             = $null; DNS = $null
        }

        $localSettings = $mockSettings.PSObject.Copy()
        $localSettings | Add-Member -NotePropertyName Paths -NotePropertyValue ([PSCustomObject]@{
            Output = "$env:TEMP\ADHCTest\out"
            Data   = "$env:TEMP\ADHCTest\data"
        }) -Force
        New-Item "$env:TEMP\ADHCTest\out"  -ItemType Directory -Force | Out-Null
        New-Item "$env:TEMP\ADHCTest\data" -ItemType Directory -Force | Out-Null

        $htmlFile = New-ADHCReport `
            -Data         $dataWithSec `
            -Settings     $localSettings `
            -I18n         $script:i18nEn `
            -Mapping      @{} `
            -TemplatePath $script:enTplPath `
            -LangCode     "en"

        $script:enHtml = Get-Content $htmlFile -Raw
    }

    AfterAll {
        Remove-Item "$env:TEMP\ADHCTestTemplateEN" -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "HTML enthält nicht 'Keine gefunden'" {
        $script:enHtml | Should -Not -Match 'Keine gefunden'
    }
    It "HTML enthält nicht 'Alle aktuell'" {
        $script:enHtml | Should -Not -Match 'Alle aktuell'
    }
    It "HTML enthält nicht 'Prüfen &amp; Bereinigen'" {
        $script:enHtml | Should -Not -Match 'Prüfen'
    }
    It "HTML enthält nicht 'Distinguished Name \(Pfad\)'" {
        $script:enHtml | Should -Not -Match 'Distinguished Name \(Pfad\)'
    }
    It "HTML enthält nicht 'Alle Server online'" {
        $script:enHtml | Should -Not -Match 'Alle Server online'
    }
    It "HTML enthält nicht 'Geprüft in'" {
        $script:enHtml | Should -Not -Match 'Geprüft in'
    }
    It "HTML enthält den erwarteten EN-String 'None found'" {
        $script:enHtml | Should -Match 'None found'
    }
    It "HTML enthält den erwarteten EN-String 'Review'" {
        $script:enHtml | Should -Match 'Review'
    }
}

# ===========================================================================
# BLOCK 6: DNS — Auswahl der Zonen für die Nameserver-Ermittlung
# ===========================================================================
Describe "Select-ADHCNameserverZone" {

    BeforeAll {
        $dnsPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "modules\ADHealthCheck.DNS.psm1"
        if (-not (Test-Path $dnsPath)) { throw "DNS-Modul nicht gefunden: $dnsPath" }
        Import-Module $dnsPath -Force -DisableNameChecking

        $script:allZones = @(
            [PSCustomObject]@{ ZoneName = "contoso.local";            ZoneType = "Primary" }
            [PSCustomObject]@{ ZoneName = "_msdcs.contoso.local";     ZoneType = "Primary" }
            [PSCustomObject]@{ ZoneName = "1.168.192.in-addr.arpa";   ZoneType = "Primary" }
            [PSCustomObject]@{ ZoneName = "TrustAnchors";             ZoneType = "Primary" }
            [PSCustomObject]@{ ZoneName = ".";                        ZoneType = "Primary" }
            [PSCustomObject]@{ ZoneName = "0.in-addr.arpa";           ZoneType = "Primary" }
            [PSCustomObject]@{ ZoneName = "127.in-addr.arpa";         ZoneType = "Primary" }
            [PSCustomObject]@{ ZoneName = "255.in-addr.arpa";         ZoneType = "Primary" }
            [PSCustomObject]@{ ZoneName = "partner.example.com";      ZoneType = "Stub" }
            [PSCustomObject]@{ ZoneName = "extern.example.com";       ZoneType = "Forwarder" }
        )
        $script:selected = @(Select-ADHCNameserverZone -Zone $script:allZones | ForEach-Object { $_.ZoneName })
    }

    AfterAll {
        Remove-Module ADHealthCheck.DNS -ErrorAction SilentlyContinue
    }

    It "schliesst die DNSSEC-Systemzone 'TrustAnchors' aus" {
        $script:selected | Should -Not -Contain "TrustAnchors"
    }
    It "schliesst die Root-Hints-Zone '.' aus" {
        $script:selected | Should -Not -Contain "."
    }
    It "schliesst die automatischen Reverse-Systemzonen aus" {
        $script:selected | Should -Not -Contain "0.in-addr.arpa"
        $script:selected | Should -Not -Contain "127.in-addr.arpa"
        $script:selected | Should -Not -Contain "255.in-addr.arpa"
    }
    It "schliesst Stub- und Forwarder-Zonen aus (NS fremder Server)" {
        $script:selected | Should -Not -Contain "partner.example.com"
        $script:selected | Should -Not -Contain "extern.example.com"
    }
    It "behaelt die echten Domaenen- und Reverse-Zonen" {
        $script:selected | Should -Contain "contoso.local"
        $script:selected | Should -Contain "_msdcs.contoso.local"
        $script:selected | Should -Contain "1.168.192.in-addr.arpa"
    }
    It "ist unabhaengig von der Gross-/Kleinschreibung des Zonennamens" {
        $mixed = @([PSCustomObject]@{ ZoneName = "trustanchors"; ZoneType = "primary" })
        @(Select-ADHCNameserverZone -Zone $mixed) | Should -HaveCount 0
    }
    It "liefert ein leeres Array bei leerer Eingabe" {
        @(Select-ADHCNameserverZone -Zone @()) | Should -HaveCount 0
    }
}

# ===========================================================================
# BLOCK 7: DNS — Trust Anchors als reine Information
# ===========================================================================
Describe "Get-ADHCTrustAnchorInfo" {

    BeforeAll {
        $dnsPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")) "modules\ADHealthCheck.DNS.psm1"
        Import-Module $dnsPath -Force -DisableNameChecking
    }

    AfterAll {
        Remove-Module ADHealthCheck.DNS -ErrorAction SilentlyContinue
    }

    Context "Zone TrustAnchors vorhanden" {
        BeforeAll {
            Mock -CommandName Get-DnsServerResourceRecord -ModuleName ADHealthCheck.DNS -MockWith {
                1..22 | ForEach-Object { [PSCustomObject]@{ RecordType = "NS" } }
            }
            Mock -CommandName Get-DnsServerTrustPoint -ModuleName ADHealthCheck.DNS -MockWith { }
            Mock -CommandName Write-ADHCLog -ModuleName ADHealthCheck.DNS -MockWith { }

            $zones = @(
                [PSCustomObject]@{ ZoneName = "contoso.local"; ZoneType = "Primary"; ReplicationScope = "Domain" }
                [PSCustomObject]@{ ZoneName = "TrustAnchors";  ZoneType = "Primary"; ReplicationScope = "Forest" }
            )
            $script:info = Get-ADHCTrustAnchorInfo -Zone $zones
        }

        It "meldet die Zone als vorhanden" {
            $script:info.ZonePresent | Should -BeTrue
            $script:info.ZoneName    | Should -Be "TrustAnchors"
        }
        It "zaehlt die NS-Records, ohne sie zu pruefen" {
            $script:info.NSRecordCount | Should -Be 22
        }
        It "traegt kein Status- oder Verdikt-Feld" {
            $names = $script:info.PSObject.Properties.Name
            $names | Should -Not -Contain "Status"
            $names | Should -Not -Contain "ICMP"
            $names | Should -Not -Contain "Service"
            $names | Should -Not -Contain "IsSigned"
            $names | Should -Not -Contain "ZoneStatus"
        }
        It "liefert eine leere Trust-Point-Liste, wenn keine konfiguriert sind" {
            @($script:info.TrustPoints) | Should -HaveCount 0
        }
    }

    Context "Weder Zone noch Trust Points vorhanden" {
        BeforeAll {
            Mock -CommandName Get-DnsServerResourceRecord -ModuleName ADHealthCheck.DNS -MockWith { }
            Mock -CommandName Get-DnsServerTrustPoint -ModuleName ADHealthCheck.DNS -MockWith { }
            Mock -CommandName Write-ADHCLog -ModuleName ADHealthCheck.DNS -MockWith { }
        }

        It 'gibt $null zurueck' {
            $zones = @([PSCustomObject]@{ ZoneName = "contoso.local"; ZoneType = "Primary"; ReplicationScope = "Domain" })
            Get-ADHCTrustAnchorInfo -Zone $zones | Should -BeNullOrEmpty
        }
    }

    Context "Trust Points vorhanden" {
        BeforeAll {
            Mock -CommandName Get-DnsServerResourceRecord -ModuleName ADHealthCheck.DNS -MockWith { }
            Mock -CommandName Get-DnsServerTrustPoint -ModuleName ADHealthCheck.DNS -MockWith {
                [PSCustomObject]@{ TrustPointName = "."; TrustPointState = "Valid" }
            }
            Mock -CommandName Get-DnsServerTrustAnchor -ModuleName ADHealthCheck.DNS -MockWith {
                @([PSCustomObject]@{ Type = "DS" }, [PSCustomObject]@{ Type = "DNSKEY" })
            }
            Mock -CommandName Write-ADHCLog -ModuleName ADHealthCheck.DNS -MockWith { }
        }

        It "meldet Trust Points auch ohne die Zone TrustAnchors" {
            $result = Get-ADHCTrustAnchorInfo -Zone @()
            $result                       | Should -Not -BeNullOrEmpty
            $result.ZonePresent           | Should -BeFalse
            @($result.TrustPoints)        | Should -HaveCount 1
            $result.TrustPoints[0].Name   | Should -Be "."
            $result.TrustPoints[0].State  | Should -Be "Valid"
            $result.TrustPoints[0].AnchorCount | Should -Be 2
        }
    }
}
