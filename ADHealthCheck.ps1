<#
.SYNOPSIS
    Haupt-Launcher fuer AD Health Check mit GUI
#>
param(
    [switch]$NoGui,
    [string]$Language = "de"
)

# Pfade & Setup
$ScriptRoot = $PSScriptRoot
$OutputPath = Join-Path $PSScriptRoot "output"
$ModulePath = Join-Path $ScriptRoot "modules"

# Module laden
try {
    # Wir laden Utils zuerst, um Logging zu haben
    Import-Module (Join-Path $ModulePath "ADHealthCheck.Utils.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulePath "ADHealthCheck.Diag.psm1") -Force -ErrorAction Stop
	Import-Module (Join-Path $ModulePath "ADHealthCheck.DNS.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulePath "ADHealthCheck.EntraSync.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $ModulePath "ADHealthCheck.Reporting.psm1") -Force -ErrorAction Stop
} catch {
    # KORREKTUR: Fehlermeldung jetzt sichtbar!
    Write-Host "FATAL ERROR: Ein Modul konnte nicht geladen werden." -ForegroundColor Red
    Write-Host "Grund: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Ort: $($_.InvocationInfo.ScriptName) (Zeile $($_.InvocationInfo.ScriptLineNumber))" -ForegroundColor Gray
    exit 1
}

# Config laden
$Settings = Get-ADHCConfig -Path (Join-Path $ScriptRoot "config\settings.json")
$Mapping = Get-ADHCMapping -Path (Join-Path $ScriptRoot "config")

# --- Analyse Logik ---
function Start-Analysis {
    param($Selection, $LangCode, $DNSTarget)
    
    $I18n = Get-ADHCI18n -Path (Join-Path $ScriptRoot "config") -Lang $LangCode
	
	if ($script:UseMockData) {
        $rptData = Get-ADHCMockData -I18n $I18n -Settings $Settings
        $rptData.DomainStats.DomainFQDN += " (MOCK DATA)"
    } else {
		
	# Automatische Versionsaktualisierung aufrufen
    if ($Settings.EntraID.AutoUpdateVersion -eq $true) {
        Write-ADHCLog "Prüfe Microsoft Dokumentation auf Entra Connect Versions-Updates..." -Component "EntraSync"
        . (Join-Path $ScriptRoot "modules\Update-EntraVersion.ps1")
        
        # Hier die Variable im Arbeitsspeicher mit dem Rückgabewert aktualisieren!
        $Settings = Update-EntraConnectVersion -SettingsPath (Join-Path $ScriptRoot "config\settings.json")
    }
	
    Write-ADHCLog "Starte Analyse ($LangCode)..."
    
    try { $DCs = (Get-ADDomainController -Filter *).HostName } 
    catch { Write-ADHCLog "Fehler: Keine Domain/DCs gefunden." -Level Error; return }

	# Domain Overview
    #$domainStats = Get-ADDomainStats
	$domainStats = if ($Selection.DomainStats) { Get-ADDomainStats } else { $null }
	
    # Conditionals
    #$fsmoData = if ($Selection.FSMO) { Get-ADFSMORoles } else { $null }
	$fsmoData = if ($Selection.FSMO) { Get-ADFSMORoles -I18n $I18n } else { $null }
    
    $discoveryData = if ($Selection.DCSystem) { 
        Get-ADHealthDiscovery -DCList $DCs -Settings $Settings 
    } else { $null }

    $svcData = if ($Selection.Services) { 
        Get-ADServiceStatus -DCList $DCs 
    } else { $null }

    $dcdiagData = if ($Selection.DCDiag) { 
        Invoke-DetailedDcdiag -DCList $DCs 
    } else { $null }

    $sitesData = if ($Selection.Sites) {
        Get-ADSitesInfo
    } else { $null }

    $secData = if ($Selection.Security) { 
        Get-ADSecurityInfo -Settings $Settings 
    } else { $null }
	
	$ouSecData = if ($Selection.OUAccountSecurity) { 
		Get-ADOUAndAccountSecurity -Settings $Settings 
	} else { $null }

    $entraData = if ($Selection.Entra) { 
        Get-EntraSyncStatus -Settings $Settings 
    } else { $null }
	
	$backupData = if ($Selection.Backup) { Get-ADBackupStatus } else { $null }
	
	$dnsData = if ($Selection.DNS) { Get-ADDNSHealthStatus -TargetServer $DNSTarget } else { $null }

    # Daten zusammenstellen
    $rptData = @{
        DomainStats = $domainStats
        FSMO        = $fsmoData
        Discovery   = $discoveryData
        DCDiag      = $dcdiagData
        Services    = $svcData
        Sites       = $sitesData
        Security    = $secData
		OUAccountSecurity = $ouSecData
        Entra       = $entraData
		Backup 		= $backupData
		DNS 		= $dnsData
    }
    
	}
	
    $template = Join-Path $ScriptRoot "templates\report.template.html"
	
    # Report-Generierung aufrufen
    $reportPath = New-ADHCReport -Data $rptData -Settings $Settings -I18n $I18n -Mapping $Mapping -TemplatePath $template -LangCode $LangCode
	
    Invoke-Item $reportPath

	# --- Excel/CSV Export für Sicherheits-Details ---
	if ($rptData.Security.RawExportData -and $rptData.Security.RawExportData.Count -gt 0) {
		
		# Pfad festlegen: output\reports
		$reportFolder = Join-Path $OutputPath "reports"
		
		# Ordner erstellen, falls nicht vorhanden
		if (-not (Test-Path $reportFolder)) { 
			New-Item -ItemType Directory -Path $reportFolder -Force | Out-Null 
		}
	
		$dateStr = Get-Date -Format "yyyyMMdd_HHmm"
		$csvPath = Join-Path $reportFolder "ADHC_Security_Details_$dateStr.csv"
		
		try {
			$rptData.Security.RawExportData | Export-Csv -Path $csvPath -NoTypeInformation -Delimiter ";" -Encoding UTF8 -ErrorAction Stop
			Write-ADHCLog "Sicherheits-Export erstellt: $csvPath" -Component "Reporting"
		} catch {
			Write-ADHCLog "Fehler beim CSV-Export: $($_.Exception.Message)" -Level Error
		}
	}

}

# --- DNS Server Discovery (Vor dem GUI Start) ---
$defaultDNSServer = ""
try {
    # Wir versuchen den PDC-Emulator zu finden, da dieser garantiert DNS-Server ist
    $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
    $defaultDNSServer = $domain.PdcRoleOwner.Name
} catch {
    # Fallback auf den ersten verfügbaren Domain Controller
    $defaultDNSServer = (Get-ADDomainController -Discover).Hostname
}

# Falls in der settings.json bereits ein Server steht, nehmen wir diesen
if ($Settings.DNS.TargetServer) {
    $defaultDNSServer = $Settings.DNS.TargetServer
}

# --- GUI ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "AD Health Check (LAKE Solutions AG)"
$form.Size = New-Object System.Drawing.Size(520, 850)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.BackColor = [System.Drawing.Color]::White

# Schriftart Setup
$fontTitle = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$fontLabel = New-Object System.Drawing.Font("Segoe UI", 9)
$fontInput = New-Object System.Drawing.Font("Segoe UI", 10)

# --- HEADER ---
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Report Konfiguration"
$lblTitle.Font = $fontTitle
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 74, 135) # LAKE Blue
$lblTitle.Location = New-Object System.Drawing.Point(25, 20)
$lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle)

