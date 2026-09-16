# AD Health Check Pro

![Version](https://img.shields.io/badge/Version-2.10.6-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blue)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)

**Entwickelt von LAKE Solutions AG**

Professionelles PowerShell-Tool zur Analyse und Bewertung von Microsoft Active Directory-Umgebungen. Das Tool führt umfassende technische Diagnosen durch und erstellt einen modernen HTML-Report mit integrierten Handlungsempfehlungen, automatisierten CSV-Exporten und einem vollständigen Governance-Dashboard.

---

## Inhaltsverzeichnis

- [Systemvoraussetzungen](#systemvoraussetzungen)
- [Hauptmerkmale](#hauptmerkmale)
- [Analyse-Bereiche](#analyse-bereiche)
- [Projektstruktur](#projektstruktur)
- [Installation und Ersteinsatz](#installation-und-ersteinsatz)
- [Anwendung](#anwendung)
- [Self-Update](#self-update)
- [Prerequisite-Check](#prerequisite-check)
- [Empfehlungs-Engine](#empfehlungs-engine)
- [Mehrsprachigkeit](#mehrsprachigkeit)
- [Pester-Tests](#pester-tests)
- [Changelog](#changelog)
- [Rechtlicher Hinweis](#rechtlicher-hinweis)

---

## Systemvoraussetzungen

| Anforderung | Details |
|---|---|
| Betriebssystem | Windows Server 2012 R2+ / Windows 10+ |
| PowerShell | **5.1 Desktop Edition** (PowerShell Core / 7+ wird nicht unterstützt) |
| .NET Framework | 4.5 oder neuer |
| RSAT-Modul | `ActiveDirectory` — Pflicht |
| RSAT-Modul | `DnsServer` — Optional (für DNS-Analyse) |
| RSAT-Modul | `GroupPolicy` — Optional (für zukünftige GPO-Analyse) |
| WinRM | Optional (für Remote-Abfragen zu DCs / Entra-Server) |
| Berechtigungen | Administrator + AD-Leserechte inkl. `nTSecurityDescriptor` |
| Netzwerk | Erreichbarkeit der DCs (RPC, LDAP, DNS, SMB) |

> Beim ersten Start prüft ADHealthCheck alle Voraussetzungen automatisch und bietet bei fehlenden Features eine interaktive Installation an.

---

## Hauptmerkmale

- **Interaktive WinForms-GUI** mit ScrollPanel und screen-aware Höhenanpassung (funktioniert auch bei niedrigen Auflösungen)
- **Self-Update** beim Start: automatischer Versionsvergleich mit GitHub, Download aller Dateien mit Backup
- **Prerequisite-Check** vor dem Start: 9 Prüfungen mit interaktivem Installations-Dialog
- **Mehrsprachigkeit** (Deutsch / Englisch) für GUI, Report und CSV-Exporte via i18n-JSON
- **Asynchrone ACL-Analyse** via PowerShell Runspace — kein GUI-Freeze auch bei grossen Umgebungen (10.000+ Objekte)
- **Fortschrittsanzeige** während der ACL-Analyse (ProgressBar + StatusLabel)
- **Dynamisches Ampel-System** im HTML-Dashboard (Grün / Gelb / Rot)
- **Empfehlungs-Engine** mit 77 Regeln in 14 Kategorien (deklarativ via `recommendations.json`)
- **Automatisierter CSV-Export** für Security-Details (Compliance-Audits)
- **Sample-Report** mit realistischen Mock-Daten (Demo / Onboarding ohne AD-Verbindung)
- **NoGui-Modus** für Scheduled Tasks und Automatisierung
- **Modul-Manifeste** (`.psd1`) mit Versionierung v2.1.0 und Abhängigkeitsdefinition

---

## Analyse-Bereiche

| # | Bereich | Beschreibung | Regeln |
|---|---|---|---|
| 1 | **Domain Infrastruktur** | Forest/Domain Level, AD Recycle Bin, KRBTGT-Passwort-Alter | 4 |
| 2 | **FSMO Rollen** | Erreichbarkeit (TCP 389/LDAP), Architektur-Best-Practices, GC-Konflikt | 8 |
| 3 | **DCDIAG Health Matrix** | 21 Tests pro DC (Connectivity, Advertising, Replications, SysVol/FRS, KCC, ...) | 21 |
| 4 | **DC System Health** | Disk-Auslastung, Uptime, Betriebssystem-Lifecycle | 4 |
| 5 | **Disaster Recovery** | Backup-Alter aller AD-Partitionen via `dsaSignature` | 2 |
| 6 | **Systemdienste** | NTDS, Netlogon, DNS, KDC Status auf allen DCs | 4 |
| 7 | **Sites & Replikation** | Site-Topologie, Verbindungen, Site Links, GC-Verteilung, Standorte ohne DC | 6 |
| 8 | **Identitäts-Sicherheit** | Inaktive Konten, Passwort-Hygiene, privilegierte Gruppen | 6 |
| 9 | **OU & ACL-Audit** | Verwaiste SIDs, deaktivierte Vererbung (OU + User) | 3 |
| 10 | **Entra ID Sync** | Agent-Version, Dienste-Status, Verbindung zum Sync-Server | 2 |
| 11 | **DNS Health** | Zonen, SRV-Records (LDAP/Kerberos/GC/PDC), Scavenging, DNSSEC | 7 |
| 12 | **Kennwortrichtlinien** | Länge, Komplexität, Historie, Lockout-Konfiguration | 6 |
| 13 | **Replikations-Latenz** | Zeit seit letzter erfolgreicher Replikation; nicht abrufbare DCs | 2 |
| 14 | **Protokollierung** | Vorhaltedauer von „Directory Service" und „System"; nicht lesbare Logs | 2 |

**Total: 77 Empfehlungsregeln** — davon 50 HIGH, 19 MEDIUM, 5 LOW, 3 INFO

---

## Projektstruktur

```
ADHealthCheck/
│
├── ADHealthCheck.ps1              Hauptprogramm (GUI, Prereq-Check, Self-Update)
├── .gitignore                     Schützt output/ vor versehentlichem Commit
├── README.md
├── CLAUDE.md                      Arbeitshinweise zum Repository (Kodierung, Tests, Fallstricke)
│
├── config/
│   ├── settings.json              Globale Einstellungen, Schwellenwerte, Pfade
│   ├── i18n.de.json               Sprachdatei Deutsch (150+ Keys)
│   ├── i18n.en.json               Sprachdatei Englisch
│   ├── mapping.json               Werte-Mapping (Forest/Domain Functional Levels)
│   └── recommendations.json      Empfehlungs-Engine (77 Regeln, zweisprachig)
│
├── modules/
│   ├── ADHealthCheck.Utils.psm1   Logging, Config-Laden, i18n, HTML-Helpers
│   ├── ADHealthCheck.Utils.psd1   Modul-Manifest v2.1.0
│   ├── ADHealthCheck.Diag.psm1    AD-Diagnose (DC, FSMO, Security, ACL, Backup)
│   ├── ADHealthCheck.Diag.psd1    Modul-Manifest v2.1.0
│   ├── ADHealthCheck.Reporting.psm1  HTML-Report-Generierung + Empfehlungs-Engine
│   ├── ADHealthCheck.Reporting.psd1  Modul-Manifest v2.1.0
│   ├── ADHealthCheck.DNS.psm1     DNS-Zonen, SRV-Records, Scavenging, NS-Status
│   ├── ADHealthCheck.DNS.psd1     Modul-Manifest v2.1.0
│   ├── ADHealthCheck.EntraSync.psm1  Entra ID / Azure AD Connect Status
│   ├── ADHealthCheck.EntraSync.psd1  Modul-Manifest v2.1.0
│   └── Update-EntraVersion.ps1   Automatische Entra-Connect Versions-Aktualisierung
│
├── templates/
│   ├── report.template.html       HTML-Gerüst (20 Platzhalter, Nav, Scroll-to-Top)
│   └── report.style.css           Design, Ampel-Farben, Matrix-Tabellen, Badges
│
├── docs/
│   ├── OFFENE-PUNKTE.md           Arbeitsgrundlage: Beobachtungen und Umsetzungsstand
│   ├── OFFENE-PUNKTE-PASS-BELEGE.md  Messung „PASS ohne Beleg" und ihr Abschluss
│   ├── DASHBOARD-VERTRAG-v4.md    Übergabevertrag schemaVersion 4 (maßgeblich, chronologisch)
│   ├── DASHBOARD-UEBERGABE.md     Handlungsanweisung fürs auswertende System (Kurzfassung)
│   └── DASHBOARD-STAND.md         Konsolidierter Ist-Zustand des Upload-JSON + Klarstellungen
│
├── tests/
│   ├── Test-ADHCCatalog.ps1       Katalogproben (ohne Domäne/Pester, < 1 s, Exit 0/1)
│   ├── New-ADHCPreviewReports.ps1 Berichte aus Mock-Daten, je Sprache ein Unterverzeichnis
│   └── pester/
│       └── ADHealthCheck.Tests.ps1  Pester v5 Tests (350 Tests)
│
└── output/                        Durch .gitignore ausgeschlossen
    ├── reports/                   Generierte HTML-Reports
    ├── data/                      JSON-Snapshots pro Analyse
    ├── logs/                      ADHealthCheck.log
    └── backup/                    Backups vor Self-Updates (vX.Y.Z/)
```

---

## Installation und Ersteinsatz

```powershell
# 1. Repository klonen
git clone https://github.com/janibrb/ADHealthCheck.git
cd ADHealthCheck

# 2. Script als Administrator starten
# Der Prerequisite-Check führt alle nötigen Installationen durch
.\ADHealthCheck.ps1
```

Beim ersten Start prüft ADHealthCheck automatisch alle Abhängigkeiten und bietet fehlende Features zur Installation an.

---

## Anwendung

### GUI-Modus (Standard)

```powershell
# Standardstart:
.\ADHealthCheck.ps1

# Mit Sprachvorgabe:
.\ADHealthCheck.ps1 -Language en
.\ADHealthCheck.ps1 -Language de
```

**Ablauf:**

1. Prerequisite-Check (automatisch, ca. 2 Sekunden)
2. Self-Update Check (automatisch, überspringbar)
3. GUI öffnet sich mit Konfigurationsoptionen:
   - Sprache (DE/EN)
   - EntraID/ADSync Server
   - Inaktivitätsschwelle (Tage)
   - DNS-Abfrageserver
   - Analyse-Bereiche aktivieren/deaktivieren
   - Empfehlungen pro Bereich aktivieren
4. **"Report erstellen"** klicken
5. HTML-Report öffnet sich automatisch im Browser
6. CSV-Export unter `output\reports\ADHC_Security_Details_*.csv`

> Nicht installierte optionale Module (z.B. DNS-Tools) werden automatisch erkannt — die betroffene Checkbox wird deaktiviert und mit einem Tooltip versehen.

### NoGui-Modus (Scheduled Task / Automatisierung)

```powershell
# Alle Bereiche, Standardsprache:
.\ADHealthCheck.ps1 -NoGui

# Englischer Report:
.\ADHealthCheck.ps1 -NoGui -Language en
```

**Scheduled Task (täglich 06:00 Uhr):**

```powershell
$action  = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NonInteractive -File C:\ADHealthCheck\ADHealthCheck.ps1 -NoGui"
$trigger = New-ScheduledTaskTrigger -Daily -At "06:00"
Register-ScheduledTask -TaskName "ADHealthCheck Daily" `
    -Action $action -Trigger $trigger -RunLevel Highest
```

### Sample-Report (Demo / Onboarding)

Der Button **"Sample Report"** im GUI generiert einen vollständigen Report mit realistischen Worst-Case Mock-Daten — ohne AD-Verbindung. Ideal für Präsentationen oder zur Ansicht des Report-Formats.

---

## Self-Update

ADHealthCheck prüft bei jedem Start ob auf GitHub eine neuere Version verfügbar ist:

```
  Prüfe auf Updates (GitHub)...

  ╔══════════════════════════════════════════════════════════╗
  ║   UPDATE VERFUEGBAR                                      ║
  ║   Lokal:  v2.2.0                                         ║
  ║   GitHub: v2.3.0                                         ║
  ╚══════════════════════════════════════════════════════════╝

  Update jetzt herunterladen? [J/N]:
```

**Was beim Update passiert:**

1. Backup der aktuellen Version unter `output\backup\vX.Y.Z\`
2. Download aller 17 Dateien von GitHub (Module, Config, Templates)
3. Binärer Download — Encoding bleibt exakt wie auf GitHub
4. Neustart-Hinweis

**Kein Internet verfügbar:** Der Check schlägt bei Netzwerk-Timeout (10 Sekunden) stillschweigend fehl — das Script startet normal.

**Neue Version veröffentlichen:** Seit v2.4.7 genügt **eine einzige Stelle** — der `.NOTES`-Header in `ADHealthCheck.ps1` (Zeile 6):

```powershell
Version:    2.7.6                    # Einzige Stelle. $script:LocalVersion
                                     # wird daraus zur Laufzeit abgeleitet.
```

Sobald gepusht, erkennen alle Installationen das Update automatisch beim nächsten Start.

> **Hinweis:** Bis v2.4.6 stand die Version an zwei Stellen (Header **und** `$script:LocalVersion`).
> Wird nur eine davon angepasst, laufen die Werte auseinander und der Self-Update löst nie aus —
> genau das ist bei v2.4.6 passiert. Seit v2.4.7 ist das konstruktiv ausgeschlossen.

> **Cache-Hinweis:** `raw.githubusercontent.com` cached mit `max-age=300`. Nach einem Push sehen
> Clients bis zu 5 Minuten lang noch die alte Version. Ein „Aktuell" direkt nach dem Release ist
> also nicht zwingend ein Fehler.

---

## Prerequisite-Check

Beim Start werden 9 Voraussetzungen geprüft:

```
  ╔══════════════════════════════════════════════════════╗
  ║     ADHealthCheck — Systemvoraussetzungen            ║
  ╚══════════════════════════════════════════════════════╝

  Administrator-Rechte...................... [OK]
  PowerShell-Version........................ [OK]   v5.1 (Desktop)
  .NET Framework............................ [OK]   v4.8
  RSAT: ActiveDirectory-Modul............... [OK]   v1.0.0.0
  RSAT: DNS-Server-Tools.................... [WARN] Nicht installiert
  RSAT: GroupPolicy-Tools................... [OK]   v1.0.0.0
  WinRM-Dienst.............................. [OK]   Gestartet
  Ausfuehrungsrichtlinie.................... [OK]   RemoteSigned
  AD-Domaene erreichbar..................... [OK]   contoso.local
```

| Status | Bedeutung |
|---|---|
| `[OK]` | Voraussetzung erfüllt |
| `[WARN]` | Optional, fehlend — betroffene GUI-Sektion wird deaktiviert |
| `[FEHLER]` | Kritisch — Script bricht mit Erklärung ab |

Die Installation fehlender Features erfolgt automatisch via `Add-WindowsCapability` (Windows Client) oder `Install-WindowsFeature` (Windows Server).

---

## Empfehlungs-Engine

Die `config/recommendations.json` enthält 77 deklarative Regeln. Jede Regel ist vollständig zweisprachig — seit v2.8.0 einschliesslich `Category` sowie der drei Katalogtexte `Requirement` (Anforderung), `Description` (Hintergrund) und `Impact` (Auswirkung), die der HTML-Report je Befund als aufklappbaren Block zeigt:

```json
{
  "Id": "PWD-01",
  "Category": { "de": "Sicherheit", "en": "Security" },
  "SubCategory": { "de": "Kennwortrichtlinien", "en": "Password Policies" },
  "Property": "MinPwdLength",
  "Condition": ["<12"],
  "Requirement":    { "de": "Die Mindestkennwortlänge muss ...", "en": "The minimum password length must ..." },
  "Description":    { "de": "Hintergrund: warum das zählt ...", "en": "Background: why this matters ..." },
  "Impact":         { "de": "Folge bei Nichterfüllung ...", "en": "Consequence if unmet ..." },
  "Recommendation": {
    "de": "Die Mindestkennwortlänge ist mit weniger als 12 Zeichen zu gering...",
    "en": "The minimum password length is less than 12 characters..."
  },
  "Priority": "High"
}
```

**Regeln nach Priorität:**

| Priorität | Anzahl | Beispiele |
|---|---|---|
| **HIGH** | 50 | FSMO nicht erreichbar, SysVol-Fehler, DCDIAG-Fehler, schwache Passwortrichtlinie |
| **MEDIUM** | 19 | Entra-Version veraltet, Site ohne GC, ACL-Vererbung deaktiviert |
| **LOW** | 5 | Forest Level veraltet |
| **INFO** | 3 | Scavenging nicht konfiguriert, DNSSEC fehlt, Standort ohne eigenen Server |

---

## Mehrsprachigkeit

Alle UI- und Report-Texte liegen in `config/i18n.de.json` und `config/i18n.en.json` mit 150+ Keys:

- `Title`, `GenDate` — Report-Metadaten
- `Sections` — Abschnittsüberschriften (12 Sektionen)
- `Labels` — Alle Beschriftungen (150+ Keys)
- `CsvHeaders` — Spaltenbezeichnungen für den CSV-Export
- `Reasons` — Begründungen für Security-Findings

**Neue Sprache hinzufügen:** `i18n.XX.json` im selben Format erstellen und in der GUI-ComboBox registrieren.

---

## Pester-Tests

```powershell
# Voraussetzung:
Install-Module Pester -Force -MinimumVersion 5.0

# Ausführen:
Invoke-Pester -Path .\tests\pester\ADHealthCheck.Tests.ps1 -Output Detailed
```

**350 Tests** (Stand v2.10.6, 333 grün / 17 vorbestehend rot — Umgebungsgrenzen ohne `DnsServer`/`ActiveDirectory`-Modul). Die Zahl ist seit v2.10.1 auch unter mehreren gleichzeitigen Läufen reproduzierbar. Die ursprünglichen sechs Blöcke:

| Block | Beschreibung |
|---|---|
| i18n JSON Struktur | Alle Keys vorhanden, DE/EN-Parität, `{0}`-Platzhalter in Reasons |
| Get-ADHCMockData | Rückgabestruktur vollständig, CSV-Spalten lokalisiert |
| Get-ADSecurityInfo Signatur | Parameter `$I18n` und `$LangCode` vorhanden und korrekt typisiert |
| Get-ADOUAndAccountSecurity | `ProgressCallback`-Parameter vom Typ `[scriptblock]` |
| htmlOUSec Null-Safety | Kein Crash wenn `OUAccountSecurity = $null`, kein offener Platzhalter |
| EN-Modus HTML-Output | Kein hartcodierter DE-String im Report bei EN-Sprache |

Seit v2.8.0 zusätzlich: Schwellenwerte aus `settings.json` erreichen das Upload-JSON ·
Determinismus des Evaluators (zwei Auswertungen desselben `$Data` liefern identische
Verdikte über alle Felder) · Katalogtexte im HTML-Bericht samt Absicherung der
`$rec.Description`/`$rule.Description`-Namenskollision · `AffectedItems` ohne übersetzte
Bestandteile · Sites-Regeln feuern in beide Richtungen · zweisprachige Verdikte
(`schemaVersion 4`, Sprachzuordnung, i18n-Ausfallpfad).

Seit v2.9.0 zusätzlich: `NOT_CHECKED` statt stillem `PASS` bei nicht ermittelbaren Werten
(`AD-04`, `PWD-02`, `OS-01`, DCDIAG `Unknown`) · die drei neuen dcdiag-Regeln `DC-CONN`,
`DC-ADVT`, `DC-FRS` · FSMO-Erreichbarkeit über TCP 389 statt ICMP · `SITE-01` mit
`ReplInterval = "Default"` als 180 Minuten · `SITE-04`/`SITE-06` als getrennte Regeln.

Seit v2.10.0 zusätzlich: dritter Anzeigezustand im HTML-Bericht für nicht ermittelbare
Prüfungen · `SEC-09`-Schnitt gegen die aktuelle Gruppenmitgliedschaft (ehemals privilegierte
Konten) · `AD-FSMO-07` prüft die Domänenzahl · FSMO-Rückfall auf Port 636 (LDAPS) ·
`scoreSummary`-Block im Upload-JSON · Kappung der Undetermined-Listen bei `OS-01`/DCDIAG auf 50.

Seit v2.10.1 zusätzlich: typbewusste Auswertung der Kennwortkomplexität (`PWD-02`) · Messwerte
auch beim Bestehen in allen Sektionen · strukturierte Werte für `ENT-01`/`DNS-06`/`DNS-07` ·
kein Messwert mehr auf `NOT_CHECKED` · Protokollfunktion bricht bei gesperrter Datei nicht mehr
ab · prozesseigene Temp-Wurzeln in der Testsuite.

Einige Tests benötigen die Windows-Module `DnsServer`/`ActiveDirectory` (RSAT) und schlagen
auf Arbeitsplatzrechnern ohne diese als bekannte Umgebungsgrenze fehl.

Zusätzlich die Katalogproben — ohne Domäne, ohne Pester, unter einer Sekunde:

```powershell
pwsh -NoProfile -File .\tests\Test-ADHCCatalog.ps1
```

Sie prüfen `config/recommendations.json` auf cp1252-Tauglichkeit (PDF-Berichte nutzen Helvetica),
Schweizer `ss` (klein **und** gross, `ß`/`ẞ`), versehentliche Markdown-Sternchen und leere Felder —
und dass `Requirement`, `Description`, `Impact`, `Recommendation`, `Title`, `SubCategory` und
`Category` bei jeder Regel zweisprachig (`{de,en}`) vorliegen. Zusätzlich bei den vier
Fliesstext-Feldern (`Requirement`, `Description`, `Impact`, `Recommendation`): `de` und `en`
wortgleich (normalisiert — führender/nachlaufender sowie mehrfacher innerer Leerraum ignoriert)
gilt als vergessene Übersetzung und wird beanstandet (bei `Title`/`SubCategory`/`Category` sind
Eigennamen wie „Active Directory" legitim identisch und bleiben aussen vor).

---

## Changelog

### v2.10.6 — Listen mit genau einem Eintrag kamen im Dashboard nicht an

- ⚠ **Ein Listenfeld mit genau einem Eintrag wurde als Objekt serialisiert, nicht als Array.**
  PowerShell unterscheidet nicht zwischen „ein Element" und „Liste mit einem Element": eine
  Erhebungsschleife mit genau einem Durchlauf liefert einen Skalar, und `ConvertTo-Json` schreibt
  daraus `{…}` statt `[{…}]`. Ein auswertendes System, das die Liste mit `forEach`/`map` liest,
  findet dann **nichts** — obwohl der Wert im JSON steht.
- An einer echten Umgebung mit einer Reverse-Zone, einem Standort und einem Domänencontroller
  waren **neun Felder** betroffen, darunter `DNS.ReverseZones`, `Sites.Sites`, `Replication` und
  `DCDiag`.
- ⚠ **Der HTML-Bericht war unauffällig** — er iteriert über den Skalar klaglos. Der Fehler war
  ausschließlich im Dashboard zu sehen. Genau diese Asymmetrie hat die Suche zunächst in die
  falsche Richtung geschickt.
- **Der Fehler ist älter als v2.10.5.** Für `DNS.ReverseZones` wurde er erst dadurch erreichbar,
  dass die drei Systemzonen wegfielen und nur noch eine Zone übrig blieb.
- **fix:** Neue Funktion `Set-ADHCJsonListShape` bringt die Listenfelder unmittelbar vor dem
  Serialisieren in Array-Form. Die Pfadliste (`$script:ADHCJsonListPaths`) fasst ausdrücklich nur
  die genannten Felder an — ein blindes Einpacken würde aus Objekten wie `QuickChecks`
  einelementige Listen machen. ⚠ `$null` bleibt `$null`: „nicht erhoben" und „erhoben, nichts
  gefunden" dürfen nicht verschmelzen.
- **fix:** `UserCount`, `SecGroupCount`, `DistGroupCount` und `ContactCount` lieferten `[]` statt
  einer Zahl, wenn die Abfrage **genau ein** Objekt fand: `(Get-ADGroup …).Count` greift dann nicht
  auf die Anzahl zu, sondern auf das gleichnamige AD-Attribut dieses Objekts — das es nicht gibt.
  Jetzt `@(…)` um die Abfrage, wie es `DomainCount` seit jeher macht.
- **`schemaVersion` bleibt 4.** Kein Feld kommt hinzu oder fällt weg; betroffene Felder tragen nur
  wieder den Typ, den der Vertrag ohnehin nennt.
### v2.10.5 — Reverse-Systemzonen stehen nicht mehr im Bericht

- **change:** `0.in-addr.arpa`, `127.in-addr.arpa` und `255.in-addr.arpa` werden nicht mehr
  aufgelistet. Windows legt sie beim Einrichten des DNS-Dienstes selbst an; sie enthalten nur
  statische Systemeinträge, und ihre Konfiguration ist nicht veränderbar — Scavenging lässt sich
  dort gar nicht einschalten. Im Bericht standen damit drei Zeilen ohne jede Handlungsoption, die
  beim Kunden regelmäßig Rückfragen auslösten.
- Die Zonen fallen **schon bei der Erhebung** heraus (neue Funktion
  `Select-ADHCReportableReverseZone` in `ADHealthCheck.DNS.psm1`), nicht erst beim Rendern. Sonst
  hätte die Zonenzahl im Kopf des Berichts mehr Zonen genannt, als die Tabelle darunter auflistet.
  Sie entfallen damit auch aus `TotalZoneCount` und aus dem Upload-JSON.
- Die Ausnahmen in den Bewertungsregeln (seit v2.7.7) **bleiben bestehen**: ein Bericht, der aus
  älteren Erhebungsdaten erzeugt wird, rechnet weiter korrekt.
### v2.10.4 — Der Bericht-Stil kam nie beim Kunden an

- ⚠ **Der Self-Updater lud `templates/report.style.css` nicht.** Die Datei wird zur **Laufzeit**
  gebraucht — sie wird gelesen und in ein `<style>`-Element des Berichts inliniert —, stand aber
  nicht in der Dateiliste des Updaters. **Jede Stiländerung seit Bestehen des Updaters ist bei
  ausgelieferten Installationen nie angekommen.** Im Entwicklungsverzeichnis lag natürlich immer
  die aktuelle Datei; deshalb fiel es nicht auf. Dasselbe galt für die beiden Logos, auf die
  `config/settings.json` per `LogoUrl` verweist.
  ⚠ **Wer von einer älteren Version aktualisiert, bekommt mit diesem Update erstmals den aktuellen
  Bericht-Stil.**
- **Ein Testblock prüft die Dateiliste jetzt gegen den tatsächlichen Repository-Inhalt**, statt
  gegen eine zweite von Hand gepflegte Aufzählung — sonst wäre nur die Stelle verdoppelt, an der
  man etwas vergessen kann. `config/settings.json` bleibt bewusst ausgenommen: sie trägt die
  Kundenkonfiguration und darf von einem Update nie überschrieben werden.
- **Entwicklung und Auslieferung sind getrennt.** Dieses Repository enthält nur noch, was zum
  Betrieb nötig ist; Historie, Tests und Arbeitsdokumente liegen privat. **Für bestehende
  Installationen ändert sich nichts** — der Updater zeigt unverändert hierher.

### v2.10.3 — Eine fehlgeschlagene Abfrage ist kein Befund

- ⚠ **`AD-03` (AD-Papierkorb) meldete eine fehlgeschlagene Abfrage als echten Befund.** Die
  Erhebung startete auf „aus" und stieg nur bei Erfolg auf „an" — fehlende Berechtigung oder ein
  nicht erreichbarer Domänencontroller waren damit von einem echten „Papierkorb ist aus" nicht zu
  unterscheiden. `AD-03` ist `Priority: High`, es entstand also ein **Falschbefund hoher
  Priorität**. Der Gegenfall war ebenso falsch: ein unbekannter Wert ergab `PASS` **mit** Messwert
  — ein bestandenes Verdikt für eine Messung, die nie stattgefunden hat. Beides meldet jetzt
  `NOT_CHECKED` mit Grund.
  ⚠ **Die Abgrenzung ist bewusst eng:** Nur wenn die Abfrage das Feature gar nicht liefert, gilt
  der Zustand als unbekannt. Leere oder unpassende `EnabledScopes` sind eine echte Aussage und
  bleiben ein Befund — sonst würde aus dem Falschbefund ein verschwiegenes Problem.
- **`AD-FSMO-08`** liest denselben Wert mit und ging bei unbekanntem Papierkorb still als `PASS`
  durch. Meldet jetzt ebenfalls `NOT_CHECKED`, aber nur dort, wo der Papierkorb den Ausschlag gibt.
- **`DNS-06`** meldete `PASS`, wenn der serverweite Scavenging-Schalter nicht ermittelbar war —
  „in Ordnung", wo niemand nachgesehen hatte. Jetzt `NOT_CHECKED` mit Grund.
- **Kennwortkomplexität und AD-Papierkorb werden in der HTML-Übersicht typbewusst ausgewertet**,
  wie seit v2.10.1 im Verdikt. Latent, kein aktiver Fehler — die Erhebung liefert `[bool]`. Der
  Papierkorb bekommt zusätzlich den dritten Zustand „nicht ermittelbar".
- ⚠ **Für Konsumenten:** Vier Regeln können jetzt einen Nicht-Ergebnis-Status tragen, wo vorher
  `PASS` oder `FAIL` stand (`AD-03`, `AD-FSMO-08`, `DNS-06` und seit v2.10.2 `DNS-01`).
  `scoreRelevant` sinkt entsprechend — **aber nur dort, wo bisher geraten wurde.** Wo die Erhebung
  gelingt, ändert sich nichts.

### v2.10.2 — `DNS-01` sagt nicht mehr „bestanden", wo es nichts prüfen konnte

- **Gegenprobe an einem echten Export.** Das Abnahmekriterium aus v2.10.1 („kein bestandenes
  Verdikt ohne Beleg") hielt gegen eine reale Umgebung bis auf **eine** Regel — und die war nicht
  nur belegfrei, sondern schlicht falsch eingestuft.
- **`DNS-01` meldet jetzt `NOT_APPLICABLE` statt `PASS`**, wenn der serverweite
  Scavenging-Schalter aus oder nicht ermittelbar ist. Scavenging hat zwei Schalter: den
  serverweiten Vorgang, der veraltete Datensätze *löscht*, und das Aging je Zone, das sie
  überhaupt erst löschbar macht. `DNS-01` fragt „Server aktiv, einzelne Zonen aus?" — ist der
  serverweite Schalter aus, ist diese Frage gar nicht gestellt. Bisher stand im Kundenbericht
  „Zonen-Scavenging: bestanden", während in Wahrheit nie etwas bereinigt wurde. Der serverweite
  Zustand ist unverändert Sache von `DNS-06`.
  ⚠ **Für Konsumenten sichtbar:** `DNS-01` wandert damit in die Ausschlüsse, `scoreRelevant` sinkt
  um eins.
- **Vertrag präzisiert (Nachtrag R2):** `AffectedValues` ist selbsttragend — `AffectedItems` darf
  daneben leer sein, was seit jeher auch für `BK-01`/`BK-02` gilt. Und bei `ENT-01` trägt `item`
  bewusst einen Wert statt eines Bezeichners, weil `ActualValue` keine Versionszeichenkette
  aufnehmen darf. `AdminSdHolderFormerMember` in die `hintKey`-Tabelle nachgetragen.

### v2.10.1 — Ein bestandenes Verdikt belegt jetzt, dass gemessen wurde

- ⚠ **`PWD-02` meldete auf jedem echten Domänencontroller „Kennwortkomplexität deaktiviert",
  obwohl sie aktiviert war.** Ursache war ein Vergleich gegen die Zeichenkette `"False"`: steht
  links ein echtes `[bool]`, wandelt PowerShell den rechten Operanden um — und `[bool]"False"`
  ist `$true`, weil die Zeichenkette nicht leer ist. Der Wert wird jetzt typbewusst ausgewertet.
  Sichtbar war der Fehler nur gegen eine echte Domäne: die Mock-Daten liefern fest `$false`, also
  genau den Fall, in dem der alte Ausdruck zufällig richtig lag. **Bereits ausgelieferte Berichte
  können diesen Falschbefund enthalten.**
- **Messwerte auch beim Bestehen.** Bisher trugen 46 von 56 bestandenen Verdikten weder
  `ActualValue` noch `AffectedValues` — im Upload-JSON war ein `PASS` damit nicht von einer
  Prüfung zu unterscheiden, die gar nichts gemessen hatte. Betroffen waren DCDIAG, FSMO,
  DCSystem, Services, Backup, Sites, DNS und Entra. Nach einem Sicherheitsvorfall ist das der
  Unterschied zwischen „das Backup war nachweislich 6 Stunden alt" und „das Backup bestand".
  Rein additiv, `schemaVersion` bleibt `4` — das auswertende System braucht keine Änderung.
  Neue Einheiten: `Zones`, `Records`, `Sites`, `SiteLinks`, `Services`.
- **Strukturierte Werte statt Prosa:** `ENT-01` trägt Ist- und Soll-Version in `AffectedValues`
  (bestehende Form, keine Vertragserweiterung; `ActualValue` bleibt `null`, weil eine
  Versionszeichenkette dort ein Typbruch wäre). `DNS-07` listet alle unsignierten Zonen statt nur
  bis zu drei. `DNS-06` nennt den abgefragten DNS-Server.
- **`NOT_CHECKED` trägt keinen Messwert mehr.** Bei `OS-01` und den `DC-*`-Regeln stand bisher
  „0 von 1 bestätigt" neben einem Verdikt, das gerade sagt, dass nichts ermittelt werden konnte.
  Ebenso entfällt bei `AD-FSMO-08` der `ExpectedValue`, der dem eigenen Verdikt widersprach,
  sobald der AD-Papierkorb aktiviert war — also bei der empfohlenen Einstellung.
- **Die Protokollfunktion bricht keinen Berichtslauf mehr ab**, wenn die Datei gesperrt ist
  (Virenscanner, Editor, zweiter Lauf). Kurze Wiederholungsversuche, danach ein Hinweis statt
  eines Abbruchs.
- **Die Testsuite ist unter gleichzeitigen Läufen reproduzierbar.** Ihre Temp-Wurzeln lagen
  prozessübergreifend fest und wurden rekursiv gelöscht; zwei Läufe rissen einander das
  Ausgabeverzeichnis weg, sichtbar als wechselnde, völlig unbeteiligte Fehlschläge.

### v2.10.0 — Nicht ermittelbare Prüfungen jetzt auch im Bericht sichtbar

- **Neuer Bereich im HTML-Bericht:** „Nicht ermittelbare Prüfungen" listet alle Fälle, in denen
  ein Wert nicht gemessen werden konnte, statt sie stillschweigend als „in Ordnung" durchgehen zu
  lassen. Betroffen unter anderem die Kennwortkomplexität (`PWD-02`): der Bericht zeigte hier
  bisher fälschlich „Deaktiviert", obwohl die Prüfung schlicht nicht ermitteln konnte, ob sie aktiv
  ist.
- **Privilegierte Konten (`SEC-09`) genauer ausgewiesen:** Konten, die ein Active Directory einmal
  als „geschützt" markiert hatte, es aber seit dem Austritt aus der zugehörigen Gruppe nicht mehr
  ist, werden jetzt nicht mehr fälschlich mitgezählt. Betrifft die Teilzahl „davon geschützt: n",
  nicht die Gesamtzahl der gemeldeten Konten.
- **FSMO-Rollenprüfung robuster:** Ist ein Domänencontroller über das Standardprotokoll (Port 389)
  nicht erreichbar, versucht die Prüfung jetzt automatisch die verschlüsselte Variante (Port 636),
  bevor sie den Server als nicht erreichbar meldet.
- **Domänenzahl-Prüfung ergänzt:** Die FSMO-Best-Practice-Regel `AD-FSMO-07` berücksichtigt jetzt,
  wie viele Domänen im Forest existieren, statt nur die Rollenverteilung zu betrachten.
- Für das auswertende Dashboard-System: neuer, additiver `scoreSummary`-Block im Upload-JSON mit
  bereits bereinigten Kennzahlen — Details in `docs/DASHBOARD-UEBERGABE.md`.
- Bewusst unverändert gelassen: die DNS-Erreichbarkeitsprüfung (`DNS-03`) nutzt weiterhin ICMP als
  Zusatzsignal — fachlich geprüft, siehe `docs/OFFENE-PUNKTE.md`.

### v2.9.0 — „Nicht ermittelbar" zählt nicht mehr als bestanden

Umsetzung von Teil 3, 5 und 6 aus `docs/OFFENE-PUNKTE.md`, in sieben einzeln geprüften Schritten
— **plus drei bereits vorher fertige, aber noch nie veröffentlichte Änderungen** (Punkte 4.1–4.3
aus derselben Datei). Sie sind hier mit aufgeführt statt in einer eigenen Version, weil es genau
das ist, was ein Anwender beim Sprung von v2.8.0 auf v2.9.0 tatsächlich bekommt — eine eigene
Zwischenversion wurde nie ausgeliefert, der Self-Updater kennt nur v2.8.0 und v2.9.0. Was ein
Anwender wirklich merkt:

- **Neue Befunde bei `SITE-01`:** Ein Site-Link ohne ausdrücklich gesetztes Replikationsintervall
  (meist `DEFAULTIPSITELINK`) wurde bisher stillschweigend übergangen. Ab jetzt gilt der
  Active-Directory-Standard von 180 Minuten als Messwert — wo bisher kein Befund erschien, kann
  jetzt einer stehen.
- **Verschobene Befunde bei `SITE-04`/`SITE-06`:** Ein Standort ganz ohne eigenen
  Domänencontroller (meist eine gewollte Aussenstelle) lief bisher unter `SITE-04` mit derselben
  Priorität wie ein echter Konfigurationsfehler (Standort **hat** DCs, keiner ist Global Catalog).
  Die beiden Lagen sind jetzt getrennt: `SITE-04` bleibt der Konfigurationsfehler (Medium), der
  serverlose Fall heisst neu `SITE-06` und läuft auf der neuen Stufe **Info**. Wer bisher einen
  `SITE-04`-Eintrag im Bericht sah, sieht ihn möglicherweise jetzt als `SITE-06`.
- **„Nicht ermittelbar" ist kein Bestehen mehr:** Vier Stellen werteten einen Wert, der sich nicht
  ermitteln liess — fehlendes Leserecht, fehlgeschlagene Abfrage, unbekanntes Betriebssystem,
  nicht erkanntes DCDIAG-Ergebnis — bisher stillschweigend als „in Ordnung". Alle vier melden
  jetzt `NOT_CHECKED` mit Grund. Betroffen: KRBTGT-Passwortalter (`AD-04`), Kennwortkomplexität
  (`PWD-02`), Betriebssystem-Lifecycle (`OS-01`) und alle 18 bisherigen DCDIAG-Regeln.
- **`DNS-06`/`DNS-07` zählen nicht mehr als Fehlschlag.** Beide sind laut ihrem eigenen Text nur
  ein Hinweis (fehlendes DNS-Scavenging bzw. keine DNSSEC-Signierung), liefen bisher aber wie ein
  echter Mangel in die Punktzahl ein — bei fast jeder Umgebung, weil unsignierte interne AD-Zonen
  der Normalfall sind. Wer die Punktzahl über die Zeit vergleicht, sieht durch diese Änderung
  einen Sprung nach oben, ohne dass sich an der Umgebung etwas geändert hat.
- **Der Bericht weist jetzt aus, wie viele der `SEC-09`-Konten (Vererbung blockiert)
  AdminSDHolder-geschützt sind.** Die Gesamtzahl im Befund bleibt gleich, aber Text und Tabelle
  zeigen zusätzlich die Teilmenge („davon AdminSDHolder-geschützt: n") — diese Konten braucht man
  in aller Regel nicht einzeln nachzubearbeiten, weil Active Directory die Vererbung dort ohnehin
  automatisch sperrt.
- **Die Ampel-Farben für Organisations- und Schema-Admins zeigen jetzt dasselbe wie der Befund
  darunter.** Bisher färbten alle drei Admin-Gruppen-Pillen erst ab 6 Mitgliedern rot, obwohl die
  zugehörigen Regeln schon ab 3 (Organisations-Admins) bzw. 2 (Schema-Admins) Mitgliedern feuern.
  Wer bisher eine grüne Pille bei 2–5 Mitgliedern sah, obwohl der Bericht darunter einen Befund
  auswies, sieht die Pille jetzt korrekt rot.
- **Lange Kontonamen (Distinguished Names) laufen in den Konto-Tabellen nicht mehr über.** Ein
  langer DN konnte bisher die Status-Spalte überschreiben; er bricht jetzt sauber in der eigenen
  Zelle um.

Weitere Änderungen:

- **feat:** Drei ausgeführte, bisher nie ausgewertete dcdiag-Tests bekamen Regeln: `DC-CONN`,
  `DC-ADVT`, `DC-FRS` (alle High). Kostet keine zusätzliche Laufzeit — die Daten wurden bereits
  erhoben.
- **feat:** `AD-FSMO-01` bis `05` prüfen die Erreichbarkeit jetzt über eine TCP-Verbindung auf
  Port 389 (LDAP) statt per ICMP-Ping — robust gegen Umgebungen, die ICMP blockieren, LDAP aber
  zulassen. Die Prüfung belegt damit, dass der Verzeichnisdienst Verbindungen entgegennimmt, nicht
  dass die Rolle selbst arbeitsfähig ist.
- **fix:** Toter `Condition`-Ausdruck bei `PWD-04` an den tatsächlich verwendeten `Threshold`
  angeglichen (Code unverändert, `SEC-05` war bereits in der Vorcharge dran).
- **docs:** dcdiag-Parser bekam einen sprachunabhängigen Rückfall für alles, was nach dem
  englischen Muster noch `"Unknown"` ist. **Achtung:** das deutsche Muster ist unbelegt — es
  stammt aus Forenzitaten, nicht von einem echten deutschsprachigen Server, und ist im Code wie im
  Test so gekennzeichnet.
- **docs:** Katalogtexte nachgezogen (`AD-FSMO-01..05`, `SITE-01`, `OS-01`, `SEC-06`).
- **test:** Suite von 94 auf **136 grün** (17 vorbestehend rot, unverändert). Katalog von 73 auf
  **77 Regeln**.
- Upload-JSON: `schemaVersion` bleibt **4** — die Änderungen sind gegenüber `schemaVersion 4`
  additiv genug (neue Werte an offenen Stellen), ein zweiter Bump mitten in der laufenden
  `4`-Umsetzung hätte mehr geschadet als genützt. **Nicht additiv für Konsumenten mit fester
  Werteliste:** `Priority` kennt jetzt zusätzlich `"Info"`. Handlungsliste für das auswertende
  System, inklusive additiv/brechend-Einordnung jedes Punkts: `docs/DASHBOARD-VERTRAG-v4.md`,
  Abschnitt „Was seit v2.8.0 dazugekommen ist".
- Weiterhin offen: siehe `docs/OFFENE-PUNKTE.md` — u. a. der DCDIAG-Parser ist nur für den
  englischen Fall belegt, `SEC-09`/`adminCount` braucht noch den Schnitt gegen die aktuelle
  Gruppenmitgliedschaft, `DNS-03` prüft weiterhin per ICMP.

### v2.8.0 — Katalogtexte im Bericht, zweisprachige Verdikte (schemaVersion 4)

Umsetzung von Teil 0 und Teil 2 aus `docs/OFFENE-PUNKTE.md`, in zwölf einzeln geprüften Schritten.

- **feat:** Der HTML-Report zeigt je Befund die drei neuen Katalogfelder als aufklappbaren Block („Details zur Prüfung": Anforderung, Hintergrund, Auswirkung) — `<details open>`, kein JavaScript, druckfest. Fehlt ein Feld, entfällt nur dessen Zeile; eine ältere `recommendations.json` läuft unverändert weiter.
- **feat:** Upload-JSON `schemaVersion 4` — die Verdikte sind zweisprachig. **Nicht additiv:** `Detail`, `SkipReason`, `Category` und `SubCategory` sind jetzt `{de,en}`-Objekte statt Strings; `language` sagt nur noch, in welcher Sprache der HTML-Bericht erzeugt wurde. Mechanik: derselbe (nachweislich deterministische) Evaluator läuft ein zweites Mal mit der Gegensprache, die Prosa wird über die Regel-`Id` zusammengeführt. Abnahmekriterium erreicht: **0 von 71** Befunden in beiden Sprachen identisch (vorher 10 von 30). Handlungsliste für das auswertende System — **C1–C4 vor dem Rollout**: `docs/DASHBOARD-VERTRAG-v4.md`.
- **feat:** `AffectedItems` enthält bei `SRV-01`, `BK-01/02`, `REP-01`, `EVT-01/02` und `SITE-01/04/05` nur noch sprachneutrale Bezeichner; Messwert bzw. Grund stehen daneben im neuen Feld `AffectedValues` (`{item,value,unit}` bzw. `{item,hintKey}`). `value: null` heisst „nicht ermittelbar", nicht `0`. Die Befundsätze im HTML-Report sind Zeichen für Zeichen unverändert — nachgemessen gegen den Stand vor dem Umbau.
- **fix:** Der Verdikt-Aufruf bekam die `Thresholds` aus `settings.json` nicht durchgereicht — bei angepasstem `KrbtgtPasswordAgeDays` meldete der HTML-Bericht `FAIL` und das Upload-JSON `PASS` für dieselbe Regel im selben Lauf. `REP-01`/`EVT-01` bezogen Status und `ExpectedValue` obendrein aus verschiedenen Quellen; bei übersteuerten Schwellen nannte das Verdikt eine Grenze, gegen die nicht gemessen wurde.
- **fix:** `SITE-05` hätte beim Bereinigen des übersetzten Platzhalters lautlos nie mehr gefeuert — die Auslösung hing allein an der Listenlänge. Jetzt entkoppelt und in beide Richtungen getestet (feuert bei 0 Subnetzen, feuert nicht bei vorhandenen).
- **test:** Die Pester-Suite lief nicht (0 von 72 — Discovery-Scoping, fehlender Utils-Import); jetzt 104 Tests, 87 grün. Neu: `tests/Test-ADHCCatalog.ps1` (Katalogproben ohne Domäne: cp1252, Schweizer `ss`, Markdown-Sternchen, leere Felder, vergessene Übersetzungen) und `tests/New-ADHCPreviewReports.ps1` (beide Berichte aus Mock-Daten).
- Weiterhin offen: Teil 3–6 der `docs/OFFENE-PUNKTE.md` (dort dokumentiert, samt Vorarbeit).

### v2.7.8 — Ein-DC-Domänen: NOT_APPLICABLE statt Fehlalarm
- **fix:** `REP-01`/`REP-02` konnten in einer Domäne mit nur einem DC nie bestehen — ohne Partner landete der Eintrag als „Unreachable" in `REP-02`, ein Befund, den niemand beheben kann. Solche Fälle tragen jetzt Status `NotApplicable`, die Regeln werden übersprungen. Upload-JSON `schemaVersion 3`: neuer Verdikt-Status `NOT_APPLICABLE` plus Feld `SkipReason` (Konsumenten, die nur PASS/FAIL/NOT_CHECKED kennen, behandeln ihn wie NOT_CHECKED).

### v2.7.7 — Reverse-Systemzonen aus der Scavenging-Bewertung genommen
- **fix:** `DNS-01` meldete dauerhaft ein nicht behebbares Finding: `0/127/255.in-addr.arpa` führen kein Aging und können es nicht. Die drei Zonen sind aus der Bewertung ausgenommen und tragen die neutrale Pille „Nicht anwendbar (Systemzone)".

### v2.7.6 — Scavenging wurde nie gemessen
Gefunden beim Feldtest von v2.7.5. Die Kachel meldete **„Inaktiv – nicht konfiguriert (Global)" über alle 21 Zonen**. Der Grund war nicht die Konfiguration:

```powershell
foreach ($zone in $allTestedZones) {
    if ($null -eq $zone.Aging -or $zone.Aging.AgingState -eq $false) { ... }
}
```

`$allTestedZones` sind die selbst gebauten Zonenobjekte — und die tragen **keine** Eigenschaft `Aging`. `$null -eq $zone.Aging` war damit immer wahr, **jede** Zone landete unbesehen in `MissingScavenging`. `AgingState` existiert obendrein nicht; das Feld heisst `AgingEnabled` und kommt aus `Get-DnsServerZoneAging`.

- **fix:** Aging wird jetzt je Zone tatsächlich erhoben (`Get-ADHCZoneAging`) und als `AgingEnabled` / `RefreshHours` / `NoRefreshHours` am Zonenobjekt geführt.

- **`AgingEnabled = $null` heisst „nicht ermittelbar", nicht „deaktiviert".** Secondary-, Stub- und Forwarder-Zonen kennen kein Aging — solche Zonen zählen **nicht** als „ohne Scavenging", sondern werden getrennt ausgewiesen (`ScavengingUnknown`). Genau diese Verwechslung war der Fehler.

- **feat:** Neue Spalte `SCAVENGING` in Forward- und Reverse-Zonentabelle:

  | Pille | Bedeutung |
  |---|---|
  | **AKTIV** (grün) | Aging aktiv; Tooltip nennt No-Refresh- und Refresh-Intervall in Stunden |
  | **INAKTIV** (gelb) | Aging nachweislich aus |
  | **UNBEKANNT** (grau) | nicht ermittelbar — bewusst neutral, damit eine fehlende Messung nicht wie ein Befund aussieht |

- **feat:** Der serverweite Schalter wird geprüft (`Get-ADHCServerScavenging` über `Get-DnsServerScavenging`). Ohne ihn läuft Aging auf Zonenebene ins Leere: die Zonen sind konfiguriert, aufgeräumt wird trotzdem nie. Die Kachel zeigt ihn zuerst; die Fusszeile zählt nur noch gemessene Zonen und nennt nicht ermittelbare separat.

- **change:** `DNS-01` und `DNS-06` lösen jetzt das aus, was ihre Texte seit jeher behaupten. `DNS-06` hängt am serverweiten Schalter statt an „alle Zonen ohne Aging"; `DNS-01` feuert, wenn der Schalter **an** ist und einzelne Zonen kein Aging haben. Beide schliessen sich damit gegenseitig aus — der Sample-Report zeigt deshalb `DNS-01`, nicht mehr beide. Die Log-Zeile in `Get-ADHCMockData` behauptete „alle 69 Empfehlungsregeln aktiv"; es sind 73 Regeln, und eine davon kann im Sample nicht feuern. Der Text sagt das jetzt.

> **Warum das zählt:** Zwei Releases hintereinander derselbe Fehlertyp — ein Feld, das nie erhoben wurde, aber als Befund im Report stand. Erst die Trust-Anchor-NS, jetzt das Aging. Ein Report, der Unwissen als Messwert ausgibt, ist schlimmer als einer, der die Spalte weglässt.

- **Kosten:** ein `Get-DnsServerZoneAging`-Aufruf je Zone. Lokal vernachlässigbar, bei entferntem Zielserver über WinRM merkbar.

### v2.7.5 — Geister-Nameserver aus `TrustAnchors`
Gefunden im Feldtest. Die Tabelle **Status der Nameserver (NS)** listete rund zwei Dutzend DNS-Server, die alle `Stopped` / `Fail` meldeten — und damit die Empfehlung `NSUnreachable` auslösten. Auf demselben Server lieferte `Get-DnsServerTrustPoint` nichts, `Get-DnsServerResourceRecord -ZoneName TrustAnchors -RRType NS` dagegen genau diese Liste.

- **fix:** Die NS-Records wurden über **alle** Zonen des Servers eingesammelt (`foreach ($zone in $allZones)`). Darin steckt die DNSSEC-Systemzone `TrustAnchors`: forestweit AD-integriert, nie gescavenged, mit NS-Einträgen längst entfernter DCs. Der Befund war ein reines Artefakt der Abfrage, kein Zustand der Umgebung.

- Neue exportierte Funktion `Select-ADHCNameserverZone` entscheidet, welche Zonen überhaupt eine Aussage über die eigenen Nameserver treffen. Ausgeschlossen werden:

  | Ausgeschlossen | Grund |
  |---|---|
  | `TrustAnchors` | DNSSEC-Systemzone, NS werden nie bereinigt |
  | `.` | Root Hints — NS zeigen auf die Internet-Rootserver |
  | `0/127/255.in-addr.arpa` | automatisch angelegte Reverse-Systemzonen |
  | Zonentyp `Stub` | hält per Definition NS einer fremden Domäne |
  | Zonentyp `Forwarder` | hält per Definition NS fremder Server |

- **`TrustAnchors` wird separat ausgewiesen, aber nicht geprüft.** Die Zone fällt aus `ForwardZones` heraus und damit automatisch aus `TotalZoneCount`, der Scavenging-Kachel sowie den Regeln `DNSSECNotConfigured`, `ScavengingGloballyDisabled`, `NonADIntegrated` und `ZoneStopped` — alle leiten sich aus Forward + Reverse ab.

- Stattdessen erscheint im DNS-Abschnitt ein rein informativer Block (`Get-ADHCTrustAnchorInfo`), der nur auftaucht, wenn überhaupt etwas vorhanden ist:

  ```
  Trust Anchors (DNSSEC)
  DNS Zone TrustAnchors (Primary, AD-integriert, Forest) · 22 NS-Records (nicht geprüft) · Keine Trust Points konfiguriert
  Information, nicht geprüft. Diese Zone wird forestweit repliziert und nicht bereinigt;
  ihre Einträge erlauben keine Aussage über den Zustand der Umgebung.
  ```

  Sind Trust Points konfiguriert (`Get-DnsServerTrustPoint`), werden sie mit Name, State und Anzahl der Anker gelistet. Das Rückgabeobjekt trägt bewusst **kein** Statusfeld — es gibt nichts, woraus das Reporting ein Verdikt ableiten könnte. Der Block ist neutral gestaltet (`.info-note`), ohne Ampelfarbe und ohne Status-Pill.

> **Warum das zählt:** Veraltete NS-Records in der Domänenzone sind ein echter Befund und bleiben sichtbar. Ein Systemartefakt als „Nameserver nicht erreichbar" zu melden, macht die Kachel dagegen unbrauchbar — 24 Fehlbefunde verdecken den einen, der zählt.

### v2.7.3 — `Coverage` behauptete mehr, als es belegte
Gefunden im Feldtest von v2.7.2. Die Partitions-Erweiterung funktionierte — `Coverage: "AllPartitions"`, sechs Einträge statt zwei. Zurück kamen aber nur **drei der fünf bekannten Partitionen**: `ForestDnsZones` und `DomainDnsZones` fehlten, obwohl sie nachweislich existieren (sie stehen im Backup-Block).

- **fix:** `Coverage` beschrieb, was **abgefragt** wurde — ein Konsument las daraus „alles geprüft". Ersetzt durch zwei getrennte Felder:

  | Feld | Bedeutung |
  |---|---|
  | `PartitionScope` | was abgefragt wurde (`AllPartitions` / `DefaultPartitionOnly`) |
  | `PartitionsFound` | welche Partitionen **tatsächlich** geantwortet haben, je DC |

  Damit lässt sich gegen die bekannten Partitionen abgleichen, statt der Zusage zu vertrauen. Die antwortenden Partitionen werden zusätzlich ins Log geschrieben.

- `PartitionsFound` ist typisiert (`[string[]]`) und bleibt auch bei null oder einem Eintrag ein Array — die Lehre aus v2.7.1.

> **Warum das zählt:** Ob `ForestDnsZones` und `DomainDnsZones` legitim fehlen (weil sie über andere Partnerbeziehungen replizieren) oder ob dort ein blinder Fleck bleibt, ist nicht abschliessend geklärt. Genau deshalb darf das Werkzeug keine Vollständigkeit behaupten, die es nicht geprüft hat — es liefert jetzt die Rohdaten für diese Beurteilung, statt sie vorwegzunehmen.

### v2.7.2 — Regression aus v2.7.1 behoben
- **fix:** Der in v2.7.1 eingeführte Parameter **`-PartitionFilter` existiert nicht.** Der Name war aus dem Gedächtnis behauptet und ohne Domänencontroller nicht überprüfbar. Folge: **jeder** Aufruf von `Get-ADReplicationPartnerMetadata` schlug fehl, REP-01 lieferte überhaupt keine Daten mehr. Im Feldtest sichtbar als:

  ```
  A parameter cannot be found that matches parameter name 'PartitionFilter'.
  ```

  Der Partitions-Parameter wird jetzt **zur Laufzeit ermittelt** (`-Partition`, sonst `-PartitionFilter`, sonst keiner). Ein unbekannter Parameter kann den Aufruf damit nicht mehr sprengen — unabhängig von der installierten RSAT-Version.

- **feat:** Das Ergebnis weist die **erreichte Abdeckung** aus und protokolliert sie:

  | `Coverage` | Bedeutung |
  |---|---|
  | `AllPartitions` | Alle Partitionen geprüft (Domain, Configuration, Schema, DNS-Zonen) |
  | `DefaultPartitionOnly` | Nur die Standard-Partition — das Cmdlet kennt keinen Partitions-Parameter |

  Ob die volle Abdeckung erreicht wurde, ist damit **nachlesbar statt angenommen**.

> **Bemerkenswert:** Die Regression wurde im Feldtest von **REP-02** gemeldet — der Regel aus v2.6.1, die „nicht prüfbar" sichtbar macht. Ohne sie wäre aus dem Totalausfall ein stilles `PASS` geworden, und der Fehler wäre unentdeckt geblieben. Das Sicherheitsnetz hat den Sturz des eigenen Entwicklers aufgefangen.

### v2.7.1 — Blinder Fleck bei der Replikation, Schema-Inkonsistenz, fehlende Messwerte
Gefunden durch Auswertung eines vollständigen Upload-JSON aus einem produktiven AD.

- **fix:** **`AffectedItems` war mal ein Array, mal ein String.** Ein Befund mit zwei Servern kam als `["a","b"]`, einer mit einem Server als `"a"` — Konsumenten mussten beide Typen behandeln. Ursache ist eine PowerShell-Eigenheit: Der Rückgabewert eines `if`-Blocks wird **enumeriert**, wodurch einelementige Arrays zum Skalar werden.

  ```powershell
  # vorher — kollabiert bei genau einem Eintrag:
  AffectedItems = if ($hit.AffectedItems) { @($hit.AffectedItems) } else { $null }
  # jetzt — typisierte Zuweisung vor dem Objektbau:
  [string[]]$affectedOut = $null
  if ($hit.AffectedItems) { $affectedOut = [string[]]@($hit.AffectedItems) }
  ```

- **fix:** **REP-01 prüfte nur eine von fünf Partitionen.** `Get-ADReplicationPartnerMetadata` liefert ohne `-PartitionFilter *` ausschliesslich die Standard-Partition. Replikationsprobleme auf **Configuration, Schema, ForestDnsZones und DomainDnsZones** blieben unsichtbar — und gerade die fallen im Alltag nicht auf, bis etwas Grösseres bricht. Im Feldtest kam pro DC genau ein Eintrag statt fünf.
- **feat:** Messwerte für **AD-01 bis AD-04** und **SEC-07 bis SEC-09** nachgezogen. Bei AD-04 ist der Messwert bewusst das **Alter in Tagen**, nicht der abgeleitete Status: Ein neun Jahre altes KRBTGT-Kennwort und ein 181 Tage altes liefern denselben Status `Expired`, aber völlig unterschiedlichen Handlungsdruck.
- Verifiziert: **0 Statusänderungen** über alle 73 Verdikte. Ohne Messwert bleiben 13 Regeln — die acht FSMO-Erreichbarkeitsprüfungen (boolesch), SITE-05, ENT-01/02 und die beiden DNS-Scavenging-Regeln.

> ⚠️ **Die Partitions-Erweiterung liefert mehr Zeilen als bisher** — statt einer pro DC nun eine je Partition und Partner. Das erhöht die Laufzeit geringfügig und kann bislang unentdeckte Befunde sichtbar machen. In der eigenen Umgebung gegenprüfen.

### v2.7.0 — Ein PASS trägt jetzt seinen Nachweis
Direkte Folge des zweiten Feldtests. Nach der Firewall-Freischaltung lieferte EVT-01 **exakt dasselbe JSON** wie zuvor — obwohl der eine Fall „ein DC wurde übersprungen" und der andere „alles gemessen und in Ordnung" bedeutete:

```json
"Id": "EVT-01",  "Status": "PASS",  "ActualValue": null,  "AffectedItems": null
```

- **feat:** **PASS-Verdikte liefern ihren Messwert mit.** Ursache war das Design aus v2.5.0: `ActualValue` kam ausschliesslich aus dem gefeuerten Befund (`$hit`). Ohne Befund gab es keinen Wert. Neu hält ein Messwert-Stash den gemessenen Wert je Regel fest — unabhängig davon, ob sie feuert:

  | Verdikt | vorher | jetzt |
  |---|---|---|
  | `EVT-01` PASS | `null` | `87 Days` (kürzeste Vorhaltedauer über alle DCs) |
  | `EVT-02` PASS | `null` | `0 Logs` (nicht lesbare Protokolle) |
  | `REP-01` PASS | `null` | `31 Minutes` (höchste Latenz über alle Partnerschaften) |
  | `REP-02` PASS | `null` | `0 Servers` (nicht abrufbare DCs) |
  | `PWD-01` PASS | `null` | `14 Characters` |

  **Ein leeres `ActualValue` bei PASS ist damit ein Warnsignal statt Normalzustand.** Dashboard wie Auditbericht können jetzt belegen, dass tatsächlich gemessen wurde — und die Werte über die Zeit vergleichen.

- Umgesetzt für Replikation, Ereignisprotokolle, Kennwortrichtlinien und die Security-Zähler. Verifiziert: **0 Statusänderungen** über alle 73 Verdikte, der Umbau ist rein additiv.
- Ohne Nachweis bleiben nur `DNS-01` und `SITE-05` — die beiden Regeln, die sich bewusst mit `DNS-06` bzw. `SITE-02` gegenseitig ausschliessen.

### v2.6.1 — Nicht prüfbare Domänencontroller wurden verschwiegen
Gefunden im ersten Feldtest von v2.6.0 gegen ein produktives AD mit zwei DCs.

- **fix:** **REP-01 und EVT-01 meldeten PASS, wenn ein DC gar nicht geprüft werden konnte.** Der Collector setzt bei einem Fehler `Status = "Unreachable"`, die `Condition` beider Regeln lautete aber nur `["Error"]` — nicht prüfbare Einträge wurden übersprungen. Im Feldtest war auf einem der beiden DCs der RPC-Zugriff blockiert; das Ergebnis lautete:

  ```json
  "Id": "EVT-01",  "Status": "PASS",  "ActualValue": null,  "AffectedItems": null
  ```

  Grün, obwohl die Hälfte der Umgebung nie betrachtet wurde. Das ist dieselbe Fehlerklasse wie die acht toten Regeln aus v2.4.11/v2.4.12 — eine Prüfung, die bei einem Problem schweigt.

- **feat:** **REP-02 und EVT-02** (beide MEDIUM) melden jetzt explizit, dass für einen DC **keine Aussage** vorliegt, samt Ursache und Handlungsanweisung. Bewusst als **eigene Regeln** statt `Unreachable` in die Condition von REP-01/EVT-01 aufzunehmen: „nicht prüfbar" und „geprüft und zu kurz" erfordern unterschiedliche Reaktionen und dürfen im Dashboard nicht verschmelzen.
- **perf:** Schlägt der erste Log-Zugriff auf einem DC am RPC fehl, werden die restlichen Logs desselben DCs übersprungen. Jeder Versuch kostet rund 20 Sekunden Timeout — im Feldtest gingen so 42 Sekunden für einen einzigen unerreichbaren DC verloren.
- **fix:** Die Fehlermeldung nennt jetzt die wahrscheinliche Ursache statt nur `The RPC server is unavailable`:

  | Fehler | Hinweis im Report und Log |
  |---|---|
  | RPC nicht verfügbar | Firewall-Regel „Remote-Ereignisprotokollverwaltung" auf dem DC aktivieren |
  | Zugriff verweigert | Konto in die Gruppe „Ereignisprotokollleser" aufnehmen |

- Verifiziert: 2 neue Verdikte, **0 Statusänderungen** bei den bestehenden 71 Regeln.

### v2.6.0 — Zwei neue Prüfungen: Replikations-Latenz und Protokoll-Vorhaltedauer
Die beiden Werte `ReplicationLatencyMaxMinutes` (45) und `MaxEventLogAgeDays` (30) standen seit jeher in `settings.json`, wurden aber **von keiner Zeile Code gelesen** — Kunden konnten sie einstellen, ohne dass etwas geschah. Beide sind jetzt wirksam.

- **feat:** **REP-01 (HIGH) — Replikations-Latenz.** Über `Get-ADReplicationPartnerMetadata -Scope Server` wird je DC und Partner die Zeit seit der **letzten erfolgreichen** Replikation ermittelt (`LastReplicationSuccess`). Liegt sie über dem Grenzwert, greift die Regel. `ConsecutiveReplicationFailures` und `LastReplicationResult` werden zur Diagnose mitgeführt. Nicht erreichbare DCs erzeugen einen Eintrag mit Status `Unreachable`, statt still zu verschwinden.
- **feat:** **EVT-01 (MEDIUM) — Vorhaltedauer der Ereignisprotokolle.**

  > **Auslegung von `MaxEventLogAgeDays`:** Geprüft wird die **Vorhaltedauer**, nicht das Alter einzelner Ereignisse. Reicht der älteste noch vorhandene Eintrag von „Directory Service" oder „System" **weniger weit zurück** als der konfigurierte Zeitraum, ist das Protokoll zu klein bemessen oder rotiert zu schnell — nach einem Sicherheitsvorfall fehlen dann genau die Einträge, die zur Aufklärung gebraucht werden. Das ist eine Auslegungsentscheidung; wenn ihr die Semantik anders wollt, ist sie in `Get-ADEventLogRetention` an einer Stelle geändert.

- **feat:** Beide Bereiche haben eigene GUI-Auswahl (Analyse + Empfehlungen) und laufen im NoGui-Modus mit. `settings.json` kennt sie unter `ShowRecommendations`.
- **fix:** Der Tooltip der KRBTGT-Kachel war hartcodiert deutsch (`Alter: N Tage`) und erschien so auch im englischen Report.
- Verifiziert: **2 neue Verdikte, 0 Statusänderungen** bei den bestehenden 69 Regeln.

> ⚠️ **Noch nicht gegen ein echtes Active Directory verifiziert.** Beide Collector wurden ausschliesslich mit Mock-Daten getestet — `Get-ADReplicationPartnerMetadata` und `Get-WinEvent -ComputerName` lassen sich ohne Domänencontroller nicht ausführen. Vor dem Kundeneinsatz in einer echten Umgebung prüfen, insbesondere Laufzeit bei vielen DCs und Berechtigungen für den Remote-Zugriff auf die Ereignisprotokolle.

### v2.5.0 — Messwerte im Upload-JSON (schemaVersion 2) und tunebare Schwellenwerte
- **feat:** **Verdikte tragen jetzt Messwerte, nicht nur einen fertigen Satz.** Bisher enthielt ein Verdikt ausschliesslich `Detail` — eine in *einer* Sprache gerenderte Zeichenkette wie „… (Aktueller Wert: 6 Zeichen)". Zahl, Einheit und Formulierung waren untrennbar verschmolzen. Neu kommen hinzu:

  | Feld | Bedeutung |
  |---|---|
  | `ActualValue` | der gemessene Wert (`6`, `18`, `0`) |
  | `Unit` | i18n-**Schlüssel** (`"Characters"`), nicht das übersetzte Wort |
  | `AffectedItems` | Liste bei listenartigen Befunden (betroffene Server, Partitionen, Subnetze) |
  | `ExpectedValue` | der Sollwert aus `recommendations.json` |
  | `Operator` | `gte` / `lte` — beschreibt den Soll-Zustand |

  Damit kann ein Dashboard „6 Zeichen (empfohlen: ≥12)" in beliebiger Sprache selbst rendern und Werte über die Zeit vergleichen. **Rein additiv:** `Detail` bleibt erhalten, Konsumenten von `schemaVersion 1` laufen unverändert weiter.
- **feat:** **Schwellenwerte stehen in `recommendations.json`** statt als Literale im Code:
  ```json
  "Threshold": { "value": 12, "operator": "gte", "unit": "Characters" }
  ```
  Neun Regeln (PWD-01, PWD-03 bis PWD-06, SEC-04 bis SEC-06, SITE-01) sind ohne Codeänderung tunebar. Domänenlogik, die sich nicht als Schwellenwert ausdrücken lässt, bleibt bewusst im Code — etwa dass `LockoutThreshold = 0` „keine Sperre" bedeutet und immer ein Befund ist, oder dass `LockoutDuration = 0` „dauerhaft gesperrt" heisst und gewollt ist.
- **feat:** Der HTML-Report zeigt den Sollwert: „(empfohlen: ≥12 Zeichen)" bzw. „(recommended: ≥12 characters)". Gerendert an **einer** Stelle aus denselben strukturierten Feldern, nicht in jedem Auswertungsblock einzeln.
- **fix:** Die KRBTGT-Regel respektiert jetzt `Thresholds.KrbtgtPasswordAgeDays` aus `settings.json`. Vorher stand in der Regel fest `180`, während die Kachel-Anzeige die Einstellung bereits auswertete — bei einem abweichenden Kundenwert färbte sich die Kachel rot, ohne dass die Empfehlung feuerte.
- Verifiziert gegen die Referenzmessung: **0 Statusänderungen** über alle 69 Verdikte. Der Umbau ist rein strukturell.

**Abdeckung:** 49 der 69 Regeln liefern jetzt einen Messwert (12× `ActualValue`, 37× `AffectedItems`, davon 9 zusätzlich mit `ExpectedValue`). Die verbleibenden 20 — DomainOverview, FSMO-Erreichbarkeit, OU-Sicherheit, Entra und die beiden DNS-Scavenging-Regeln — liefern weiterhin nur `Detail` und sind ein Kandidat für eine Folgeversion.

### v2.4.12 — Die letzten drei nicht feuernden Regeln repariert
- **fix:** **SITE-03 (Änderungsbenachrichtigung der Site-Links).** Für diese Regel existierte **überhaupt kein Auswertungscode** — sie stand in `recommendations.json`, wurde aber nirgends geprüft und meldete immer PASS. Das benötigte Feld liefert `Get-ADSitesInfo` seit jeher (`ChangeNotification = options -band 1`).
- **fix:** **AD-FSMO-08 (Infrastruktur-Master ist Global Catalog).** Die Prüfung las `IsGC` aus `$Data.Discovery`; dieses Objekt führt nur `Server, OS, IPv4, UptimeHrs, FreeDiskGB, FreeDiskPct, Status`. Die GC-Eigenschaft steht unter `$Data.Sites.Sites[].Servers[].IsGC`. `$isGC` war damit immer `$false`.
- **fix:** **SRV-02 (DC-Erreichbarkeit).** Der Auswertungscode war korrekt — die Mock-Daten setzten `Status = "Error"`, aber nicht `OS = "Unreachable"`, woran die Regel einen nicht erreichbaren DC erkennt. Nur der Sample-Report war betroffen, nicht der Produktivbetrieb.
- Verifiziert gegen die Referenzmessung: exakt 3 Statusänderungen, keine Regression bei den abhängigen Regeln (SITE-04, OS-01, SRV-01-E/W feuern weiterhin).

**Damit feuern bei Worst-Case-Mockdaten 67 von 69 Regeln.** Die verbleibenden zwei sind **bewusst** inaktiv und kein Defekt:

| Regel | Grund |
|---|---|
| `DNS-01` Scavenging-Zonenkonflikt | schliesst sich mit `DNS-06` aus — DNS-01 meldet *einige* Zonen ohne Scavenging, DNS-06 *alle*. Die Mock-Daten decken den DNS-06-Fall ab. |
| `SITE-05` Keine Subnetze definiert | schliesst sich mit `SITE-02` aus — sind Subnetze vorhanden (aber ohne Site), greift SITE-02. |

### v2.4.11 — Fünf Empfehlungsregeln haben nie gefeuert
- **fix:** **PWD-04 (Sperrschwelle bei Fehlversuchen).** Das Switch-Label in `Reporting.psm1` hiess `"LockoutThreshold"`, Collector und `recommendations.json` liefern aber `LockoutThresh`. Der `case` matchte nie. Bei einer Domäne mit `LockoutThreshold = 0` — also **komplett deaktiviertem Kontosperr-Schutz** — meldete der Report für diese HIGH-Prüfung „bestanden".
- **fix:** **SVC-NTDS, SVC-NET, SVC-DNS, SVC-KDC.** Die Auswertung erwartete `$entry.Details` mit `.ServiceName`/`.ShortName`. Weder `Get-ADServiceStatus` noch die Mock-Daten liefern diese Felder — beide erzeugen eine flache Liste mit `.Service`. Damit war `$svc` immer `$null` und keine der vier Dienste-Regeln konnte feuern: ein gestoppter NTDS-, Netlogon-, DNS- oder KDC-Dienst blieb im Report unsichtbar.
- **fix:** Sample-Reports neu erzeugt. Sie enthielten ENT-01 nicht und natürlich keine der fünf reparierten Regeln.
- Verifiziert gegen eine Referenzmessung aller 69 Verdikte: exakt 5 Statusänderungen (PWD-04, SVC-DNS, SVC-KDC, SVC-NET, SVC-NTDS jeweils PASS → FAIL), keine Kollateraleffekte. Worst-Case-Mockdaten: vorher 59 FAIL / 10 PASS, jetzt 64 FAIL / 5 PASS.

> **Noch offen (bekannt, nicht in dieser Version behoben):**
> `SITE-03` (Änderungsbenachrichtigung der Site-Links) hat **überhaupt keinen Auswertungscode** — die Regel steht in `recommendations.json`, wird aber nirgends geprüft.
> `AD-FSMO-08` (Infrastruktur-Master ist GC) liest `IsGC` aus `$Data.Discovery`; dieses Objekt führt das Feld nicht — der echte Collector liefert `IsGC` nur in `Sites.Servers`.
> `SRV-02` (DC-Erreichbarkeit) funktioniert produktiv korrekt — nur die Mock-Daten setzen `Status="Error"` ohne `OS="Unreachable"`, weshalb die Regel im Sample-Report fehlt.
> `SITE-05` und `DNS-01` feuern bewusst nicht: sie schliessen sich mit `SITE-02` bzw. `DNS-06` gegenseitig aus.

### v2.4.10 — Encoding beim Config-Laden + Mehrsprachigkeit des Reports
- **fix:** Die Loader in `Utils.psm1` (`Get-ADHCConfig`, `Get-ADHCI18n`, `Get-ADHCMapping`) sowie das Laden von Template und CSS in `Reporting.psm1` riefen `Get-Content -Raw` **ohne** `-Encoding UTF8` auf. PowerShell 5.1 dekodiert dann mit der System-ANSI-Codepage. Da die `config/*.json` konventionsgemäss BOM-frei sind, wurde auf Servern mit Codepage **1252** aus `Kennwörter` ein `KennwÃ¶rter` und aus `Die Mindestkennwortlänge…` ein `Die MindestkennwortlÃ¤nge…` — der Mojibake landete über i18n-Labels und Empfehlungstexte direkt im Kundenreport. Alle fünf Aufrufe lesen jetzt explizit UTF-8.
- **fix:** 9 hartcodierte deutsche Strings im Report lokalisiert. Der **englische** Report enthielt bisher `Betroffene Server` (18×), `Partitionen`, `Vorkommen`, `Empfehlung`, `Benutzer`, `Distinguished Name (Pfad)` (2 Tabellen), `Keine Server vorhanden`, `Kein GC konfiguriert`, `Keine gefunden`, `Detaillierte Liste: Verwaiste SIDs (ACLs)` und `Prüfen & Bereinigen`. Dafür kamen 7 neue i18n-Keys hinzu.
- **fix:** Tippfehler in `i18n.en.json` — `"Recommandation"` → `"Recommendation"`.
- **docs:** Sample-Reports neu erzeugt. Die alte englische Fassung enthielt den deutschen Text, die alte deutsche Fassung enthielt Mojibake im eingebetteten CSS.
- Verifiziert durch Erzeugung beider Reports aus Mock-Daten: der englische Report enthält 0 deutsche Strings, der deutsche ist unverändert korrekt.

> **Hinweis für Entwickler:** `Get-Content` in diesem Projekt **immer** mit `-Encoding UTF8` aufrufen. Ohne den Parameter ist das Verhalten davon abhängig, ob auf dem Zielserver die Systemoption „Beta: Unicode UTF-8" aktiv ist — auf Entwicklungsmaschinen mit UTF-8-Codepage bleibt der Fehler unsichtbar und schlägt erst beim Kunden zu.

### v2.4.9 — UTF-8-BOM auf alle PowerShell-Dateien ausgeweitet
- **fix:** Der BOM-Fix aus v2.4.4 betraf **nur** `Reporting.psm1`. `Diag.psm1`, `Utils.psm1`, `Update-EntraVersion.ps1` und drei `.psd1`-Manifeste blieben BOM-los. Auf Servern mit ANSI-Codepage **1252** wurden die Umlaute dort verfälscht dekodiert — betroffen waren unter anderem die i18n-Fallbacks „Passwort läuft nie ab" und „Passwort älter als Richtlinie", die im **Report und CSV** erscheinen, sowie mehrere Log-Ausgaben.
- **fix:** Alle `.ps1`/`.psm1`/`.psd1` tragen jetzt ein UTF-8-BOM — auch die aktuell ASCII-reinen. Damit führt ein später hinzugefügter Umlaut das Problem nicht stillschweigend wieder ein. JSON-Dateien bleiben konventionsgemäss BOM-frei.
- **docs:** README nannte die Modul-Manifeste als v2.3.0; tatsächlich stehen sie auf **v2.1.0**. Korrigiert.
- Verifiziert durch Simulation des CP1252-Lesevorgangs: vor dem Fix parste `tests/pester/ADHealthCheck.Tests.ps1` mit 25 Fehlern, die übrigen Dateien parsten zwar, lieferten aber verfälschte Zeichen. Nach dem Fix sind alle 13 Dateien geschützt.

### v2.4.8 — Korrektur irreführender PII-Kommentare
- **docs:** Die Kommentare in `modules/ADHealthCheck.Reporting.psm1` beschrieben das Upload-JSON als „Rohdaten **ohne** PII". Das trifft seit v2.4.6 nicht mehr zu — `DisabledInheritanceUser` enthält bewusst wieder **Klarnamen und DNs** der ersten 50 Konten. Die Kommentare sprechen jetzt von *minimierter* PII und benennen ausdrücklich, was enthalten bleibt.
- Keine Verhaltensänderung — der Export selbst ist unverändert. Der Bump dient allein dazu, die Korrektur über den Self-Update auf bestehende Installationen auszurollen.

### v2.4.7 — Fix: Self-Update löste nie aus (Version aus Header abgeleitet)
- **fix:** Die Version stand an **zwei** Stellen: im `.NOTES`-Header (Zeile 6, gegen den der Remote-Vergleich läuft) und als Literal in `$script:LocalVersion`. Beim Bump auf v2.4.6 wurde der Header vergessen — jeder Client verglich Remote `2.4.5` gegen lokal `2.4.6`, wertete das als „nicht neuer" und meldete dauerhaft **„Aktuell"**. Der Self-Update konnte seit v2.4.5 nicht mehr auslösen.
- **fix:** `$script:LocalVersion` wird jetzt zur Laufzeit aus dem eigenen Header geparst (erste 20 Zeilen), das Literal entfällt. Ein Auseinanderlaufen ist damit konstruktiv ausgeschlossen.
- **refactor:** `$script:VersionPattern` als einzige Regex-Definition für die lokale **und** die entfernte Seite — beide Werte werden garantiert identisch geparst.
- **fix:** Ist der Header nicht lesbar, bricht der Update-Check mit Meldung ab, statt blind zu vergleichen.
- **chore:** Erstveröffentlichung als öffentliches Repository (MIT-Lizenz), damit der Self-Update ohne Authentifizierung funktioniert.

### v2.4.6 — Vererbungs-Benutzerliste im Upload-JSON
- **feat:** Die Liste der Konten mit deaktivierter AD-Vererbung wird wieder ins Upload-JSON aufgenommen: `DisabledInheritanceUser` mit den ersten **50** Einträgen (`Name`, `DN`) — Parität zum HTML-Report, der ebenfalls `Select-Object -First 50` nutzt.
- **feat:** `DisabledInheritanceUserCount` enthält unverändert die **volle** Anzahl als Basis für die „… und N weitere"-Fussnote im Dashboard.
- ⚠️ **Datenschutz:** Dies ist eine bewusste Wiederaufnahme von **Klarnamen und DNs** ins Upload-JSON. Das JSON unter `output/data/` enthält damit personenbezogene Daten und ist entsprechend zu behandeln (`output/` ist per `.gitignore` ausgeschlossen). Die Benutzer-Detailliste `Security.RawExportData` bleibt weiterhin entfernt und existiert nur in der CSV.

### v2.4.5 — DNS-Reverse-Zonen, Übersetzungen, Encoding
- **fix:** System-Reverse-Zonen (`0/127/255.in-addr.arpa`) werden von der „nicht AD-integriert"-Prüfung ausgeschlossen. Diese Standard-Primary-Zonen können nie AD-integriert sein und erzeugten sonst falsche Findings.
- **fix:** `recommendations.json` — englische `SubCategory`-Werte korrigiert (Server Gesundheit → Server Health, Konnektivität → Connectivity, Objekt-Sicherheit → Object Security).
- **chore:** Encoding vereinheitlicht — JSON BOM-frei, `.psm1` mit UTF-8-BOM.

### v2.4.4 — Fix: Ladefehler auf ANSI-Codepage-Servern (UTF-8-BOM)
- **fix:** `modules/ADHealthCheck.Reporting.psm1` wird jetzt mit **UTF-8-BOM** gespeichert. Windows PowerShell 5.1 liest BOM-lose Dateien anhand der System-Codepage; auf Servern mit ANSI-Codepage **1252** wurden die UTF-8-Sonderzeichen (Umlaute, Box-Zeichen) falsch dekodiert, wodurch die Datei nicht mehr parste (`Missing closing '}'` an `function New-ADHCReport`). Das BOM erzwingt UTF-8 auf jeder Codepage. (Die BOM-Entfernung aus v2.4.0 war die eigentliche Ursache — sie blieb auf UTF-8-Systemen unsichtbar.)

### v2.4.3 — Robuster Self-Update (Fix: korrupte Dateien bei flaky Netzwerk)
- **fix:** Der Self-Update lädt jede Datei zuerst in eine Temp-Datei, prüft die Integrität (nicht leer; PowerShell-Dateien via Parser, JSON via `ConvertFrom-Json`) und verschiebt sie **erst nach erfolgreicher Validierung** atomar an den Zielort. Ein abgebrochener/abgeschnittener Download (Timeout, Netzwerkabbruch) überschreibt damit **nie** mehr die installierte Datei — behebt den `Missing closing '}'`-Ladefehler nach einem unterbrochenen Update.

### v2.4.2 — HTML-Report nutzt den eindeutigen Titel
- **feat:** Der HTML-Report zeigt in der Empfehlungsliste (`Area`-Spalte) den kuratierten `Title` je Regel statt der gruppierenden `SubCategory` — konsistent zum M365-Security-Dashboard. Fällt auf `SubCategory` zurück, wenn eine Regel (noch) keinen `Title` hat. Der Verdikt-Export im Upload-JSON bleibt unverändert.

### v2.4.1 — Eindeutige, zweisprachige Check-Titel
- **feat:** Jede der 69 Regeln in `config/recommendations.json` hat jetzt ein kuratiertes `Title { de, en }` — eine kurze, eindeutige Überschrift je Check (z.B. `DCDIAG: DFSR-Replikation (SYSVOL)` statt der 18-fach wiederholten SubCategory `DCDIAG`). Das M365-Security-Dashboard nutzt `Title` als Anzeigetitel; `SubCategory` bleibt als Gruppierung/Fallback erhalten (rückwärtskompatibel).

### v2.4.0 — Dashboard-Upload-Export (JSON)
- **feat:** Das `output/data/ADHealthCheck_*.json` ist jetzt ein Upload-Vertrag für das M365-Security-Dashboard: Metadaten (`schemaVersion`, `collectorVersion`, `collectedAt`, `language`, `domainFQDN`), ein `assessment`-Block mit dem Verdikt (PASS/FAIL/NOT_CHECKED) je Regel über ALLE 69 Regeln, und die Rohdaten unter `data`.
- **feat:** Verdikt-Export nutzt die bestehende Empfehlungs-Engine (keine doppelte Logik) — die Auswertung erfolgt für alle Sektionen unabhängig von den `ShowRecommendations`-Anzeige-Toggles.
- **feat:** Datumsangaben im Upload-JSON als ISO-8601 (statt WCF `/Date(ms)/`).
- **feat:** Datenschutz: personenbezogene Detaillisten werden aus dem Upload-JSON entfernt (`Security.RawExportData` komplett; `OUAccountSecurity.DisabledInheritanceUser` → `DisabledInheritanceUserCount`). Die vollständige Benutzerliste bleibt weiterhin im CSV-Export erhalten.
- **fix:** BOM aus `ADHealthCheck.Reporting.psm1` entfernt (PS 5.1).

### v2.3.0 — Self-Update
- **feat:** Self-Update beim Start — Versionsvergleich gegen GitHub Raw-URL
- **feat:** Interaktiver Download-Dialog mit Bestätigung (J/N)
- **feat:** Backup der aktuellen Version vor Update (`output\backup\vX.Y.Z\`)
- **feat:** Download aller 17 Projektdateien (Module, Config, Templates)
- **feat:** Konfigurierbare GitHub-Parameter (User, Repo, Branch) im Script-Header
- **feat:** Fehlerbehandlung bei Netzwerk-Timeout — Script startet normal

### v2.2.0 — Prerequisite-Check
- **feat:** 9 Voraussetzungen werden beim Start geprüft
- **feat:** Admin-Rechte Prüfung — sofortiger Abbruch wenn nicht erfüllt
- **feat:** PowerShell-Version und Edition Check (Desktop 5.1 Pflicht, Core blockiert)
- **feat:** .NET Framework Version Check (min. 4.5)
- **feat:** RSAT ActiveDirectory-Modul Check — kritisch, Auto-Install möglich
- **feat:** RSAT DNS-Server-Tools + GroupPolicy-Tools — optional, Auto-Install
- **feat:** WinRM-Dienst Status und Ausführungsrichtlinie Check
- **feat:** AD-Domänen-Erreichbarkeit Check
- **feat:** Interaktiver Installations-Dialog (kritisch vs. optional)
- **feat:** DNS-Checkbox in GUI bei fehlendem RSAT deaktiviert + Tooltip
- **fix:** `$psEdition` → `$psEditionVal` (PowerShell read-only Variable Konflikt)

### v2.1.0 — GUI, Module, Stabilität
- **feat:** GUI auf `ScrollablePanel` umgestellt — funktioniert auf allen Auflösungen
- **feat:** `FormBorderStyle` auf `Sizable` — Fenster manuell anpassbar
- **feat:** `NoGui`-Modus für Scheduled Tasks implementiert
- **feat:** 5 Modul-Manifeste (`.psd1`) v2.1.0 erstellt
- **feat:** `report.template.html` erstellt (war fehlend, 20 Platzhalter)
- **feat:** `.gitignore` hinzugefügt (schützt `output/` vor Commit)
- **feat:** Input-Validierung vor Start-Analysis
- **feat:** `settings.json` Safe-Merge verhindert Datenverlust
- **feat:** Fortschrittsbalken und StatusLabel im GUI
- **fix:** `Get-ADSecurityInfo` Aufruf im Launcher mit korrekter Signatur
- **fix:** `$script:UseMockData` korrekt initialisiert und zurückgesetzt
- **fix:** Entra-Versionsabfrage mit `TimeoutSec=15`
- **fix:** DNS Scavenging-Loop über `$allTestedZones` statt `$allZones`
- **fix:** Log-Pfad in `Utils.psm1` robuster via `$repoRoot`
- **fix:** UTF-8 BOM aus allen PS-Dateien entfernt (PS5.1 Startfehler)
- **fix:** Inline-`if` in `[PSCustomObject]` für PS5.1 Kompatibilität
- **fix:** `SubCategory`-Objekt `{de/en}` via `$LangCode` aufgelöst
- **fix:** Umlaute in GUI-Checkboxen durch Encoding-Fehler

### v2.0.0 — i18n & Robustheit
- **feat:** `Get-ADOUAndAccountSecurity` asynchron via PowerShell Runspace
- **feat:** `ProgressCallback`-Parameter für ACL-Analyse
- **feat:** Pester-Tests neu geschrieben (6 Blöcke, 30+ Tests)
- **feat:** `SubCategory` in `recommendations.json` zweisprachig `{de/en}`
- **feat:** 11 neue i18n-Keys (NoneFound, AllUpToDate, AllServersOnline, ...)
- **fix:** Alle hartcodierten DE-Strings durch i18n-Keys ersetzt
- **fix:** `$htmlOUSec` NullPointer-Bug
- **fix:** `Get-ADSecurityInfo` Scope-Bug
- **fix:** DNS TotalZoneCount / MissingScavenging Mismatch
- **fix:** `PWD-04/05/06` in `recommendations.json` vervollständigt
- **fix:** `i18n.en.json` deutsche Werte korrigiert

### v1.0.0 — Erstveröffentlichung
- WinForms GUI mit 11 Analyse-Bereichen
- HTML-Report mit dynamischem Ampel-System
- Zweisprachigkeit DE/EN via i18n-JSON
- Empfehlungs-Engine mit 69 Regeln
- CSV-Export für Security-Details (lokalisiert)
- Sample-Report mit Mock-Daten

---

## Rechtlicher Hinweis

Das Skript führt **ausschliesslich Lesevorgänge** im Active Directory durch. Es werden keine Konfigurationsänderungen vorgenommen. Die generierten Reports und CSV-Exporte können personenbezogene Daten (AD-Benutzernamen, UPNs) enthalten — diese sind durch `.gitignore` vom Repository ausgeschlossen.

Die Nutzung erfolgt auf eigene Gefahr. Eine vorherige Prüfung in einer Testumgebung wird empfohlen.

---

*ADHealthCheck Pro v2.10.6 — LAKE Solutions AG*
