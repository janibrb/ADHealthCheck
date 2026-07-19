# MODULE: Update-EntraVersion.ps1
# Fix: Präzises Regex verhindert falsche Versionen (z.B. .NET 8.0.0.0 Assembly-Bindings)

function Update-EntraConnectVersion {
    param(
        [string]$SettingsPath,
        [int]$TimeoutSec = 15
    )

    try {
        $settingsContent = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json

        $url = "https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/reference-connect-version-history"

        Write-ADHCLog "Rufe Entra Connect Version von Microsoft ab (Timeout: ${TimeoutSec}s)..." -Component "EntraSync"

        $webResponse = Invoke-WebRequest `
            -Uri             $url `
            -UseBasicParsing `
            -TimeoutSec      $TimeoutSec `
            -ErrorAction     Stop

        # -----------------------------------------------------------------------
        # PRÄZISES PARSING: Nur Entra Connect Versionen im Format 2.x.x.x
        # Die Seite enthält auch .NET Assembly-Bindings wie "8.0.0.0" —
        # diese werden durch das strikte Pattern und den Bereich-Filter ausgeschlossen.
        #
        # Strategie 1: Markdown-Überschriften "## 2.x.x.x" (primär, zuverlässigste Quelle)
        # Strategie 2: Versions-Tabelle "[2.x.x.x]" in Tabellenzellen (Fallback)
        # -----------------------------------------------------------------------
        $latestVersion = $null

        # Strategie 1: Überschriften der Form "## 2.6.3.0" oder "<h2>2.6.3.0</h2>"
        # Entra Connect Versionen beginnen immer mit "2."
        $headingPattern = '(?:^|\n)#+\s+(2\.\d+\.\d+\.\d+)|<h[23][^>]*>\s*(2\.\d+\.\d+\.\d+)\s*<\/h[23]>'
        $headingMatches = [regex]::Matches($webResponse.Content, $headingPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)

        if ($headingMatches.Count -gt 0) {
            $latestVersion = $headingMatches | ForEach-Object {
                # Gruppe 1 (Markdown) oder Gruppe 2 (HTML)
                if ($_.Groups[1].Value) { $_.Groups[1].Value.Trim() }
                elseif ($_.Groups[2].Value) { $_.Groups[2].Value.Trim() }
            } | Where-Object { $_ } |
              Sort-Object { [Version]$_ } -Descending |
              Select-Object -First 1

            Write-ADHCLog "Strategie 1 (Überschriften): $($headingMatches.Count) Versionen gefunden, höchste: $latestVersion" -Component "EntraSync"
        }

        # Strategie 2: Tabellen-Links "[2.x.x.x](#...)" als Fallback
        if (-not $latestVersion) {
            $tablePattern = '\[(2\.\d+\.\d+\.\d+)\]\(#'
            $tableMatches = [regex]::Matches($webResponse.Content, $tablePattern)

            if ($tableMatches.Count -gt 0) {
                $latestVersion = $tableMatches |
                    ForEach-Object { $_.Groups[1].Value } |
                    Sort-Object { [Version]$_ } -Descending |
                    Select-Object -First 1

                Write-ADHCLog "Strategie 2 (Tabelle): $($tableMatches.Count) Versionen gefunden, höchste: $latestVersion" -Component "EntraSync"
            }
        }

        # Validierung: Version muss mit "2." beginnen (niemals 8.x oder andere Fremdzahlen)
        if ($latestVersion -and $latestVersion -notmatch '^2\.\d+\.\d+\.\d+$') {
            Write-ADHCLog "Ungültige Version erkannt und verworfen: $latestVersion" -Level Warning -Component "EntraSync"
            $latestVersion = $null
        }

        if ($latestVersion) {
            if ($latestVersion -ne $settingsContent.EntraID.ExpectedAgentVersion) {
                Write-ADHCLog "Neue Entra Connect Version gefunden: $latestVersion (war: $($settingsContent.EntraID.ExpectedAgentVersion))" -Component "EntraSync"
                $settingsContent.EntraID.ExpectedAgentVersion = $latestVersion
                $settingsContent | ConvertTo-Json -Depth 10 | Out-File $SettingsPath -Encoding UTF8 -Force
                Write-ADHCLog "settings.json mit neuer Version aktualisiert." -Component "EntraSync"
            } else {
                Write-ADHCLog "Entra Connect Version ist aktuell: $($settingsContent.EntraID.ExpectedAgentVersion)" -Component "EntraSync"
            }
        } else {
            Write-ADHCLog "Konnte keine gültige Entra Connect Version aus der Microsoft-Seite extrahieren." -Level Warning -Component "EntraSync"
        }

    } catch [System.Net.WebException] {
        Write-ADHCLog "Entra-Versionsabfrage fehlgeschlagen (Netzwerk/Timeout): $($_.Exception.Message)" -Level Warning -Component "EntraSync"
    } catch {
        Write-ADHCLog "Entra-Versionsabfrage fehlgeschlagen: $($_.Exception.Message)" -Level Warning -Component "EntraSync"
    }

    return Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
