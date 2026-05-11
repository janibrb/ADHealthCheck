
<#
.SYNOPSIS
    Haupt-Launcher fuer AD Health Check mit GUI

.NOTES
    Version:    2.1.0
    Fixes:      - Get-ADSecurityInfo Signatur (I18n + LangCode Parameter)
                - $script:UseMockData wird nach Sample-Report zurückgesetzt
                - ProgressCallback für ACL-Analyse verdrahtet (Fortschrittsbalken)
                - Input-Validierung vor Start-Analysis
                - settings.json Safe-Merge (kein Datenverlust)
                - Timeout bei Entra-Versionsabfrage
                - Debug Write-Host entfernt
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

# $script:UseMockData sauber initialisieren (Fix #2)
$script:UseMockData = $false

# ---------------------------------------------------------------------------
# Module laden
# ---------------------------------------------------------------------------
try {
    Import-Module (Join-Path $ModulePath "ADHealthCheck.Utils.psm1")    -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulePath "ADHealthCheck.Diag.psm1")     -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulePath "ADHealthCheck.DNS.psm1")      -Force -ErrorAction Stop
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
        $rptData = Get-ADHCMockData -I18n $I18n -Settings $Settings
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
                                 -Mapping $Mapping -TemplatePath $template -LangCode $LangCode
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
    }
    Start-Analysis -Selection $selection -LangCode $Language -DNSTarget $defaultDNSServer
    exit 0
}

# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form                  = New-Object System.Windows.Forms.Form
$form.Text             = "AD Health Check (LAKE Solutions AG)"
$form.Size             = New-Object System.Drawing.Size(520, 920)
$form.StartPosition    = "CenterScreen"
$form.FormBorderStyle  = "FixedDialog"
$form.BackColor        = [System.Drawing.Color]::White

$fontTitle = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$fontLabel = New-Object System.Drawing.Font("Segoe UI", 9)
$fontInput = New-Object System.Drawing.Font("Segoe UI", 10)
$colorBlue = [System.Drawing.Color]::FromArgb(0, 74, 135)
$colorCyan = [System.Drawing.Color]::FromArgb(0, 169, 206)

# --- HEADER ---
$lblTitle           = New-Object System.Windows.Forms.Label
$lblTitle.Text      = "Report Konfiguration"
$lblTitle.Font      = $fontTitle
$lblTitle.ForeColor = $colorBlue
$lblTitle.Location  = New-Object System.Drawing.Point(25, 20)
$lblTitle.AutoSize  = $true
$form.Controls.Add($lblTitle)

# --- EINGABEFELDER ---
[int]$yPos = 70

# Sprache
$lblLang          = New-Object System.Windows.Forms.Label
$lblLang.Text     = "Sprache / Language:"
$lblLang.Font     = $fontLabel
$lblLang.Location = New-Object System.Drawing.Point(30, $yPos)
$lblLang.AutoSize = $true
$form.Controls.Add($lblLang)

$cbLang                = New-Object System.Windows.Forms.ComboBox
$cbLang.Location       = New-Object System.Drawing.Point(250, ($yPos - 3))
$cbLang.Width          = 180
$cbLang.DropDownStyle  = "DropDownList"
[void]$cbLang.Items.Add("de")
[void]$cbLang.Items.Add("en")
$cbLang.SelectedItem   = $Language
$form.Controls.Add($cbLang)

# Entra ID Sync Server
$yPos += 40
$lblSync          = New-Object System.Windows.Forms.Label
$lblSync.Text     = "EntraID / ADSync Server:"
$lblSync.Font     = $fontLabel
$lblSync.Location = New-Object System.Drawing.Point(30, $yPos)
$lblSync.AutoSize = $true
$form.Controls.Add($lblSync)

$txtSync          = New-Object System.Windows.Forms.TextBox
$txtSync.Location = New-Object System.Drawing.Point(250, ($yPos - 3))
$txtSync.Width    = 180
$txtSync.Font     = $fontInput
$txtSync.Text     = $Settings.EntraID.SyncServer
$form.Controls.Add($txtSync)

# Inaktive Tage
$yPos += 40
$lblDays          = New-Object System.Windows.Forms.Label
$lblDays.Text     = "Inaktive Accounts (< X-Tage):"
$lblDays.Font     = $fontLabel
$lblDays.Location = New-Object System.Drawing.Point(30, $yPos)
$lblDays.AutoSize = $true
$form.Controls.Add($lblDays)

$numDays          = New-Object System.Windows.Forms.NumericUpDown
$numDays.Location = New-Object System.Drawing.Point(250, ($yPos - 3))
$numDays.Width    = 180
$numDays.Font     = $fontInput
$numDays.Minimum  = 1
$numDays.Maximum  = 999
$numDays.Value    = [decimal]$Settings.Thresholds.InactiveAccountDays
$form.Controls.Add($numDays)

# DNS Server
$yPos += 40
$lblDNSTarget          = New-Object System.Windows.Forms.Label
$lblDNSTarget.Text     = "DNS Abfrage Server:"
$lblDNSTarget.Font     = $fontLabel
$lblDNSTarget.Location = New-Object System.Drawing.Point(30, $yPos)
$lblDNSTarget.AutoSize = $true
$form.Controls.Add($lblDNSTarget)

$txtDNSServer          = New-Object System.Windows.Forms.TextBox
$txtDNSServer.Location = New-Object System.Drawing.Point(250, ($yPos - 3))
$txtDNSServer.Width    = 180
$txtDNSServer.Font     = $fontInput
$txtDNSServer.Text     = $defaultDNSServer
$form.Controls.Add($txtDNSServer)

