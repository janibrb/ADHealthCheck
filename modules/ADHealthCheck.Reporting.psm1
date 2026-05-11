# MODULE: ADHealthCheck.Reporting.psm1

function New-ADHCReport {
    param($Data, $Settings, $I18n, $Mapping, $TemplatePath, $LangCode="de")
    
    Write-ADHCLog -Message "Generiere Reports..." -Component "Reporting"
    
    # 1. JSON Export
    $dataDir = $Settings.Paths.Data
    if (-not $dataDir) { $dataDir = "./output/data" }
    if (-not (Test-Path $dataDir)) { New-Item -Type Directory $dataDir -Force | Out-Null }
    
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $jsonFile = Join-Path $dataDir ("ADHealthCheck_{0}.json" -f $timestamp)
    $Data | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonFile -Encoding utf8

    # 2. HTML Template & CSS laden
    if (-not (Test-Path $TemplatePath)) { Throw "Template nicht gefunden unter: $TemplatePath" }
    
    # Pfad absolut auflösen, um Fehler mit relativen Pfaden zu vermeiden
    $resolvedTemplatePath = Resolve-Path $TemplatePath
    $templateDir = Split-Path $resolvedTemplatePath -Parent
    
    # HTML einlesen
    $html = Get-Content $resolvedTemplatePath -Raw
    
	# Text aus i18n holen
    $footerLabel = $I18n.Labels.FooterText
    
    $html = $html.Replace("{{FOOTER_TEXT}}", $footerLabel)
	
    # CSS einlesen (erwartet report.style.css im selben Ordner)
    $cssPath = Join-Path $templateDir "report.style.css"
    $cssContent = "/* CSS Datei nicht gefunden oder leer */"
    
    if (Test-Path $cssPath) {
        $cssContent = Get-Content $cssPath -Raw
        Write-ADHCLog "CSS Stylesheet erfolgreich geladen ($cssPath)."
    } else {
        Write-ADHCLog "FEHLER: CSS Datei nicht gefunden! Erwartet unter: $cssPath" -Level Error
        # Fallback CSS damit es nicht ganz kaputt aussieht
        $cssContent = "body { font-family: sans-serif; padding: 20px; } .card { border: 1px solid #ccc; padding: 10px; margin: 10px 0; }"
    }

    # --- Helper: Mapping Value Lookup ---
    function Get-MappedValue {
        param($Category, $Value)
        if ($Mapping -and $Mapping.$Category -and $Mapping.$Category.$Value) {
            return $Mapping.$Category.$Value
        }
        return $Value
    }

    # --- Helper: Status Pill Generator ---
    function Get-StatusPill {
        param($Value)
        $cls = "status-warning"
        if ($Value -match "^(OK|Running|Enabled|True)$") { $cls = "status-ok" }
        if ($Value -match "^(Error|Stopped|False|Disabled)$") { $cls = "status-error" }
        return "<span class='status-pill $cls'>$Value</span>"
    }

    # --- Helper: Table Generator with Pills ---
    function New-HTMLTableWithPills {
        param($Data, $Headers)
        if (-not $Data) { return "<p>No Data.</p>" }
        
        $t = "<table class='styled-table'><thead><tr>"
        $props = if ($Headers) { $Headers.Keys } else { $Data[0].PSObject.Properties.Name }
        $labels = if ($Headers) { $Headers.Values } else { $props }

        foreach ($l in $labels) { $t += "<th>$l</th>" }
        $t += "</tr></thead><tbody>"

        foreach ($row in $Data) {
            $t += "<tr>"
            foreach ($p in $props) {
                $val = $row.$p
                if ($val -match "^(OK|Error|Warning|Running|Stopped|Enabled|Disabled)$") {
                    $val = Get-StatusPill -Value $val
                }
                $t += "<td>$val</td>"
            }
            $t += "</tr>"
        }
        $t += "</tbody></table>"
        return $t
    }
		
	# --- Sektion: Domain Stats ---
	$dStats = $Data.DomainStats
	$htmlStats = ""
	if ($Data.DomainStats) {
		$displayForest = Get-MappedValue -Category "ForestMode" -Value $dStats.ForestLevel
		$displayDomain = Get-MappedValue -Category "DomainMode" -Value $dStats.DomainLevel
		
		# --- RECYCLE BIN LOGIK (KORRIGIERT FÜR MEHRSPRACHIGKEIT) ---
		# Wir holen den Text direkt aus der I18n-Datei
		$rbText = if ($dStats.RecycleBin) { $I18n.Labels.Enabled } else { $I18n.Labels.Disabled }
		
		# Wir bestimmen die Farbe manuell oder übergeben den Status an Get-StatusPill
		$rbClass = if ($dStats.RecycleBin) { "status-ok" } else { "status-error" }
		$rbPill = "<span class='status-pill $rbClass'>$rbText</span>"
	
		# --- KRBTGT LOGIK (BLEIBT GLEICH) ---
		$krbPill = "-"
		if ($dStats.KrbtgtLastSet) {
			$krbDate = $dStats.KrbtgtLastSet
			$daysOld = ((Get-Date) - $krbDate).Days
			$limit = if ($Settings.Thresholds.KrbtgtPasswordAgeDays) { $Settings.Thresholds.KrbtgtPasswordAgeDays } else { 180 }
			$krbClass = if ($daysOld -gt $limit) { "status-error" } else { "status-ok" }
			$krbDisplay = $krbDate.ToString("dd.MM.yyyy")
			$krbPill = "<span class='status-pill $krbClass' title='Alter: $daysOld Tage'>$krbDisplay</span>"
		}
	
		# --- HTML TABELLE ---
		$htmlStats = "<div class='card'><h2>$($I18n.Sections.Overview)</h2>"
		$htmlStats += "<table class='styled-table'>
			<tbody>
				<tr><td>$($I18n.Labels.DomainNetBIOS)</td><td><b>$($dStats.DomainNetBIOS)</b></td>
					<td>$($I18n.Labels.UserCount)</td><td>$($dStats.UserCount)</td></tr>
				<tr><td>$($I18n.Labels.DomainFQDN)</td><td><b>$($dStats.DomainFQDN)</b></td>
					<td>$($I18n.Labels.SecGroups)</td><td>$($dStats.SecGroupCount)</td></tr>
				<tr><td>$($I18n.Labels.ForestLevel)</td><td>$displayForest</td>
					<td>$($I18n.Labels.DistLists)</td><td>$($dStats.DistGroupCount)</td></tr>
				<tr><td>$($I18n.Labels.DomainLevel)</td><td>$displayDomain</td>
					<td>$($I18n.Labels.Contacts)</td><td>$($dStats.ContactCount)</td></tr>
				
				<tr>
					<td>$($I18n.Labels.RecycleBin)</td><td>$rbPill</td>
					<td>$($I18n.Labels.KrbtgtPwd)</td><td>$krbPill</td>
				</tr>
			</tbody>
		</table>"
		$htmlStats += "</div>"
	}

    # --- Sektion: FSMO ---
    $htmlFSMO = ""
	if ($Data.FSMO) {
		# Definierte Header mit i18n Unterstützung
		$fsmoHeaders = [ordered]@{
			Role       = $I18n.Labels.Role       # z.B. "Rolle" oder "Role"
			Owner      = $I18n.Labels.Owner      # z.B. "Inhaber" oder "Owner"
			Erreichbar = $I18n.Labels.Reachable  # z.B. "Erreichbar" oder "Reachable"
		}
	
		$htmlFSMO = "<div class='card'><h2>$($I18n.Sections.FSMO)</h2>"
		$htmlFSMO += New-HTMLTableWithPills -Data $Data.FSMO -Headers $fsmoHeaders
		$htmlFSMO += "</div>"
	}
	
	# --- Sektion: DCs (Domain Controller Systemstatus) ---
	$htmlDCs = "" # Variable initialisieren
	if ($Data.Discovery) {
		# Wir speichern das Ergebnis in $htmlDCs (achte auf das 's' am Ende, falls du es weiter unten so ausgibst)
		$htmlDCs = "<div class='card'><h2>$($I18n.Sections.DCSystem)</h2>"
		
		$htmlDCs += "<table class='styled-table dc-system-table'>
			<thead>
				<tr>
					<th>$($I18n.Labels.Server)</th>
					<th>$($I18n.Labels.OS)</th>
					<th>$($I18n.Labels.IPv4)</th>
					<th style='text-align:center;'>$($I18n.Labels.Uptime)</th> 
					<th style='text-align:center;'>$($I18n.Labels.FreeDiskGB)</th>
					<th style='text-align:center;'>$($I18n.Labels.FreeDiskPct)</th>
					<th style='text-align:center;'>$($I18n.Labels.Status)</th>
				</tr>
			</thead>
			<tbody>"
		
		# Korrektur: Nutze $Data.Discovery statt $Data.DCSystem
		foreach ($row in $Data.Discovery) {
			$statusClass = if ($row.Status -eq "OK") { "status-ok" } else { "status-error" }
			
			$htmlDCs += "<tr>
				<td>$($row.Server)</td>
				<td>$($row.OS)</td>
				<td>$($row.IPv4)</td>
				<td style='text-align:center;'>$($row.UptimeHrs)</td> 
				<td style='text-align:center;'>$($row.FreeDiskGB)</td>
				<td style='text-align:center;'>$($row.FreeDiskPct)</td>
				<td style='text-align:center;'><span class='status-pill ${statusClass}'>$($row.Status)</span></td>
			</tr>"
		}
		$htmlDCs += "</tbody></table></div>"
	}
	
	# --- Sektion: DCDIAG Matrix ---
	$htmlDcdiag = ""
	$dcdiagEntries = @($Data.DCDiag)
	
	# Nur wenn Daten vorhanden sind und die Sektion nicht leer ist
	if ($dcdiagEntries.Count -gt 0 -and $null -ne $dcdiagEntries[0].Server) {
		$strMat = "<div class='card'><h2>$($I18n.Sections.DCDiag)</h2>" # Card-Start hier!
		$strMat += "<div class='matrix-container'><table class='styled-table matrix-table'>"
		$strMat += "<thead><tr><th style='width:200px;'>$($I18n.Labels.Check)</th>"
		
		foreach ($serverResult in $dcdiagEntries) {
			$strMat += "<th class='rotate'><div><span>$($serverResult.Server)</span></div></th>"
		}
		$strMat += "</tr></thead><tbody>"
		
		$testNames = $dcdiagEntries[0].PSObject.Properties.Name | Where-Object { $_ -ne "Server" }
		
		foreach ($test in $testNames) {
			$strMat += "<tr><td><b>$test</b></td>"
			foreach ($serverRow in $dcdiagEntries) {
				$val = $serverRow.$test
				$cls = "status-warn-bg"; $symbol = "?"
				if ($val -eq "Passed" -or $val -eq "OK") { $cls = "status-ok-bg"; $symbol = "&#10004;" }
				elseif ($val -eq "Failed" -or $val -eq "Error") { $cls = "status-error-bg"; $symbol = "&#10008;" }
				
				$strMat += "<td class='$cls'>$symbol</td>"
			}
			$strMat += "</tr>"
		}
		$strMat += "</tbody></table></div></div>" # Card-Ende hier!
		$htmlDcdiag = $strMat
	} else {
		# Wenn deaktiviert oder leer, bleibt $htmlDcdiag einfach ein leerer String ""
		$htmlDcdiag = "" 
	}

	# --- Sektion: AD Backup Status ---
	$htmlBackup = ""
	if ($Data.Backup -and ($Data.Backup.Count -gt 0)) {
		$htmlBackup = "<div class='card'><h2>$($I18n.Sections.Backup)</h2>"
		
		# Hinzufügen der spezifischen Klasse 'backup-table'
		$htmlBackup += "<table class='styled-table backup-table'>
			<thead>
				<tr>
					<th>Partition</th>
					<th>$($I18n.Labels.LastBackup)</th>
					<th>$($I18n.Labels.DaysAgo)</th>
					<th>Status</th>
				</tr>
			</thead>
			<tbody>"
		
		foreach ($item in $Data.Backup) {
			# 1. Zeit-String lokalisiert zusammenbauen
			$timeDisplay = "-"
			if ($null -ne $item.LastBackup) {
				if ($item.Days -lt 1) {
					$timeDisplay = "$($item.Hours) $($I18n.Labels.HoursShort)"
				} else {
					$timeDisplay = "$($item.Days) $($I18n.Labels.DaysShort) $($item.Hours) $($I18n.Labels.HoursShort)"
				}
			} else {
				$timeDisplay = $I18n.Labels.NoBackupFound
			}
		
			# 2. Status-Pille bestimmen
			$statusClass = "status-ok"
			$statusText = "OK"
		
			switch ($item.Status) {
				"Warning"  { $statusClass = "status-warning"; $statusText = $I18n.Labels.Warning }
				"Critical" { $statusClass = "status-error";   $statusText = $I18n.Labels.UrgentAction }
				"Error"    { $statusClass = "status-error";   $statusText = $I18n.Labels.NoBackupFound }
			}
		
			$htmlBackup += "<tr>
				<td>$($item.Partition)</td>
				<td>$($item.LastBackup)</td>
				<td>${timeDisplay}</td>
				<td><span class='status-pill ${statusClass}'>${statusText}</span></td>
			</tr>"
		}
		$htmlBackup += "</tbody></table></div>"
	}

    # --- Sektion: Services ---
    $htmlSvcs = ""
    if ($Data.Services) {
        $htmlSvcs = "<div class='card'><h2>$($I18n.Sections.Services)</h2>" + 
                    (New-HTMLTableWithPills -Data $Data.Services) + "</div>"
    }

	# --- Sektion: Entra ---
    $htmlEntra = ""
    if ($Data.Entra) {
        $entraData = $Data.Entra
        
        # 1. Versions Check & Lokalisierung "Nicht installiert"
        $instVer = $entraData.InstalledVersion
        $expVer = $entraData.ExpectedVersion
        
        $verStatusClass = "status-ok"
        $verDisplay = $instVer
        
        # Prüfung auf den speziellen String aus dem Diag-Modul
        if ($instVer -eq "NotInstalled") {
            $verStatusClass = "status-warning"
            $verDisplay = $I18n.Labels.NotInstalled # Nutzt Label "Nicht installiert"
        }
        elseif ($instVer -eq "Error" -or $instVer -eq "Unknown") {
            $verStatusClass = "status-error"
            $verDisplay = "Error / Unknown"
        }
        elseif ($instVer -ne $expVer) {
            $verStatusClass = "status-warning"
            # Lokalisiert "Erwartet"
            $verDisplay = "$instVer ($($I18n.Labels.Expected): $expVer)"
        }
        $verPill = "<span class='status-pill $verStatusClass'>$verDisplay</span>"

        # 2. Dienste Logik (Validierung ob Dienste existieren)
		$svcDisplay = ""
		$allRunning = $false
		
		# Wir prüfen zuerst, ob überhaupt Dienste gefunden wurden
		if ($entraData.ServiceDetails -and ($entraData.ServiceDetails.Count -gt 0)) {
			$allRunning = $true
			$failedSvcs = @()
			
			foreach ($svc in $entraData.ServiceDetails) {
				# Status-Vergleich (je nach Modul 'Status' oder 'State')
				if ($svc.Status -ne "Running" -and $svc.Status -ne "OK") {
					$allRunning = $false
					$failedSvcs += "<div><b>$($svc.Name)</b>: <span class='status-error'>$($svc.Status)</span></div>"
				}
			}
		
			if ($allRunning) {
				$svcDisplay = "<span class='status-pill status-ok' style='width:auto; padding:5px 20px;'>$($I18n.Labels.AllServicesRunning)</span>"
			} else {
				$svcDisplay = $failedSvcs -join ""
			}
		} else {
			# FALLBACK: Wenn die Liste leer ist -> Dienste sind nicht installiert/auffindbar
			$svcDisplay = "<span class='status-pill status-error' style='width:auto; padding:5px 20px;'>$($I18n.Labels.NoServicesFound)</span>"
			$allRunning = $false
		}

        # 3. Gesamtstatus
		# Wir definieren zuerst die Bedingungen als klare Variablen für bessere Lesbarkeit
		$isNotInstalled = ($entraData.InstalledVersion -eq "NotInstalled")
		$noServicesFound = ($entraData.FoundAnyService -eq $false)
		$hasConnectionError = ($null -ne $entraData.Error)
		
		$globalStatus = "OK"
		$globalClass = "status-ok"
		
		# BEDINGUNG 1: Harter FEHLER (Rot)
		# Wenn Agent nicht installiert UND keine Dienste gefunden ODER ein Verbindungsfehler vorliegt
		if (($isNotInstalled -and $noServicesFound) -or $hasConnectionError) {
			$globalStatus = if ($I18n.Labels.Error) { $I18n.Labels.Error } else { "Fehler" }
			$globalClass = "status-error"
		}
		# BEDINGUNG 2: WARNUNG (Gelb)
		# Wenn der Agent zwar da ist, aber die Version falsch ist ODER Dienste gestoppt sind
		elseif ($allRunning -eq $false -or $verStatusClass -eq "status-warning") {
			$globalStatus = $I18n.Labels.Warning
			$globalClass = "status-warning"
		}
		
		$globalPill = "<span class='status-pill $globalClass'>$globalStatus</span>"

        # Tabelle bauen
        $htmlEntra = "<div class='card'><h2>$($I18n.Sections.Entra)</h2>"
        $htmlEntra += "<table class='styled-table'>
            <thead>
                <tr>
                    <th>$($I18n.Labels.SyncServer)</th>
                    <th>$($I18n.Labels.InstalledVersion)</th>
                    <th>$($I18n.Labels.ServiceStatus)</th>
                    <th>$($I18n.Labels.GlobalStatus)</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td><b>$($entraData.Server)</b></td>
                    <td>$verPill</td>
                    <td>$svcDisplay</td>
                    <td>$globalPill</td>
                </tr>
            </tbody>
        </table></div>"
    }

    # --- Sektion: Sites ---
    $htmlSites = ""
    if ($Data.Sites) {
        $htmlSites = "<div class='card'><h2>$($I18n.Sections.Sites)</h2>"
        
        $htmlSites += "<h3>$($I18n.Labels.Transports)</h3>"
        $transHeaders = [ordered]@{Name=$I18n.Labels.Name; Type=$I18n.Labels.Type; Description=$I18n.Labels.Desc; Cost=$I18n.Labels.Cost; ReplInterval=$I18n.Labels.Interval}
        $htmlSites += New-HTMLTableWithPills -Data $Data.Sites.Transports -Headers $transHeaders

        $htmlSites += "<h3>$($I18n.Labels.Subnets)</h3>"
        $subHeaders = [ordered]@{Name=$I18n.Labels.Name; Site=$I18n.Labels.AssignedSite}
        $htmlSites += New-HTMLTableWithPills -Data $Data.Sites.Subnets -Headers $subHeaders

        $htmlSites += "<h3>$($I18n.Labels.SiteList)</h3>"
        foreach ($site in $Data.Sites.Sites) {
            $htmlSites += "<div style='background:#fcfcfc; border:1px solid #eee; padding:15px; margin-top:10px; border-radius:6px;'>"
            $htmlSites += "<h4 style='margin:0 0 10px 0; color:#004a87;'>Site: $($site.Name)</h4>"
            
            if ($site.Servers) {
               $srvHeaders = [ordered]@{Name=$I18n.Labels.Server; IsGC=$I18n.Labels.GlobalCatalog}
               $htmlSites += New-HTMLTableWithPills -Data $site.Servers -Headers $srvHeaders
            } else { $htmlSites += "<p>No Servers</p>" }

            if ($site.Connections) {
                $htmlSites += "<br/><b>$($I18n.Labels.Connections):</b>"
                $connHeaders = [ordered]@{Source="Source Server"; Transport="Transport"; Enabled=$I18n.Labels.Enabled; DestinationServer="Destination"}
                $htmlSites += New-HTMLTableWithPills -Data $site.Connections -Headers $connHeaders
            }
            $htmlSites += "</div>"
        }
        $htmlSites += "</div>"
    }

    # --- Sektion: Sicherheit + Kennwortrichtlinien ---
    $htmlSec = ""
    if ($Data.Security) {
        $secInfo = $Data.Security
        
        $htmlSec = "<div class='card'><h2>$($I18n.Sections.Security)</h2>"
        
        # --- Unterbereich: Sicherheit ---
        $htmlSec += "<h3>$($I18n.Labels.SecuritySubHeader)</h3>"
        
        # Pille für Aktive Inaktive (Rot/Grün)
        $inactiveCount = [int]$secInfo.InactiveUsers
        $inactiveStatusClass = if ($inactiveCount -eq 0) { "status-ok" } else { "status-error" }
        $inactiveLabel = if ($inactiveCount -eq 0) { "Keine gefunden" } else { "$inactiveCount $($I18n.Labels.Users)" }

        # Pille für Deaktivierte Konten (Gelb wenn > 0)
        $disabledCount = [int]$secInfo.DisabledUsers
        $disabledStatusClass = if ($disabledCount -eq 0) { "status-ok" } else { "status-warn" }
        $disabledLabel = "$disabledCount $($I18n.Labels.Users)"

        # Pille für Passwortablauf (Rot/Grün)
        $noExpiryCount = [int]$secInfo.NoPwdExpiryUsers
        $noExpiryStatusClass = if ($noExpiryCount -eq 0) { "status-ok" } else { "status-error" }
        $noExpiryLabel = if ($noExpiryCount -eq 0) { "Keine gefunden" } else { "$noExpiryCount $($I18n.Labels.Users)" }

        # Pille für Abgelaufene Kennwörter (Neu)
        $expiredCount = [int]$secInfo.ExpiredPwdUsers
        $expiredStatusClass = if ($expiredCount -eq 0) { "status-ok" } else { "status-error" }
        $expiredLabel = if ($expiredCount -eq 0) { "Alle aktuell" } else { "$expiredCount $($I18n.Labels.Users)" }

        $htmlSec += "<table class='styled-table'>
			<thead>
				<tr><th>$($I18n.Labels.Property)</th><th>$($I18n.Labels.Value)</th></tr>
			</thead>
			<tbody>
				<tr><td>$($I18n.Labels.InactiveThreshold)</td><td>$($secInfo.InactiveThresholdDays) $($I18n.Labels.Days)</td></tr>
				<tr>
					<td>$($I18n.Labels.InactiveFound)</td>
					<td><span class='status-pill $inactiveStatusClass'>$($inactiveCount) $($I18n.Labels.Users)</span></td>
				</tr>
				<tr>
					<td>$($I18n.Labels.DisabledFound)</td>
					<td><span class='status-pill $disabledStatusClass'>$($disabledCount) $($I18n.Labels.Users)</span></td>
				</tr>
				<tr>
					<td>$($I18n.Labels.NoPwdExpiry)</td>
					<td><span class='status-pill $noExpiryStatusClass'>$($noExpiryCount) $($I18n.Labels.Users)</span></td>
				</tr>
				<tr>
					<td>$($I18n.Labels.PasswordExpired) ($($secInfo.MaxPwdAge) $($I18n.Labels.Days))</td>
					<td><span class='status-pill $expiredStatusClass'>$($expiredCount) $($I18n.Labels.Users)</span></td>
				</tr>
				<tr>
					<td>$($I18n.Labels.DomAdminName)</td>
					<td><span class='status-pill $(if($secInfo.DomAdminCount -le 5){"status-ok"}else{"status-error"})'>$($secInfo.DomAdminCount) $($I18n.Labels.Users)</span></td>
				</tr>
				<tr>
					<td>$($I18n.Labels.EntAdminName)</td>
					<td><span class='status-pill $(if($secInfo.EntAdminCount -le 5){"status-ok"}else{"status-error"})'>$($secInfo.EntAdminCount) $($I18n.Labels.Users)</span></td>
				</tr>
				<tr>
					<td>$($I18n.Labels.SchAdminName)</td>
					<td><span class='status-pill $(if($secInfo.SchAdminCount -le 5){"status-ok"}else{"status-error"})'>$($secInfo.SchAdminCount) $($I18n.Labels.Users)</span></td>
				</tr>
			</tbody>
		</table>"

        $htmlSec += "<br/>"
		
		$complexityLabel = if ($secInfo.Complexity) { $I18n.Labels.Enabled } else { $I18n.Labels.Disabled }
		
        # --- Unterbereich: Kennwortrichtlinie ---
        $htmlSec += "<h3>$($I18n.Labels.PasswordPolicySubHeader)</h3>"
        $htmlSec += "<table class='styled-table'>
            <thead>
                <tr><th>$($I18n.Labels.Property)</th><th>$($I18n.Labels.Value)</th></tr>
            </thead>
            <tbody>
                <tr><td>$($I18n.Labels.PwdComplexity)</td><td>$complexityLabel</td></tr>
                <tr><td>$($I18n.Labels.MinLength)</td><td>$($secInfo.MinPwdLength) $($I18n.Labels.Chars)</td></tr>
                <tr><td>$($I18n.Labels.MinAge)</td><td>$($secInfo.MinPwdAge)</td></tr>
                <tr><td>$($I18n.Labels.MaxAge)</td><td>$($secInfo.MaxPwdAge)</td></tr>
                <tr><td>$($I18n.Labels.History)</td><td>$($secInfo.PwdHistory) $($I18n.Labels.Passwords)</td></tr>
                <tr><td>$($I18n.Labels.Lockout)</td><td>$($secInfo.LockoutThresh) $($I18n.Labels.Attempts)</td></tr>
				<tr><td>$($I18n.Labels.LockoutDuration)</td><td>$($secInfo.LockoutDuration) $($I18n.Labels.Minutes)</td></tr>
				<tr><td>$($I18n.Labels.ResetLockoutCount)</td><td>$($secInfo.ResetLockoutCount) $($I18n.Labels.Minutes)</td></tr>
            </tbody>
        </table>"

        $htmlSec += "</div>"
    }
	
	# --- SEKTION: OU & KONTO SICHERHEIT ---
	$htmlOUSec = ""  # Fix: Initialisierung vor dem if-Block verhindert NullPointerException
	if ($Data.OUAccountSecurity) {
		$ouSec = $Data.OUAccountSecurity
		$htmlOUSec = "<div class='card'><h2>$($I18n.Sections.OUAccountSecurity)</h2>"
		
		# --- Hilfsfunktion für Ampel-Farben ---
		# 0 = status-ok (Grün), < 10 = status-warn (Gelb), >= 10 = status-error (Rot)
		function Get-SecurityColor {
			param([int]$Count)
			if ($Count -eq 0) { return "status-ok" }
			if ($Count -lt 10) { return "status-warn" }
			return "status-error"
		}
	
		# Wir berechnen die Klassen hier vorab
		$sidColor   = Get-SecurityColor -Count $ouSec.UniqueOrphanCount
		$ouColor    = Get-SecurityColor -Count $ouSec.DisabledInheritanceOU.Count
		$userColor  = Get-SecurityColor -Count $ouSec.DisabledInheritanceUser.Count
	
		# Pillen-Layout oben
		$htmlOUSec += "<div style='display: flex; gap: 10px; margin-bottom: 25px; flex-wrap: wrap;'>"
		$htmlOUSec += "<span class='status-pill $sidColor'>$($I18n.Labels.OrphanedSIDs): $($ouSec.UniqueOrphanCount)</span>"
		$htmlOUSec += "<span class='status-pill $ouColor'>$($I18n.Labels.ProtectedOUs): $($ouSec.DisabledInheritanceOU.Count)</span>"
		$htmlOUSec += "<span class='status-pill $userColor'>$($I18n.Labels.ProtectedUsers): $($ouSec.DisabledInheritanceUser.Count)</span>"
		$htmlOUSec += "</div>"
	
		# --- TABELLE 1: VERWAISTE SIDs (JETZT EXPLIZIT) ---
		if ($ouSec.UniqueOrphanCount -gt 0) {
			$htmlOUSec += "<div style='margin-top:20px;'><h3 style='border-left: 3px solid #004a87; padding-left: 10px;'>Detaillierte Liste: Verwaiste SIDs (ACLs)</h3>"
			
			# Wir bereiten die Daten für die SID-Tabelle auf
			$sidTableData = foreach ($group in $ouSec.TopOrphanedSIDs) {
				[PSCustomObject]@{ 
					SID       = $group.Name; 
					Anzahl    = $group.Count; 
					Empfehlung = "Prüfen & Bereinigen" 
				}
			}
			
			# Rendern der SID Tabelle
			$htmlOUSec += New-HTMLTableWithPills -Data $sidTableData -Headers ([ordered]@{"SID"="SID"; "Anzahl"="Vorkommen"; "Empfehlung"="Empfehlung"})
			$htmlOUSec += "</div>"
		}
	
		# --- TABELLE 2: ORGANIZATIONAL UNITS ---
		if ($ouSec.DisabledInheritanceOU.Count -gt 0) {
			$htmlOUSec += "<div style='margin-top:20px;'><h3 style='border-left: 3px solid #004a87; padding-left: 10px;'>$($I18n.Labels.ProtectedOUs)</h3>"
			$ouData = foreach($ou in ($ouSec.DisabledInheritanceOU | Select-Object -First 50)) {
				[PSCustomObject]@{ "OU Name" = $ou.Name; "Distinguished Name (Pfad)" = $ou.DN; "Status" = $I18n.Labels.InheritanceDisabled }
			}
			$htmlOUSec += New-HTMLTableWithPills -Data $ouData -Headers ([ordered]@{"OU Name"="OU Name"; "Distinguished Name (Pfad)"="Distinguished Name (Pfad)"; "Status"="Status"})
			$htmlOUSec += "</div>"
		}
	
		# --- TABELLE 3: BENUTZER ---
		if ($ouSec.DisabledInheritanceUser.Count -gt 0) {
			$htmlOUSec += "<div style='margin-top:20px;'><h3 style='border-left: 3px solid #004a87; padding-left: 10px;'>$($I18n.Labels.ProtectedUsers)</h3>"
			$userData = foreach($u in ($ouSec.DisabledInheritanceUser | Select-Object -First 50)) {
				[PSCustomObject]@{ "Benutzer" = $u.Name; "Distinguished Name (Pfad)" = $u.DN; "Status" = $I18n.Labels.InheritanceDisabled }
			}
			$htmlOUSec += New-HTMLTableWithPills -Data $userData -Headers ([ordered]@{"Benutzer"="Benutzer"; "Distinguished Name (Pfad)"="Distinguished Name (Pfad)"; "Status"="Status"})
			$htmlOUSec += "</div>"
		}
	
		$htmlOUSec += "</div>"
	}

	# --- Sektion: DNS Health ---
	$htmlDNS = ""
	if ($Data.DNS) {
		$htmlDNS = "<div class='card'><h2>$($I18n.Sections.DNSHealth)</h2>"
		
		# --- QUICK CHECKS KACHELN ---
		if ($Data.DNS.QuickChecks) {
			$qc = $Data.DNS.QuickChecks
			$htmlDNS += "<div class='quick-check-container'>"

			# Fix #7: TotalZoneCount konsistent aus Forward+Reverse berechnen
			# (nicht aus $qc.TotalZoneCount, das Forwarder mitzählen kann)
			$effectiveTotalZones = @($Data.DNS.ForwardZones).Count + @($Data.DNS.ReverseZones).Count
			$missingScavCount    = @($qc.MissingScavenging).Count
		
			# --- Kachel 1: Scavenging ---
			$scavClass = "status-ok"
			if ($missingScavCount -gt 0) {
				$scavClass = if ($missingScavCount -ge $effectiveTotalZones) { "status-error" } else { "status-warning" }
			}
		
			if ($missingScavCount -eq 0) {
				$scavContent = $I18n.Labels.Active
			} elseif ($missingScavCount -ge $effectiveTotalZones) {
				$scavContent = $I18n.Labels.ScavengingGlobalInactive
			} else {
				$maxDisplay = 2
				$displayedZones = $qc.MissingScavenging | Select-Object -First $maxDisplay
				$scavContent = "$($I18n.Labels.Inactive): " + ($displayedZones -join ", ")
				if ($missingScavCount -gt $maxDisplay) {
					$remaining = $missingScavCount - $maxDisplay
					$scavContent += " (+ ${remaining})"
				}
			}
		
			$htmlDNS += "<div class='quick-info-box qbox-scavenging'>
							<div class='qbox-label'>Scavenging (Aging)</div>
							<div class='status-text ${scavClass}' style='font-size: 1.1rem; font-weight: 700;'>${scavContent}</div>
							<div style='font-size: 0.75rem; color: #888; margin-top: auto; padding-top: 10px;'>
								$($I18n.Labels.ScavengingCheckedIn -f $effectiveTotalZones)
							</div>
						</div>"
		
			# --- Kachel 2: Nameserver Status (DNS-Integrität) ---
			$nsErrCount = ($qc.NSCondition | Where-Object { $_.Status -ne "OK" }).Count
			$nsClass = if ($nsErrCount -eq 0) { "status-ok" } else { "status-error" }
			# Wir nutzen hier einen sprechenderen Text als nur "OK"
			$nsStatusText = if ($nsErrCount -eq 0) { "Alle Server online" } else { "${nsErrCount} $($I18n.Labels.Error)" }
			
			$htmlDNS += "<div class='quick-info-box qbox-forwarder'>
							<div class='qbox-label'>$($I18n.Labels.DNSForwarder)</div>
							<div class='status-text ${nsClass}' style='font-size: 1.3rem; font-weight: 700;'>${nsStatusText}</div>
						</div>"
		
			# --- Kachel 3: AD Service Records (Strukturierte Liste) ---
			$srvLines = ""
			foreach ($item in $qc.SRVDetails) {
				$serviceLabel = $I18n.Labels.$($item.ServiceKey)
				$statusLabel  = if ($item.Status -eq "OK") { "OK" } else { "CRITICAL" }
				$colorClass   = if ($item.Status -eq "OK") { "status-ok" } else { "status-error" }
		
				$srvLines += "<div class='srv-row'>
								<div class='srv-name'>${serviceLabel}</div>
								<div class='srv-status ${colorClass}'>${statusLabel}</div>
							</div>"
			}
		
			$htmlDNS += "<div class='quick-info-box qbox-srv'>
							<div class='qbox-label'>$($I18n.Labels.ADServiceRecords)</div>
							<div style='width: 100%;'>${srvLines}</div>
						</div>"
		
			$htmlDNS += "</div>" # Ende quick-check-container
		}
	
		# --- TABELLE: NAMESERVER STATUS ---
		$htmlDNS += "<h3 class='dns-table-header'>$($I18n.Labels.NameserverStatus)</h3>"
		$htmlDNS += "<table class='styled-table'><thead><tr>
						<th>NAMESERVER</th><th>IP</th><th>SERVICE</th><th>ICMP</th>
					</tr></thead><tbody>"
		foreach ($ns in $Data.DNS.NSStatus) {
			$displayService = switch ($ns.Service) {
				"Running"      { $I18n.Labels.Running }
				"Stopped"      { $I18n.Labels.Stopped }
				"NotFound"     { $I18n.Labels.NotFound }
				"AccessDenied" { $I18n.Labels.AccessDenied }
				Default        { $ns.Service }
			}
			$svcClass = if ($ns.Service -eq "Running") { "status-ok" } else { "status-error" }
			$icmpClass = if ($ns.ICMP -eq "OK") { "status-ok" } else { "status-error" }
			$htmlDNS += "<tr><td><b>$($ns.Name)</b></td><td>$($ns.IP)</td>
						<td><span class='status-pill ${svcClass}'>${displayService}</span></td>
						<td><span class='status-pill ${icmpClass}'>$($ns.ICMP)</span></td></tr>"
		}
		$htmlDNS += "</tbody></table>"
	
		# --- TABELLE: FORWARD LOOKUP ZONEN ---
		$htmlDNS += "<h3 class='dns-table-header'>$($I18n.Labels.ForwardZones)</h3>"
		$htmlDNS += "<table class='styled-table'><thead><tr>
						<th>$($I18n.Labels.ZoneName)</th><th>$($I18n.Labels.Type)</th>
						<th>$($I18n.Labels.Status)</th><th>$($I18n.Labels.Replication)</th><th>DNSSEC</th>
					</tr></thead><tbody>"
		foreach ($zone in $Data.DNS.ForwardZones) {
			$translatedBaseType = switch ($zone.ZoneType) {
				"Primary"   { $I18n.Labels.Primary }
				"Secondary" { $I18n.Labels.Secondary }
				"Stub"      { $I18n.Labels.Stub }
				Default     { $zone.ZoneType }
			}
			$fullTypeDisplay = if ($zone.IsADIntegrated) { "${translatedBaseType}, $($I18n.Labels.ADIntegrated)" } else { $translatedBaseType }
			$statusText = if ($zone.ZoneStatus -eq "Running") { $I18n.Labels.Running } else { $I18n.Labels.Stopped }
			$statusClass = if ($zone.ZoneStatus -eq "Running") { "status-ok" } else { "status-error" }
			$secPill = if ($zone.IsSigned) { "<span class='status-pill status-ok'>ACTIVE</span>" } else { "<span class='status-pill status-warning'>INACTIVE</span>" }
			$htmlDNS += "<tr><td><b>$($zone.ZoneName)</b></td><td>${fullTypeDisplay}</td>
						<td><span class='status-pill ${statusClass}'>${statusText}</span></td>
						<td>$($zone.ReplicationScope)</td><td>${secPill}</td></tr>"
		}
		$htmlDNS += "</tbody></table>"
	
		# --- TABELLE: REVERSE LOOKUP ZONEN ---
		$htmlDNS += "<h3 class='dns-table-header'>$($I18n.Labels.ReverseZones)</h3>"
		$htmlDNS += "<table class='styled-table'><thead><tr>
						<th>$($I18n.Labels.ZoneName)</th><th>$($I18n.Labels.Type)</th>
						<th>$($I18n.Labels.Status)</th><th>$($I18n.Labels.Replication)</th><th>DNSSEC</th>
					</tr></thead><tbody>"
		if ($Data.DNS.ReverseZones.Count -eq 0) {
			$htmlDNS += "<tr><td colspan='5' style='text-align:center;'>$($I18n.Labels.NoZonesFound)</td></tr>"
		} else {
			foreach ($zone in $Data.DNS.ReverseZones) {
				$translatedBaseType = switch ($zone.ZoneType) {
					"Primary"   { $I18n.Labels.Primary }
					"Secondary" { $I18n.Labels.Secondary }
					"Stub"      { $I18n.Labels.Stub }
					Default     { $zone.ZoneType }
				}
				$fullTypeDisplay = if ($zone.IsADIntegrated) { "${translatedBaseType}, $($I18n.Labels.ADIntegrated)" } else { $translatedBaseType }
				$statusText = if ($zone.ZoneStatus -eq "Running") { $I18n.Labels.Running } else { $I18n.Labels.Stopped }
				$statusClass = if ($zone.ZoneStatus -eq "Running") { "status-ok" } else { "status-error" }
				$secPill = if ($zone.IsSigned) { "<span class='status-pill status-ok'>ACTIVE</span>" } else { "<span class='status-pill status-warning'>INACTIVE</span>" }
				$htmlDNS += "<tr><td><b>$($zone.ZoneName)</b></td><td>${fullTypeDisplay}</td>
							<td><span class='status-pill ${statusClass}'>${statusText}</span></td>
							<td>$($zone.ReplicationScope)</td><td>${secPill}</td></tr>"
			}
		}
		$htmlDNS += "</tbody></table></div>"
	}
	
	# --- START DEBUG MOCK DATA: DNS FULL TEST ---
	#$debugDNSFull = $true
	#
	#if ($debugDNSFull) {
	#	Write-ADHCLog "DEBUG: Simuliere DNS-Probleme (SRV, NS, AD-Int, Scavenging)..." -Level Warning
	#	
	#	$Data.DNS = [PSCustomObject]@{
	#		ForwardZones = @(
	#			[PSCustomObject]@{ ZoneName = "contoso.com"; ZoneStatus = "Running"; IsADIntegrated = $true; IsSigned = $false }
	#		)
	#		ReverseZones = @(
	#			[PSCustomObject]@{ ZoneName = "192.168.1.in-addr.arpa"; ZoneStatus = "Stopped"; IsADIntegrated = $false; IsSigned = $false }
	#		)
	#		NSStatus = @(
	#			[PSCustomObject]@{ Name = "DC01"; Service = "Running"; ICMP = "OK" },
	#			[PSCustomObject]@{ Name = "DC02-OLD"; Service = "Stopped"; ICMP = "Fail" }
	#		)
	#		QuickChecks = @{
	#			MissingScavenging = @("contoso.com") # 1 von 2 Zonen fehlt -> Trigger Mismatch
	#			SRVDetails = @(
	#				[PSCustomObject]@{ ServiceKey = "PDC"; Status = "Critical" },
	#				[PSCustomObject]@{ ServiceKey = "LDAP"; Status = "OK" }
	#			)
	#		}
	#	}
	#
	#	if ($Settings.ShowRecommendations -is [hashtable]) { $Settings.ShowRecommendations["DNS"] = $true }
	#}
	# --- ENDE DEBUG MOCK DATA ---

	# --- EMPFEHLUNGEN GENERIEREN ---
	function Get-ADHCRecommendations {
		param($Data, $Settings, $I18n, $LangCode)
		
		$recPath = Join-Path $PSScriptRoot "..\config\recommendations.json"

		if (-not (Test-Path $recPath)) { return "" }
		
		try {
			$recJson = Get-Content $recPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
		} catch { return "" }
	
		$activeRecs = @()
	
		# --- PRÜFUNG: DOMAIN ÜBERSICHT ---
		$showDomainRec = if ($Settings.ShowRecommendations -is [hashtable]) {
			$Settings.ShowRecommendations["DomainOverview"]
		} else {
			$Settings.ShowRecommendations.DomainOverview
		}
		
		if ($showDomainRec -and $Data.DomainStats) {
			$stats = $Data.DomainStats
			
			# --- KRBTGT Alter berechnen ---
			$krbtgtStatus = "OK"
			if ($stats.KrbtgtLastSet) {
				# Wir berechnen das Alter in Tagen
				$daysOld = ((Get-Date) - $stats.KrbtgtLastSet).Days
				if ($daysOld -gt 180) { $krbtgtStatus = "Expired" }
			}
	
			foreach ($rule in $recJson.DomainOverview) {
				# Dynamische Wert-Ermittlung basierend auf der Property in der JSON
				$val = switch ($rule.Property) {
					"KrbtgtStatus" { $krbtgtStatus }
					"RecycleBin"   { $stats.RecycleBin }
					"ForestLevel"  { [int]$stats.ForestLevel }
					"DomainLevel"  { [int]$stats.DomainLevel }
					Default        { $stats.$($rule.Property) }
				}
	
				# Vergleich
				$conditions = $rule.Condition | ForEach-Object { [string]$_ }
				if ($conditions -contains [string]$val) {
					$areaLabel = if ($rule.SubCategory -is [string]) { $rule.SubCategory } else { $rule.SubCategory.$LangCode }
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $rule.Category
						Area        = $areaLabel
						Description = $rule.Recommendation.$LangCode
						Priority    = $rule.Priority
					}
				}
			}
		}
		
		# --- PRÜFUNG: FSMO Architektur & Erreichbarkeit ---
		$showFsmoRec = if ($Settings.ShowRecommendations -is [hashtable]) {
			$Settings.ShowRecommendations["FSMO"]
		} else {
			$Settings.ShowRecommendations.FSMO
		}
		
		if ($showFsmoRec -and $Data.FSMO) {
			$fsmo = $Data.FSMO
			$stats = $Data.DomainStats
			$dcs = $Data.Discovery # Liste der DCs für den GC-Check
		
			# 1. KLASSISCHE ERREICHBARKEIT (Deine bestehende Schleife)
			foreach ($rule in ($recJson.FSMO | Where-Object { $_.RoleKey })) {
				$roleData = $fsmo | Where-Object { $_.RoleID -eq $rule.RoleKey }
				if ($roleData -and $rule.Condition -contains $roleData.Erreichbar) {
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $rule.Category
						Area        = "$($roleData.Role)"
						Description = "$($rule.Recommendation.$LangCode) (Server: $($roleData.Owner))"
						Priority    = $rule.Priority
					}
				}
			}
		
			# 2. ARCHITEKTUR-CHECKS (Vergleiche)
			
			# Helfer: Rolleninhaber extrahieren
			$schemaOwner = ($fsmo | Where-Object { $_.RoleID -eq "SchemaMaster" }).Owner
			$namingOwner = ($fsmo | Where-Object { $_.RoleID -eq "DomainNamingMaster" }).Owner
			$infraOwner  = ($fsmo | Where-Object { $_.RoleID -eq "InfrastructureMaster" }).Owner
			$allOwners   = $fsmo.Owner | Select-Object -Unique
		
			# AD-FSMO-06: Schema & Naming Consolidation
			if ($schemaOwner -and $namingOwner -and ($schemaOwner -ne $namingOwner)) {
				$rule = $recJson.FSMO | Where-Object { $_.Id -eq "AD-FSMO-06" }
				$areaLabel = if ($rule.SubCategory -is [string]) { $rule.SubCategory } else { $rule.SubCategory.$LangCode }
				$activeRecs += [PSCustomObject]@{
					Id = $rule.Id; Category = $rule.Category; Area = $areaLabel
					Description = $rule.Recommendation.$LangCode; Priority = $rule.Priority
				}
			}
		
			# AD-FSMO-07: Gesamte Rollenkonzentration (für Single Domain)
			if ($allOwners.Count -gt 1) {
				$rule = $recJson.FSMO | Where-Object { $_.Id -eq "AD-FSMO-07" }
				$areaLabel = if ($rule.SubCategory -is [string]) { $rule.SubCategory } else { $rule.SubCategory.$LangCode }
				$activeRecs += [PSCustomObject]@{
					Id = $rule.Id; Category = $rule.Category; Area = $areaLabel
					Description = $rule.Recommendation.$LangCode; Priority = $rule.Priority
				}
			}
		
			# AD-FSMO-08: Infrastructure Master vs. Global Catalog (Die "Phantom-Objekt" Regel)
			# Wir suchen den Infrastructure-Owner in der Discovery-Liste, um seinen GC-Status zu prüfen
			$infraDC = $dcs | Where-Object { $infraOwner -like "*$($_.Server)*" }
			$isGC = $infraDC.IsGC -eq $true -or $infraDC.IsGC -eq "True"
		
			if ($dcs.Count -gt 1 -and $stats.RecycleBin -eq $false -and $isGC) {
				$rule = $recJson.FSMO | Where-Object { $_.Id -eq "AD-FSMO-08" }
				$areaLabel = if ($rule.SubCategory -is [string]) { $rule.SubCategory } else { $rule.SubCategory.$LangCode }
				$activeRecs += [PSCustomObject]@{
					Id = $rule.Id; Category = $rule.Category; Area = $areaLabel
					Description = "$($rule.Recommendation.$LangCode) (Server: $infraOwner)"; Priority = $rule.Priority
				}
			}
		}
			
		# --- PRÜFUNG: DCDIAG HEALTH MATRIX ---
		$showDcdiagRec = if ($Settings.ShowRecommendations -is [hashtable]) {
			$Settings.ShowRecommendations["DCDIag"]
		} else {
			$Settings.ShowRecommendations.DCDIag
		}
	
		if ($showDcdiagRec -and $Data.DCDiag) {
			Write-ADHCLog "Analysiere DCDIAG Matrix auf Fehler..." -Component "Reporting"
			
			foreach ($rule in $recJson.DCDIag) {
				$failedServers = @()
				$testProp = $rule.Property
	
				# Wir prüfen JEDEN Server in den Daten auf diesen spezifischen Test
				foreach ($dcEntry in $Data.DCDiag) {
					$status = [string]$dcEntry.$testProp
					
					# Wenn der Status in den Fehler-Conditions der JSON enthalten ist
					if ($rule.Condition -contains $status) {
						$failedServers += $dcEntry.Server
					}
				}
	
				# Falls Server gefunden wurden, erstelle EINE gruppierte Empfehlung
				if ($failedServers.Count -gt 0) {
					$serverList = $failedServers -join ", "
					$areaLabel = if ($rule.SubCategory -is [string]) { $rule.SubCategory } else { $rule.SubCategory.$LangCode }
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $rule.Category
						Area        = $areaLabel
						# Wir hängen die Serverliste an die Beschreibung an
						Description = "$($rule.Recommendation.$LangCode) (Betroffene Server: $serverList)"
						Priority    = $rule.Priority
					}
				}
			}
		}

		# --- PRÜFUNG: DC SYSTEMSTATUS (DCSystem) ---
		if ($Settings.ShowRecommendations.DCSystem -and $Data.Discovery) {
			Write-ADHCLog "Analysiere DCSystem (Lokalisiert & Fehlerbereinigt)..." -Component "Reporting"
			
			$osLifecycle = @{
				"2012" = @{ Main = "10.10.2018"; Ext = "10.10.2023"; Status = "OutOfSupport" }
				"2016" = @{ Main = "11.01.2022"; Ext = "12.01.2027"; Status = "OutOfMainstream" }
				"2019" = @{ Main = "09.01.2024"; Ext = "09.01.2029"; Status = "OutOfMainstream" }
				"2022" = @{ Main = "13.10.2026"; Ext = "14.10.2031"; Status = "Supported" }
			}
		
			$rules = if ($recJson.DCSystem) { $recJson.DCSystem } else { $recJson.Discovery }
		
			foreach ($rule in $rules) {
				$failedServers = @()
				$infoSuffix = ""
		
				foreach ($srv in $Data.Discovery) {
					
					# FALL 1: OS Lifecycle (OS-01)
					if ($rule.Property -eq "OSSupportStatus") {
						$yearMatch = $osLifecycle.Keys | Where-Object { $srv.OS -like "*$_*" }
						if ($yearMatch) {
							$lifecycle = $osLifecycle[$yearMatch]
							if ($rule.Condition -contains $lifecycle.Status) {
								$failedServers += $srv.Server
								# LOKALISIERUNG: Wir nutzen Keys aus der i18n für 'Mainstream Ende' etc.
								$infoSuffix = " [$($I18n.Labels.MainstreamEnd): $($lifecycle.Main) | $($I18n.Labels.ExtendedUntil): $($lifecycle.Ext)]"
							}
						}
					}
					
					# FALL 2: Festplattenplatz (SRV-01)
					elseif ($rule.Property -eq "DiskSpace") {
						if ($rule.Condition -contains $srv.Status -and $srv.OS -ne "Unreachable") {
							# LOKALISIERUNG: 'frei' durch i18n Label ersetzen
							$failedServers += "$($srv.Server) ($($srv.FreeDiskPct) $($I18n.Labels.FreeDisk))"
						}
					}
		
					# FALL 3: Erreichbarkeit (SRV-02)
					elseif ($rule.Property -eq "Status" -and $srv.OS -eq "Unreachable") {
						if ($rule.Condition -contains $srv.Status) {
							$failedServers += $srv.Server
						}
					}
				}
		
				if ($failedServers.Count -gt 0) {
					# SubCategory ist jetzt ein {de/en}-Objekt — direkt per LangCode auflösen
					$localizedArea = if ($rule.SubCategory -is [string]) { $rule.SubCategory } else { $rule.SubCategory.$LangCode }
		
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $rule.Category
						Area        = $localizedArea
						Description = "$($rule.Recommendation.$LangCode)$($infoSuffix) (Server: $($failedServers -join ', '))"
						Priority    = $rule.Priority
					}
				}
			}
		}
		
		# --- PRÜFUNG: AD BACKUP STATUS ---
		$showBackupRec = if ($Settings.ShowRecommendations -is [hashtable]) {
			$Settings.ShowRecommendations["Backup"]
		} else {
			$Settings.ShowRecommendations.Backup
		}
		
		if ($showBackupRec -and $Data.Backup) {
			Write-ADHCLog "Analysiere Backup-Daten für Empfehlungen..." -Component "Reporting"
			
			foreach ($rule in $recJson.Backup) {
				$failedPartitions = @()
		
				foreach ($b in $Data.Backup) {
					# Wir prüfen, ob der Status der Partition in der Regel-Bedingung enthalten ist
					if ($rule.Condition -contains $b.Status) {
						
						# Zeit-Info generieren: "X Tage, Y Stunden her"
						# Falls kein Datum gefunden wurde (Error), geben wir einen Platzhalter aus
						$timeString = if ($b.LastBackup) {
							"$($b.Days) $($I18n.Labels.Days), $($b.Hours) $($I18n.Labels.Hours) $($I18n.Labels.TimeAgo)"
						} else {
							"$($I18n.Labels.NoADBackupFound)"
						}
		
						$failedPartitions += "$($b.Partition) ($timeString)"
					}
				}
		
				if ($failedPartitions.Count -gt 0) {
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $rule.Category
						Area        = $I18n.Labels.BackupStatus
						# Die detaillierte Zeit-Information wird an den Beschreibungstext angehängt
						Description = "$($rule.Recommendation.$LangCode) (Partitionen: $($failedPartitions -join '; '))"
						Priority    = $rule.Priority
					}
				}
			}
		}
		
		# --- PRÜFUNG: DIENSTE STATUS (Services) ---
		$showServiceRec = if ($Settings.ShowRecommendations -is [hashtable]) {
			$Settings.ShowRecommendations["Services"]
		} else {
			$Settings.ShowRecommendations.Services
		}
		
		if ($showServiceRec -and $Data.Services) {
			Write-ADHCLog "Analysiere Dienste-Status für Empfehlungen..." -Component "Reporting"
			
			foreach ($rule in $recJson.Services) {
				$failedServers = @()
				$serviceName = $rule.Property # z.B. 'dns', 'kdc'...
		
				foreach ($srvEntry in $Data.Services) {
					# Wir suchen den spezifischen Dienst in den Daten des Servers
					# Annahme: $Data.Services ist ein Array von Objekten mit Server-Name und Dienst-Details
					$svc = $srvEntry.Details | Where-Object { $_.ServiceName -eq $serviceName -or $_.ShortName -eq $serviceName }
					
					if ($svc) {
						# FEHLER-BEDINGUNG: Status nicht OK -ODER- StartType nicht Automatic
						$isNotAuto = ($svc.StartMode -ne "Auto" -and $svc.StartMode -ne "Automatic")
						$isNotRunning = ($svc.Status -ne "OK" -and $svc.Status -ne "Running")
		
						if ($isNotRunning -or $isNotAuto) {
							$detail = "($($svc.Status) / $($svc.StartMode))"
							$failedServers += "$($srvEntry.Server) $detail"
						}
					}
				}
		
				if ($failedServers.Count -gt 0) {
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $rule.Category
						Area        = "$($serviceName.ToUpper())"
						Description = "$($rule.Recommendation.$LangCode) (Server: $($failedServers -join ', '))"
						Priority    = $rule.Priority
					}
				}
			}
		}
		
		# --- PRÜFUNG: SITES & SERVICES (Sites) ---
		$showSitesRec = if ($Settings.ShowRecommendations -is [hashtable]) {
			$Settings.ShowRecommendations["Sites"]
		} else {
			$Settings.ShowRecommendations.Sites
		}
		
		if ($showSitesRec -and $Data.Sites) {
			Write-ADHCLog "Analysiere Sites & Services für Empfehlungen..." -Component "Reporting"
			
			# Sicherstellen, dass wir den richtigen Block aus der JSON lesen
			$siteRules = if ($recJson.Sites) { $recJson.Sites } else { $recJson.SitesServices }
		
			foreach ($rule in $siteRules) {
				$affectedItems = @()
				# WICHTIG: Variable immer leeren, damit Suffixe nicht 'kleben' bleiben
				$infoSuffix = "" 
		
				switch ($rule.Property) {
					"ReplicationInterval" {
						foreach ($link in $Data.Sites.Transports) {
							# Prüfung gegen 15 Min (Microsoft Empfehlung)
							if ($link.ReplInterval -ne "Default" -and [int]$link.ReplInterval -gt 15) {
								$affectedItems += "$($link.Name) ($($link.ReplInterval) min)"
							}
						}
					}
					"SubnetsWithoutSite" {
						foreach ($sub in $Data.Sites.Subnets) {
							if ($sub.Site -eq "-") { $affectedItems += $sub.Name }
						}
					}
					"SitesWithoutGC" {
					foreach ($site in $Data.Sites.Sites) {
						# Prüfen, ob ein Server in der Site die GC-Rolle hat
						$hasGC = $site.Servers | Where-Object { $_.IsGC -eq $true -or $_.IsGC -eq "True" }

						if (-not $hasGC) {
							$statusInfo = if ($site.Servers.Count -eq 0) { " (Keine Server vorhanden)" } else { " (Kein GC konfiguriert)" }
							$affectedItems += "$($site.Name)$($statusInfo)"
						}
					}
				}
					
					"NoSubnetsDefined" {
						if (-not $Data.Sites.Subnets -or $Data.Sites.Subnets.Count -eq 0) {
							# Wir fügen einen Platzhalter hinzu, damit die Empfehlung ausgelöst wird
							$affectedItems += "$($I18n.Labels.NoSubnetsDefined)"
						}
					}
				}
		
				if ($affectedItems.Count -gt 0) {
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $rule.Category
						Area        = $I18n.Labels.SitesServices
						Description = "$($rule.Recommendation.$LangCode) (Details: $($affectedItems -join ', '))"
						Priority    = $rule.Priority
					}
				}
			}
		}
	
		# --- PRÜFUNG: SICHERHEIT (Security) ---
		if ($Settings.ShowRecommendations.Security -and $Data.Security) {
			Write-ADHCLog "Verarbeite Sicherheits-Empfehlungen (lokalisiert)..." -Component "Reporting"
			
			$sec = $Data.Security
		
			foreach ($rule in $recJson.Security) {
				$val = [int]$sec.$($rule.Property)
				$isTriggered = $false
		
				# Logische Prüfung (Schema Admins > 1 für Trigger)
				switch ($rule.Property) {
					"DomAdminCount" { $isTriggered = ($val -gt 5) }
					"EntAdminCount" { $isTriggered = ($val -gt 2) }
					"SchAdminCount" { $isTriggered = ($val -gt 1) }
					Default         { $isTriggered = ($val -gt 0) }
				}
		
				if ($isTriggered) {
					# SubCategory ist jetzt ein {de/en}-Objekt — direkt per LangCode auflösen
					$translatedArea = if ($rule.SubCategory -is [string]) { $rule.SubCategory } else { $rule.SubCategory.$LangCode }
		
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $I18n.Labels.Security
						Area        = $translatedArea
						Description = "$($rule.Recommendation.$LangCode) ($($I18n.Labels.Value): $val $($I18n.Labels.Users))"
						Priority    = $rule.Priority
					}
				}
			}
		}
		
		# --- PRÜFUNG: KENNWORTRICHTLINIEN (Sub-Section von Security) ---
		if ($Settings.ShowRecommendations.Security -and $Data.Security) {
			Write-ADHCLog "Verarbeite Kennwortrichtlinien-Empfehlungen..." -Component "Reporting"
			
			$sec = $Data.Security
		
			foreach ($rule in $recJson.PasswordPolicy) {
				$isTriggered = $false
				$val = $sec.$($rule.Property)
				$suffix = ""
		
				switch ($rule.Property) {
					"MinPwdLength" { 
						$isTriggered = ([int]$val -lt 12)
						$suffix = "$val $($I18n.Labels.Characters)"
					}
					"Complexity" { 
						$isTriggered = ($val -eq $false -or $val -eq "False")
						$suffix = if ($isTriggered) { $I18n.Labels.Disabled } else { $I18n.Labels.Enabled }
					}
					"PwdHistory" { 
						$isTriggered = ([int]$val -lt 24)
						$suffix = "$val $($I18n.Labels.Passwords)"
					}
					"LockoutThreshold" { 
						# Trigger bei 0 (kein Schutz) oder über 10 (zu unsicher)
						$numVal = [int]$val
						$isTriggered = ($numVal -eq 0 -or $numVal -gt 10)
						$suffix = "$([string]$numVal) $($I18n.Labels.Attempts)"
					}
					
					"LockoutDuration" {
						$numVal = [int]$val
						# Trigger wenn < 15 Minuten (ausser 0, was permanent bedeutet)
						$isTriggered = ($numVal -gt 0 -and $numVal -lt 15)
						$suffix = "$([string]$numVal) $($I18n.Labels.Minutes)"
					}
					"ResetLockoutCount" {
						$numVal = [int]$val
						$isTriggered = ($numVal -lt 15)
						$suffix = "$([string]$numVal) $($I18n.Labels.Minutes)"
					}
				}
		
				if ($isTriggered) {
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $I18n.Labels.Security
						Area        = $I18n.Labels.PasswordPolicy
						Description = "$($rule.Recommendation.$LangCode) ($($I18n.Labels.CurrentValue): $suffix)"
						Priority    = $rule.Priority
					}
				}
			}
		}
		
		# --- PRÜFUNG: OU & KONTO SICHERHEIT ---
		if ($Settings.ShowRecommendations.OUAccountSecurity -and $Data.OUAccountSecurity) {
			$ouSec = $Data.OUAccountSecurity
			
			foreach ($rule in $recJson.OUAccountSecurity) {
				$isTriggered = $false
				$currentValue = 0
		
				switch ($rule.Property) {
					"OrphanedSIDsCount" {
						$currentValue = $ouSec.UniqueOrphanCount
						if ($currentValue -gt 0) { $isTriggered = $true }
					}
					"OUInheritanceDisabled" {
						$currentValue = $ouSec.DisabledInheritanceOU.Count
						if ($currentValue -gt 0) { $isTriggered = $true }
					}
					"UserInheritanceDisabled" {
						$currentValue = $ouSec.DisabledInheritanceUser.Count
						if ($currentValue -gt 0) { $isTriggered = $true }
					}
				}
		
				if ($isTriggered) {
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $I18n.Labels.Security
						Area        = $I18n.Labels.ObjectSecurity
						Description = "$($rule.Recommendation.$LangCode) ($($I18n.Labels.CurrentValue): $currentValue)"
						Priority    = $rule.Priority
					}
				}
			}
		}

		# --- PRÜFUNG: ENTRA ID / AZURE AD CONNECT ---
		if ($Settings.ShowRecommendations.Entra -and $Data.Entra) {
			Write-ADHCLog "Verarbeite Entra Connect Empfehlungen..." -Component "Reporting"
			
			$entra = $Data.Entra # Das Objekt aus Get-EntraSyncStatus
			
			foreach ($rule in $recJson.Entra) {
				$isTriggered = $false
				$detail = ""
		
				switch ($rule.Property) {
					"VersionMismatch" {
						# Versions-Vergleich (als [version] Objekt für korrekte Logik)
						try {
							$curr = [version]$entra.InstalledVersion
							$exp  = [version]$entra.ExpectedVersion
							if ($curr -lt $exp) {
								$isTriggered = $true
								$detail = "($($entra.InstalledVersion) < $($entra.ExpectedVersion))"
							}
						} catch { 
							# Falls Versionen kein Standardformat haben (z.B. "Error")
							if ($entra.InstalledVersion -ne $entra.ExpectedVersion) { $isTriggered = $true }
						}
					}
					"ServiceStatus" {
						# Prüfen ob Dienste in ServiceDetails nicht "Running" sind
						$stopped = $entra.ServiceDetails | Where-Object { $_.Status -ne "Running" }
						if ($stopped) {
							$isTriggered = $true
							$detail = "($($stopped.Name -join ', '))"
						}
					}
				}
		
				if ($isTriggered) {
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $I18n.Labels.Security # Oder Infrastruktur
						Area        = $I18n.Labels.HybridIdentity
						Description = "$($rule.Recommendation.$LangCode) $detail"
						Priority    = $rule.Priority
					}
				}
			}
		}
		
		# --- PRÜFUNG: DNS ZONE HEALTH ---
		if ($Settings.ShowRecommendations.DNS -and $Data.DNS) {
			Write-ADHCLog "Analysiere alle DNS-Health Metriken..." -Component "Reporting"
			
			$dns = $Data.DNS
			$allZones = $dns.ForwardZones + $dns.ReverseZones
			$totalZonesCount = $allZones.Count
			$missingScavengingCount = $dns.QuickChecks.MissingScavenging.Count
		
			foreach ($rule in $recJson.DNS) {
				$affectedItems = @()
				$isTriggered = $false
		
				switch ($rule.Property) {
					# 1. Scavenging Mismatch (Teilweise vergessen)
					"ScavengingZoneMismatch" {
						if ($missingScavengingCount -gt 0 -and $missingScavengingCount -lt $totalZonesCount) {
							$isTriggered = $true
							$affectedItems = $dns.QuickChecks.MissingScavenging
						}
					}
					# 2. Kritische SRV Records
					"MissingSRV" {
						$failedSRV = $dns.QuickChecks.SRVDetails | Where-Object { $_.Status -ne "OK" }
						if ($failedSRV) {
							$isTriggered = $true
							foreach ($srv in $failedSRV) { $affectedItems += $srv.ServiceKey }
						}
					}
					# 3. Nameserver Erreichbarkeit
					"NSUnreachable" {
						$failedNS = $dns.NSStatus | Where-Object { $_.ICMP -ne "OK" -or $_.Service -ne "Running" }
						if ($failedNS) {
							$isTriggered = $true
							foreach ($ns in $failedNS) { $affectedItems += "$($ns.Name) ($($ns.Service))" }
						}
					}
					# 4. Nicht AD-integrierte Zonen
					"NonADIntegrated" {
						$nonAD = $allZones | Where-Object { $_.IsADIntegrated -eq $false }
						if ($nonAD) {
							$isTriggered = $true
							foreach ($z in $nonAD) { $affectedItems += $z.ZoneName }
						}
					}
					# 5. Gestoppte Zonen
					"ZoneStopped" {
						$stopped = $allZones | Where-Object { $_.ZoneStatus -ne "Running" }
						if ($stopped) {
							$isTriggered = $true
							foreach ($z in $stopped) { $affectedItems += $z.ZoneName }
						}
					}
					# 6. Scavenging Global Aus (Nur Hinweis)
					"ScavengingGloballyDisabled" {
						if ($missingScavengingCount -eq $totalZonesCount -and $totalZonesCount -gt 0) {
							$isTriggered = $true
						}
					}
					# 7. DNSSEC Inaktiv (Nur Hinweis)
					"DNSSECNotConfigured" {
						$unsigned = $allZones | Where-Object { $_.IsSigned -eq $false }
						if ($unsigned) {
							$isTriggered = $true
							# Wir listen hier nicht alle Zonen auf, um den Report nicht zu fluten, außer es sind wenige
							if ($unsigned.Count -le 3) { foreach ($z in $unsigned) { $affectedItems += $z.ZoneName } }
						}
					}
				}
		
				if ($isTriggered) {
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $I18n.Labels.Infrastructure
						Area        = $I18n.Labels.DNSZoneHealth
						Description = if ($affectedItems) { "$($rule.Recommendation.$LangCode) (Details: $($affectedItems -join ', '))" } else { $rule.Recommendation.$LangCode }
						Priority    = $rule.Priority
					}
				}
			}
		}
		
			# --- HTML GENERIERUNG ---
			if ($activeRecs.Count -gt 0) {
				$html = "<div class='card'><h2>$($I18n.Sections.Recommendations)</h2>"
				$html += "<table class='rec-matrix'><thead><tr>"
				$html += "<th class='text-center'>ID</th>"
				$html += "<th class='text-left'>$($I18n.Labels.Category)</th>"
				$html += "<th class='text-left'>$($I18n.Labels.Area)</th>"
				$html += "<th class='text-left'>$($I18n.Labels.Recommendation)</th>"
				$html += "<th class='text-center'>$($I18n.Labels.Priority)</th>"
				$html += "</tr></thead><tbody>"
				
				foreach ($rec in $activeRecs) {
					$prioClass = "prio-badge prio-$($rec.Priority.ToLower())"
					$html += "<tr class='rec-row'>
								<td class='rec-id text-center'>$($rec.Id)</td>
								<td class='rec-cat text-left'>$($rec.Category)</td>
								<td class='rec-sub text-left'>$($rec.Area)</td>
								<td class='rec-text text-left'>$($rec.Description)</td>
								<td class='text-center'><span class='$prioClass'>$($rec.Priority.ToUpper())</span></td>
							</tr>"
				}
				$html += "</tbody></table></div>"
				return $html
			}
			return ""
		}

	# Empfehlungen generieren
	$htmlRec = Get-ADHCRecommendations -Data $Data -Settings $Settings -I18n $I18n -LangCode $LangCode

    # --- Replacements ---
    # CSS Injection
    $html = $html.Replace("{{CSS_CONTENT}}", $cssContent)
    # Sprache
    $html = $html.Replace("{{LANG_CODE}}", $LangCode)

    $html = $html.Replace("{{TITLE}}", $I18n.Title)
    $html = $html.Replace("{{DATE}}", (Get-Date).ToString("dd.MM.yyyy HH:mm"))
    
    # --- LOGO LOGIK ---
    $logoInput = $Settings.Company.LogoUrl
    $finalLogoSrc = ""
    
    if (-not [string]::IsNullOrWhiteSpace($logoInput)) {
        $logoToLoad = $null
        if (Test-Path $logoInput -PathType Leaf) {
            $logoToLoad = Resolve-Path $logoInput
        } else {
            # Suche im Template-Ordner
            if ($templateDir) {
                $logoName = Split-Path $logoInput -Leaf
                $candidate = Join-Path $templateDir $logoName
                if (Test-Path $candidate -PathType Leaf) { $logoToLoad = $candidate }
            }
        }

        if ($logoToLoad) {
            try {
                $imgBytes = [System.IO.File]::ReadAllBytes($logoToLoad)
                $b64 = [Convert]::ToBase64String($imgBytes)
                $ext = [System.IO.Path]::GetExtension($logoToLoad).Replace(".","")
                if ($ext -eq "svg") { $ext = "svg+xml" }
                $finalLogoSrc = "data:image/$ext;base64,$b64"
                Write-ADHCLog "Logo eingebettet: $logoToLoad"
            } catch {
                Write-ADHCLog "Fehler beim Einbetten des Logos: $_" -Level Warning
                $finalLogoSrc = $logoInput
            }
        }
    }

    $compName = if ($Settings.Company.Name) { $Settings.Company.Name } else { "Company Name" }
    $compAddr = if ($Settings.Company.Address) { $Settings.Company.Address } else { "" }
    
    $html = $html.Replace("{{COMPANY_NAME}}", $compName)
    $html = $html.Replace("{{COMPANY_ADDRESS}}", $compAddr)
    $html = $html.Replace("{{LOGO_URL}}", $finalLogoSrc)

    $html = $html.Replace("{{SECTION_DOMAIN_STATS}}", $htmlStats)
    $html = $html.Replace("{{SECTION_FSMO}}", $htmlFSMO)
    $html = $html.Replace("{{SECTION_DCDIAG}}", $htmlDcdiag)
    $html = $html.Replace("{{SECTION_DCS}}", $htmlDCs)
	$html = $html.Replace("{{SECTION_BACKUP}}", $htmlBackup)
    $html = $html.Replace("{{SECTION_SERVICES}}", $htmlSvcs)
    $html = $html.Replace("{{SECTION_SITES}}", $htmlSites)
    $html = $html.Replace("{{SECTION_SECURITY}}", $htmlSec)
	$html = $html.Replace("{{SECTION_OU_ACCOUNT_SECURITY}}", $htmlOUSec)
    $html = $html.Replace("{{SECTION_ENTRA}}", $htmlEntra)
	$html = $html.Replace("{{SECTION_DNS}}", $htmlDNS)
	$html = $html.Replace("{{SECTION_RECOMMENDATIONS}}", $htmlRec)
	
    
    $outDir = $Settings.Paths.Output
    if (-not (Test-Path $outDir)) { New-Item -Type Directory $outDir -Force | Out-Null }
    
    $htmlFile = Join-Path $outDir ("ADHealthCheck_Report_{0}.html" -f $timestamp)
    $html | Out-File -FilePath $htmlFile -Encoding utf8
    Write-ADHCLog -Message "HTML Report: $htmlFile" -Component "Reporting"
    return $htmlFile
}

Export-ModuleMember -Function New-ADHCReport