# --- EINSTELLUNGEN (INPUTS) ---
[int]$yPos = 70 # Wir erzwingen hier [int]

# Sprache
$lblLang = New-Object System.Windows.Forms.Label
$lblLang.Text = "Sprache / Language:"
$lblLang.Font = $fontLabel
$lblLang.Location = New-Object System.Drawing.Point(30, $yPos)
$lblLang.AutoSize = $true
$form.Controls.Add($lblLang)

$cbLang = New-Object System.Windows.Forms.ComboBox
$cbLang.Location = New-Object System.Drawing.Point(250, ($yPos - 3)) # Klammern zur Sicherheit
$cbLang.Width = 180; $cbLang.DropDownStyle = "DropDownList"
[void]$cbLang.Items.Add("de"); [void]$cbLang.Items.Add("en")
$cbLang.SelectedItem = $Language
$form.Controls.Add($cbLang)

# Entra ID Sync Server
$yPos += 40
$lblSync = New-Object System.Windows.Forms.Label
$lblSync.Text = "EntraID / ADSync Server:"
$lblSync.Font = $fontLabel
$lblSync.Location = New-Object System.Drawing.Point(30, $yPos)
$lblSync.AutoSize = $true
$form.Controls.Add($lblSync)

$txtSync = New-Object System.Windows.Forms.TextBox
$txtSync.Location = New-Object System.Drawing.Point(250, ($yPos - 3))
$txtSync.Width = 180; $txtSync.Font = $fontInput
$txtSync.Text = $Settings.EntraID.SyncServer
$form.Controls.Add($txtSync)

