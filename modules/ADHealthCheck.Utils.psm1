# MODULE: ADHealthCheck.Utils.psm1

function Get-ADHCConfig {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "Config file not found at $Path" }
    return Get-Content -Path $Path -Raw | ConvertFrom-Json
}

function Get-ADHCI18n {
    param([string]$Path, [string]$Lang)
    $file = Join-Path $Path "i18n.$Lang.json"
    if (-not (Test-Path $file)) { $file = Join-Path $Path "i18n.de.json" }
    return Get-Content -Path $file -Raw | ConvertFrom-Json
}

function Get-ADHCMapping {
    param([string]$Path)
    $file = Join-Path $Path "mapping.json"
    if (-not (Test-Path $file)) { 
        # Fallback, leeres Objekt zurückgeben
        return @{} 
    }
    return Get-Content -Path $file -Raw | ConvertFrom-Json
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
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $logDir   = Join-Path $repoRoot "output\logs"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

    $logFile = Join-Path $logDir "ADHealthCheck.log"
    $logEntry | Out-File -FilePath $logFile -Append -Encoding utf8
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