# AD Health Check Pro

**Version 2.1.0** | LAKE Solutions AG

Professionelles PowerShell-Tool zur Analyse und Bewertung von Microsoft Active Directory-Umgebungen. Das Tool führt technische Diagnosen durch und erstellt einen modernen HTML-Report mit integrierten Handlungsempfehlungen und automatisierten CSV-Exporten.

---

## Systemvoraussetzungen

| Anforderung | Details |
|---|---|
| Betriebssystem | Windows Server 2012 R2+ / Windows 10+ |
| PowerShell | Version 5.1 (Desktop Edition) |
| RSAT-Modul | ActiveDirectory (AD PowerShell) |
| Berechtigungen | Administrator + AD-Leserechte (inkl. nTSecurityDescriptor) |
| Netzwerk | Erreichbarkeit der DCs (RPC, LDAP, DNS, SMB) |

---

## Hauptmerkmale

- Interaktive WinForms-GUI mit Scroll-Unterstützung (auch bei niedrigen Auflösungen)
- Mehrsprachigkeit (Deutsch / Englisch) für GUI, Report und CSV-Exporte
- Asynchrone ACL-Analyse mit Fortschrittsanzeige (kein GUI-Freeze)
- Dynamisches Ampel-System im HTML-Dashboard (Grün/Gelb/Rot)
- Deklarative Empfehlungs-Engine via `recommendations.json` (69 Regeln)
- Automatisierter CSV-Export für Compliance-Audits
- NoGui-Modus für Scheduled Tasks und Automatisierung

---

## Analyse-Bereiche

| Bereich | Beschreibung |
|---|---|
| Domain Infrastruktur | Forest/Domain Level, Recycle Bin, KRBTGT-Alter |
| FSMO Rollen | Erreichbarkeit und Architektur-Checks |
| DCDIAG Health Matrix | 20+ Tests pro Domain Controller |
| DC System Health | Disk, Uptime, OS, IPv4 |
| Disaster Recovery | AD Backup-Alter aller Partitionen |
| Systemdienste | NTDS, Netlogon, DNS, KDC Status |
| Sites & Replikation | Topologie, Verbindungen, Site Links |
| Identitäts-Sicherheit | Inaktive Konten, Passwort-Hygiene, Privilegierte Gruppen |
| OU & ACL-Audit | Verwaiste SIDs, Vererbungsstatus |
| Entra ID Sync | Versions- und Dienste-Check des Azure AD Connect Agents |
| DNS Health | Zonen, SRV-Records, Scavenging, Nameserver-Status |

---

## Projektstruktur

```
ADHealthCheck/
├── ADHealthCheck.ps1              Hauptprogramm (GUI + Launcher)
├── .gitignore
├── README.md
│
├── config/
│   ├── settings.json              Globale Einstellungen & Schwellenwerte
│   ├── i18n.de.json               Sprachdatei Deutsch
│   ├── i18n.en.json               Sprachdatei Englisch
│   ├── mapping.json               Werte-Mapping (Forest/Domain Levels)
│   └── recommendations.json      Empfehlungs-Engine (69 Regeln, de/en)
│
├── modules/
│   ├── ADHealthCheck.Utils.psm1   Logging, Config, i18n, HTML-Helpers
│   ├── ADHealthCheck.Utils.psd1   Modul-Manifest v2.1.0
│   ├── ADHealthCheck.Diag.psm1    AD-Diagnose (DC, FSMO, Security, ACL)
│   ├── ADHealthCheck.Diag.psd1    Modul-Manifest v2.1.0
│   ├── ADHealthCheck.Reporting.psm1  HTML-Report & Empfehlungs-Engine
│   ├── ADHealthCheck.Reporting.psd1  Modul-Manifest v2.1.0
│   ├── ADHealthCheck.DNS.psm1     DNS-Zonen, SRV, Scavenging
│   ├── ADHealthCheck.DNS.psd1     Modul-Manifest v2.1.0
│   ├── ADHealthCheck.EntraSync.psm1  Entra ID / Azure AD Connect
│   ├── ADHealthCheck.EntraSync.psd1  Modul-Manifest v2.1.0
│   └── Update-EntraVersion.ps1   Automatische Versions-Aktualisierung
│
├── templates/
│   ├── report.template.html       HTML-Gerüst mit Platzhaltern
│   └── report.style.css           Design & Ampel-Styling
│
├── tests/
│   └── pester/
│       └── ADHealthCheck.Tests.ps1  Pester v5 Tests (30+ Tests, 6 Blöcke)
│
└── output/                        (durch .gitignore ausgeschlossen)
    ├── reports/                   Generierte HTML-Reports
    ├── data/                      JSON-Snapshots
    └── logs/                      ADHealthCheck.log
```

---

## Anwendung

### GUI-Modus (Standard)

```powershell
# Als Administrator ausführen:
.\ADHealthCheck.ps1

# Mit Sprachvorgabe:
.\ADHealthCheck.ps1 -Language en
```

1. Sprache, Entra-Server, Inaktivitätsschwelle und DNS-Server konfigurieren
2. Analyse-Bereiche und Empfehlungen aktivieren/deaktivieren
3. **„Report erstellen"** klicken — der HTML-Report öffnet sich automatisch
4. CSV-Export findet sich unter `output\reports\`

### NoGui-Modus (Scheduled Task / Automatisierung)

```powershell
# Alle Bereiche, Standardsprache (de):
.\ADHealthCheck.ps1 -NoGui

# Mit englischem Report:
.\ADHealthCheck.ps1 -NoGui -Language en
```

### Pester-Tests ausführen

```powershell
Install-Module Pester -Force -MinimumVersion 5.0
Invoke-Pester -Path .\tests\pester\ADHealthCheck.Tests.ps1 -Output Detailed
```

---

## Handlungsempfehlungen (Governance)

Die `recommendations.json` enthält 69 Regeln in 12 Kategorien:

| Priorität | Bedeutung |
|---|---|
| **HIGH** | Kritische Infrastrukturfehler, Replikationsstopps, Sicherheitslücken |
| **MEDIUM** | Sicherheitsmängel, verwaiste SIDs, ACL-Vererbungsprobleme |
| **LOW** | Hygiene-Massnahmen, Best-Practice-Abweichungen |

---

## Rechtlicher Hinweis

Das Skript führt **ausschliesslich Lesevorgänge** durch. Dennoch erfolgt die Nutzung auf eigene Gefahr. Eine vorherige Prüfung in einer Testumgebung wird empfohlen.