# Inaktive Tage
$yPos += 40
$lblDays = New-Object System.Windows.Forms.Label
$lblDays.Text = "Inaktive Accounts (< X-Tage):"
$lblDays.Font = $fontLabel
$lblDays.Location = New-Object System.Drawing.Point(30, $yPos)
$lblDays.AutoSize = $true
$form.Controls.Add($lblDays)

$numDays = New-Object System.Windows.Forms.NumericUpDown
$numDays.Location = New-Object System.Drawing.Point(250, ($yPos - 3))
$numDays.Width = 180; $numDays.Font = $fontInput
$numDays.Minimum = 1; $numDays.Maximum = 999
$numDays.Value = [decimal]$Settings.Thresholds.InactiveAccountDays
$form.Controls.Add($numDays)

# DNS Server
$yPos += 40
$lblDNSTarget = New-Object System.Windows.Forms.Label
$lblDNSTarget.Text = "DNS Abfrage Server:"
$lblDNSTarget.Font = $fontLabel
$lblDNSTarget.Location = New-Object System.Drawing.Point(30, $yPos); $lblDNSTarget.AutoSize = $true
$form.Controls.Add($lblDNSTarget)

$txtDNSServer = New-Object System.Windows.Forms.TextBox
$txtDNSServer.Location = New-Object System.Drawing.Point(250, ($yPos - 3))
$txtDNSServer.Width = 180; $txtDNSServer.Font = $fontInput
$txtDNSServer.Text = $defaultDNSServer
$form.Controls.Add($txtDNSServer)

# --- CHECKBOXEN (BEREICHE + EMPFEHLUNGEN) ---
$yPos += 50
$gbChecks = New-Object System.Windows.Forms.GroupBox
$gbChecks.Text = "Analyse-Umfang & Empfehlungen"
$gbChecks.Font = $fontLabel
$gbChecks.Location = New-Object System.Drawing.Point(25, $yPos)
$gbChecks.Size = New-Object System.Drawing.Size(450, 420) 
$form.Controls.Add($gbChecks)

# Header-Labels für die Spalten
$lblCol1 = New-Object System.Windows.Forms.Label
$lblCol1.Text = "Bereich"; $lblCol1.Location = New-Object System.Drawing.Point(20, 25)
$lblCol1.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$lblCol1.AutoSize = $true
$gbChecks.Controls.Add($lblCol1)

$lblCol2 = New-Object System.Windows.Forms.Label
$lblCol2.Text = "Empfehlungen"; $lblCol2.Location = New-Object System.Drawing.Point(300, 25)
$lblCol2.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$lblCol2.AutoSize = $true
$gbChecks.Controls.Add($lblCol2)

# Definition der Datenstruktur
$checks = @(
    @{ Name="DomainStats"; Label="Domain Infrastruktur"; Var="chkDomain"; RecVar="chkRecDC" },
    @{ Name="FSMO";        Label="Betriebsmaster (FSMO)"; Var="chkFSMO";   RecVar="chkRecFSMO" },
    @{ Name="DCDIAG";      Label="Verzeichnisdienst (AD)";    Var="chkDCDIag"; RecVar="chkRecDCDIag" },
    @{ Name="DCSystem";    Label="Domain Controller Health";  Var="chkDC";     RecVar="chkRecDCSystem" },
    @{ Name="Backup";      Label="Disaster Recovery Readiness"; Var="chkBackup"; RecVar="chkRecBackup" },
    @{ Name="Services";    Label="AD Systemdienste";   Var="chkSvc";    RecVar="chkRecSvc" },
    @{ Name="Sites";       Label="AD Standorte und Replikation";         Var="chkSites";  RecVar="chkRecSites" },
    @{ Name="Security";    Label="Identitäts-Sicherheit (Accounts)";       Var="chkSec";    RecVar="chkRecSec" },
	@{ Name="OUAccountSecurity"; Label="AD Objekt- und ACL-Audit"; Var="chkOUSec";  RecVar="chkRecOUSec" },
    @{ Name="Entra";       Label="Entra ID Sync";    Var="chkEntra";  RecVar="chkRecEntra" },
    @{ Name="DNS";         Label="Namensauflösung (DNS Health)";       Var="chkDNS";    RecVar="chkRecDNS" }
)

