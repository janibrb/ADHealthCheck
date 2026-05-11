# MODULE: Update-EntraVersion.ps1
# Fix #6: TimeoutSec Parameter verhindert GUI-Freeze bei nicht erreichbarem Server

function Update-EntraConnectVersion {
    param(
        [string]$SettingsPath,
        [int]$TimeoutSec = 15   # Fix: Expliziter Timeout (Standard war 100s -> GUI-Freeze)
    )

    try {
        $settingsContent = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json

        # Aktuelle Version von Microsoft Docs abrufen — mit Timeout
        $url = "https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/reference-connect-version-history"

        Write-ADHCLog "Rufe Entra Connect Version von Microsoft ab (Timeout: ${TimeoutSec}s)..." -Component "EntraSync"

        $webResponse = Invoke-WebRequest `
            -Uri             $url `
            -UseBasicParsing `
            -TimeoutSec      $TimeoutSec `
            -ErrorAction     Stop

        # Versionsnummer aus dem HTML parsen
        # Format: "V2.x.x.x" oder "2.x.x.x" in Überschriften
        $versionPattern = '(?:V|Version\s+)?(\d+\.\d+\.\d+\.\d+)'
        $matches = [regex]::Matches($webResponse.Content, $versionPattern)

        if ($matches.Count -gt 0) {
            # Höchste gefundene Version nehmen
            $latestVersion = $matches |
                ForEach-Object { $_.Groups[1].Value } |
                Sort-Object { [Version]$_ } -Descending |
                Select-Object -First 1

            if ($latestVersion -and $latestVersion -ne $settingsContent.EntraID.ExpectedAgentVersion) {
                Write-ADHCLog "Neue Entra Connect Version gefunden: $latestVersion (war: $($settingsContent.EntraID.ExpectedAgentVersion))" -Component "EntraSync"
                $settingsContent.EntraID.ExpectedAgentVersion = $latestVersion

                # Zurückschreiben
                $settingsContent | ConvertTo-Json -Depth 10 | Out-File $SettingsPath -Encoding UTF8 -Force
                Write-ADHCLog "settings.json mit neuer Version aktualisiert." -Component "EntraSync"
            } else {
                Write-ADHCLog "Entra Connect Version ist aktuell: $($settingsContent.EntraID.ExpectedAgentVersion)" -Component "EntraSync"
            }
        } else {
            Write-ADHCLog "Konnte keine Versionsnummer aus der Microsoft-Seite extrahieren." -Level Warning -Component "EntraSync"
        }

    } catch [System.Net.WebException] {
        # Timeout oder Netzwerkfehler — kein Crash, nur Log
        Write-ADHCLog "Entra-Versionsabfrage fehlgeschlagen (Netzwerk/Timeout): $($_.Exception.Message)" -Level Warning -Component "EntraSync"
    } catch {
        Write-ADHCLog "Entra-Versionsabfrage fehlgeschlagen: $($_.Exception.Message)" -Level Warning -Component "EntraSync"
    }

    # Immer die (ggf. aktualisierte) Settings zurückgeben
    return Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
