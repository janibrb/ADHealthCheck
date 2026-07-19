<#
.SYNOPSIS
    Haupt-Launcher fuer AD Health Check mit GUI

.NOTES
    Version:    2.7.1
    Changelog:  - FIX: AffectedItems war im JSON mal ein Array, mal ein String. Der
                  Rueckgabewert eines if-Blocks wird von PowerShell ENUMERIERT —
                  einelementige Arrays wurden dabei zum Skalar. Ein Befund mit zwei
                  Servern kam als ["a","b"], einer mit einem Server als "a".
                  Konsumenten mussten beide Typen behandeln. Jetzt typisierte
                  Zuweisung vor dem Objektbau.
                - FIX: REP-01 prueft jetzt ALLE Partitionen (-PartitionFilter *).
                  Ohne den Parameter liefert Get-ADReplicationPartnerMetadata nur
                  die Standard-Partition; Replikationsprobleme auf Configuration,
                  Schema, ForestDnsZones und DomainDnsZones blieben unsichtbar.
                  Im Feldtest kam pro DC genau EIN Eintrag statt fuenf.
                - FEAT: Messwerte fuer AD-01 bis AD-04 und SEC-07 bis SEC-09
                  nachgezogen. Bei AD-04 ist der Messwert das ALTER in Tagen, nicht
                  der abgeleitete Status: ein 9 Jahre altes KRBTGT-Kennwort und ein
                  181 Tage altes liefern denselben Status, aber sehr
                  unterschiedlichen Handlungsdruck.
                - FEAT: PASS-Verdikte tragen jetzt ihren MESSWERT. Bisher kam
                  ActualValue nur aus dem gefeuerten Befund — bei PASS war das Feld
                  leer und damit nicht von einer Pruefung zu unterscheiden, die gar
                  nichts gemessen hatte. Genau diese Verwechslung trat im Feldtest
                  auf: EVT-01 meldete zweimal exakt dasselbe JSON, einmal weil ein DC
                  uebersprungen wurde und einmal weil alles in Ordnung war.
                  Neu belegt ein PASS die Messung:
                    EVT-01 PASS -> ActualValue 87 Days   (kuerzeste Vorhaltedauer)
                    EVT-02 PASS -> ActualValue 0 Logs    (nicht lesbare Logs)
                    REP-01 PASS -> ActualValue 31 Minutes (hoechste Latenz)
                  Ein leeres ActualValue bei PASS ist damit ein Warnsignal statt
                  Normalzustand. Umgesetzt fuer Replication, EventLog,
                  Kennwortrichtlinien und die Security-Zaehler.
                - FIX: REP-01 und EVT-01 meldeten PASS, wenn ein DC gar nicht
                  gepruefte werden konnte. Der Collector setzt bei einem Fehler
                  Status="Unreachable", die Condition beider Regeln lautete aber
                  nur ["Error"] — nicht pruefbare DCs wurden stillschweigend
                  uebersprungen. Im ersten Feldtest lieferte EVT-01 dadurch PASS,
                  obwohl einer von zwei DCs nie erreicht wurde.
                  Neu: REP-02 und EVT-02 (Medium) melden explizit, dass fuer einen
                  DC KEINE Aussage vorliegt — bewusst als eigene Regeln, damit
                  "nicht pruefbar" nicht mit "geprueft und zu kurz" vermischt wird.
                - PERF: Schlaegt der erste Log-Zugriff auf einem DC am RPC fehl,
                  werden die restlichen Logs desselben DCs uebersprungen. Jeder
                  Versuch kostet rund 20 Sekunden Timeout; bisher liefen sie alle.
                - FIX: Fehlermeldung nennt jetzt die Ursache — bei RPC-Fehlern die
                  Firewall-Regel "Remote-Ereignisprotokollverwaltung", bei
                  Zugriffsfehlern die Gruppe "Ereignisprotokollleser".
                - FEAT: Zwei neue Pruefungen — die bisher toten Config-Werte
                  ReplicationLatencyMaxMinutes und MaxEventLogAgeDays sind jetzt
                  wirksam:
                  * REP-01 (High): Replikations-Latenz je DC und Partner ueber
                    Get-ADReplicationPartnerMetadata. Bewertet wird die Zeit seit
                    der letzten ERFOLGREICHEN Replikation gegen den Grenzwert.
                  * EVT-01 (Medium): Vorhaltedauer der Ereignisprotokolle
                    ("Directory Service" und "System"). ACHTUNG zur Auslegung:
                    geprueft wird, wie weit ein Log ZURUECKREICHT — reicht es
                    weniger weit als MaxEventLogAgeDays, ist es zu klein bzw.
                    rotiert zu schnell fuer eine Vorfallanalyse.
                  Damit 71 Regeln. Beide neuen Bereiche haben eigene GUI-Auswahl
                  und laufen im NoGui-Modus mit.
                - FIX: Tooltip der KRBTGT-Kachel war hartcodiert deutsch
                  ("Alter: N Tage") und erschien so auch im englischen Report.
                - FEAT: Upload-JSON schemaVersion 2 — Verdikte tragen jetzt MESSWERTE
                  statt nur einen fertig gerenderten Satz: ActualValue, Unit (als
                  i18n-Schluessel, nicht als uebersetztes Wort), AffectedItems,
                  ExpectedValue und Operator. Ein Dashboard kann damit "6 Zeichen
                  (empfohlen: >=12)" in eigener Sprache rendern und Werte ueber die
                  Zeit vergleichen. Rein additiv — Konsumenten von schemaVersion 1
                  laufen unveraendert weiter.
                - FEAT: Schwellenwerte liegen in recommendations.json ("Threshold":
                  value/operator/unit) statt als Literale im PowerShell-Code. Neun
                  Regeln sind damit ohne Codeaenderung tunebar.
                - FEAT: Der HTML-Report zeigt den Sollwert an ("empfohlen: >=12
                  Zeichen" / "recommended: >=12 characters"), gerendert an EINER
                  Stelle aus denselben strukturierten Feldern.
                - FIX: Die KRBTGT-Regel respektiert jetzt Thresholds.KrbtgtPasswordAgeDays
                  aus settings.json. Vorher stand dort fest 180, waehrend die
                  Kachel-Anzeige die Einstellung bereits auswertete — beide liefen
                  auseinander, sobald ein Kunde den Wert anpasste.
                - FIX: Die letzten drei nicht feuernden Regeln repariert:
                  * SITE-03 (Aenderungsbenachrichtigung): hatte ueberhaupt keinen
                    Auswertungscode. Das Feld liefert Get-ADSitesInfo seit jeher.
                  * AD-FSMO-08 (Infrastruktur-Master ist GC): las IsGC aus
                    $Data.Discovery, das dieses Feld nicht fuehrt. Kommt aus
                    $Data.Sites.Sites[].Servers[].
                  * SRV-02 (DC-Erreichbarkeit): Code war korrekt, die Mock-Daten
                    setzten Status="Error" ohne OS="Unreachable".
                  Damit feuern bei Worst-Case-Mockdaten 67 von 69 Regeln; die
                  restlichen zwei (DNS-01, SITE-05) sind bewusst inaktiv, weil sie
                  sich mit DNS-06 bzw. SITE-02 gegenseitig ausschliessen.
                - FIX: Fuenf Empfehlungsregeln haben NIE gefeuert und meldeten auch im
                  Fehlerfall PASS:
                  * PWD-04 (Sperrschwelle): Switch-Label hiess "LockoutThreshold",
                    Collector und recommendations.json liefern aber "LockoutThresh".
                    Bei komplett deaktivierter Kontosperre (Threshold=0) meldete der
                    Report "bestanden".
                  * SVC-NTDS / SVC-NET / SVC-DNS / SVC-KDC: die Auswertung erwartete
                    $entry.Details mit .ServiceName; Get-ADServiceStatus liefert aber
                    eine flache Liste mit .Service. Ein gestoppter NTDS-Dienst blieb
                    unsichtbar.
                - FIX: Sample-Reports neu erzeugt (enthielten ENT-01 nicht und keine
                  der fuenf reparierten Regeln).
                - FIX: Get-Content ohne -Encoding UTF8 in den Config-Loadern (Utils.psm1:
                  Config, i18n, Mapping) und beim Laden von Template/CSS. PS 5.1 nutzt
                  ohne den Parameter die System-ANSI-Codepage; da die config/*.json
                  BOM-frei sind, wurde daraus auf CP1252-Servern "KennwÃ¶rter" statt
                  "Kennwörter" — der Mojibake landete direkt im Kundenreport.
                - FIX: 9 hartcodierte deutsche Strings im Report lokalisiert. Der
                  englische Report enthielt u.a. "Betroffene Server" (18x), "Partitionen",
                  "Vorkommen", "Benutzer" und "Distinguished Name (Pfad)".
                - FIX: Tippfehler "Recommandation" -> "Recommendation" (i18n.en.json).
                - FIX: UTF-8-BOM auf ALLE PowerShell-Dateien ausgeweitet. Der v2.4.4-Fix
                  betraf nur Reporting.psm1; Diag.psm1, Utils.psm1, Update-EntraVersion.ps1
                  und drei .psd1 blieben BOM-los. Auf ANSI-CP1252-Servern wurden dort
                  Umlaute verfaelscht — u.a. in den i18n-Fallbacks "Passwort laeuft nie
                  ab" / "Passwort aelter als Richtlinie", die im Report/CSV landen.
                - DOC: Kommentare im Reporting-Modul korrigiert — das Upload-JSON wurde
                  als "ohne PII" beschrieben, enthaelt seit v2.4.6 aber wieder
                  Klarnamen und DNs (DisabledInheritanceUser, erste 50 Eintraege).
                - FIX: Self-Update loeste nie aus — die Header-Version (Single Source of
                  Truth fuer den Vergleich) stand auf 2.4.5, waehrend $script:LocalVersion
                  bereits 2.4.6 war. LocalVersion wird jetzt aus dem Header abgeleitet,
                  ein Auseinanderlaufen ist konstruktiv ausgeschlossen.
                - FIX: Reporting.psm1 mit UTF-8-BOM (PS5.1 las BOM-lose UTF-8 auf ANSI-CP1252-
                  Servern falsch -> "Missing closing '}'"-Ladefehler)
                - Self-Update haertet ab: Temp-Download + Syntax/JSON-Validierung + atomarer Move
                  (verhindert korrupte/abgeschnittene Dateien bei flaky Netzwerk)
                - HTML-Report zeigt den eindeutigen Title je Regel (statt SubCategory)
                - Kuratierte, zweisprachige Title{de,en} je Regel (recommendations.json)
                - Fixing Update Routine
				- Self-Update: automatischer Versionscheck gegen GitHub
                - Download aller Dateien mit Backup der alten Version
                - Prereq-Check aus v2.2.0
                - Alle bisherigen Fixes aus v2.1.0
#>

param(
    [switch]$NoGui,
    [string]$Language = "de"
)

# ---------------------------------------------------------------------------
# Pfade & Setup
# ---------------------------------------------------------------------------
$ScriptRoot  = $PSScriptRoot
$OutputPath  = Join-Path $PSScriptRoot "output"
$ModulePath  = Join-Path $ScriptRoot "modules"

$script:UseMockData = $false

# ===========================================================================
# PREREQUISITE-CHECK
# Prüft alle Abhängigkeiten VOR dem Laden der Module.
# Fehlende optionale Features können direkt installiert werden.
# ===========================================================================
function Test-ADHCPrerequisites {

    # Hilfsfunktion: farbige Statuszeile
    function Write-CheckResult {
        param([string]$Label, [string]$Status, [string]$Detail = "")
        $color = switch ($Status) {
            "OK"      { "Green"  }
            "WARN"    { "Yellow" }
            "FEHLER"  { "Red"    }
            default   { "White"  }
        }
        $padLabel = $Label.PadRight(45, '.')
        Write-Host "  $padLabel " -NoNewline
        Write-Host "[$Status]" -ForegroundColor $color -NoNewline
        if ($Detail) { Write-Host "  $Detail" -ForegroundColor Gray } else { Write-Host "" }
    }

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║     ADHealthCheck — Systemvoraussetzungen        ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    $allCriticalOk = $true
    $installQueue  = @()   # Sammelt Features die installiert werden sollen

    # -------------------------------------------------------------------
    # 1. ADMINISTRATOR-RECHTE (Kritisch — ohne Admin kein AD-Zugriff)
    # -------------------------------------------------------------------
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                 [Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-CheckResult "Administrator-Rechte" "OK"
    } else {
        Write-CheckResult "Administrator-Rechte" "FEHLER" "Skript muss als Administrator ausgefuehrt werden"
        Write-Host ""
        Write-Host "  ABBRUCH: Bitte PowerShell als Administrator starten und erneut ausfuehren." -ForegroundColor Red
        Write-Host "  Tipp: Rechtsklick auf PowerShell -> 'Als Administrator ausfuehren'" -ForegroundColor Yellow
        Write-Host ""
        Read-Host "  Enter druecken zum Beenden"
        exit 1
    }

    # -------------------------------------------------------------------
    # 2. POWERSHELL-VERSION (Kritisch — min. 5.1 Desktop)
    # -------------------------------------------------------------------
    $psVer   = $PSVersionTable.PSVersion
    $psEditionVal = $PSVersionTable.PSEdition
    $psOk    = ($psVer.Major -gt 5) -or ($psVer.Major -eq 5 -and $psVer.Minor -ge 1)
    $psCore  = ($psEditionVal -eq "Core")   # PS Core (6+) wird nicht unterstützt (WinForms!)

    if ($psCore) {
        Write-CheckResult "PowerShell-Version" "FEHLER" "PowerShell Core $psVer nicht unterstuetzt — benoetigt Desktop 5.1"
        Write-Host ""
        Write-Host "  ABBRUCH: Bitte Windows PowerShell 5.1 (nicht PowerShell Core/7) verwenden." -ForegroundColor Red
        Write-Host ""
        Read-Host "  Enter druecken zum Beenden"
        exit 1
    } elseif ($psOk) {
        Write-CheckResult "PowerShell-Version" "OK" "v$psVer (Desktop)"
    } else {
        Write-CheckResult "PowerShell-Version" "FEHLER" "v$psVer gefunden — benoetigt >= 5.1"
        $allCriticalOk = $false
    }

    # -------------------------------------------------------------------
    # 3. .NET FRAMEWORK (Kritisch — WinForms benötigt .NET 4.5+)
    # -------------------------------------------------------------------
    try {
        $dotnetKey = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction Stop
        $release   = $dotnetKey.Release
        # Release 379893 = .NET 4.5.2 / 528040 = .NET 4.8
        if ($release -ge 379893) {
            $dotnetVer = switch ($true) {
                ($release -ge 528040) { "4.8" }
                ($release -ge 461808) { "4.7.2" }
                ($release -ge 460798) { "4.7" }
                ($release -ge 394802) { "4.6.2" }
                ($release -ge 379893) { "4.5.2" }
                default               { "4.x" }
            }
            Write-CheckResult ".NET Framework" "OK" "v$dotnetVer"
        } else {
            Write-CheckResult ".NET Framework" "FEHLER" "v4.5+ benoetigt (Release $release gefunden)"
            $allCriticalOk = $false
        }
    } catch {
        Write-CheckResult ".NET Framework" "WARN" ".NET 4.x Registry-Key nicht gefunden"
    }

    # -------------------------------------------------------------------
    # 4. RSAT: ActiveDirectory-Modul (Kritisch — Kernfunktion)
    # -------------------------------------------------------------------
    $adModAvail = Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue
    if ($adModAvail) {
        Write-CheckResult "RSAT: ActiveDirectory-Modul" "OK" "v$($adModAvail[0].Version)"
    } else {
        Write-CheckResult "RSAT: ActiveDirectory-Modul" "FEHLER" "Nicht installiert — benoetigt fuer alle AD-Abfragen"
        $allCriticalOk = $false
        $installQueue += [PSCustomObject]@{
            Name        = "RSAT: ActiveDirectory-Modul"
            Critical    = $true
            InstallCmd  = {
                $osInfo = Get-WmiObject Win32_OperatingSystem
                if ($osInfo.ProductType -eq 1) {
                    # Windows 10/11 Client
                    if (Get-Command Add-WindowsCapability -ErrorAction SilentlyContinue) {
                        Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -ErrorAction Stop
                    } else {
                        throw "Add-WindowsCapability nicht verfuegbar. Bitte RSAT manuell installieren."
                    }
                } else {
                    # Windows Server
                    Install-WindowsFeature RSAT-AD-PowerShell -ErrorAction Stop
                }
            }
        }
    }

    # -------------------------------------------------------------------
    # 5. RSAT: DNS-Server-Tools (Optional — nur fuer DNS-Sektion)
    # -------------------------------------------------------------------
    $dnsModAvail = Get-Module -ListAvailable -Name DnsServer -ErrorAction SilentlyContinue
    if ($dnsModAvail) {
        Write-CheckResult "RSAT: DNS-Server-Tools" "OK" "v$($dnsModAvail[0].Version)"
    } else {
        Write-CheckResult "RSAT: DNS-Server-Tools" "WARN" "Nicht installiert — DNS-Analyse wird deaktiviert"
        $installQueue += [PSCustomObject]@{
            Name        = "RSAT: DNS-Server-Tools"
            Critical    = $false
            InstallCmd  = {
                $osInfo = Get-WmiObject Win32_OperatingSystem
                if ($osInfo.ProductType -eq 1) {
                    Add-WindowsCapability -Online -Name "Rsat.Dns.Tools~~~~0.0.1.0" -ErrorAction Stop
                } else {
                    Install-WindowsFeature RSAT-DNS-Server -ErrorAction Stop
                }
            }
        }
    }

    # -------------------------------------------------------------------
    # 6. RSAT: GroupPolicy-Tools (Optional — für GPO-Checks, zukünftig)
    # -------------------------------------------------------------------
    $gpModAvail = Get-Module -ListAvailable -Name GroupPolicy -ErrorAction SilentlyContinue
    if ($gpModAvail) {
        Write-CheckResult "RSAT: GroupPolicy-Tools" "OK" "v$($gpModAvail[0].Version)"
    } else {
        Write-CheckResult "RSAT: GroupPolicy-Tools" "WARN" "Nicht installiert — GPO-Analyse nicht verfuegbar"
        $installQueue += [PSCustomObject]@{
            Name        = "RSAT: GroupPolicy-Tools"
            Critical    = $false
            InstallCmd  = {
                $osInfo = Get-WmiObject Win32_OperatingSystem
                if ($osInfo.ProductType -eq 1) {
                    Add-WindowsCapability -Online -Name "Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0" -ErrorAction Stop
                } else {
                    Install-WindowsFeature GPMC -ErrorAction Stop
                }
            }
        }
    }

    # -------------------------------------------------------------------
    # 7. WinRM (Optional — für Remote-Abfragen zu DCs und Entra-Server)
    # -------------------------------------------------------------------
    try {
        $winrmSvc = Get-Service WinRM -ErrorAction Stop
        if ($winrmSvc.Status -eq "Running") {
            Write-CheckResult "WinRM-Dienst" "OK" "Gestartet"
        } else {
            Write-CheckResult "WinRM-Dienst" "WARN" "Gestoppt — Remote-Abfragen (Entra-Check) beeintraechtigt"
            $installQueue += [PSCustomObject]@{
                Name       = "WinRM aktivieren"
                Critical   = $false
                InstallCmd = { Enable-PSRemoting -Force -ErrorAction Stop }
            }
        }
    } catch {
        Write-CheckResult "WinRM-Dienst" "WARN" "Status konnte nicht ermittelt werden"
    }

    # -------------------------------------------------------------------
    # 8. Ausführungsrichtlinie (Warnung wenn zu restriktiv)
    # -------------------------------------------------------------------
    $execPolicy = Get-ExecutionPolicy -Scope Process
    $effPolicy  = Get-ExecutionPolicy
    if ($effPolicy -in @("Restricted", "AllSigned")) {
        Write-CheckResult "Ausfuehrungsrichtlinie" "WARN" "$effPolicy — Skript-Ausfuehrung evtl. eingeschraenkt"
    } else {
        Write-CheckResult "Ausfuehrungsrichtlinie" "OK" "$effPolicy"
    }

    # -------------------------------------------------------------------
    # 9. Netzwerk / AD-Erreichbarkeit
    # -------------------------------------------------------------------
    try {
        $domainObj = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
        Write-CheckResult "AD-Domaene erreichbar" "OK" $domainObj.Name
    } catch {
        Write-CheckResult "AD-Domaene erreichbar" "WARN" "Keine Domäne gefunden oder nicht erreichbar"
    }

    # -------------------------------------------------------------------
    # INSTALLATIONS-DIALOG
    # -------------------------------------------------------------------
    Write-Host ""

    if ($installQueue.Count -gt 0) {
        $criticalMissing  = $installQueue | Where-Object { $_.Critical }
        $optionalMissing  = $installQueue | Where-Object { -not $_.Critical }

        if ($criticalMissing) {
            Write-Host "  ┌─ KRITISCHE ABHÄNGIGKEITEN FEHLEN ─────────────────────┐" -ForegroundColor Red
            foreach ($item in $criticalMissing) {
                Write-Host "  │  • $($item.Name)" -ForegroundColor Red
            }
            Write-Host "  └───────────────────────────────────────────────────────┘" -ForegroundColor Red
            Write-Host ""
        }

        if ($optionalMissing) {
            Write-Host "  ┌─ OPTIONALE FEATURES FEHLEN ────────────────────────────┐" -ForegroundColor Yellow
            foreach ($item in $optionalMissing) {
                Write-Host "  │  • $($item.Name)" -ForegroundColor Yellow
            }
            Write-Host "  └────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
            Write-Host ""
        }

        # Interaktive Abfrage
        $toInstall = @()
        foreach ($item in $installQueue) {
            $label   = if ($item.Critical) { "[KRITISCH]" } else { "[Optional]" }
            $color   = if ($item.Critical) { "Red" }        else { "Yellow" }
            Write-Host "  $label " -ForegroundColor $color -NoNewline
            Write-Host "$($item.Name) installieren?" -NoNewline
            Write-Host " [J/N]: " -NoNewline -ForegroundColor Cyan
            $answer = Read-Host
            if ($answer -match '^[JjYy]') {
                $toInstall += $item
            }
        }

        # Installation durchführen
        if ($toInstall.Count -gt 0) {
            Write-Host ""
            Write-Host "  Installiere fehlende Features..." -ForegroundColor Cyan

            $installErrors = @()
            foreach ($item in $toInstall) {
                Write-Host "  ► $($item.Name)..." -NoNewline
                try {
                    & $item.InstallCmd
                    Write-Host " OK" -ForegroundColor Green
                } catch {
                    Write-Host " FEHLER: $($_.Exception.Message)" -ForegroundColor Red
                    $installErrors += $item.Name
                }
            }

            if ($installErrors.Count -gt 0) {
                Write-Host ""
                Write-Host "  Folgende Features konnten nicht installiert werden:" -ForegroundColor Red
                $installErrors | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
            }

            # Nach Installation: kritische Module erneut prüfen
            $stillMissingCritical = $toInstall | Where-Object {
                $_.Critical -and -not (Get-Module -ListAvailable -Name ActiveDirectory -EA SilentlyContinue)
            }

            if ($stillMissingCritical) {
                Write-Host ""
                Write-Host "  ABBRUCH: Kritische Module sind nach der Installation immer noch nicht verfuegbar." -ForegroundColor Red
                Write-Host "  Bitte System neu starten und Skript erneut ausfuehren." -ForegroundColor Yellow
                Write-Host ""
                Read-Host "  Enter druecken zum Beenden"
                exit 1
            }

            Write-Host ""
            Write-Host "  Installation abgeschlossen. Starte ADHealthCheck..." -ForegroundColor Green
            Write-Host ""
        } elseif ($criticalMissing) {
            # Kritische Features abgelehnt -> Abbruch
            Write-Host ""
            Write-Host "  ABBRUCH: Ohne die kritischen Abhängigkeiten kann ADHealthCheck nicht gestartet werden." -ForegroundColor Red
            Write-Host ""
            Read-Host "  Enter druecken zum Beenden"
            exit 1
        } else {
            # Nur optionale abgelehnt -> Warnung aber weiter
            Write-Host "  Optionale Features wurden nicht installiert. Betroffene Sektionen werden deaktiviert." -ForegroundColor Yellow
            Write-Host ""
        }
    } else {
        Write-Host "  Alle Voraussetzungen erfuellt. Starte ADHealthCheck..." -ForegroundColor Green
        Write-Host ""
        Start-Sleep -Milliseconds 800
    }

    # Rückgabe: DNS-Modul verfügbar?
    return @{
        DNSModuleAvailable = [bool](Get-Module -ListAvailable -Name DnsServer -EA SilentlyContinue)
        GPOModuleAvailable = [bool](Get-Module -ListAvailable -Name GroupPolicy -EA SilentlyContinue)
    }
}

# Prereq-Check ausführen (gibt Feature-Status zurück)
$prereqResult = Test-ADHCPrerequisites

# ===========================================================================
# SELF-UPDATE CHECK
# Vergleicht lokale Version mit der aktuellen Version auf GitHub.
# Bei neuer Version: Download aller geänderten Dateien mit Bestätigung.
# ===========================================================================

# Versions-Regex — EINE Definition fuer die lokale UND die entfernte Seite.
# So kann der Vergleich nicht mehr auseinanderlaufen.
$script:VersionPattern = 'Version:\s+([\d]+\.[\d]+\.[\d]+)'

# Aktuelle lokale Version — wird aus dem .NOTES-Header dieses Scripts (Zeile 6)
# abgeleitet. Der Header ist damit die EINZIGE Stelle, an der die Version beim
# Release gepflegt werden muss. Frueher stand die Nummer zusaetzlich hier als
# Literal, was beim Bump auf 2.4.6 vergessen wurde -> Remote meldete 2.4.5
# gegen lokal 2.4.6 und der Self-Update loeste nie aus.
# Nur die ersten 20 Zeilen lesen: das ist der Header-Block und verhindert,
# dass eine spaetere Fundstelle im Code faelschlich greift.
$script:LocalVersion = $null
if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
    try {
        $ownHeader = Get-Content -LiteralPath $PSCommandPath -TotalCount 20 `
                        -Encoding UTF8 -ErrorAction Stop
        if (($ownHeader -join "`n") -match $script:VersionPattern) {
            $script:LocalVersion = $Matches[1]
        }
    } catch {
        # Bleibt $null -> Update-Check meldet das sauber und ueberspringt.
    }
}

# GitHub Repository-Konfiguration
$script:GitHubUser   = "janibrb"
$script:GitHubRepo   = "ADHealthCheck"
$script:GitHubBranch = "main"
$script:GitHubRaw    = "https://raw.githubusercontent.com/$script:GitHubUser/$script:GitHubRepo/$script:GitHubBranch"

function Invoke-ADHCUpdateCheck {
    param(
        [string]$ScriptRoot,
        [int]$TimeoutSec = 10
    )

    Write-Host ""
    Write-Host "  Prüfe auf Updates (GitHub)..." -ForegroundColor Cyan -NoNewline

    try {
        # Version aus dem Remote-Launcher lesen
        $remoteUrl = "$script:GitHubRaw/ADHealthCheck.ps1"

        if (-not $script:GitHubRaw) {
            Write-Host " Konfigurationsfehler (GitHubRaw leer)." -ForegroundColor Red
            return
        }

        # Ohne bekannte lokale Version ist kein Vergleich moeglich. Lieber
        # ueberspringen als blind ein Update anbieten (oder unterdruecken).
        if (-not $script:LocalVersion) {
            Write-Host " Lokale Version nicht lesbar (Header)." -ForegroundColor Yellow
            return
        }

        $remoteContent = Invoke-WebRequest -Uri $remoteUrl -UseBasicParsing `
                            -TimeoutSec $TimeoutSec -ErrorAction Stop

        # Versionsnummer aus Header extrahieren: "Version:    x.y.z"
        # Gleiches Pattern wie fuer die lokale Version (siehe $script:VersionPattern).
        $remoteVersion = $null
        if ($remoteContent.Content -match $script:VersionPattern) {
            $remoteVersion = $Matches[1]
        }

        if (-not $remoteVersion) {
            Write-Host " Version nicht lesbar." -ForegroundColor Yellow
            return
        }

        # Versionen vergleichen
        $localVer  = [Version]$script:LocalVersion
        $remoteVer = [Version]$remoteVersion

        if ($remoteVer -le $localVer) {
            Write-Host " Aktuell (v$script:LocalVersion)." -ForegroundColor Green
            return
        }

        # Neuere Version gefunden
        Write-Host ""
        Write-Host ""
        Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "  ║   UPDATE VERFUEGBAR                                      ║" -ForegroundColor Yellow
        Write-Host "  ║   Lokal:  v$($script:LocalVersion.PadRight(49))║" -ForegroundColor Yellow
        Write-Host "  ║   GitHub: v$($remoteVersion.PadRight(49))║" -ForegroundColor Yellow
        Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Update jetzt herunterladen? [J/N]: " -ForegroundColor Cyan -NoNewline
        $answer = Read-Host

        if ($answer -notmatch '^[JjYy]') {
            Write-Host "  Update übersprungen. Starte mit v$script:LocalVersion..." -ForegroundColor Gray
            Write-Host ""
            return
        }

        # Liste aller Dateien die heruntergeladen werden sollen
        # Struktur: @{ RemotePfad = Lokaler Zielpfad }
        $updateFiles = @{
            "ADHealthCheck.ps1"                    = Join-Path $ScriptRoot "ADHealthCheck.ps1"
            "modules/ADHealthCheck.Diag.psm1"      = Join-Path $ScriptRoot "modules\ADHealthCheck.Diag.psm1"
            "modules/ADHealthCheck.Diag.psd1"      = Join-Path $ScriptRoot "modules\ADHealthCheck.Diag.psd1"
            "modules/ADHealthCheck.Reporting.psm1" = Join-Path $ScriptRoot "modules\ADHealthCheck.Reporting.psm1"
            "modules/ADHealthCheck.Reporting.psd1" = Join-Path $ScriptRoot "modules\ADHealthCheck.Reporting.psd1"
            "modules/ADHealthCheck.Utils.psm1"     = Join-Path $ScriptRoot "modules\ADHealthCheck.Utils.psm1"
            "modules/ADHealthCheck.Utils.psd1"     = Join-Path $ScriptRoot "modules\ADHealthCheck.Utils.psd1"
            "modules/ADHealthCheck.DNS.psm1"       = Join-Path $ScriptRoot "modules\ADHealthCheck.DNS.psm1"
            "modules/ADHealthCheck.DNS.psd1"       = Join-Path $ScriptRoot "modules\ADHealthCheck.DNS.psd1"
            "modules/ADHealthCheck.EntraSync.psm1" = Join-Path $ScriptRoot "modules\ADHealthCheck.EntraSync.psm1"
            "modules/ADHealthCheck.EntraSync.psd1" = Join-Path $ScriptRoot "modules\ADHealthCheck.EntraSync.psd1"
            "modules/Update-EntraVersion.ps1"      = Join-Path $ScriptRoot "modules\Update-EntraVersion.ps1"
            "config/recommendations.json"          = Join-Path $ScriptRoot "config\recommendations.json"
            "config/i18n.de.json"                  = Join-Path $ScriptRoot "config\i18n.de.json"
            "config/i18n.en.json"                  = Join-Path $ScriptRoot "config\i18n.en.json"
            "config/mapping.json"                  = Join-Path $ScriptRoot "config\mapping.json"
            "templates/report.template.html"       = Join-Path $ScriptRoot "templates\report.template.html"
        }

        # Backup-Verzeichnis anlegen
        $backupDir = Join-Path $ScriptRoot "output\backup\v$script:LocalVersion"
        if (-not (Test-Path $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }

        Write-Host ""
        Write-Host "  Lade Update v$remoteVersion herunter..." -ForegroundColor Cyan
        Write-Host "  Backup der aktuellen Version unter: output\backup\v$script:LocalVersion" -ForegroundColor Gray
        Write-Host ""

        $downloadErrors = @()
        $downloadCount  = 0

        # Invoke-WebRequest mit -OutFile ist in PS5.1 der robusteste Download-Weg:
        # - Schreibt direkt auf Disk (kein Speicher-Problem bei grossen Dateien)
        # - Kein Add-Type / C#-Kompilierung nötig (kein "Type already exists"-Fehler)
        # - $ProgressPreference = SilentlyContinue verhindert Fortschrittsanzeige im Terminal
        #   (die normalerweise den Download massiv verlangsamt)
        $savedProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'

        foreach ($entry in $updateFiles.GetEnumerator()) {
            $remotePath = $entry.Key
            $localPath  = $entry.Value
            $fileName   = Split-Path $localPath -Leaf

            Write-Host "  ► $fileName..." -NoNewline

            try {
                # Backup der bestehenden Datei
                if (Test-Path $localPath) {
                    $backupTarget = Join-Path $backupDir ($remotePath.Replace("/", "_"))
                    Copy-Item $localPath $backupTarget -Force | Out-Null
                }

                # Zielverzeichnis sicherstellen
                $targetDir = Split-Path $localPath -Parent
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }

                # ATOMAR + VALIDIERT: erst in eine Temp-Datei laden, Integritaet
                # pruefen, dann verschieben. So kann ein abgebrochener/abgeschnittener
                # Download (flaky Netzwerk) die installierte Datei NIE korrupt
                # ueberschreiben (fixt "Missing closing '}'"-Ladefehler nach Update).
                $url = "$script:GitHubRaw/$remotePath"
                $tmpPath = "$localPath.download.tmp"
                Invoke-WebRequest -Uri $url -OutFile $tmpPath `
                    -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop

                # 1) Datei muss existieren und darf nicht leer/winzig sein
                if (-not (Test-Path $tmpPath)) { throw "Download nicht auf Disk angekommen." }
                if ((Get-Item $tmpPath).Length -lt 32) { throw "Download leer/zu klein (abgeschnitten?)." }
                # 2) PowerShell-Dateien: Syntax pruefen (abgeschnittene Datei => Parserfehler)
                if ($fileName -match '\.psm?1$') {
                    $ptok = $null; $perr = $null
                    [void][System.Management.Automation.Language.Parser]::ParseFile($tmpPath, [ref]$ptok, [ref]$perr)
                    if ($perr -and $perr.Count -gt 0) { throw "Syntaxfehler im Download ($($perr.Count)) - vermutlich abgeschnitten." }
                }
                # 3) JSON-Dateien: Parsebarkeit pruefen
                elseif ($fileName -match '\.json$') {
                    $null = Get-Content $tmpPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                }
                # 4) Erst jetzt atomar an den Zielort verschieben
                Move-Item -Path $tmpPath -Destination $localPath -Force -ErrorAction Stop

                Write-Host " OK" -ForegroundColor Green
                $downloadCount++

            } catch {
                $errMsg = $_.Exception.InnerException.Message
                if (-not $errMsg) { $errMsg = $_.Exception.Message }
                Write-Host " FEHLER" -ForegroundColor Red
                Write-Host "    $errMsg" -ForegroundColor DarkRed
                $downloadErrors += $remotePath

                # Temp-Datei aufraeumen; die installierte Datei wurde NICHT angefasst
                $tmpPath = "$localPath.download.tmp"
                if (Test-Path $tmpPath) { Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue }

                # Backup nur wiederherstellen, falls die Zieldatei tatsaechlich fehlt
                $backupTarget = Join-Path $backupDir ($remotePath.Replace("/", "_"))
                if ((-not (Test-Path $localPath)) -and (Test-Path $backupTarget)) {
                    Copy-Item $backupTarget $localPath -Force | Out-Null
                }
            }
        }

        # Progress-Einstellung wiederherstellen
        $ProgressPreference = $savedProgress

        # Zusammenfassung
        Write-Host ""
        if ($downloadErrors.Count -eq 0) {
            Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Green
            Write-Host "  ║   UPDATE ERFOLGREICH: v$script:LocalVersion -> v$remoteVersion" -ForegroundColor Green
            Write-Host "  ║   $downloadCount Dateien aktualisiert." -ForegroundColor Green
            Write-Host "  ║                                                          ║" -ForegroundColor Green
            Write-Host "  ║   Bitte Script neu starten:  .\ADHealthCheck.ps1        ║" -ForegroundColor Green
            Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Green
        } else {
            Write-Host "  Update teilweise fehlgeschlagen:" -ForegroundColor Yellow
            Write-Host "  $downloadCount Dateien OK, $($downloadErrors.Count) Fehler:" -ForegroundColor Yellow
            $downloadErrors | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
            Write-Host ""
            Write-Host "  Backup verfuegbar unter: output\backup\v$script:LocalVersion" -ForegroundColor Gray
        }

        Write-Host ""
        Read-Host "  Enter druecken zum Beenden (dann Script neu starten)"
        exit 0

    } catch [System.Net.WebException] {
        Write-Host " Keine Verbindung zu GitHub (Timeout/Netzwerk)." -ForegroundColor Gray
    } catch {
        Write-Host " Update-Check fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Gray
    }
}

# Update-Check ausführen (schlägt stillschweigend fehl wenn kein Internet)
Invoke-ADHCUpdateCheck -ScriptRoot $ScriptRoot

# ---------------------------------------------------------------------------
# Module laden (nach Prereq-Check — AD-Modul ist jetzt garantiert verfügbar)
# ---------------------------------------------------------------------------
try {
    Import-Module (Join-Path $ModulePath "ADHealthCheck.Utils.psm1")     -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulePath "ADHealthCheck.Diag.psm1")      -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulePath "ADHealthCheck.DNS.psm1")       -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulePath "ADHealthCheck.EntraSync.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulePath "ADHealthCheck.Reporting.psm1") -Force -ErrorAction Stop
} catch {
    Write-Host "FATAL ERROR: Ein Modul konnte nicht geladen werden." -ForegroundColor Red
    Write-Host "Grund: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Ort:   $($_.InvocationInfo.ScriptName) (Zeile $($_.InvocationInfo.ScriptLineNumber))" -ForegroundColor Gray
    exit 1
}

# ---------------------------------------------------------------------------
# Config laden — Safe-Merge: bestehende settings.json vollständig einlesen
# ---------------------------------------------------------------------------
$Settings = Get-ADHCConfig -Path (Join-Path $ScriptRoot "config\settings.json")
$Mapping  = Get-ADHCMapping -Path (Join-Path $ScriptRoot "config")

# ---------------------------------------------------------------------------
# Helper: Settings sicher speichern (Fix #5 — kein Datenverlust durch Merge)
# ---------------------------------------------------------------------------
function Save-Settings {
    param($SettingsObject, $Path)
    try {
        # Bestehende JSON einlesen und mit neuen Werten zusammenführen
        $existingJson = if (Test-Path $Path) {
            Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        } else {
            [PSCustomObject]@{}
        }

        # Nur explizit geänderte Felder überschreiben
        foreach ($prop in $SettingsObject.PSObject.Properties) {
            $existingJson | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force
        }

        $existingJson | ConvertTo-Json -Depth 10 | Out-File $Path -Encoding UTF8 -Force
        Write-ADHCLog "settings.json erfolgreich gespeichert." -Component "Config"
    } catch {
        Write-ADHCLog "Fehler beim Speichern der settings.json: $($_.Exception.Message)" -Level Warning
    }
}

# ---------------------------------------------------------------------------
# Analyse-Logik
# ---------------------------------------------------------------------------
function Start-Analysis {
    param($Selection, $LangCode, $DNSTarget, $StatusLabel, $ProgressBar)

    $I18n = Get-ADHCI18n -Path (Join-Path $ScriptRoot "config") -Lang $LangCode

    if ($script:UseMockData) {
        $rptData = Get-ADHCMockData -I18n $I18n -Settings $Settings -LangCode $LangCode
        $rptData.DomainStats.DomainFQDN += " (MOCK DATA)"
    } else {

        # Entra-Version automatisch aktualisieren (mit Timeout-Schutz — Fix #6)
        if ($Settings.EntraID.AutoUpdateVersion -eq $true) {
            Write-ADHCLog "Prüfe Entra Connect Versions-Updates (Timeout: 15s)..." -Component "EntraSync"
            try {
                . (Join-Path $ScriptRoot "modules\Update-EntraVersion.ps1")
                $Settings = Update-EntraConnectVersion `
                    -SettingsPath (Join-Path $ScriptRoot "config\settings.json") `
                    -TimeoutSec 15
            } catch {
                Write-ADHCLog "Entra-Versionsabfrage fehlgeschlagen (Timeout/Netzwerk): $_" -Level Warning
            }
        }

        Write-ADHCLog "Starte Analyse ($LangCode)..." -Component "Launcher"

        try {
            $DCs = (Get-ADDomainController -Filter *).HostName
        } catch {
            Write-ADHCLog "Fehler: Keine Domain/DCs gefunden." -Level Error
            return
        }

        # --- Einzelne Sektionen ---
        $domainStats = if ($Selection.DomainStats) { Get-ADDomainStats } else { $null }
        $fsmoData    = if ($Selection.FSMO)         { Get-ADFSMORoles -I18n $I18n } else { $null }

        $discoveryData = if ($Selection.DCSystem) {
            Get-ADHealthDiscovery -DCList $DCs -Settings $Settings
        } else { $null }

        $svcData = if ($Selection.Services) {
            Get-ADServiceStatus -DCList $DCs
        } else { $null }

        $dcdiagData = if ($Selection.DCDiag) {
            Invoke-DetailedDcdiag -DCList $DCs
        } else { $null }

        $sitesData = if ($Selection.Sites) { Get-ADSitesInfo } else { $null }

        # Fix #1: Korrekte Signatur mit -I18n und -LangCode
        $secData = if ($Selection.Security) {
            Get-ADSecurityInfo -Settings $Settings -I18n $I18n -LangCode $LangCode
        } else { $null }

        # Fix #3: ProgressCallback verdrahten — Label + Progressbar aus der GUI
        $ouSecData = if ($Selection.OUAccountSecurity) {
            $progressCallback = if ($StatusLabel -and $ProgressBar) {
                {
                    param($current, $total, $message)
                    $StatusLabel.Text = "$message ($current / $total)"
                    if ($total -gt 0) {
                        $ProgressBar.Value = [Math]::Min([int](($current / $total) * 100), 100)
                    }
                    [System.Windows.Forms.Application]::DoEvents()
                }
            } else { $null }

            Get-ADOUAndAccountSecurity -Settings $Settings -ProgressCallback $progressCallback
        } else { $null }

        $replData = if ($Selection.Replication) {
            Get-ADReplicationLatency -DCList $DCs -Settings $Settings
        } else { $null }

        $evtData = if ($Selection.EventLog) {
            Get-ADEventLogRetention -DCList $DCs -Settings $Settings
        } else { $null }

        $entraData  = if ($Selection.Entra)  { Get-EntraSyncStatus -Settings $Settings } else { $null }
        $backupData = if ($Selection.Backup) { Get-ADBackupStatus } else { $null }
        $dnsData    = if ($Selection.DNS)    { Get-ADDNSHealthStatus -TargetServer $DNSTarget } else { $null }

        $rptData = @{
            DomainStats       = $domainStats
            FSMO              = $fsmoData
            Discovery         = $discoveryData
            DCDiag            = $dcdiagData
            Services          = $svcData
            Sites             = $sitesData
            Replication       = $replData
            EventLog          = $evtData
            Security          = $secData
            OUAccountSecurity = $ouSecData
            Entra             = $entraData
            Backup            = $backupData
            DNS               = $dnsData
        }
    }

    # Report generieren
    $template   = Join-Path $ScriptRoot "templates\report.template.html"
    $reportPath = New-ADHCReport -Data $rptData -Settings $Settings -I18n $I18n `
                                 -Mapping $Mapping -TemplatePath $template -LangCode $LangCode `
                                 -CollectorVersion $script:LocalVersion
    Invoke-Item $reportPath

    # CSV/Security-Export
    if ($rptData.Security.RawExportData -and $rptData.Security.RawExportData.Count -gt 0) {
        $reportFolder = Join-Path $OutputPath "reports"
        if (-not (Test-Path $reportFolder)) {
            New-Item -ItemType Directory -Path $reportFolder -Force | Out-Null
        }
        $dateStr = Get-Date -Format "yyyyMMdd_HHmm"
        $csvPath = Join-Path $reportFolder "ADHC_Security_Details_$dateStr.csv"
        try {
            $rptData.Security.RawExportData | Export-Csv -Path $csvPath -NoTypeInformation `
                -Delimiter ";" -Encoding UTF8 -ErrorAction Stop
            Write-ADHCLog "Sicherheits-Export erstellt: $csvPath" -Component "Reporting"
        } catch {
            Write-ADHCLog "Fehler beim CSV-Export: $($_.Exception.Message)" -Level Error
        }
    }

    # Fix #2: UseMockData nach Analyse immer zurücksetzen
    $script:UseMockData = $false
}

# ---------------------------------------------------------------------------
# DNS-Server Vorauswahl
# ---------------------------------------------------------------------------
$defaultDNSServer = ""
try {
    $domain           = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
    $defaultDNSServer = $domain.PdcRoleOwner.Name
} catch {
    try { $defaultDNSServer = (Get-ADDomainController -Discover).Hostname } catch {}
}
if ($Settings.DNS.TargetServer) { $defaultDNSServer = $Settings.DNS.TargetServer }

# ---------------------------------------------------------------------------
# NoGui-Modus
# ---------------------------------------------------------------------------
if ($NoGui) {
    Write-Host "NoGui-Modus: Starte Analyse mit Standardeinstellungen..." -ForegroundColor Cyan
    $i18n = Get-ADHCI18n -Path (Join-Path $ScriptRoot "config") -Lang $Language
    $selection = @{
        DomainStats=1; FSMO=1; DCDiag=1; DCSystem=1; Backup=1
        Services=1; Sites=1; Security=1; OUAccountSecurity=1; Entra=1; DNS=1
        Replication=1; EventLog=1
    }
    Start-Analysis -Selection $selection -LangCode $Language -DNSTarget $defaultDNSServer
    exit 0
}

# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$fontTitle = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$fontLabel = New-Object System.Drawing.Font("Segoe UI", 9)
$fontInput = New-Object System.Drawing.Font("Segoe UI", 10)
$colorBlue = [System.Drawing.Color]::FromArgb(0, 74, 135)
$colorCyan = [System.Drawing.Color]::FromArgb(0, 169, 206)

# ---------------------------------------------------------------------------
# Form — Höhe wird auf nutzbaren Bildschirmbereich begrenzt (Taskleiste!)
# ---------------------------------------------------------------------------
$screenH      = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height
$formWidth    = 510
$contentWidth = 470   # Scrollpanel-Innenbreite

# Gesamthöhe des Inhalts berechnen (wird nach Erstellung auf Panel gesetzt)
# Formhöhe = Min(Inhalt + Rahmen, verfügbarer Bildschirm - 20px Puffer)
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "AD Health Check (LAKE Solutions AG)"
$form.Width           = $formWidth
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "Sizable"          # Resizable — User kann Fenster anpassen
$form.MinimumSize     = New-Object System.Drawing.Size($formWidth, 400)
$form.BackColor       = [System.Drawing.Color]::White

# ---------------------------------------------------------------------------
# ScrollablePanel — nimmt gesamten Inhalt auf, scrollt bei kleinem Bildschirm
# ---------------------------------------------------------------------------
$scrollPanel                    = New-Object System.Windows.Forms.Panel
$scrollPanel.Dock               = [System.Windows.Forms.DockStyle]::Fill
$scrollPanel.AutoScroll         = $true
$scrollPanel.BackColor          = [System.Drawing.Color]::White
$form.Controls.Add($scrollPanel)

# ---------------------------------------------------------------------------
# Ab hier alle Controls auf $scrollPanel (statt $form)
# ---------------------------------------------------------------------------

# --- HEADER ---
$lblTitle           = New-Object System.Windows.Forms.Label
$lblTitle.Text      = "Report Konfiguration"
$lblTitle.Font      = $fontTitle
$lblTitle.ForeColor = $colorBlue
$lblTitle.Location  = New-Object System.Drawing.Point(20, 20)
$lblTitle.AutoSize  = $true
$scrollPanel.Controls.Add($lblTitle)

# --- EINGABEFELDER ---
[int]$yPos = 70

# Sprache
$lblLang          = New-Object System.Windows.Forms.Label
$lblLang.Text     = "Sprache / Language:"
$lblLang.Font     = $fontLabel
$lblLang.Location = New-Object System.Drawing.Point(25, $yPos)
$lblLang.AutoSize = $true
$scrollPanel.Controls.Add($lblLang)

$cbLang               = New-Object System.Windows.Forms.ComboBox
$cbLang.Location      = New-Object System.Drawing.Point(240, ($yPos - 3))
$cbLang.Width         = 185
$cbLang.DropDownStyle = "DropDownList"
[void]$cbLang.Items.Add("de")
[void]$cbLang.Items.Add("en")
$cbLang.SelectedItem  = $Language
$scrollPanel.Controls.Add($cbLang)

# Entra ID Sync Server
$yPos += 40
$lblSync          = New-Object System.Windows.Forms.Label
$lblSync.Text     = "EntraID / ADSync Server:"
$lblSync.Font     = $fontLabel
$lblSync.Location = New-Object System.Drawing.Point(25, $yPos)
$lblSync.AutoSize = $true
$scrollPanel.Controls.Add($lblSync)

$txtSync          = New-Object System.Windows.Forms.TextBox
$txtSync.Location = New-Object System.Drawing.Point(240, ($yPos - 3))
$txtSync.Width    = 185
$txtSync.Font     = $fontInput
$txtSync.Text     = $Settings.EntraID.SyncServer
$scrollPanel.Controls.Add($txtSync)

# Inaktive Tage
$yPos += 40
$lblDays          = New-Object System.Windows.Forms.Label
$lblDays.Text     = "Inaktive Accounts (< X-Tage):"
$lblDays.Font     = $fontLabel
$lblDays.Location = New-Object System.Drawing.Point(25, $yPos)
$lblDays.AutoSize = $true
$scrollPanel.Controls.Add($lblDays)

$numDays          = New-Object System.Windows.Forms.NumericUpDown
$numDays.Location = New-Object System.Drawing.Point(240, ($yPos - 3))
$numDays.Width    = 185
$numDays.Font     = $fontInput
$numDays.Minimum  = 1
$numDays.Maximum  = 999
$numDays.Value    = [decimal]$Settings.Thresholds.InactiveAccountDays
$scrollPanel.Controls.Add($numDays)

# DNS Server
$yPos += 40
$lblDNSTarget          = New-Object System.Windows.Forms.Label
$lblDNSTarget.Text     = "DNS Abfrage Server:"
$lblDNSTarget.Font     = $fontLabel
$lblDNSTarget.Location = New-Object System.Drawing.Point(25, $yPos)
$lblDNSTarget.AutoSize = $true
$scrollPanel.Controls.Add($lblDNSTarget)

$txtDNSServer          = New-Object System.Windows.Forms.TextBox
$txtDNSServer.Location = New-Object System.Drawing.Point(240, ($yPos - 3))
$txtDNSServer.Width    = 185
$txtDNSServer.Font     = $fontInput
$txtDNSServer.Text     = $defaultDNSServer
$scrollPanel.Controls.Add($txtDNSServer)

# --- CHECKBOXEN ---
$yPos += 50
$gbChecks          = New-Object System.Windows.Forms.GroupBox
$gbChecks.Text     = "Analyse-Umfang & Empfehlungen"
$gbChecks.Font     = $fontLabel
$gbChecks.Location = New-Object System.Drawing.Point(20, $yPos)
$gbChecks.Size     = New-Object System.Drawing.Size(455, 440)
$scrollPanel.Controls.Add($gbChecks)

$lblCol1          = New-Object System.Windows.Forms.Label
$lblCol1.Text     = "Bereich"
$lblCol1.Location = New-Object System.Drawing.Point(20, 25)
$lblCol1.Font     = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$lblCol1.AutoSize = $true
$gbChecks.Controls.Add($lblCol1)

$lblCol2          = New-Object System.Windows.Forms.Label
$lblCol2.Text     = "Empfehlungen"
$lblCol2.Location = New-Object System.Drawing.Point(305, 25)
$lblCol2.Font     = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$lblCol2.AutoSize = $true
$gbChecks.Controls.Add($lblCol2)

$checks = @(
    @{ Name="DomainStats";       Label="Domain Infrastruktur";              Var="chkDomain";  RecVar="chkRecDC"       },
    @{ Name="FSMO";              Label="Betriebsmaster (FSMO)";             Var="chkFSMO";    RecVar="chkRecFSMO"     },
    @{ Name="DCDiag";            Label="Verzeichnisdienst (AD)";            Var="chkDCDiag";  RecVar="chkRecDCDiag"   },
    @{ Name="DCSystem";          Label="Domain Controller Health";          Var="chkDC";      RecVar="chkRecDCSystem" },
    @{ Name="Backup";            Label="Disaster Recovery Readiness";       Var="chkBackup";  RecVar="chkRecBackup"   },
    @{ Name="Services";          Label="AD Systemdienste";                  Var="chkSvc";     RecVar="chkRecSvc"      },
    @{ Name="Sites";             Label="AD Standorte und Replikation";      Var="chkSites";   RecVar="chkRecSites"    },
    @{ Name="Security";          Label="Identitäts-Sicherheit (Accounts)"; Var="chkSec";     RecVar="chkRecSec"      },
    @{ Name="OUAccountSecurity"; Label="AD Objekt- und ACL-Audit";          Var="chkOUSec";   RecVar="chkRecOUSec"    },
    @{ Name="Entra";             Label="Entra ID Sync";                     Var="chkEntra";   RecVar="chkRecEntra"    },
    @{ Name="DNS";               Label="Namensauflösung (DNS Health)";     Var="chkDNS";     RecVar="chkRecDNS"      },
    @{ Name="Replication";       Label="Replikations-Latenz";               Var="chkRepl";    RecVar="chkRecRepl"     },
    @{ Name="EventLog";          Label="Ereignisprotokoll-Vorhaltedauer";   Var="chkEvt";     RecVar="chkRecEvt"      }
)

$chkY               = 55
$allScopeCheckboxes = New-Object System.Collections.Generic.List[System.Windows.Forms.CheckBox]
$allRecCheckboxes   = New-Object System.Collections.Generic.List[System.Windows.Forms.CheckBox]

foreach ($c in $checks) {
    $cb          = New-Object System.Windows.Forms.CheckBox
    $cb.Text     = $c.Label
    $cb.Location = New-Object System.Drawing.Point(20, $chkY)
    $cb.AutoSize = $true
    $cb.Checked  = $true
    $gbChecks.Controls.Add($cb)
    Set-Variable -Name $c.Var -Value $cb
    $allScopeCheckboxes.Add($cb)

    $cbRec          = New-Object System.Windows.Forms.CheckBox
    $cbRec.Text     = "Anzeigen"
    $cbRec.Location = New-Object System.Drawing.Point(305, $chkY)
    $cbRec.AutoSize = $true
    $cbRec.Checked  = $false
    $gbChecks.Controls.Add($cbRec)
    Set-Variable -Name $c.RecVar -Value $cbRec
    $allRecCheckboxes.Add($cbRec)

    $chkY += 35
}
$chkY += 15

# Master-Checkbox Bereiche
$chkSelectAllScope           = New-Object System.Windows.Forms.CheckBox
$chkSelectAllScope.Text      = "Alle abwählen"
$chkSelectAllScope.Location  = New-Object System.Drawing.Point(20, $chkY)
$chkSelectAllScope.AutoSize  = $true
$chkSelectAllScope.Checked   = $true
$chkSelectAllScope.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$chkSelectAllScope.ForeColor = $colorBlue
$gbChecks.Controls.Add($chkSelectAllScope)

$chkSelectAllScope.Add_CheckedChanged({
    foreach ($cb in $allScopeCheckboxes) { $cb.Checked = $chkSelectAllScope.Checked }
    if ($chkSelectAllScope.Checked) {
        $chkSelectAllScope.ForeColor = $colorBlue
        $chkSelectAllScope.Text      = "Alle abwählen"
    } else {
        $chkSelectAllScope.ForeColor = [System.Drawing.Color]::Gray
        $chkSelectAllScope.Text      = "Alle auswählen"
    }
})

# Master-Checkbox Empfehlungen
$chkSelectAllRec           = New-Object System.Windows.Forms.CheckBox
$chkSelectAllRec.Text      = "Alle auswählen"
$chkSelectAllRec.Location  = New-Object System.Drawing.Point(305, $chkY)
$chkSelectAllRec.AutoSize  = $true
$chkSelectAllRec.Checked   = $false
$chkSelectAllRec.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$chkSelectAllRec.ForeColor = [System.Drawing.Color]::Gray
$gbChecks.Controls.Add($chkSelectAllRec)

$chkSelectAllRec.Add_CheckedChanged({
    foreach ($cb in $allRecCheckboxes) { $cb.Checked = $chkSelectAllRec.Checked }
    if ($chkSelectAllRec.Checked) {
        $chkSelectAllRec.ForeColor = $colorBlue
        $chkSelectAllRec.Text      = "Alle abwählen"
    } else {
        $chkSelectAllRec.ForeColor = [System.Drawing.Color]::Gray
        $chkSelectAllRec.Text      = "Alle auswählen"
    }
})

$gbChecks.Height = $chkY + 45

# ---------------------------------------------------------------------------
# Prereq-Ergebnis auf GUI anwenden:
# Fehlende optionale Module -> Checkboxen deaktivieren + Tooltip anzeigen
# ---------------------------------------------------------------------------
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 8000
$toolTip.InitialDelay = 400

if (-not $prereqResult.DNSModuleAvailable) {
    $chkDNS.Checked  = $false
    $chkDNS.Enabled  = $false
    $chkDNS.ForeColor = [System.Drawing.Color]::Gray
    $chkRecDNS.Checked = $false
    $chkRecDNS.Enabled = $false
    $toolTip.SetToolTip($chkDNS, "Nicht verfuegbar: RSAT DNS-Tools nicht installiert")
    $toolTip.SetToolTip($chkRecDNS, "Nicht verfuegbar: RSAT DNS-Tools nicht installiert")
}

if (-not $prereqResult.GPOModuleAvailable) {
    # GPO-Sektion existiert noch nicht im GUI — nur für zukünftige Erweiterung
    # (kein Checkbox vorhanden, daher kein Disable nötig)
}

# --- FORTSCHRITTSBEREICH ---
$yStatusTop = $gbChecks.Location.Y + $gbChecks.Height + 15

$lblStatus           = New-Object System.Windows.Forms.Label
$lblStatus.Text      = "Bereit."
$lblStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$lblStatus.ForeColor = [System.Drawing.Color]::Gray
$lblStatus.Location  = New-Object System.Drawing.Point(20, $yStatusTop)
$lblStatus.Size      = New-Object System.Drawing.Size(440, 18)
$scrollPanel.Controls.Add($lblStatus)

$progressBar          = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, ($yStatusTop + 22))
$progressBar.Size     = New-Object System.Drawing.Size(440, 14)
$progressBar.Style    = "Continuous"
$progressBar.Minimum  = 0
$progressBar.Maximum  = 100
$progressBar.Value    = 0
$progressBar.Visible  = $false
$scrollPanel.Controls.Add($progressBar)

# --- BUTTONS ---
$yBtnTop = $yStatusTop + 50

$btnRun           = New-Object System.Windows.Forms.Button
$btnRun.Text      = "Report erstellen"
$btnRun.Location  = New-Object System.Drawing.Point(20, $yBtnTop)
$btnRun.Size      = New-Object System.Drawing.Size(200, 45)
$btnRun.BackColor = $colorCyan
$btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.FlatStyle = "Flat"
$btnRun.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$scrollPanel.Controls.Add($btnRun)

$btnSample           = New-Object System.Windows.Forms.Button
$btnSample.Text      = "Sample Report"
$btnSample.Location  = New-Object System.Drawing.Point(240, $yBtnTop)
$btnSample.Size      = New-Object System.Drawing.Size(200, 45)
$btnSample.BackColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
$btnSample.ForeColor = [System.Drawing.Color]::White
$btnSample.FlatStyle = "Flat"
$btnSample.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$scrollPanel.Controls.Add($btnSample)

# ---------------------------------------------------------------------------
# Gesamtinhaltshöhe berechnen und Form-Höhe auf Bildschirm begrenzen
# Scrollbar übernimmt den Rest automatisch
# ---------------------------------------------------------------------------
$totalContentHeight = $yBtnTop + 70   # Unterkante Buttons + Puffer
$scrollPanel.AutoScrollMinSize = New-Object System.Drawing.Size($contentWidth, $totalContentHeight)

# Form-Höhe = min(Inhalt + Titelleiste, nutzbarer Bildschirm - 20px Puffer)
$titleBarHeight  = 39   # Titelleiste + Rahmen
$desiredFormH    = $totalContentHeight + $titleBarHeight
$finalFormH      = [Math]::Min($desiredFormH, ($screenH - 20))
$form.Height     = $finalFormH

# ---------------------------------------------------------------------------
# Sample-Button Handler
# ---------------------------------------------------------------------------
$btnSample.Add_Click({
    $script:UseMockData = $true
    $btnRun.PerformClick()
})

# ---------------------------------------------------------------------------
# Run-Button Handler
# ---------------------------------------------------------------------------
$btnRun.Add_Click({

    # Fix #4: Input-Validierung
    if ($chkEntra.Checked -and [string]::IsNullOrWhiteSpace($txtSync.Text)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Bitte einen EntraID / ADSync Server angeben oder die Sektion 'Entra ID Sync' deaktivieren.",
            "Eingabe erforderlich", "OK", "Warning") | Out-Null
        return
    }
    if ($chkDNS.Checked -and [string]::IsNullOrWhiteSpace($txtDNSServer.Text)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Bitte einen DNS-Abfrageserver angeben oder die Sektion 'DNS Health' deaktivieren.",
            "Eingabe erforderlich", "OK", "Warning") | Out-Null
        return
    }

    # Settings aus GUI übertragen
    $Settings.EntraID.SyncServer               = $txtSync.Text
    $Settings.Thresholds.InactiveAccountDays   = [int]$numDays.Value
    if ($null -eq $Settings.DNS) {
        $Settings | Add-Member -MemberType NoteProperty -Name "DNS" -Value ([PSCustomObject]@{}) -Force
    }
    $Settings.DNS.TargetServer = $txtDNSServer.Text

    # Empfehlungs-Flags
    if ($null -eq $Settings.ShowRecommendations) {
        $Settings | Add-Member -MemberType NoteProperty -Name "ShowRecommendations" -Value @{} -Force
    }
    $Settings.ShowRecommendations = @{
        DomainOverview    = $chkRecDC.Checked
        FSMO              = $chkRecFSMO.Checked
        DCDiag            = $chkRecDCDiag.Checked
        DCSystem          = $chkRecDCSystem.Checked
        Backup            = $chkRecBackup.Checked
        Services          = $chkRecSvc.Checked
        Sites             = $chkRecSites.Checked
        Security          = $chkRecSec.Checked
        OUAccountSecurity = $chkRecOUSec.Checked
        Entra             = $chkRecEntra.Checked
        DNS               = $chkRecDNS.Checked
        Replication       = $chkRecRepl.Checked
        EventLog          = $chkRecEvt.Checked
    }

    # Fix #5: Sicheres Speichern (Safe-Merge)
    Save-Settings -SettingsObject $Settings -Path (Join-Path $PSScriptRoot "config\settings.json")

    # Selektion zusammenbauen
    $selection = @{
        DomainStats       = $chkDomain.Checked
        FSMO              = $chkFSMO.Checked
        DCDiag            = $chkDCDiag.Checked
        DCSystem          = $chkDC.Checked
        Backup            = $chkBackup.Checked
        Services          = $chkSvc.Checked
        Sites             = $chkSites.Checked
        Security          = $chkSec.Checked
        OUAccountSecurity = $chkOUSec.Checked
        Entra             = $chkEntra.Checked
        DNS               = $chkDNS.Checked
        Replication       = $chkRepl.Checked
        EventLog          = $chkEvt.Checked
    }

    # UI in Analyse-Modus
    $btnRun.Enabled    = $false
    $btnSample.Enabled = $false
    $btnRun.Text       = "Analysiere..."
    $lblStatus.Text    = "Analyse läuft..."
    $lblStatus.ForeColor = $colorBlue
    $progressBar.Value   = 0
    $progressBar.Visible = $true
    $form.Refresh()

    try {
        # Fix #3: StatusLabel + ProgressBar als Parameter übergeben
        Start-Analysis `
            -Selection   $selection `
            -LangCode    $cbLang.SelectedItem `
            -DNSTarget   $txtDNSServer.Text `
            -StatusLabel $lblStatus `
            -ProgressBar $progressBar
    } finally {
        # UI immer zurücksetzen, auch bei Fehler
        $btnRun.Enabled      = $true
        $btnSample.Enabled   = $true
        $btnRun.Text         = "Report erstellen"
        $lblStatus.Text      = "Fertig."
        $lblStatus.ForeColor = [System.Drawing.Color]::Gray
        $progressBar.Value   = 100
        $form.Refresh()
    }

    $form.Close()
})

$form.ShowDialog() | Out-Null