# --- BEREICHE & EMPFEHLUNGEN INITIALISIEREN ---
$chkY = 55
$allScopeCheckboxes = New-Object System.Collections.Generic.List[System.Windows.Forms.CheckBox]
$allRecCheckboxes = New-Object System.Collections.Generic.List[System.Windows.Forms.CheckBox]

foreach ($c in $checks) {
    # 1. Analyse-Checkbox (Spalte 1: Bereich) - Standardmäßig AN
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $c.Label; $cb.Location = New-Object System.Drawing.Point(20, $chkY)
    $cb.AutoSize = $true
    $cb.Checked = $true # Standardmäßig ausgewählt
    $gbChecks.Controls.Add($cb)
    Set-Variable -Name $c.Var -Value $cb
    $allScopeCheckboxes.Add($cb) # In Liste für Master-Switch 1

    # 2. Empfehlungs-Checkbox (Spalte 2: Anzeigen) - Standardmäßig AUS
    $cbRec = New-Object System.Windows.Forms.CheckBox
    $cbRec.Text = "Anzeigen"; $cbRec.Location = New-Object System.Drawing.Point(300, $chkY)
    $cbRec.AutoSize = $true
    $cbRec.Checked = $false # Standardmäßig nicht ausgewählt
    $gbChecks.Controls.Add($cbRec)
    Set-Variable -Name $c.RecVar -Value $cbRec
    $allRecCheckboxes.Add($cbRec) # In Liste für Master-Switch 2

    $chkY += 35
}

$chkY += 15 # Zusätzlicher Abstand nach der Liste

# --- MASTER-CHECKBOX 1: BEREICHE (Links) ---
$chkSelectAllScope = New-Object System.Windows.Forms.CheckBox
$chkSelectAllScope.Text = "Alle abwählen" # Da Standard AN, ist der erste Klick "Abwählen"
$chkSelectAllScope.Location = New-Object System.Drawing.Point(20, $chkY)
$chkSelectAllScope.AutoSize = $true
$chkSelectAllScope.Checked = $true # Muss mit dem Status der Einzel-CBs übereinstimmen
$chkSelectAllScope.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$chkSelectAllScope.ForeColor = [System.Drawing.Color]::FromArgb(0, 74, 135)
$gbChecks.Controls.Add($chkSelectAllScope)

# Event-Handler für Bereich-Master
$chkSelectAllScope.Add_CheckedChanged({
    foreach ($cb in $allScopeCheckboxes) { $cb.Checked = $chkSelectAllScope.Checked }
    if ($chkSelectAllScope.Checked) {
        $chkSelectAllScope.ForeColor = [System.Drawing.Color]::FromArgb(0, 74, 135)
        $chkSelectAllScope.Text = "Alle abwählen"
    } else {
        $chkSelectAllScope.ForeColor = [System.Drawing.Color]::Gray
        $chkSelectAllScope.Text = "Alle auswählen"
    }
})

# --- MASTER-CHECKBOX 2: EMPFEHLUNGEN (Rechts) ---
$chkSelectAllRec = New-Object System.Windows.Forms.CheckBox
$chkSelectAllRec.Text = "Alle auswählen"
$chkSelectAllRec.Location = New-Object System.Drawing.Point(300, $chkY)
$chkSelectAllRec.AutoSize = $true
$chkSelectAllRec.Checked = $false
$chkSelectAllRec.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
$chkSelectAllRec.ForeColor = [System.Drawing.Color]::Gray
$gbChecks.Controls.Add($chkSelectAllRec)

# Event-Handler für Empfehlungen-Master
$chkSelectAllRec.Add_CheckedChanged({
    foreach ($cb in $allRecCheckboxes) { $cb.Checked = $chkSelectAllRec.Checked }
    if ($chkSelectAllRec.Checked) {
        $chkSelectAllRec.ForeColor = [System.Drawing.Color]::FromArgb(0, 74, 135)
        $chkSelectAllRec.Text = "Alle abwählen"
    } else {
        $chkSelectAllRec.ForeColor = [System.Drawing.Color]::Gray
        $chkSelectAllRec.Text = "Alle auswählen"
    }
})

