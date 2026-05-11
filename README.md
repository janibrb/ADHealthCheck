### Active Directory Health Check

# PROJEKTBESCHREIBUNG

AD Health Check Pro ist ein professionelles PowerShell-Tool zur Analyse und
Bewertung von Microsoft Active Directory-Umgebungen. Das Tool führt technische
Diagnosen durch und erstellt einen modernen HTML-Report mit integrierten
Handlungsempfehlungen und automatisierten CSV-Exporten.

#SYSTEMVORAUSSETZUNGEN

    Betriebssystem: Windows Server 2012 R2 oder neuer / Windows 10 oder neuer.
    PowerShell-Version: Mindestens Version 5.1 (Desktop Edition).

    Erforderliche Module: RSAT-AD-PowerShell (Active Directory Modul).

    Berechtigungen:

        Das Skript muss als Administrator ("Als Administrator ausführen")
        gestartet werden.

        Leseberechtigung auf die Konfigurationspartition und Domänenpartition.

        Erweiterte Leserechte für Sicherheitsanalysen (nTSecurityDescriptor).

    Netzwerk: Erreichbarkeit der Domain Controller (RPC, LDAP, DNS, SMB).

# HAUPTMERKMALE

    Interaktive Benutzeroberfläche zur Konfiguration des Scan-Umfangs.

    Mehrsprachigkeit (Deutsch und Englisch) für GUI, Report und CSV-Exporte.

    Performance-optimierte ACL-Analyse zur Identifizierung von Sicherheitsrisiken.

    Dynamisches Ampel-System im HTML-Dashboard (Grün/Gelb/Rot).

    Automatisierte Datenaufbereitung für Compliance-Audits.

# ANALYSE-BEREICHE

Das Tool prüft die folgenden Sektionen:

    Domänen-Infrastruktur: Basisinformationen zur Gesamtstruktur.

    Betriebsmaster-Konfiguration: Status und Erreichbarkeit der FSMO-Rollen.

    Verzeichnisdienst-Integrität: Umfassende Diagnose der DC-Funktionen (DCDIAG).

    Domain Controller Health: Vitalwerte und Betriebszustand der Server.

    Disaster Recovery Readiness: Status der Active Directory Backups.

    Systemdienste-Monitor: Statusprüfung kritischer AD-Dienste.

    Standorte & Replikation: Analyse der Topologie und Replikationsvorgänge.

    Identitäts-Sicherheit (Accounts): Audit von inaktiven oder unsicheren Konten.

    Objekt- & ACL-Audit: Prüfung auf verwaiste SIDs und Vererbungsstatus.

    Hybrid Identity Sync: Status der Entra ID (Azure AD) Synchronisation.

    Namensauflösung (DNS): Integritätsprüfung der DNS-Zonen und Einträge.

# PROJEKTSTRUKTUR

ADHealthCheck/
|-- ADHealthCheck.ps1          (Hauptprogramm)
|-- config/
|   |-- settings.json          (Globale Einstellungen)
|   |-- i18n.de.json           (Sprachdatei Deutsch)
|   |-- i18n.en.json           (Sprachdatei Englisch)
|   -- recommendations.json   (Logik für Empfehlungen) |-- modules/ |   |-- ADHealthCheck.Diag.psm1      (Diagnose-Logik) |   -- ADHealthCheck.Reporting.psm1 (Report-Generierung)
|-- templates/
|   |-- report.template.html   (HTML-Struktur)
|   -- report.style.css       (Design-Definitionen) -- output/
|-- reports/               (Generierte HTML-Berichte)
`-- csv/                   (Sicherheits-Detailberichte)

# ANWENDUNG

    Starten Sie die "ADHealthCheck.ps1" mit Administratorrechten.
    Wählen Sie in der GUI die gewünschte Sprache und die Prüfungsbereiche aus.
    Passen Sie bei Bedarf die Schwellenwerte für inaktive Konten an.
    Klicken Sie auf "Report erstellen".

    Nach Abschluss öffnet sich der HTML-Report automatisch. Detaillierte
    Nutzerlisten finden Sie im Unterordner "output\reports" als CSV.

# HANDLUNGSEMPFEHLUNGEN (GOVERNANCE)

Basierend auf den Ergebnissen generiert das Tool Empfehlungen:

    Priorität Hoch: Kritische Infrastrukturfehler oder Replikationsstopps.
    Priorität Mittel: Sicherheitsmängel (z. B. verwaiste SIDs, ACL-Vererbung).
    Priorität Niedrig: Hygiene-Maßnahmen (z. B. Bereinigung inaktiver Konten).

# RECHTLICHER HINWEIS

Das Skript führt ausschließlich Lesevorgänge durch. Dennoch erfolgt die Nutzung
auf eigene Gefahr. Eine vorherige Prüfung in einer Testumgebung wird empfohlen.
