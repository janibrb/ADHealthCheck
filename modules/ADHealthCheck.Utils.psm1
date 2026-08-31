# MODULE: ADHealthCheck.Utils.psm1

# WICHTIG fuer alle Loader hier: -Encoding UTF8 ist zwingend.
# Die config/*.json sind konventionsgemaess BOM-frei. Ohne den Parameter
# dekodiert PS 5.1 sie mit der System-ANSI-Codepage — auf CP1252-Servern
# wird daraus "KennwÃ¶rter" statt "Kennwörter", und der Mojibake landet
# ueber i18n und recommendations.json direkt im Kundenreport.
function Get-ADHCConfig {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "Config file not found at $Path" }
    return Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-ADHCI18n {
    param([string]$Path, [string]$Lang)
    $file = Join-Path $Path "i18n.$Lang.json"
    if (-not (Test-Path $file)) { $file = Join-Path $Path "i18n.de.json" }
    return Get-Content -Path $file -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-ADHCMapping {
    param([string]$Path)
    $file = Join-Path $Path "mapping.json"
    if (-not (Test-Path $file)) { 
        # Fallback, leeres Objekt zurückgeben
        return @{} 
    }
    return Get-Content -Path $file -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-ADHCLog {
    param(
        [string]$Message,
        [ValidateSet("Info","Warning","Error","Debug")]$Level = "Info",
        [string]$Component = "General"
    )
    $color = "Cyan"
    switch ($Level) {
        "Error"   { $color = "Red" }
        "Warning" { $color = "Yellow" }
        "Debug"   { $color = "Gray" }
    }

    $logEntry = "[{0}][{1}][{2}] {3}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level.ToUpper(), $Component, $Message
    Write-Host $logEntry -ForegroundColor $color
    
    # Log-Pfad: vom Modul-Verzeichnis (modules\) eine Ebene hoch = Repo-Root, dann output\logs
    # Robuster als Split-Path -Parent: funktioniert unabhängig vom Aufrufkontext
    #
    # Ausnahme ADHC_LOG_FILE: ohne diesen Schalter schreiben Testlaeufe in
    # DIESELBE Datei wie echte Berichtslaeufe. Das ist eine zweite, von der
    # Sperre unabhaengige Ursache derselben Stoerung — parallele Pester-Laeufe
    # blockieren sich gegenseitig und blaehen ein Kundenartefakt auf. Die
    # Pester-Suite setzt die Variable auf eine prozesseigene Datei; die 87
    # Aufrufstellen und die Signatur bleiben davon unberuehrt. Ist die
    # Variable nicht gesetzt (Normalfall, echter Lauf), aendert sich nichts.
    #
    # Die Pfadermittlung selbst darf ebenfalls nie werfen. Ein fehlerhafter
    # ADHC_LOG_FILE-Wert liess frueher Split-Path bzw. Test-Path VOR jedem
    # try-Block werfen und riss damit den Aufrufer ab -- also genau die
    # Wirkung, die diese Funktion ausschliessen soll. Belege:
    #   'xyz::foo\bar.log'    -> Split-Path: ProviderNotFoundException
    #   'C:\temp\ad|hc\x.log' -> Test-Path:  ArgumentException (Illegal characters)
    # Darum: erst den Standardpfad setzen, den Sonderweg nur versuchsweise
    # gehen, und im Zweifel beim Standardpfad bleiben.
    $repoRoot = $PSScriptRoot
    if ($repoRoot) { $repoRoot = Split-Path $repoRoot -Parent }
    if (-not $repoRoot) { $repoRoot = (Get-Location).Path }
    $logDir     = Join-Path $repoRoot "output\logs"
    $logFile    = Join-Path $logDir "ADHealthCheck.log"
    $pathNotice = $null

    if ($env:ADHC_LOG_FILE) {
        $candidate = $env:ADHC_LOG_FILE
        try {
            # Unerlaubte Zeichen ausdruecklich selbst pruefen statt sich auf
            # das Framework zu verlassen: unter PS 5.1 (.NET Framework) wirft
            # schon [Path]::IsPathRooted bei '|', unter PS 7 (.NET Core) faellt
            # dieselbe Pruefung ersatzlos weg und der Wert liefe bis Out-File
            # durch. Die Funktion soll sich auf beiden gleich verhalten --
            # sonst laesst sich das Verhalten des Zielsystems nicht testen.
            # Wildcards sind mit erfasst: Out-File -FilePath wertet sie aus.
            #
            # Der zweite Zweig weist relative Werte zurueck, statt sie
            # aufzuloesen: sie landen sonst still im jeweiligen
            # Arbeitsverzeichnis. Das ist bei einer geplanten Aufgabe ein
            # anderes als beim Aufruf von Hand -- ein Protokoll, dessen Ort
            # vom Zufall abhaengt, ist keines. Der Standardpfad ist dagegen
            # bekannt und dokumentiert.
            $badChars = [char[]]@('|', '<', '>', '"', '*', '?')
            if ($candidate.IndexOfAny($badChars) -ge 0) {
                $pathNotice = "ADHC_LOG_FILE ist auf den Wert '$candidate' gesetzt, der unerlaubte Zeichen enthaelt. Es gilt der Standardpfad '$logFile'."
            } elseif (-not [System.IO.Path]::IsPathRooted($candidate)) {
                $pathNotice = "ADHC_LOG_FILE ist auf den relativen Wert '$candidate' gesetzt. Relative Pfade werden nicht ausgewertet, weil das Ziel sonst vom Arbeitsverzeichnis abhinge. Es gilt der Standardpfad '$logFile'."
            } else {
                # Erst ermitteln, dann uebernehmen: wirft Split-Path, bleibt
                # der Standardpfad unangetastet stehen.
                $candidateDir = Split-Path $candidate -Parent
                $logFile = $candidate
                $logDir  = $candidateDir
            }
        } catch {
            $pathNotice = "ADHC_LOG_FILE ist auf den unbrauchbaren Wert '$candidate' gesetzt ($($_.Exception.Message)). Es gilt der Standardpfad '$logFile'."
        }
    }

    if ($pathNotice) {
        # Nicht stillschweigend umleiten -- sonst sucht der Anwender sein
        # Protokoll an einer Stelle, an der nie etwas ankommt.
        Write-Host ("[{0}][WARNING][Logging] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $pathNotice) -ForegroundColor Yellow
    }

    # Auch das Pruefen und das Anlegen koennen scheitern (Rennen zweier
    # Prozesse, fehlendes Recht, unerlaubte Zeichen im Verzeichnisteil).
    # Auch hier gilt: niemals den Aufrufer abbrechen -- der Schreibversuch
    # unten meldet den Folgefehler ohnehin.
    if ($logDir) {
        try {
            if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null }
        } catch { }
    }

    # Alle Prozesse schreiben in DIESELBE Datei. Laufen zwei gleichzeitig
    # (zwei Pester-Laeufe, ein Bericht neben einem Test), sperrt Windows sie
    # exklusiv und Out-File wirft. Frueher riss dieser Fehler den AUFRUFER ab,
    # also den ganzen Gesundheitsbericht. Der Bericht ist aber der Zweck, das
    # Protokoll ist Beiwerk.
    #
    # Darum: kurze Wiederholungsversuche (Sperren dauern Millisekunden), und
    # wenn es endgueltig nicht geht, geht die Protokollzeile verloren -- aber
    # sichtbar, nicht stillschweigend. Ohne Konflikt greift der erste Versuch
    # und es entsteht keinerlei Verzoegerung.
    $retryWaitsMs = @(20, 50, 100, 150, 200)   # nur im Konfliktfall wirksam, max. ~520 ms
    $written   = $false
    $lastError = $null
    for ($attempt = 0; $attempt -le $retryWaitsMs.Count; $attempt++) {
        try {
            $logEntry | Out-File -FilePath $logFile -Append -Encoding utf8 -ErrorAction Stop
            $written = $true
            break
        } catch {
            $lastError = $_
            if ($attempt -lt $retryWaitsMs.Count) { Start-Sleep -Milliseconds $retryWaitsMs[$attempt] }
        }
    }

    if (-not $written) {
        $reason = "unbekannter Fehler"
        if ($lastError) { $reason = $lastError.Exception.Message }
        # Write-Host laeuft ueber die Konsole und ist von der Dateisperre nicht
        # betroffen; die Protokollzeile selbst steht oben bereits dort.
        Write-Host ("[{0}][WARNING][Logging] Protokollzeile konnte nicht nach '{1}' geschrieben werden ({2}). Der Lauf wird fortgesetzt, diese Zeile steht nur auf der Konsole." -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $logFile, $reason) -ForegroundColor Yellow
    }
}

function New-HTMLTable {
    param($Data, $CssClass="table-default")
    if (-not $Data) { return "<p>No Data.</p>" }
    $html = "<table class='$CssClass'><thead><tr>"
    
    if ($Data -is [System.Collections.IEnumerable] -and $Data.Count -gt 0) {
        $props = $Data[0].PSObject.Properties.Name
    } elseif ($Data.PSObject) {
        $props = $Data.PSObject.Properties.Name
    } else {
        return "<p>Data Format Error</p>"
    }

    foreach ($p in $props) { $html += "<th>$p</th>" }
    $html += "</tr></thead><tbody>"
    foreach ($row in $Data) {
        $html += "<tr>"
        foreach ($p in $props) {
            $val = $row.$p
            $cellClass = ""
            if ($val -eq "OK" -or $val -eq "Running" -or $val -eq "Enabled") { $cellClass = "status-ok" }
            elseif ($val -eq "Error" -or $val -eq "Stopped") { $cellClass = "status-error" }
            elseif ($val -eq "Warning" -or $val -eq "Disabled") { $cellClass = "status-warning" }
            
            $html += "<td class='$cellClass'>$val</td>"
        }
        $html += "</tr>"
    }
    $html += "</tbody></table>"
    return $html
}

Export-ModuleMember -Function Get-ADHCConfig, Get-ADHCI18n, Get-ADHCMapping, Write-ADHCLog, New-HTMLTable