# FILE: modules\Update-EntraVersion.ps1

function Update-EntraConnectVersion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SettingsPath
    )

    $url = "https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/reference-connect-version-history"

    try {
        Write-ADHCLog "Lade Microsoft Webseite zur Versionsermittlung: $url" -Component "EntraSync"
        
        # Webseite abrufen
        $webResponse = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        $content = $webResponse.Content

        # 1. Bereich zwischen "Version release history" und "All other versions are not supported" isolieren
        # Dies verhindert, dass 4.x Versionen des Health Agents fälschlicherweise gelesen werden
        if ($content -match "(?s)Version release history(?<inner>.*?)All other versions are not supported") {
            $relevantSection = $Matches['inner']
            Write-ADHCLog "Relevanter Versionsbereich der Sync-Historie isoliert." -Component "EntraSync"
        } else {
            $relevantSection = $content
            Write-ADHCLog "Warnung: Bereichsbegrenzung fehlgeschlagen, verwende gesamten Inhalt als Fallback." -Level Warning -Component "EntraSync"
        }

        # 2. Alle Versionsnummern im Format 2.x.x.x extrahieren
        $versionMatches = [regex]::Matches($relevantSection, '(?<version>2\.\d+\.\d+\.\d+)') 
        $foundVersions = $versionMatches | ForEach-Object { $_.Groups['version'].Value }

        if ($foundVersions) {
            # 3. Logische Sortierung über System.Version Objekte (wichtig für 2.10 > 2.2 Vergleich)
            # Wir nehmen das höchste Objekt (die neuste Version)
            $latestVersion = ($foundVersions | ForEach-Object { [version]$_ } | Sort-Object -Descending | Select-Object -First 1).ToString()
            
            Write-ADHCLog "Höchste ermittelte Sync-Version auf Microsoft Seite: $latestVersion" -Component "EntraSync"
            
            if (Test-Path $SettingsPath) {
                # Aktuelle Einstellungen laden
                $settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
                $oldVersion = $settings.EntraID.ExpectedAgentVersion
                
                # Nur aktualisieren, wenn sich die Version geändert hat
                if ($oldVersion -ne $latestVersion) {
                    Write-ADHCLog "Update settings.json: $oldVersion -> $latestVersion" -Component "EntraSync"
                    $settings.EntraID.ExpectedAgentVersion = $latestVersion
                    
                    # Sauber formatiert zurück in die Datei schreiben
                    $settings | ConvertTo-Json -Depth 10 | Out-File $SettingsPath -Encoding utf8
                    Write-ADHCLog "settings.json erfolgreich auf Version $latestVersion aktualisiert." -Component "EntraSync"
                } else {
                    Write-ADHCLog "Referenzversion in settings.json ist bereits aktuell ($oldVersion)." -Component "EntraSync"
                }

                # WICHTIG: Das aktualisierte Settings-Objekt zurückgeben, 
                # damit der Launcher die Variable im RAM sofort aktualisieren kann.
                return $settings
            }
        } else {
            Write-ADHCLog "Fehler: Keine Versionen im Format 2.x.x.x im Sync-Bereich gefunden." -Level Error -Component "EntraSync"
        }
    } catch {
        Write-ADHCLog "Verbindungsfehler bei der Versionsabfrage: $($_.Exception.Message)" -Level Warning -Component "EntraSync"
    }

    # Fallback: Wenn nichts aktualisiert wurde oder ein Fehler auftrat, 
    # laden wir die bestehenden Settings, um den Skriptlauf nicht zu unterbrechen.
    if (Test-Path $SettingsPath) {
        return Get-Content $SettingsPath -Raw | ConvertFrom-Json
    }
}