# --- CHECKBOXEN ---
$yPos += 50
$gbChecks          = New-Object System.Windows.Forms.GroupBox
$gbChecks.Text     = "Analyse-Umfang & Empfehlungen"
$gbChecks.Font     = $fontLabel
$gbChecks.Location = New-Object System.Drawing.Point(25, $yPos)
$gbChecks.Size     = New-Object System.Drawing.Size(460, 440)
$form.Controls.Add($gbChecks)

$lblCol1          = New-Object System.Windows.Forms.Label
$lblCol1.Text     = "Bereich"
$lblCol1.Location = New-Object System.Drawing.Point(20, 25)
$lblCol1.Font     = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$lblCol1.AutoSize = $true
$gbChecks.Controls.Add($lblCol1)

$lblCol2          = New-Object System.Windows.Forms.Label
$lblCol2.Text     = "Empfehlungen"
$lblCol2.Location = New-Object System.Drawing.Point(310, 25)
$lblCol2.Font     = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$lblCol2.AutoSize = $true
$gbChecks.Controls.Add($lblCol2)

$checks = @(
    @{ Name="DomainStats";       Label="Domain Infrastruktur";             Var="chkDomain";  RecVar="chkRecDC"       },
    @{ Name="FSMO";              Label="Betriebsmaster (FSMO)";            Var="chkFSMO";    RecVar="chkRecFSMO"     },
    @{ Name="DCDiag";            Label="Verzeichnisdienst (AD)";           Var="chkDCDiag";  RecVar="chkRecDCDiag"   },
    @{ Name="DCSystem";          Label="Domain Controller Health";         Var="chkDC";      RecVar="chkRecDCSystem" },
    @{ Name="Backup";            Label="Disaster Recovery Readiness";      Var="chkBackup";  RecVar="chkRecBackup"   },
    @{ Name="Services";          Label="AD Systemdienste";                 Var="chkSvc";     RecVar="chkRecSvc"      },
    @{ Name="Sites";             Label="AD Standorte und Replikation";     Var="chkSites";   RecVar="chkRecSites"    },
    @{ Name="Security";          Label="Identitäts-Sicherheit (Accounts)"; Var="chkSec";     RecVar="chkRecSec"      },
    @{ Name="OUAccountSecurity"; Label="AD Objekt- und ACL-Audit";         Var="chkOUSec";   RecVar="chkRecOUSec"    },
    @{ Name="Entra";             Label="Entra ID Sync";                    Var="chkEntra";   RecVar="chkRecEntra"    },
    @{ Name="DNS";               Label="Namensauflösung (DNS Health)";     Var="chkDNS";     RecVar="chkRecDNS"      }
)

$chkY                 = 55
$allScopeCheckboxes   = New-Object System.Collections.Generic.List[System.Windows.Forms.CheckBox]
$allRecCheckboxes     = New-Object System.Collections.Generic.List[System.Windows.Forms.CheckBox]

foreach ($c in $checks) {
    $cb           = New-Object System.Windows.Forms.CheckBox
    $cb.Text      = $c.Label
    $cb.Location  = New-Object System.Drawing.Point(20, $chkY)
    $cb.AutoSize  = $true
    $cb.Checked   = $true
    $gbChecks.Controls.Add($cb)
    Set-Variable -Name $c.Var -Value $cb
    $allScopeCheckboxes.Add($cb)

    $cbRec          = New-Object System.Windows.Forms.CheckBox
    $cbRec.Text     = "Anzeigen"
    $cbRec.Location = New-Object System.Drawing.Point(310, $chkY)
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
$chkSelectAllRec.Location  = New-Object System.Drawing.Point(310, $chkY)
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

# --- FORTSCHRITTSBEREICH (Fix #3 — sichtbarer Status während ACL-Analyse) ---
$yStatusTop = $gbChecks.Location.Y + $gbChecks.Height + 15

$lblStatus           = New-Object System.Windows.Forms.Label
$lblStatus.Text      = "Bereit."
$lblStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$lblStatus.ForeColor = [System.Drawing.Color]::Gray
$lblStatus.Location  = New-Object System.Drawing.Point(30, $yStatusTop)
$lblStatus.Size      = New-Object System.Drawing.Size(440, 18)
$form.Controls.Add($lblStatus)

$progressBar               = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location      = New-Object System.Drawing.Point(30, ($yStatusTop + 22))
$progressBar.Size          = New-Object System.Drawing.Size(440, 14)
$progressBar.Style         = "Continuous"
$progressBar.Minimum       = 0
$progressBar.Maximum       = 100
$progressBar.Value         = 0
$progressBar.Visible       = $false
$form.Controls.Add($progressBar)

# --- BUTTONS ---
$yBtnTop = $yStatusTop + 50

$btnRun               = New-Object System.Windows.Forms.Button
$btnRun.Text          = "Report erstellen"
$btnRun.Location      = New-Object System.Drawing.Point(30, $yBtnTop)
$btnRun.Size          = New-Object System.Drawing.Size(200, 45)
$btnRun.BackColor     = $colorCyan
$btnRun.ForeColor     = [System.Drawing.Color]::White
$btnRun.FlatStyle     = "Flat"
$btnRun.Font          = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnRun)

$btnSample            = New-Object System.Windows.Forms.Button
$btnSample.Text       = "Sample Report"
$btnSample.Location   = New-Object System.Drawing.Point(250, $yBtnTop)
$btnSample.Size       = New-Object System.Drawing.Size(200, 45)
$btnSample.BackColor  = [System.Drawing.Color]::FromArgb(100, 100, 100)
$btnSample.ForeColor  = [System.Drawing.Color]::White
$btnSample.FlatStyle  = "Flat"
$btnSample.Font       = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnSample)

# Form-Höhe dynamisch anpassen
$form.ClientSize = New-Object System.Drawing.Size(490, ($yBtnTop + 75))

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