# GroupBox Höhe anpassen, damit alles Platz hat
$gbChecks.Height = $chkY + 40

# --- BUTTON ---
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Report erstellen"
$btnRun.Location = New-Object System.Drawing.Point(80, ($gbChecks.Location.Y + $gbChecks.Height + 20))
$btnRun.Size = New-Object System.Drawing.Size(200, 45)
$btnRun.BackColor = [System.Drawing.Color]::FromArgb(0, 169, 206) # LAKE Cyan
$btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.FlatStyle = "Flat"
$btnRun.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

# NEUER Button: Sample Report
$btnSample = New-Object System.Windows.Forms.Button
$btnSample.Text = "Sample Report"
$btnSample.Location = New-Object System.Drawing.Point(260, ($gbChecks.Location.Y + $gbChecks.Height + 20))
$btnSample.Size = New-Object System.Drawing.Size(180, 45)
$btnSample.BackColor = [System.Drawing.Color]::Gray
$btnSample.ForeColor = [System.Drawing.Color]::White
$btnSample.FlatStyle = "Flat"
$btnSample.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

$btnSample.Add_Click({
    $script:UseMockData = $true
    $btnRun.PerformClick()
})
$form.Controls.Add($btnSample)

$btnRun.Add_Click({
    # 1. Sicherstellen, dass die hierarchischen Objekte in $Settings existieren
    if ($null -eq $Settings.DNS) {
        $Settings | Add-Member -MemberType NoteProperty -Name "DNS" -Value (New-Object -TypeName PSObject)
    }

    # 2. Werte aus den GUI-Feldern in das Settings-Objekt übertragen
    $Settings.EntraID.SyncServer = $txtSync.Text
    $Settings.Thresholds.InactiveAccountDays = [int]$numDays.Value
    $Settings.DNS.TargetServer = $txtDNSServer.Text 

    # 3. Empfehlungs-Logik: Sicherstellen, dass das Objekt existiert
    if ($null -eq $Settings.ShowRecommendations) {
        $Settings | Add-Member -MemberType NoteProperty -Name "ShowRecommendations" -Value @{} -Force
    }

    # 4. Jetzt die Checkboxen zuweisen
    $Settings.ShowRecommendations = @{
        DomainOverview = $chkRecDC.Checked
        FSMO           = $chkRecFSMO.Checked
        DCDIag         = $chkRecDCDIag.Checked
		DCSystem 	   = $chkRecDCSystem.Checked
        Backup         = $chkRecBackup.Checked
        Services       = $chkRecSvc.Checked
        Sites          = $chkRecSites.Checked
        Security       = $chkRecSec.Checked
		OUAccountSecurity = $chkRecOUSec.Checked
        Entra          = $chkRecEntra.Checked
        DNS            = $chkRecDNS.Checked
    }

    try {
        # Speichern der settings.json
        $Settings | ConvertTo-Json -Depth 10 | Out-File (Join-Path $PSScriptRoot "config\settings.json") -Encoding UTF8 -Force
        Write-ADHCLog "Konfiguration erfolgreich gespeichert."
    } catch {
        Write-ADHCLog "Fehler beim Speichern der settings.json: $($_.Exception.Message)" -Level Warning
    }
    
    Write-Host "DEBUG GUI: DomainRec ist $($chkRecDC.Checked)"
    
    # 5. Auswahl der Analyse-Sektionen sammeln
    $selection = @{
        DomainStats = $chkDomain.Checked
        FSMO        = $chkFSMO.Checked
        DCDIag      = $chkDCDIag.Checked
        DCSystem    = $chkDC.Checked
        Backup      = $chkBackup.Checked
        Services    = $chkSvc.Checked
        Sites       = $chkSites.Checked
        Security    = $chkSec.Checked
		OUAccountSecurity = $chkOUSec.Checked
        Entra       = $chkEntra.Checked
        DNS         = $chkDNS.Checked
    }
    
    $btnRun.Enabled = $false
    $btnRun.Text = "Analysiere..."
    $form.Refresh()
    
    # 6. Analyse starten
    Start-Analysis -Selection $selection -LangCode $cbLang.SelectedItem -DNSTarget $txtDNSServer.Text
    
    $form.Close()
})
$form.Controls.Add($btnRun)

$form.ShowDialog() | Out-Null