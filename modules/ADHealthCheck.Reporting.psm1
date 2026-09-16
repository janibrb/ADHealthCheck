# MODULE: ADHealthCheck.Reporting.psm1

# Listenfelder des Upload-JSON, Pfade relativ zum Knoten "data".
#
# ⚠ Warum es diese Liste braucht: PowerShell kennt keinen Unterschied zwischen
# "ein Element" und "eine Liste mit einem Element". Eine Erhebungsschleife, die
# genau EINMAL durchlaeuft, liefert einen Skalar — und ConvertTo-Json schreibt
# daraus ein Objekt statt eines Arrays. Ein Konsument, der die Liste mit
# forEach/map liest, findet dann NICHTS, obwohl der Wert im JSON steht.
#
# Im Feld beobachtet an einer Umgebung mit genau einer Reverse-Zone, einem
# Standort und einem Domaenencontroller: neun Felder kamen als Objekt an.
# Der Bericht war unauffaellig — HTML iteriert ueber den Skalar klaglos.
$script:ADHCJsonListPaths = @(
    'Backup', 'DCDiag', 'Discovery', 'EventLog', 'FSMO', 'Services', 'Replication',
    'Replication[].PartitionsFound',
    'DNS.ForwardZones', 'DNS.ReverseZones', 'DNS.NSStatus',
    'DNS.TrustAnchors.TrustPoints',
    'DNS.QuickChecks.MissingScavenging', 'DNS.QuickChecks.ScavengingUnknown',
    'DNS.QuickChecks.NSCondition', 'DNS.QuickChecks.SRVDetails',
    'Entra.ServiceDetails',
    'OUAccountSecurity.DisabledInheritanceOU', 'OUAccountSecurity.DisabledInheritanceUser',
    'OUAccountSecurity.TopOrphanedSIDs',
    'Security.ProtectedGroupMemberDNs',
    'Sites.Sites', 'Sites.Subnets', 'Sites.Transports',
    'Sites.Sites[].Servers', 'Sites.Sites[].Connections'
)

function Set-ADHCJsonListShape {
    <#
    .SYNOPSIS
        Erzwingt Array-Form fuer die genannten Felder, vor dem Serialisieren.
    .DESCRIPTION
        Fasst ausdruecklich NUR die uebergebenen Pfade an — ein blindes Einpacken
        aller Felder wuerde aus Objekten wie QuickChecks einelementige Listen
        machen und den Vertrag an anderer Stelle brechen.

        ⚠ $null bleibt $null. Der Unterschied traegt Bedeutung: $null heisst
        "nicht erhoben", [] heisst "erhoben, nichts gefunden". @($null) wuerde
        das eine still in das andere verwandeln.
    .PARAMETER Data
        Der zu serialisierende Datenknoten. Wird in place geaendert.
    .PARAMETER Path
        Pfade mit "." als Trenner. Ein Segment mit "[]" steigt in die Elemente
        einer Liste ab, z.B. "Sites.Sites[].Servers".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        $Data,

        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [string[]]$Path
    )

    foreach ($p in $Path) {
        Set-ADHCListShapeAt -Node $Data -Segment @($p -split '\.')
    }
    return $Data
}

function Set-ADHCListShapeAt {
    # Rekursiver Helfer zu Set-ADHCJsonListShape. Nicht exportiert.
    [CmdletBinding()]
    param($Node, [string[]]$Segment)

    if ($null -eq $Node -or $Segment.Count -eq 0) { return }
    if ($Node -isnot [psobject]) { return }

    $name         = $Segment[0]
    $ueberElement = $false
    if ($name -match '^(.+)\[\]$') { $name = $Matches[1]; $ueberElement = $true }

    $prop = $Node.PSObject.Properties[$name]
    if (-not $prop) { return }

    $rest = @($Segment | Select-Object -Skip 1)
    if ($rest.Count -eq 0) {
        # $null bleibt $null — siehe Kopfkommentar.
        if ($null -ne $prop.Value -and $prop.Value -isnot [object[]]) {
            $prop.Value = @($prop.Value)
        }
        return
    }

    if ($ueberElement) {
        foreach ($element in @($prop.Value)) { Set-ADHCListShapeAt -Node $element -Segment $rest }
    } else {
        Set-ADHCListShapeAt -Node $prop.Value -Segment $rest
    }
}

function New-ADHCReport {
    param($Data, $Settings, $I18n, $Mapping, $TemplatePath, $LangCode="de", $CollectorVersion="unknown")
    
    Write-ADHCLog -Message "Generiere Reports..." -Component "Reporting"
    
    # 1. JSON Export
    $dataDir = $Settings.Paths.Data
    if (-not $dataDir) { $dataDir = "./output/data" }
    if (-not (Test-Path $dataDir)) { New-Item -Type Directory $dataDir -Force | Out-Null }
    
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $jsonFile = Join-Path $dataDir ("ADHealthCheck_{0}.json" -f $timestamp)
    # HINWEIS: Das JSON wird NICHT mehr hier (roh) geschrieben, sondern am Ende von
    # New-ADHCReport als Dashboard-Upload-Vertrag (Metadaten + Verdikte + Rohdaten
    # mit MINIMIERTER PII, Datumsangaben als ISO-8601). Siehe Block "Upload-JSON
    # (Dashboard)". ACHTUNG: "minimiert" heisst NICHT "frei von PII" — seit v2.4.6
    # enthaelt das JSON wieder Klarnamen und DNs (DisabledInheritanceUser, erste 50).

    # 2. HTML Template & CSS laden
    if (-not (Test-Path $TemplatePath)) { Throw "Template nicht gefunden unter: $TemplatePath" }
    
    # Pfad absolut auflösen, um Fehler mit relativen Pfaden zu vermeiden
    $resolvedTemplatePath = Resolve-Path $TemplatePath
    $templateDir = Split-Path $resolvedTemplatePath -Parent
    
    # HTML einlesen — -Encoding UTF8 ist Pflicht: ohne den Parameter nutzt
    # PS 5.1 die System-ANSI-Codepage und verfaelscht Umlaute auf CP1252-Servern.
    $html = Get-Content $resolvedTemplatePath -Raw -Encoding UTF8
    
	# Text aus i18n holen
    $footerLabel = $I18n.Labels.FooterText
    
    $html = $html.Replace("{{FOOTER_TEXT}}", $footerLabel)
	
    # CSS einlesen (erwartet report.style.css im selben Ordner)
    $cssPath = Join-Path $templateDir "report.style.css"
    $cssContent = "/* CSS Datei nicht gefunden oder leer */"
    
    if (Test-Path $cssPath) {
        # -Encoding UTF8 zwingend: report.style.css hat kein BOM. Ohne den
        # Parameter landen auf CP1252-Servern verfaelschte Umlaute im Report
        # (sichtbar in den alten Sample-Reports: "gemÃ¤ÃŸ" statt "gemäß").
        $cssContent = Get-Content $cssPath -Raw -Encoding UTF8
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
		# S4: typbewusst statt ueber PowerShells Wahrheitswert-Umwandlung.
		# Vorher entschied hier `if ($dStats.RecycleBin)`: fuer die ZEICHENKETTE
		# "False" ist das $true, weil sie nicht leer ist -- die Uebersicht zeigte
		# dann "Aktiviert" in GRUEN, wo "Deaktiviert" in Rot stuende. Die Form
		# ist bewusst zeichengleich zu 01c6d2d (PWD-02) und 8382b6b
		# (Kennwortkomplexitaet im HTML): drei Stellen, die dasselbe
		# entscheiden, sollen nicht auf drei Arten entscheiden.
		$rbOn = if ($dStats.RecycleBin -is [string]) {
			-not ($dStats.RecycleBin.Trim() -in @("", "false", "0"))
		} else {
			[bool]$dStats.RecycleBin
		}
		# Dritter Zustand: seit S4 kann der Collector $null liefern, wenn sich
		# der Papierkorb-Status NICHT ERMITTELN liess. Ein rotes "Deaktiviert"
		# waere dort derselbe Falschbefund wie im Verdikt, nur in der Tabelle.
		# Dieselbe status-neutral-Pille wie bei KRBTGT und Kennwortkomplexitaet;
		# den Grund liefert der Nicht-ermittelbar-Abschnitt unter den
		# Empfehlungen (AD-03).
		$rbText  = if ($rbOn) { $I18n.Labels.Enabled } else { $I18n.Labels.Disabled }
		$rbClass = if ($rbOn) { "status-ok" }          else { "status-error" }
		$rbPill  = if ($null -eq $dStats.RecycleBin) {
			"<span class='status-pill status-neutral'>$($I18n.Labels.Unknown)</span>"
		} else {
			"<span class='status-pill $rbClass'>$rbText</span>"
		}
	
		# --- KRBTGT LOGIK ---
		# Vorher ein blosser Bindestrich, wenn KrbtgtLastSet fehlt -- neutral,
		# aber ohne erkennbaren Grund (Schlussprüfung W3: die Uebersichtszeile
		# "entfaellt" inhaltlich, auch wenn die Zelle nicht leer ist). Jetzt
		# dieselbe status-neutral-Pille wie beim dritten Zustand der
		# Kennwortkomplexitaet weiter unten; den Grund liefert der neue
		# Nicht-ermittelbar-Abschnitt unter den Empfehlungen (AD-04).
		$krbPill = "<span class='status-pill status-neutral'>$($I18n.Labels.Unknown)</span>"
		if ($dStats.KrbtgtLastSet) {
			$krbDate = $dStats.KrbtgtLastSet
			$daysOld = ((Get-Date) - $krbDate).Days
			$limit = if ($Settings.Thresholds.KrbtgtPasswordAgeDays) { $Settings.Thresholds.KrbtgtPasswordAgeDays } else { 180 }
			$krbClass = if ($daysOld -gt $limit) { "status-error" } else { "status-ok" }
			$krbDisplay = $krbDate.ToString("dd.MM.yyyy")
			$krbPill = "<span class='status-pill $krbClass' title='$($I18n.Labels.Age): $daysOld $($I18n.Labels.Days)'>$krbDisplay</span>"
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
        $inactiveLabel = if ($inactiveCount -eq 0) { $I18n.Labels.NoneFound } else { "$inactiveCount $($I18n.Labels.Users)" }

        # Pille für Deaktivierte Konten (Gelb wenn > 0)
        $disabledCount = [int]$secInfo.DisabledUsers
        $disabledStatusClass = if ($disabledCount -eq 0) { "status-ok" } else { "status-warn" }
        $disabledLabel = "$disabledCount $($I18n.Labels.Users)"

        # Pille für Passwortablauf (Rot/Grün)
        $noExpiryCount = [int]$secInfo.NoPwdExpiryUsers
        $noExpiryStatusClass = if ($noExpiryCount -eq 0) { "status-ok" } else { "status-error" }
        $noExpiryLabel = if ($noExpiryCount -eq 0) { $I18n.Labels.NoneFound } else { "$noExpiryCount $($I18n.Labels.Users)" }

        # Pille für Abgelaufene Kennwörter (Neu)
        $expiredCount = [int]$secInfo.ExpiredPwdUsers
        $expiredStatusClass = if ($expiredCount -eq 0) { "status-ok" } else { "status-error" }
        $expiredLabel = if ($expiredCount -eq 0) { "Alle aktuell" } else { "$expiredCount $($I18n.Labels.Users)" }

        # Schwellen fuer die drei privilegierten-Gruppen-Pillen: dieselbe Quelle
        # wie die Regeln SEC-04/05/06 (config/recommendations.json), Rueckfall
        # auf 5/2/1 (siehe Reporting.psm1 ~:1692-1694), falls der Katalog fehlt
        # oder eine Regel keinen Threshold traegt. Bewusst ein gezieltes,
        # einmaliges Lesen hier statt eines zweiten Katalog-Lade-Mechanismus —
        # Get-ADHCRecommendations laedt den Katalog erst spaeter (verschachtelt).
        $secDomAdminLimit = 5
        $secEntAdminLimit = 2
        $secSchAdminLimit = 1
        try {
            $secPillRecPath = Join-Path $PSScriptRoot "..\config\recommendations.json"
            if (Test-Path $secPillRecPath) {
                $secPillRecJson = Get-Content $secPillRecPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
                $secPillRule04 = $secPillRecJson.Security | Where-Object { $_.Id -eq "SEC-04" }
                $secPillRule05 = $secPillRecJson.Security | Where-Object { $_.Id -eq "SEC-05" }
                $secPillRule06 = $secPillRecJson.Security | Where-Object { $_.Id -eq "SEC-06" }
                if ($null -ne $secPillRule04.Threshold.value) { $secDomAdminLimit = [int]$secPillRule04.Threshold.value }
                if ($null -ne $secPillRule05.Threshold.value) { $secEntAdminLimit = [int]$secPillRule05.Threshold.value }
                if ($null -ne $secPillRule06.Threshold.value) { $secSchAdminLimit = [int]$secPillRule06.Threshold.value }
            }
        } catch {
            Write-ADHCLog "Threshold-Werte fuer Sicherheits-Pillen konnten nicht aus recommendations.json gelesen werden — Rueckfall auf 5/2/1: $($_.Exception.Message)" -Level Warning -Component "Reporting"
        }

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
					<td><span class='status-pill $(if($secInfo.DomAdminCount -le $secDomAdminLimit){"status-ok"}else{"status-error"})'>$($secInfo.DomAdminCount) $($I18n.Labels.Users)</span></td>
				</tr>
				<tr>
					<td>$($I18n.Labels.EntAdminName)</td>
					<td><span class='status-pill $(if($secInfo.EntAdminCount -le $secEntAdminLimit){"status-ok"}else{"status-error"})'>$($secInfo.EntAdminCount) $($I18n.Labels.Users)</span></td>
				</tr>
				<tr>
					<td>$($I18n.Labels.SchAdminName)</td>
					<td><span class='status-pill $(if($secInfo.SchAdminCount -le $secSchAdminLimit){"status-ok"}else{"status-error"})'>$($secInfo.SchAdminCount) $($I18n.Labels.Users)</span></td>
				</tr>
			</tbody>
		</table>"

        $htmlSec += "<br/>"
		
		# $null (nicht gelesen) muss sich vom echten Befund $false (deaktiviert)
		# unterscheiden -- sonst behauptet die Tabelle "Deaktiviert", wo PWD-02
		# im Upload-JSON bereits korrekt NOT_CHECKED meldet (Schlussprüfung W2).
		# Dritter Zustand ueber die BESTEHENDE status-neutral-Pille (Zeile ~138
		# in report.style.css, dort schon fuer "nicht ermittelbar" verwendet --
		# siehe Scavenging-Pille weiter unten). $true/$false bleiben unveraendert
		# reiner Text, wie zuvor.
		# Typbewusst statt ueber PowerShells Wahrheitswert-Umwandlung (S3).
		# Vorher entschied hier `elseif ($secInfo.Complexity)`: fuer die
		# ZEICHENKETTE "False" ist das $true, weil sie nicht leer ist -- die
		# Tabelle haette "Aktiviert" gezeigt, wo "Deaktiviert" steht. Heute
		# liefert der Collector ein [bool] (Diag.psm1, ComplexityEnabled aus
		# Get-ADDefaultDomainPasswordPolicy), die Falle ist also latent. Sie
		# bekommt trotzdem dieselbe Form wie der Auswerter-Zweig "Complexity"
		# (PWD-02, v2.10.1): zwei Stellen, die dasselbe entscheiden, sollen
		# nicht auf zwei Arten entscheiden.
		$complexityOn = if ($secInfo.Complexity -is [string]) {
			-not ($secInfo.Complexity.Trim() -in @("", "false", "0"))
		} else {
			[bool]$secInfo.Complexity
		}
		$complexityLabel = if ($null -eq $secInfo.Complexity) { "<span class='status-pill status-neutral'>$($I18n.Labels.Unknown)</span>" }
		                    elseif ($complexityOn)             { $I18n.Labels.Enabled }
		                    else                                { $I18n.Labels.Disabled }
		
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
		# U3/SEC-09: In der Pille NUR die aktionable Teilmenge zusaetzlich ausweisen
		# -- die Gesamtzahl bleibt unveraendert. Entscheidung (siehe u3-report.md):
		# zwei Zahlen sind in dieser Pille gewohnt (Gesamt + EINE Aufschluesselung),
		# drei koennen erschlagen. Von den drei Lagen (aktuell geschuetzt / ehemals
		# privilegiert / manuell abgeschaltet) braucht der Kunde auf einen Blick nur
		# die ehemals privilegierten Konten: das ist die Teilmenge, die SDProp nicht
		# mehr pflegt und die sich dauerhaft bereinigen liesse. "Aktuell geschuetzt"
		# ist erwarteter, unauffaelliger SDProp-Betrieb; "manuell abgeschaltet" bleibt
		# der urspruengliche B3-Befund und ergibt sich als Rest. Beide vollstaendigen
		# Zahlen stehen weiterhin in der Tabelle darunter (Spalte AdminSDHolder) und
		# im JSON-Detail (Description unten).
		$userFormerMemberCount = @($ouSec.DisabledInheritanceUser | Where-Object { $_.AdminSdHolder -eq $true -and $_.CurrentlyProtectedMember -eq $false }).Count
		$htmlOUSec += "<span class='status-pill $userColor'>$($I18n.Labels.ProtectedUsers): $($ouSec.DisabledInheritanceUser.Count) ($($I18n.Labels.OfWhichFormerMember): $userFormerMemberCount)</span>"
		$htmlOUSec += "</div>"
	
		# --- TABELLE 1: VERWAISTE SIDs (JETZT EXPLIZIT) ---
		if ($ouSec.UniqueOrphanCount -gt 0) {
			$htmlOUSec += "<div style='margin-top:20px;'><h3 style='border-left: 3px solid #004a87; padding-left: 10px;'>$($I18n.Labels.OrphanedSIDsDetailTitle)</h3>"
			
			# Wir bereiten die Daten für die SID-Tabelle auf
			$sidTableData = foreach ($group in $ouSec.TopOrphanedSIDs) {
				[PSCustomObject]@{ 
					SID       = $group.Name; 
					Anzahl    = $group.Count; 
					Empfehlung = $I18n.Labels.ReviewAndCleanup 
				}
			}
			
			# Rendern der SID Tabelle
			$htmlOUSec += New-HTMLTableWithPills -Data $sidTableData -Headers ([ordered]@{"SID"="SID"; "Anzahl"=$I18n.Labels.Occurrences; "Empfehlung"=$I18n.Labels.Recommendation})
			$htmlOUSec += "</div>"
		}
	
		# --- TABELLE 2: ORGANIZATIONAL UNITS ---
		if ($ouSec.DisabledInheritanceOU.Count -gt 0) {
			$htmlOUSec += "<div style='margin-top:20px;'><h3 style='border-left: 3px solid #004a87; padding-left: 10px;'>$($I18n.Labels.ProtectedOUs)</h3>"
			$ouData = foreach($ou in ($ouSec.DisabledInheritanceOU | Select-Object -First 50)) {
				[PSCustomObject]@{ "OU Name" = $ou.Name; "Distinguished Name (Pfad)" = $ou.DN; "Status" = $I18n.Labels.InheritanceDisabled }
			}
			$htmlOUSec += New-HTMLTableWithPills -Data $ouData -Headers ([ordered]@{"OU Name"="OU Name"; "Distinguished Name (Pfad)"=$I18n.Labels.DistinguishedNamePath; "Status"=$I18n.Labels.Status})
			$htmlOUSec += "</div>"
		}
	
		# --- TABELLE 3: BENUTZER ---
		if ($ouSec.DisabledInheritanceUser.Count -gt 0) {
			$htmlOUSec += "<div style='margin-top:20px;'><h3 style='border-left: 3px solid #004a87; padding-left: 10px;'>$($I18n.Labels.ProtectedUsers)</h3>"
			$userData = foreach($u in ($ouSec.DisabledInheritanceUser | Select-Object -First 50)) {
				# Markierung sprachneutral (Symbol statt Text) -- kein hartcodiertes
				# DE/EN-Wort, das im EN-Modus falsch waere.
				# U3/SEC-09: drei Lagen, drei Symbole -- "✓" (aktuell geschuetzt,
				# erwartet), "⚠" (ehemals privilegiert, bereinigbar), leer (manuell
				# abgeschaltet, kein adminCount).
				$adminSdHolderMark = if ($u.AdminSdHolder -ne $true) { "" }
					elseif ($u.CurrentlyProtectedMember -eq $false) { "⚠" }
					else { "✓" }
				[PSCustomObject]@{ "Benutzer" = $u.Name; "Distinguished Name (Pfad)" = $u.DN; "Status" = $I18n.Labels.InheritanceDisabled; "AdminSDHolder" = $adminSdHolderMark }
			}
			$htmlOUSec += New-HTMLTableWithPills -Data $userData -Headers ([ordered]@{"Benutzer"=$I18n.Labels.User; "Distinguished Name (Pfad)"=$I18n.Labels.DistinguishedNamePath; "Status"=$I18n.Labels.Status; "AdminSDHolder"=$I18n.Labels.OfWhichAdminSdHolder})
			$htmlOUSec += "</div>"
		}
	
		$htmlOUSec += "</div>"
	}

	# Scavenging-Pille je Zone. $null heisst "nicht ermittelbar" und wird auch so
	# angezeigt — nicht als "inaktiv". Genau diese Verwechslung war der Fehler.
	# Die automatischen Reverse-Systemzonen 0/127/255.in-addr.arpa koennen kein
	# Scavenging fuehren — sie werden als "nicht anwendbar" ausgewiesen und sind
	# bereits in der DNS-Erhebung aus der Bewertung ausgenommen.
	$scavPill = {
		param($zone, $I18n)
		$scavSystemZones = @('0.in-addr.arpa', '127.in-addr.arpa', '255.in-addr.arpa')
		if ($scavSystemZones -contains ("$($zone.ZoneName)").Trim().ToLower()) {
			return "<span class='status-pill status-neutral'>$($I18n.Labels.ScavengingNotApplicable)</span>"
		}
		if ($null -eq $zone.AgingEnabled) {
			return "<span class='status-pill status-neutral'>$($I18n.Labels.Unknown)</span>"
		}
		if ($zone.AgingEnabled) {
			$tip = ""
			if ($null -ne $zone.NoRefreshHours -and $null -ne $zone.RefreshHours) {
				$tip = " title='$($I18n.Labels.NoRefreshInterval): $($zone.NoRefreshHours) h / $($I18n.Labels.RefreshInterval): $($zone.RefreshHours) h'"
			}
			return "<span class='status-pill status-ok'${tip}>$($I18n.Labels.Active)</span>"
		}
		return "<span class='status-pill status-warning'>$($I18n.Labels.Inactive)</span>"
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
			# Zwei Ebenen: der serverweite Schalter und die Zonen. Ist der Schalter aus,
			# steht das zuerst — dann ist jede Zonenkonfiguration wirkungslos und eine
			# Zonenliste waere irrefuehrend.
			$srvScav      = $qc.ServerScavenging
			$unknownCount = @($qc.ScavengingUnknown).Count
			$measured     = if ($null -ne $qc.ScavengingMeasured) { [int]$qc.ScavengingMeasured } else { $effectiveTotalZones }

			if ($srvScav -and $srvScav.Enabled -eq $false) {
				$scavClass   = "status-error"
				$scavContent = $I18n.Labels.ScavengingServerDisabled
			} elseif ($missingScavCount -eq 0) {
				$scavClass   = "status-ok"
				$scavContent = $I18n.Labels.Active
			} else {
				$scavClass      = if ($measured -gt 0 -and $missingScavCount -ge $measured) { "status-error" } else { "status-warning" }
				$maxDisplay     = 2
				$displayedZones = $qc.MissingScavenging | Select-Object -First $maxDisplay
				$scavContent    = "$($I18n.Labels.Inactive): " + ($displayedZones -join ", ")
				if ($missingScavCount -gt $maxDisplay) {
					$remaining = $missingScavCount - $maxDisplay
					$scavContent += " (+ ${remaining})"
				}
			}

			# Fusszeile: nur zaehlen, was tatsaechlich gemessen wurde. Nicht ermittelbare
			# Zonen werden getrennt genannt statt stillschweigend mitgezaehlt.
			$scavFooter = $I18n.Labels.ScavengingCheckedIn -f $measured
			if ($unknownCount -gt 0) {
				$scavFooter += " &middot; " + ($I18n.Labels.ScavengingUnknownCount -f $unknownCount)
			}
			if ($srvScav -and $srvScav.Enabled -eq $true -and $null -ne $srvScav.IntervalHours) {
				$scavFooter += " &middot; " + ($I18n.Labels.ScavengingServerInterval -f $srvScav.IntervalHours)
			}

			$htmlDNS += "<div class='quick-info-box qbox-scavenging'>
							<div class='qbox-label'>Scavenging (Aging)</div>
							<div class='status-text ${scavClass}' style='font-size: 1.1rem; font-weight: 700;'>${scavContent}</div>
							<div style='font-size: 0.75rem; color: #888; margin-top: auto; padding-top: 10px;'>
								${scavFooter}
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
						<th>$($I18n.Labels.Status)</th><th>$($I18n.Labels.Replication)</th>
						<th>SCAVENGING</th><th>DNSSEC</th>
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
						<td>$($zone.ReplicationScope)</td>
						<td>$(& $scavPill $zone $I18n)</td><td>${secPill}</td></tr>"
		}
		$htmlDNS += "</tbody></table>"
	
		# --- TABELLE: REVERSE LOOKUP ZONEN ---
		$htmlDNS += "<h3 class='dns-table-header'>$($I18n.Labels.ReverseZones)</h3>"
		$htmlDNS += "<table class='styled-table'><thead><tr>
						<th>$($I18n.Labels.ZoneName)</th><th>$($I18n.Labels.Type)</th>
						<th>$($I18n.Labels.Status)</th><th>$($I18n.Labels.Replication)</th>
						<th>SCAVENGING</th><th>DNSSEC</th>
					</tr></thead><tbody>"
		if ($Data.DNS.ReverseZones.Count -eq 0) {
			$htmlDNS += "<tr><td colspan='6' style='text-align:center;'>$($I18n.Labels.NoZonesFound)</td></tr>"
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
							<td>$($zone.ReplicationScope)</td>
							<td>$(& $scavPill $zone $I18n)</td><td>${secPill}</td></tr>"
			}
		}
		$htmlDNS += "</tbody></table>"

		# --- INFO: TRUST ANCHORS ---
		# Bewusst ohne Bewertung: keine status-pill, keine Ampelfarbe, kein Eintrag in
		# den Empfehlungen. Die Zone "TrustAnchors" wird forestweit repliziert und nie
		# bereinigt — ihre Eintraege lassen sich nicht sinnvoll pruefen. Der Block
		# erscheint nur, wenn ueberhaupt etwas vorhanden ist.
		$ta = $Data.DNS.TrustAnchors
		if ($ta) {
			$taFacts = @()

			if ($ta.ZonePresent) {
				$taType = switch ($ta.ZoneType) {
					"Primary"   { $I18n.Labels.Primary }
					"Secondary" { $I18n.Labels.Secondary }
					"Stub"      { $I18n.Labels.Stub }
					Default     { $ta.ZoneType }
				}
				if ($ta.IsADIntegrated) { $taType = "${taType}, $($I18n.Labels.ADIntegrated)" }
				$scope = if ($ta.ReplicationScope) { ", $($ta.ReplicationScope)" } else { "" }
				$taFacts += "$($I18n.Labels.ZoneName) <b>$($ta.ZoneName)</b> (${taType}${scope})"
				$taFacts += ($I18n.Labels.TrustAnchorNSCount -f $ta.NSRecordCount)
			}

			if (@($ta.TrustPoints).Count -eq 0) {
				$taFacts += $I18n.Labels.NoTrustPoints
			} else {
				foreach ($tp in $ta.TrustPoints) {
					$taFacts += "$($I18n.Labels.TrustPoint) <b>$($tp.Name)</b> ($($tp.State), $($I18n.Labels.TrustAnchorCount -f $tp.AnchorCount))"
				}
			}

			$htmlDNS += "<h3 class='dns-table-header'>$($I18n.Labels.TrustAnchors)</h3>"
			$htmlDNS += "<div class='info-note'>
							<div>$($taFacts -join ' &middot; ')</div>
							<div class='info-note-hint'>$($I18n.Labels.TrustAnchorsNotChecked)</div>
						</div>"
		}

		$htmlDNS += "</div>"
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
		# -Now: Bezugszeitpunkt fuer alle Altersberechnungen. Wird von aussen
		# hineingegeben, damit ZWEI Aufrufe mit demselben $Data garantiert
		# dasselbe Ergebnis liefern — die Voraussetzung, auf der der
		# Zweisprachigkeits-Durchlauf (siehe Verdikt-Block) vollstaendig ruht.
		# Ohne das lieferten zwei Laeufe ueber Mitternacht verschiedene Werte.
		param($Data, $Settings, $I18n, $LangCode, [datetime]$Now = (Get-Date))
		
		$recPath = Join-Path $PSScriptRoot "..\config\recommendations.json"

		if (-not (Test-Path $recPath)) { return "" }
		
		try {
			$recJson = Get-Content $recPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
		} catch { return "" }
	
		$activeRecs = @()

		# Messwert-Stash: haelt je Regel-Id den gemessenen Wert fest — AUCH wenn die
		# Regel nicht feuert. Ohne das ist ein PASS im Upload-JSON nicht von einer
		# Pruefung zu unterscheiden, die gar nichts gemessen hat (beides ergab
		# ActualValue = null). Genau diese Verwechslung trat im Feldtest auf.
		$script:ADHCMeasurements = @{}
		function Set-ADHCMeasure {
			param([string]$Id, $ActualValue, $Unit, $ExpectedValue, $Operator, $AffectedItems, $AffectedValues)
			$script:ADHCMeasurements[$Id] = [PSCustomObject]@{
				ActualValue    = $ActualValue
				Unit           = $Unit
				ExpectedValue  = $ExpectedValue
				Operator       = $Operator
				AffectedItems  = if ($AffectedItems)  { @($AffectedItems) }  else { $null }
				# AffectedValues traegt das, was frueher als uebersetzter Zusatz
				# in AffectedItems stand: {item, value, unit} oder {item, hintKey}.
				AffectedValues = if ($AffectedValues) { @($AffectedValues) } else { $null }
			}
		}

		# Skip-Stash: haelt je Regel-Id fest, dass die Pruefung NICHT ANWENDBAR ist.
		# Das ist ausdruecklich weder PASS noch FAIL: eine Domaene mit nur einem
		# Domaenencontroller hat keine Replikation, die bestanden oder gerissen sein
		# koennte. Vorher fiel so eine Regel in den PASS-Zweig (weil sie nicht feuerte)
		# oder feuerte als FAIL (weil die Metadaten-Abfrage erwartungsgemaess scheiterte)
		# — beides behauptete etwas ueber einen nicht existierenden Sachverhalt.
		$script:ADHCSkipped = @{}
		function Set-ADHCSkip {
			param([string]$Id, [string]$Reason, [string[]]$AffectedItems, $AffectedValues)
			$script:ADHCSkipped[$Id] = [PSCustomObject]@{
				Reason         = $Reason
				AffectedItems  = if ($AffectedItems)  { [string[]]@($AffectedItems) } else { $null }
				AffectedValues = if ($AffectedValues) { @($AffectedValues) }          else { $null }
			}
		}

		# Undetermined-Stash: haelt je Regel-Id fest, dass sich der Wert NICHT
		# ERMITTELN liess (fehlendes Attribut, fehlgeschlagene Abfrage) — anders
		# als beim Skip-Stash geht es hier NICHT um "trifft nicht zu", sondern um
		# "wir wissen es schlicht nicht". Ohne diesen Stash fiel so ein Fall
		# bisher an vier Stellen im Code auf den PASS-Zweig zurueck: eine
		# geschoente Anzeige, bei der niemand nachsieht (docs/OFFENE-PUNKTE.md,
		# Teil 3). Der Reset-Punkt bleibt bewusst neben den beiden Stashes oben —
		# der Zweisprachigkeits-Durchlauf ruft Get-ADHCRecommendations DREIMAL
		# auf, ein abweichender Reset wuerde Werte ueber die Aufrufe hinweg
		# mitschleppen.
		$script:ADHCUndetermined = @{}
		function Set-ADHCUndetermined {
			# AffectedItems/AffectedValues additiv (T2, nach dem Vorbild von
			# Set-ADHCSkip) — DCDIAG-Befunde sind listenartig (mehrere Tests,
			# mehrere Server), der bisherige skalare Reason konnte das nicht
			# abbilden. Bestehende Aufrufe ohne die neuen Parameter (Krbtgt,
			# Kennwortkomplexitaet) laufen unveraendert weiter.
			param([string]$Id, [string]$Reason, [string[]]$AffectedItems, $AffectedValues)
			$script:ADHCUndetermined[$Id] = [PSCustomObject]@{
				Reason         = $Reason
				AffectedItems  = if ($AffectedItems)  { [string[]]@($AffectedItems) } else { $null }
				AffectedValues = if ($AffectedValues) { @($AffectedValues) }          else { $null }
			}
		}

		# Anzeige-Titel je Regel: bevorzugt den kuratierten, EINDEUTIGEN Title{de,en}
		# (v2.4.1), faellt auf die (gruppierende, ggf. mehrfach genutzte) SubCategory
		# zurueck, wenn keine Title vorhanden ist. Analog zum M365-Dashboard.
		function Get-ADHCDisplayTitle {
			param($Rule, [string]$Lang)
			$t = $Rule.Title
			if ($t) {
				$val = if ($t -is [string]) { $t } else { $t.$Lang }
				if ([string]::IsNullOrWhiteSpace($val) -and $t -isnot [string]) {
					$val = if ($Lang -eq 'de') { $t.en } else { $t.de }
				}
				if (-not [string]::IsNullOrWhiteSpace($val)) { return $val }
			}
			if ($Rule.SubCategory -is [string]) { return $Rule.SubCategory }
			return $Rule.SubCategory.$Lang
		}

		# Category ist seit dem Katalog-Update ein {de,en}-Objekt. Der Rueckfall
		# auf den String haelt eine aeltere config/recommendations.json am Laufen.
		function Get-ADHCCategoryText {
			param($Category, [string]$Lang)
			if ($null -eq $Category) { return "" }
			if ($Category -is [string]) { return $Category }
			$val = $Category.$Lang
			if ([string]::IsNullOrWhiteSpace($val)) { $val = if ($Lang -eq 'de') { $Category.en } else { $Category.de } }
			return $val
		}

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
			$krbtgtDays   = $null
			# Schwelle aus settings.json — wie es die Kachel-Anzeige oben bereits tut.
			# Vorher stand hier fest 180, wodurch Anzeige und Regel auseinanderliefen,
			# sobald ein Kunde KrbtgtPasswordAgeDays anpasste.
			$krbtgtLimit = if ($Settings.Thresholds.KrbtgtPasswordAgeDays) {
				[int]$Settings.Thresholds.KrbtgtPasswordAgeDays
			} else { 180 }
			if ($stats.KrbtgtLastSet) {
				# Wir berechnen das Alter in Tagen
				$krbtgtDays = ($Now - $stats.KrbtgtLastSet).Days
				if ($krbtgtDays -gt $krbtgtLimit) { $krbtgtStatus = "Expired" }
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
	
				# Messwert festhalten — auch wenn die Regel nicht feuert.
				# Bei KRBTGT ist der aussagekraeftige Wert das ALTER in Tagen, nicht
				# der abgeleitete Status "OK"/"Expired": ein 9 Jahre altes Kennwort und
				# ein 181 Tage altes liefern denselben Status, aber sehr
				# unterschiedlichen Handlungsdruck.
				switch ($rule.Property) {
					"KrbtgtStatus" {
						Set-ADHCMeasure -Id $rule.Id -ActualValue $krbtgtDays -Unit "Days" `
							-ExpectedValue $krbtgtLimit -Operator "lte"
						# Fehlt KrbtgtLastSet (fehlendes Leserecht, Fehler in der Abfrage),
						# bleibt $krbtgtStatus auf "OK" — das behauptete bisher stillschweigend
						# ein gutes Kennwortalter, das nie gemessen wurde (docs/OFFENE-PUNKTE.md,
						# Teil 3, AD-04). Jetzt wird die Regel stattdessen als NICHT ERMITTELBAR
						# gemeldet, statt als bestanden durchzugehen.
						if (-not $stats.KrbtgtLastSet) {
							Set-ADHCUndetermined -Id $rule.Id -Reason $I18n.Labels.ReasonKrbtgtUnknown
						}
					}
					"ForestLevel" {
						Set-ADHCMeasure -Id $rule.Id -ActualValue ([int]$val) -Unit $null -ExpectedValue 7 -Operator "gte"
					}
					"DomainLevel" {
						Set-ADHCMeasure -Id $rule.Id -ActualValue ([int]$val) -Unit $null -ExpectedValue 7 -Operator "gte"
					}
					"RecycleBin" {
						# S4: der Papierkorb kennt seit dieser Charge DREI Zustaende.
						# $null heisst "liess sich nicht ermitteln" (Diag.psm1: die
						# Abfrage von Get-ADOptionalFeature ist fehlgeschlagen) und ist
						# NICHT dasselbe wie "aus". Vorher startete der Collector auf
						# $false; eine fehlgeschlagene Abfrage erzeugte damit einen
						# Falschbefund der Prioritaet High -- genau das Muster, das
						# 2cdff84 fuer AD-04 und PWD-02 behoben hat und bei AD-03
						# uebersehen wurde.
						#
						# Der Messwert bleibt in diesem Fall AUS: ein NOT_CHECKED traegt
						# keinen Messwert, sonst behauptete er eine Messung, die es nie
						# gab (CLAUDE.md). ([bool]$null) haette hier $false geliefert --
						# also ausgerechnet "Papierkorb ist aus".
						if ($null -eq $val) {
							Set-ADHCUndetermined -Id $rule.Id -Reason $I18n.Labels.ReasonRecycleBinUnknown
						} else {
							# Typbewusst wie die Anzeige oben und wie der Zweig
							# "Complexity": ([bool]"False") ist $true, der Messwert haette
							# dem eigenen FAIL widersprochen ("Befund: Ja, Soll: Ja").
							$rbMeasured = if ($val -is [string]) {
								-not ($val.Trim() -in @("", "false", "0"))
							} else {
								[bool]$val
							}
							Set-ADHCMeasure -Id $rule.Id -ActualValue $rbMeasured -Unit $null -ExpectedValue $true -Operator "eq"
						}
					}
					Default {
						Set-ADHCMeasure -Id $rule.Id -ActualValue $val -Unit $null -ExpectedValue $null -Operator $null
					}
				}

				# Vergleich
				$conditions = $rule.Condition | ForEach-Object { [string]$_ }
				if ($conditions -contains [string]$val) {
					$areaLabel = Get-ADHCDisplayTitle -Rule $rule -Lang $LangCode
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

				# Messwert AUCH beim Bestehen -- Vorbild SITE-05 (OFFENE-PUNKTE 1.1).
				# Nur gesetzt, wenn $roleData ueberhaupt existiert: fehlt die Rolle in
				# $Data.FSMO, wurde nichts gemessen, und ein Messwert waere erfunden.
				#
				# P57/P5b: Der Messwert haengt an "OK", das Feuern unten an
				# $rule.Condition (heute ["Error"]). Zwei Quellen fuer dieselbe
				# Aussage. Sie sind heute deckungsgleich -- Get-ADFSMORoles
				# schreibt genau zwei Werte (Diag.psm1:847: "OK" bzw. "Error"),
				# und der Mock ebenso (Diag.psm1:40-44). Kaeme ein dritter Wert
				# hinzu, feuerte die Regel nicht (PASS), waehrend der Messwert
				# ActualValue=$false, ExpectedValue=$true auswiese: ein Messwert,
				# der dem eigenen Verdikt widerspricht -- genau der Fehler, den
				# X4/E1 bei AD-FSMO-08 beseitigt hat.
				# Darum die Wache: gemessen wird nur, was eine der beiden Quellen
				# KENNT. Ein unbekannter dritter Wert bekommt gar keinen Messwert
				# statt eines falschen. Das Feuerverhalten bleibt unberuehrt --
				# die Bedingung unten liest weiterhin allein $rule.Condition.
				$fsmoStatus = [string]$roleData.Erreichbar
				if ($roleData -and ($fsmoStatus -eq "OK" -or $rule.Condition -contains $fsmoStatus)) {
					Set-ADHCMeasure -Id $rule.Id -ActualValue ($fsmoStatus -eq "OK") `
						-Unit $null -ExpectedValue $true -Operator "eq"
				}

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
			# Messwert: "sind Schema- und Naming-Master konsolidiert (derselbe
			# Inhaber)?" -- $true ist der erwuenschte Zustand, ExpectedValue $true.
			# Nur gemessen, wenn beide Inhaber bekannt sind -- dieselbe Bedingung,
			# unter der die Regel ueberhaupt feuern kann.
			if ($schemaOwner -and $namingOwner) {
				$rule06 = $recJson.FSMO | Where-Object { $_.Id -eq "AD-FSMO-06" }
				Set-ADHCMeasure -Id $rule06.Id -ActualValue ($schemaOwner -eq $namingOwner) `
					-Unit $null -ExpectedValue $true -Operator "eq"
			}
			if ($schemaOwner -and $namingOwner -and ($schemaOwner -ne $namingOwner)) {
				$rule = $recJson.FSMO | Where-Object { $_.Id -eq "AD-FSMO-06" }
				$areaLabel = Get-ADHCDisplayTitle -Rule $rule -Lang $LangCode
				$activeRecs += [PSCustomObject]@{
					Id = $rule.Id; Category = $rule.Category; Area = $areaLabel
					Description = $rule.Recommendation.$LangCode; Priority = $rule.Priority
				}
			}
		
			# AD-FSMO-07: Gesamte Rollenkonzentration (nur in Single-Domain-Gesamtstrukturen
			# sinnvoll -- U3). Vorher feuerte die Regel bei jeder Verteilung auf mehrere
			# DCs, unabhaengig von der Domaenenzahl; in einer Gesamtstruktur mit mehreren
			# Domaenen ist die Verteilung normal (PDC/RID/Infra je Domaene), der Katalogtext
			# nannte diese Luecke bereits, ohne sie zu schliessen.
			$rule = $recJson.FSMO | Where-Object { $_.Id -eq "AD-FSMO-07" }
			$domainCount = $stats.DomainCount
			if ($null -eq $domainCount) {
				# Domaenenzahl nicht ermittelbar (DomainStats nicht gelaufen oder
				# Get-ADForest.Domains nicht auslesbar) -- NICHT still "eine Domaene"
				# annehmen und NICHT fälschlich feuern lassen (Teil-3-Konvention).
				# KEIN Set-ADHCMeasure hier: NOT_CHECKED darf keinen Messwert
				# tragen, der eine Messung behauptet, die nicht stattfand.
				Set-ADHCUndetermined -Id $rule.Id -Reason $I18n.Labels.ReasonDomainCountUnknown
			} else {
				# Messwert: Zahl der VERSCHIEDENEN Rolleninhaber. Eine Zahl statt
				# eines bool, weil das die tatsaechlich ausgewertete Groesse ist --
				# der bool "gefeuert/nicht gefeuert" haengt zusaetzlich von
				# $domainCount ab und waere fuer sich allein irrefuehrend. Ein
				# Schwellenwert (ExpectedValue/Operator) wird NUR in der
				# Single-Domain-Gesamtstruktur gesetzt, denn nur dort gilt "1
				# Inhaber" als Sollwert -- in einer Multi-Domain-Gesamtstruktur ist
				# Verteilung normal, ein Schwellenwert waere dort erfunden.
				if ($domainCount -eq 1) {
					Set-ADHCMeasure -Id $rule.Id -ActualValue $allOwners.Count `
						-Unit $null -ExpectedValue 1 -Operator "eq"
				} else {
					Set-ADHCMeasure -Id $rule.Id -ActualValue $allOwners.Count `
						-Unit $null -ExpectedValue $null -Operator $null
				}
			}
			if ($domainCount -eq 1 -and $allOwners.Count -gt 1) {
				$areaLabel = Get-ADHCDisplayTitle -Rule $rule -Lang $LangCode
				$activeRecs += [PSCustomObject]@{
					Id = $rule.Id; Category = $rule.Category; Area = $areaLabel
					Description = $rule.Recommendation.$LangCode; Priority = $rule.Priority
				}
			}
			# $domainCount -gt 1: Verteilung ist in einer Multi-Domain-Gesamtstruktur
			# normal -- die Regel feuert bewusst nicht (Kernzweck von U3).
		
			# AD-FSMO-08: Infrastructure Master vs. Global Catalog (Die "Phantom-Objekt" Regel)
			# Wir suchen den Infrastructure-Owner in der Discovery-Liste, um seinen GC-Status zu prüfen
			# IsGC steht NICHT in $Data.Discovery — dieses Objekt fuehrt nur
			# Server, OS, IPv4, UptimeHrs, FreeDiskGB, FreeDiskPct, Status.
			# Die GC-Eigenschaft liefert Get-ADSitesInfo unter
			# $Data.Sites.Sites[].Servers[].IsGC. Vorher wurde $infraDC.IsGC
			# aus Discovery gelesen und war immer $null, wodurch AD-FSMO-08
			# nie feuern konnte.
			$siteServers = @($Data.Sites.Sites | ForEach-Object { $_.Servers })
			$infraSrv = $siteServers | Where-Object { $_.Name -and $infraOwner -like "*$($_.Name)*" } | Select-Object -First 1
			$isGC = ($infraSrv.IsGC -eq $true -or $infraSrv.IsGC -eq "True")

			# Messwert: "ist der Infrastructure-Master-Inhaber ein Global Catalog?"
			# -- die Eigenschaft, die dieser Regel ihren Namen gibt. RecycleBin
			# (AD-03) und dcs.Count (Anwendbarkeits-Wache bei nur einem DC) werden
			# an anderer Stelle bzw. gar nicht separat gemessen; $isGC ist der Teil,
			# den nur diese Regel auswertet. Nur gesetzt, wenn $infraSrv gefunden
			# wurde: fehlt der Server in der Site-Liste, ist $isGC ungeprueft
			# $false (kein Treffer der Vergleiche oben) -- kein erfundener Messwert.
			# X4/E1: KEIN ExpectedValue/Operator mehr. Vorher stand hier
			# ExpectedValue $false -- das behauptete einen Sollwert, den die Regel
			# gar nicht hat: sie feuert nur bei dcs.Count > 1 UND RecycleBin =
			# $false UND isGC. Mit aktiviertem Papierkorb (der EMPFOHLENEN
			# Einstellung) oder bei nur einem Domaenencontroller ist isGC = $true
			# voellig in Ordnung; im Export stand dann trotzdem
			# "PASS, Befund: Ja, Soll: Nein" -- ein Messwert, der dem eigenen
			# Verdikt widerspricht. Ein reiner Ist-Wert ohne Sollwert ist die
			# ehrliche Form; dasselbe Mittel nutzt AD-FSMO-07 bereits im
			# Mehrdomaenenfall (oben). Die volle Regelbedingung zu messen waere
			# die Alternative gewesen -- sie haette den Messwert aber von der
			# Eigenschaft, die der Regel ihren Namen gibt, auf ein
			# "gefeuert ja/nein" verkuerzt, das der Status ohnehin schon sagt.
			$rule08 = $recJson.FSMO | Where-Object { $_.Id -eq "AD-FSMO-08" }

			# S4: diese Regel liest denselben Papierkorb-Wert wie AD-03 und ist
			# gegen ein $null nicht von sich aus sicher -- `$null -eq $false` ist
			# $false, die Bedingung unten wird also STILL falsch und die Regel
			# ginge als PASS durch, obwohl genau der Wert fehlt, der sie
			# entscheidet.
			#
			# Nicht ermittelbar gemeldet wird sie darum GENAU dann, wenn der
			# Papierkorb den Ausschlag gibt: mehrere Domaenencontroller UND der
			# Infrastructure Master ist Global Catalog. Bei nur einem DC oder
			# wenn der Inhaber kein GC ist, steht das Ergebnis auch ohne den
			# Papierkorb-Wert fest (die Regel kann gar nicht feuern) -- dort
			# waere ein NOT_CHECKED eine erfundene Wissensluecke.
			$rb08Unbekannt = ($dcs.Count -gt 1 -and $null -eq $stats.RecycleBin -and $isGC)

			# Messwert nur, wenn die Regel auch ein Verdikt traegt: ein
			# NOT_CHECKED traegt keinen Messwert (CLAUDE.md), auch wenn $isGC
			# hier fuer sich genommen ermittelt ist.
			if ($infraSrv -and -not $rb08Unbekannt) {
				Set-ADHCMeasure -Id $rule08.Id -ActualValue $isGC -Unit $null -ExpectedValue $null -Operator $null
			}
			if ($rb08Unbekannt) {
				Set-ADHCUndetermined -Id $rule08.Id -Reason $I18n.Labels.ReasonFsmoRecycleBinUnknown
			}

			if ($dcs.Count -gt 1 -and $stats.RecycleBin -eq $false -and $isGC) {
				$rule = $recJson.FSMO | Where-Object { $_.Id -eq "AD-FSMO-08" }
				$areaLabel = Get-ADHCDisplayTitle -Rule $rule -Lang $LangCode
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
				$failedServers  = @()
				# T2: sammelt Server, deren Testergebnis "Unknown" blieb — der
				# Parser initialisiert JEDEN der 21 Tests darauf (Diag.psm1:588)
				# und schreibt sonst nur "OK"/"Error". "Unknown" steht in
				# KEINER der 18 Conditions, ein solcher Test bestand also
				# bisher stillschweigend.
				# P57/P5a: hier landet seitdem JEDER unverwertbare Wert, nicht
				# nur der Wortlaut "Unknown" -- auch ein leeres oder fehlendes
				# Testfeld und ein unbekannter dritter Wert.
				$unknownServers = @()
				$testProp = $rule.Property

				# P57/P5a: Server mit BESTANDENEM Test werden direkt gezaehlt statt
				# hinterher von der Gesamtzahl abgezogen. Der Unterschied betrifft
				# Werte, die WEDER in einer Condition stehen NOCH "Unknown" sind:
				# ein Eintrag ohne das Testfeld (dann ist $dcEntry.$testProp $null
				# und [string]$null der leere String) oder ein dritter, unbekannter
				# Wert. Die Subtraktion zaehlte beides stillschweigend als
				# bestanden -- "1 von 1 Servern bestanden" auf einer Spalte, die es
				# gar nicht gibt. Verwertbar ist allein "OK": das ist der einzige
				# Nicht-Fehler-Wert, den der Parser erzeugt (Diag.psm1:647/847 und
				# die Vorbelegung Diag.psm1:633/681). Alles andere ist unbestimmt
				# und faellt damit in denselben Zweig wie "Unknown" -- also in den
				# SkipReason unten (U2) und in die X4-Wache, die auf einem
				# NOT_CHECKED keinen Messwert stehen laesst.
				#
				# Heutige Wirkung: keine. Die beiden einzigen Erzeuger von
				# $Data.DCDiag legen jede der 21 Spalten an (Diag.psm1:681 bzw. der
				# Mock ab Diag.psm1:53), und die 21 Regel-Properties decken sich
				# genau mit dieser Liste. Der Gewinn ist Robustheit gegen fremde
				# oder unvollstaendige Daten, kein heutiger Fehler.
				$passedServers = 0
				foreach ($dcEntry in $Data.DCDiag) {
					$status = [string]$dcEntry.$testProp

					# Wenn der Status in den Fehler-Conditions der JSON enthalten ist
					if ($rule.Condition -contains $status) {
						$failedServers += $dcEntry.Server
					}
					elseif ($status -eq "OK") {
						$passedServers++
					}
					else {
						$unknownServers += $dcEntry.Server
					}
				}

				# Messwert AUCH beim Bestehen -- Vorbild SITE-05 (OFFENE-PUNKTE 1.1).
				# ActualValue = Zahl der DCs mit BESTANDENEM Test (weder Fehler
				# noch Unknown); ExpectedValue = Gesamtzahl der DCs in den Daten.
				# Bewusst die Gesamtzahl und NICHT nur die DCs mit verwertbarem
				# Ergebnis: "2 von 2 Servern bestanden" bleibt eine einfache,
				# stabile Aussage unabhaengig davon, ob ein Server dabei war,
				# dessen Ergebnis unbestimmt blieb -- die Unbestimmtheit selbst
				# steht bereits separat im SkipReason (siehe U2 unten). Ein
				# Unknown-Server zaehlt hier NICHT als bestanden (Rangfolge aus
				# Nachtrag U2 bleibt unberuehrt), senkt also ActualValue, ohne
				# ExpectedValue zu veraendern.
				#
				# X4/E2: Der Messwert steht NICHT mehr auf einem NOT_CHECKED.
				# Sind ALLE Server "Unknown" (und feuert die Regel deshalb nicht),
				# wird das Verdikt unten NOT_CHECKED -- ein Messwert
				# "0 von 1 Servern bestanden" behauptete dort eine Messung, die
				# gerade nicht zustande kam. Dieselbe Wache haelt AD-FSMO-07
				# (oben) schon seit X1 ein, und OS-01 tut es seit X4 ebenso.
				# Feuert die Regel dagegen (failedServers > 0), gewinnt FAIL in
				# der Statusherleitung -- dann ist der Messwert erwuenscht und
				# bleibt erhalten, auch wenn nebenher ein Server unbestimmt war.
				$totalServers  = @($Data.DCDiag).Count
				if ($unknownServers.Count -eq 0 -or $failedServers.Count -gt 0) {
					Set-ADHCMeasure -Id $rule.Id -ActualValue $passedServers -Unit "Servers" `
						-ExpectedValue $totalServers -Operator "eq"
				}

				# Falls Server gefunden wurden, erstelle EINE gruppierte Empfehlung
				if ($failedServers.Count -gt 0) {
					$serverList = $failedServers -join ", "
					$areaLabel = Get-ADHCDisplayTitle -Rule $rule -Lang $LangCode
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $rule.Category
						Area        = $areaLabel
						# Wir hängen die Serverliste an die Beschreibung an
						AffectedItems = @($failedServers)
						Description = "$($rule.Recommendation.$LangCode) ($($I18n.Labels.AffectedServers): $serverList)"
						Priority    = $rule.Priority
					}
				}
				# U2: additiv statt "elseif" -- nach dem Vorbild von OS-01
				# (Reporting.psm1 ~1350). Vorher galt Rangfolge per Ausschluss:
				# feuerte die Regel oben als FAIL, blieb dieser Zweig aus, und
				# ein zweiter Server mit "Unknown" verschwand spurlos aus dem
				# Bericht -- der Vertrag (docs/DASHBOARD-VERTRAG-v4.md) kennt
				# aber keinen Grund, warum SkipReason bei FAIL leer bleiben
				# sollte. Der $Status bleibt trotzdem FAIL (Statusherleitung,
				# Reporting.psm1 ~2522, prueft $firedIds weiterhin VOR
				# $undetermined) -- es geht nur darum, dass die Unbestimmtheit
				# des zweiten Servers zusaetzlich zum Befund erhalten bleibt.
				if ($unknownServers.Count -gt 0) {
					# V2/Punkt 4: Kappung auf 50, analog zu DisabledInheritanceUser
					# (Reporting.psm1, Select-Object -First 50) -- Einheitlichkeit mit
					# den bestehenden Kappungen. Die Gesamtzahl geht dabei NICHT
					# verloren: Set-ADHCUndetermined kennt kein ActualValue (anders
					# als Set-ADHCMeasure), deshalb steht sie -- wie schon beim
					# AdminSDHolder-Block oben -- in der Reason-Zeile, ueber das
					# bereits vorhandene CurrentValue-Label statt eines neuen.
					$unknownServersCapped = @($unknownServers | Select-Object -First 50)
					$unknownReason = "$($I18n.Labels.ReasonDcdiagUnknown) ($($I18n.Labels.AffectedServers): $($unknownServersCapped -join ', '))"
					if ($unknownServers.Count -gt 50) {
						$unknownReason += " ($($I18n.Labels.CurrentValue): $($unknownServers.Count))"
					}
					Set-ADHCUndetermined -Id $rule.Id `
						-Reason $unknownReason `
						-AffectedItems $unknownServersCapped
				}
			}
		}

		# --- PRÜFUNG: DC SYSTEMSTATUS (DCSystem) ---
		if ($Settings.ShowRecommendations.DCSystem -and $Data.Discovery) {
			Write-ADHCLog "Analysiere DCSystem (Lokalisiert & Fehlerbereinigt)..." -Component "Reporting"
			
			# T2: 2003/2008/2008 R2 ergaenzt (alle OutOfSupport) und 2025
			# (Supported) — vorher begann die Tabelle bei 2012, wodurch
			# GENAU die aeltesten (und damit dringendsten) Systeme unsichtbar
			# blieben. Daten je Microsoft-Lifecycle-Seite (Mainstream-/
			# Extended-Ende, siehe Bericht fuer die einzelnen Quellen-URLs).
			# "2008 R2" MUSS vor "2008" stehen: $srv.OS "Windows Server 2008
			# R2" matcht -like "*2008*" ebenso wie -like "*2008 R2*" — ohne
			# den nach Schluessellaenge sortierten Abgleich unten waere das
			# Ergebnis von der (nicht garantierten) Hashtable-Aufzaehlreihenfolge
			# abhaengig.
			$osLifecycle = @{
				"2003"    = @{ Main = "14.07.2010"; Ext = "15.07.2015"; Status = "OutOfSupport" }
				"2008 R2" = @{ Main = "14.01.2015"; Ext = "15.01.2020"; Status = "OutOfSupport" }
				"2008"    = @{ Main = "14.01.2015"; Ext = "15.01.2020"; Status = "OutOfSupport" }
				"2012"    = @{ Main = "10.10.2018"; Ext = "10.10.2023"; Status = "OutOfSupport" }
				"2016"    = @{ Main = "11.01.2022"; Ext = "12.01.2027"; Status = "OutOfMainstream" }
				"2019"    = @{ Main = "09.01.2024"; Ext = "09.01.2029"; Status = "OutOfMainstream" }
				"2022"    = @{ Main = "13.10.2026"; Ext = "14.10.2031"; Status = "Supported" }
				"2025"    = @{ Main = "14.11.2029"; Ext = "15.11.2034"; Status = "Supported" }
			}
		
			$rules = if ($recJson.DCSystem) { $recJson.DCSystem } else { $recJson.Discovery }
		
			foreach ($rule in $rules) {
				$failedServers = @()
				$infoSuffix = ""
				# ZWEI Listen mit Absicht: $failedServers geht ins Upload-JSON und
				# enthaelt nur Bezeichner; $displayServers traegt die heutigen
				# Texte und speist den Befundsatz im Bericht. Vorher tat eine
				# Liste beides — deshalb liessen sich die uebersetzten Zusaetze
				# nicht entfernen, ohne den Kundenbericht zu veraendern.
				$displayServers = @()
				# Messwert je Bezeichner. Nicht jeder Eintrag hat einen — OS-01
				# und SRV-02 liefern nur den Namen.
				$failedValues   = @()
				# T2: Server, deren Betriebssystem in $osLifecycle KEINEN
				# Eintrag findet — nicht ermittelbar, nicht "in Ordnung".
				# Ohne diesen Zweig wiederholt sich die Luecke mit jeder
				# neuen Windows-Version von selbst. Zwei Listen aus demselben
				# Grund wie $failedServers/$displayServers oben: AffectedItems
				# bleibt reiner Bezeichner, der Reason-Text nennt zusaetzlich
				# das unbekannte Betriebssystem.
				$undeterminedOsServers = @()
				$undeterminedOsDisplay = @()

				foreach ($srv in $Data.Discovery) {

					# FALL 1: OS Lifecycle (OS-01)
					if ($rule.Property -eq "OSSupportStatus") {
						# Laengster Schluessel zuerst ("2008 R2" vor "2008"):
						# $osLifecycle.Keys | Where-Object liefert bei mehreren
						# Treffern ein ARRAY, und $osLifecycle[<Array>] wird
						# dabei stillschweigend zu $null — die Regel haette
						# dann nie gefeuert, ohne dass ein Fehler auftritt.
						$yearMatch = $osLifecycle.Keys |
							Where-Object { $srv.OS -like "*$_*" } |
							Sort-Object -Property Length -Descending |
							Select-Object -First 1
						if ($yearMatch) {
							$lifecycle = $osLifecycle[$yearMatch]
							if ($rule.Condition -contains $lifecycle.Status) {
								$failedServers += $srv.Server
								$displayServers += $srv.Server
								# LOKALISIERUNG: Wir nutzen Keys aus der i18n für 'Mainstream Ende' etc.
								$infoSuffix = " [$($I18n.Labels.MainstreamEnd): $($lifecycle.Main) | $($I18n.Labels.ExtendedUntil): $($lifecycle.Ext)]"
							}
						} else {
							$undeterminedOsServers += $srv.Server
							$undeterminedOsDisplay += "$($srv.Server) ($($srv.OS))"
						}
					}

					# FALL 2: Festplattenplatz (SRV-01)
					elseif ($rule.Property -eq "DiskSpace") {
						if ($rule.Condition -contains $srv.Status -and $srv.OS -ne "Unreachable") {
							# AffectedItems traegt nur noch den Bezeichner. Der
							# Messwert und seine Einheit wandern nach AffectedValues,
							# damit ein Konsument sie in eigener Sprache darstellen
							# kann — frueher stand hier "SRVDC01 (12 frei)".
							$failedServers  += $srv.Server
							# $displayServers behaelt genau diesen Text, damit der
							# Befundsatz im Bericht unveraendert bleibt.
							$displayServers += "$($srv.Server) ($($srv.FreeDiskPct) $($I18n.Labels.FreeDisk))"
							# AffectedValues.value muss eine ECHTE Zahl sein, kein
							# formatierter Text — sonst muesste ein Konsument die
							# Zeichenkette selbst zerlegen, was das Feld gerade
							# ersparen soll. $srv.FreeDiskPct ist "2 %" (Diag.psm1:536),
							# die Zahl wird hier separat herausgezogen. Schlaegt das
							# fehl, ist $null ("nicht ermittelbar") richtig — NICHT 0
							# ("0 % frei" haette eine andere Bedeutung: Platte voll).
							$freeDiskPctValue = $null
							if ($srv.FreeDiskPct -match '^\s*(-?\d+(?:[.,]\d+)?)') {
								$freeDiskPctValue = [double]($matches[1] -replace ',', '.')
							}
							$failedValues   += [PSCustomObject]@{
								item  = $srv.Server
								value = $freeDiskPctValue
								unit  = "Percent"
							}
						}
					}

					# FALL 3: Erreichbarkeit (SRV-02)
					elseif ($rule.Property -eq "Status" -and $srv.OS -eq "Unreachable") {
						if ($rule.Condition -contains $srv.Status) {
							$failedServers += $srv.Server
							$displayServers += $srv.Server
						}
					}
				}

				# Messwert AUCH beim Bestehen -- Vorbild SITE-05/DCDIAG (X2,
				# OFFENE-PUNKTE-PASS-BELEGE 1.1). Muss VOR der Feuer-Entscheidung stehen.
				switch ($rule.Property) {
					"OSSupportStatus" {
						# Wie beim DCDIAG-Block oben: ExpectedValue bleibt die
						# GESAMTZAHL der Server, ActualValue sinkt sowohl durch
						# echte Befunde ($failedServers) als auch durch Server mit
						# unbestimmbarem Betriebssystem ($undeterminedOsServers) --
						# ein unbekanntes OS zaehlt nicht als "im Support bestaetigt".
							#
							# X4/D1: ... aber NICHT auf einem NOT_CHECKED. Blieb das
							# Betriebssystem eines Servers unbestimmt und feuerte die
							# Regel nicht, wird das Verdikt unten NOT_CHECKED --
							# "0 von 1 bestaetigt" behauptete dort eine Messung, die
							# gerade nicht zustande kam. Der Undetermined-ZWEIG setzte
							# schon vorher keinen Messwert; der Blockmesswert feuerte
							# trotzdem, und der bewachende Test hiess "OHNE Messwert",
							# pruefte im Rumpf aber ActualValue = 0. Gleiche Wache und
							# gleiche Begruendung wie bei DCDIAG (E2, oben): feuert die
							# Regel, gewinnt FAIL -- dann bleibt der Messwert.
							$osTotal  = @($Data.Discovery).Count
							$osPassed = $osTotal - $failedServers.Count - $undeterminedOsServers.Count
							if ($undeterminedOsServers.Count -eq 0 -or $failedServers.Count -gt 0) {
								Set-ADHCMeasure -Id $rule.Id -ActualValue $osPassed -Unit "Servers" `
									-ExpectedValue $osTotal -Operator "eq"
							}
					}
					"DiskSpace" {
						# Niedrigster freier Anteil ueber alle ERREICHBAREN Server --
						# nicht erreichbare gehoeren zu SRV-02 und liefern "-" statt
						# einer Zahl (FreeDiskPct ist eine Zeichenkette, siehe FALL 2
						# oben). Derselbe Umwandlungsweg wie dort, damit ein
						# ActualValue niemals eine Zeichenkette wird.
						$reachablePct = @()
						foreach ($srv in $Data.Discovery) {
							if ($srv.OS -eq "Unreachable") { continue }
							if ($srv.FreeDiskPct -match '^\s*(-?\d+(?:[.,]\d+)?)') {
								$reachablePct += [double]($matches[1] -replace ',', '.')
							}
						}
						$minPct = if ($reachablePct.Count -gt 0) { ($reachablePct | Measure-Object -Minimum).Minimum } else { $null }
						Set-ADHCMeasure -Id $rule.Id -ActualValue $minPct -Unit "Percent"
					}
					"Status" {
						# SRV-02: Zahl der erreichbaren gegen die Gesamtzahl der DCs.
						$totalServers = @($Data.Discovery).Count
						$unreachable  = @($Data.Discovery | Where-Object { $_.OS -eq "Unreachable" }).Count
						Set-ADHCMeasure -Id $rule.Id -ActualValue ($totalServers - $unreachable) -Unit "Servers" `
							-ExpectedValue $totalServers -Operator "eq"
					}
				}

				if ($failedServers.Count -gt 0) {
					# Anzeige-Titel: kuratiertes Title{de,en} bevorzugt, sonst SubCategory
					$localizedArea = Get-ADHCDisplayTitle -Rule $rule -Lang $LangCode

					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $rule.Category
						Area        = $localizedArea
						AffectedItems = @($failedServers)
						AffectedValues = if ($failedValues.Count -gt 0) { @($failedValues) } else { $null }
						Description = "$($rule.Recommendation.$LangCode)$($infoSuffix) (Server: $($displayServers -join ', '))"
						Priority    = $rule.Priority
					}
				}
				# Nur fuer OS-01 relevant (die anderen DCSystem-Regeln fuellen
				# $undeterminedOsServers nie). Rangfolge wie bei DCDIAG: ein
				# echter Befund (oben, FAIL) hat Vorrang — dieser Zweig laueft
				# additiv daneben, nicht statt dessen, weil ein unbekanntes
				# Betriebssystem auf einem ANDEREN Server nichts an einem
				# echten Befund auf diesem Server aendert.
				if ($rule.Property -eq "OSSupportStatus" -and $undeterminedOsServers.Count -gt 0) {
					# V2/Punkt 4: gleiche Kappung wie beim DCDIAG-Zweig oben (50,
					# Gesamtzahl ueber CurrentValue in der Reason-Zeile). $undeterminedOsDisplay
					# entsteht 1:1 im selben Schleifendurchlauf wie $undeterminedOsServers
					# (oben, "$server ($OS)" je Eintrag) -- Select-Object -First 50 haelt
					# die Reihenfolge, die Kappung bleibt also paarweise ausgerichtet.
					$undeterminedOsServersCapped = @($undeterminedOsServers | Select-Object -First 50)
					$undeterminedOsDisplayCapped = @($undeterminedOsDisplay | Select-Object -First 50)
					$osUnknownReason = "$($I18n.Labels.ReasonOsUnknown) ($($undeterminedOsDisplayCapped -join ', '))"
					if ($undeterminedOsServers.Count -gt 50) {
						$osUnknownReason += " ($($I18n.Labels.CurrentValue): $($undeterminedOsServers.Count))"
					}
					Set-ADHCUndetermined -Id $rule.Id `
						-Reason $osUnknownReason `
						-AffectedItems $undeterminedOsServersCapped
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
				# Siehe Grundmuster oben: zwei Listen, weil AffectedItems bisher
				# zugleich Datenfeld und Textbaustein war.
				$displayPartitions = @()
				$failedPartValues  = @()

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

						# In AffectedItems steht nur noch die Partition; das Alter
						# wandert als Stundenwert nach AffectedValues.
						# value = $null bedeutet "Sicherungszeitpunkt nicht
						# ermittelbar" — genau der Fall, den BK-02 meldet.
						$failedPartitions  += $b.Partition
						# $displayPartitions traegt den heutigen Text weiter, damit
						# der Befundsatz im Bericht unveraendert bleibt.
						$displayPartitions += "$($b.Partition) ($timeString)"
						$failedPartValues  += [PSCustomObject]@{
							item  = $b.Partition
							value = if ($b.LastBackup) { [int]$b.Days * 24 + [int]$b.Hours } else { $null }
							unit  = "Hours"
						}
					}
				}

				# Messwert AUCH beim Bestehen -- Vorbild SITE-05/DCDIAG (X2,
				# OFFENE-PUNKTE-PASS-BELEGE 1.1). Muss VOR der Feuer-Entscheidung stehen.
				# Alter der AELTESTEN Sicherung in Stunden, dieselbe Einheit wie im
				# Feuer-Fall oben. Partitionen ohne ermittelbares Datum bleiben beim
				# Skalar aussen vor: ihr Alter ist nicht "gross", sondern schlicht
				# UNBEKANNT -- 0 waere falsch (Sicherung "gerade eben"), ein
				# Hoechstwert waere geraten. Bleibt dadurch nichts uebrig (alle
				# Partitionen ohne Datum), ist auch der Skalar nicht ermittelbar:
				# $null statt einer erfundenen Zahl.
				#
				# X4/D2 -- Richtigstellung der X2-Begruendung: Dort stand, eine
				# Partition ohne Datum koenne im PASS-Zweig ohnehin nicht
				# auftreten, weil "Error" in der Condition stehe. Das gilt NUR
				# fuer BK-02 (Condition: Critical, Error). BK-01s Condition ist
				# "Warning" allein -- eine undatierte Partition laesst BK-01
				# also sehr wohl bestehen, und der Skalar stammt dann aus einer
				# ANDEREN Partition. Ebenso kann eine Partition mit Status
				# "Critical" den Skalar stellen, waehrend BK-01 besteht.
				#
				# Die Form bleibt trotzdem so, und zwar bewusst: Der Skalar ist
				# hier eine BLOCK-Groesse ("Alter der aeltesten datierten
				# Sicherung"), keine Wiederholung des Regelverdikts. Genau aus
				# dieser Groesse leitet Get-ADBackupStatus (Diag.psm1) den
				# Status jeder Partition ab, den beide Regeln bewerten -- der
				# Messwert ist damit die Datengrundlage des Verdikts, nicht sein
				# Echo. Er kann dem Verdikt auch nicht widersprechen: BK-01 und
				# BK-02 haben keinen Threshold im Katalog, es steht also kein
				# Sollwert daneben, gegen den sich der Istwert lesen liesse.
				# Und die partitionsgenaue Wahrheit -- inklusive "Datum nicht
				# ermittelbar" als value = null -- steht vollstaendig in
				# AffectedValues direkt darunter.
				$datedPartitions = @($Data.Backup | Where-Object { $_.LastBackup })
				$maxAgeHours = if ($datedPartitions.Count -gt 0) {
					($datedPartitions | ForEach-Object { [int]$_.Days * 24 + [int]$_.Hours } | Measure-Object -Maximum).Maximum
				} else { $null }
				# AffectedValues je Partition zusaetzlich zum Skalar: eine einzelne
				# Zahl sagt nur "aelteste Sicherung X Stunden", die Liste sagt es je
				# Partition -- und der Feuer-Zweig oben baut dieselbe Form ohnehin
				# schon, das Nachziehen hier kostet nichts extra (X2-Auftrag,
				# Entscheidung: beides setzen statt nur eines der beiden).
				$allPartValues = @($Data.Backup | ForEach-Object {
					[PSCustomObject]@{
						item  = $_.Partition
						value = if ($_.LastBackup) { [int]$_.Days * 24 + [int]$_.Hours } else { $null }
						unit  = "Hours"
					}
				})
				Set-ADHCMeasure -Id $rule.Id -ActualValue $maxAgeHours -Unit "Hours" -AffectedValues $allPartValues

				if ($failedPartitions.Count -gt 0) {
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $rule.Category
						Area        = $I18n.Labels.BackupStatus
						# Die detaillierte Zeit-Information wird an den Beschreibungstext angehängt
						AffectedItems = @($failedPartitions)
						AffectedValues = if ($failedPartValues.Count -gt 0) { @($failedPartValues) } else { $null }
						Description = "$($rule.Recommendation.$LangCode) ($($I18n.Labels.Partitions): $($displayPartitions -join '; '))"
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
				# DC-Zahl fuer den Messwert unten: Zahl der EINTRAEGE fuer diesen
				# Dienst (nicht aller Server) -- $Data.Services ist eine flache Liste
				# mit einem Eintrag je Dienst je DC, siehe Kommentar unten.
				$svcTotal = 0
				$svcOk    = 0

				# $Data.Services ist eine FLACHE Liste — siehe Get-ADServiceStatus:
				#   @{ Server; Service; Status; StartType }
				# Frueher wurde hier $srvEntry.Details mit .ServiceName/.ShortName
				# erwartet. Diese Felder liefert weder der Collector noch die
				# Mock-Daten, wodurch $svc immer $null war und KEINE der vier
				# SVC-Regeln jemals feuerte — auch nicht bei gestopptem NTDS.
				foreach ($svc in $Data.Services) {
					if ($svc.Service -ne $serviceName) { continue }
					$svcTotal++

					$startMode = [string]$svc.StartType
					# Status-Fehler laut Condition der Regel (Error/Warning/Manual/Disabled)
					$isNotRunning = ($rule.Condition -contains $svc.Status) -or
					                ($svc.Status -ne "OK" -and $svc.Status -ne "Running")
					# Starttyp muss Automatic sein; leerer Wert wird nicht bemaengelt
					$isNotAuto = ($startMode -and $startMode -ne "Auto" -and $startMode -ne "Automatic")

					if ($isNotRunning -or $isNotAuto) {
						$failedServers += "$($svc.Server) ($($svc.Status) / $startMode)"
					} else {
						$svcOk++
					}
				}

				# Messwert AUCH beim Bestehen -- Vorbild SITE-05/DCDIAG (X2,
				# OFFENE-PUNKTE-PASS-BELEGE 1.1). Muss VOR der Feuer-Entscheidung
				# stehen. ExpectedValue ist bewusst $svcTotal (Eintraege fuer DIESEN
				# Dienst), NICHT die Gesamtzahl aller Server -- ein Dienst, der auf
				# einem Server nie erhoben wurde, hat dafuer auch keinen Eintrag.
				#
				# X4/D3: Gibt es fuer diesen Dienst GAR KEINEN Eintrag, wird auch
				# nichts behauptet. "0 von 0 Servern" belegt nichts -- vorher sagte
				# $null das ehrlich, seit X2 stand dort ein Zaehlerpaar, das wie
				# eine Messung aussah. Es ist derselbe Fehler in klein, den diese
				# Charge behebt.
				if ($svcTotal -gt 0) {
					Set-ADHCMeasure -Id $rule.Id -ActualValue $svcOk -Unit "Servers" `
						-ExpectedValue $svcTotal -Operator "eq"
				}

				if ($failedServers.Count -gt 0) {
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $rule.Category
						Area        = "$($serviceName.ToUpper())"
						AffectedItems = @($failedServers)
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
				# Siehe Grundmuster oben: zwei Listen.
				$displayItems   = @()
				$affectedValues = @()
				# Ob eine Regel feuert, darf NICHT laenger allein an der Laenge von
				# $affectedItems haengen: SITE-05 hat keine betroffenen Objekte,
				# sondern die ABWESENHEIT welcher. Bisher stand deshalb ein
				# uebersetzter Platzhalter in der Liste, nur damit sie nicht leer
				# blieb. Faellt der weg, ohne dass diese Bedingung existiert,
				# verstummt SITE-05 lautlos — wie SITE-03, SVC-*, AD-FSMO-08 und
				# PWD-04 es in diesem Projekt bereits getan haben.
				$ruleFired      = $false
				$siteActual     = $null
				$siteUnit       = $null
				# X3: Sollwert/Operator waren bislang fest an $rule.Threshold
				# gebunden -- das reicht nur fuer SITE-01 (15/lte). SITE-02 und
				# SITE-04 sind Zaehlerstaende ohne Katalog-Schwellenwert; ihr
				# "0/lte" gehoert deshalb in den jeweiligen Zweig, nicht in den
				# Katalog (dort waere es eine Konfigurationsoption, die niemand
				# je aendern soll). Vorbelegung aus dem Katalog, damit SITE-01
				# und SITE-05 sich unveraendert verhalten.
				$siteExpected   = $rule.Threshold.value
				$siteOperator   = $rule.Threshold.operator

				switch ($rule.Property) {
					"ReplicationInterval" {
						foreach ($link in $Data.Sites.Transports) {
							# "Default" bedeutet NICHT "nicht ermittelbar": Ohne
							# ausdruecklich gesetztes Intervall repliziert AD mit dem
							# eingebauten Standard von 180 Minuten (Microsoft-Doku zu
							# replInterval bei siteLink-Objekten) — das Zwoelffache der
							# empfohlenen 15 Minuten. Bisher wurde dieser Fall komplett
							# uebersprungen; T5 wertet ihn ausdruecklich als 180.
							$istStandard = ($link.ReplInterval -eq "Default")
							$effektivesIntervall = if ($istStandard) { 180 } else { [int]$link.ReplInterval }

							# Prüfung gegen 15 Min (Microsoft Empfehlung)
							if ($effektivesIntervall -gt 15) {
								# "min" war hier fest verdrahtet — sprachneutral zwar,
								# aber trotzdem eine Einheit im Bezeichner. Sie gehoert
								# nach AffectedValues, damit ein Konsument sie in
								# eigenem Format darstellen kann.
								$affectedItems += $link.Name
								if ($istStandard) {
									# Muss erkennbar bleiben, dass der AD-Standard greift
									# und nicht jemand 180 eingetragen hat.
									$displayItems += "$($link.Name) ($effektivesIntervall min, $($I18n.Labels.ADDefaultInterval))"
								} else {
									$displayItems += "$($link.Name) ($effektivesIntervall min)"
								}
								# hintKey nur ergaenzen, wenn der Standard gilt — die
								# bestehende Form {item,value,unit} bleibt fuer den
								# expliziten Fall unveraendert (kein neues null-Feld).
								if ($istStandard) {
									$affectedValues += [PSCustomObject]@{
										item    = $link.Name
										value   = $effektivesIntervall
										unit    = "Minutes"
										hintKey = "ADDefaultInterval"
									}
								} else {
									$affectedValues += [PSCustomObject]@{
										item  = $link.Name
										value = $effektivesIntervall
										unit  = "Minutes"
									}
								}
								$ruleFired = $true
							}
						}

						# Messwert AUCH beim Bestehen (X3, OFFENE-PUNKTE-PASS-BELEGE 1.1).
						# HOECHSTES Intervall ueber alle Links -- das ist die Groesse,
						# gegen die die Regel oben entscheidet: bleibt der schlechteste
						# Link unter 15 Minuten, bleiben es alle. "Default" MUSS dabei
						# als 180 eingehen (gleiche Umrechnung wie oben), sonst
						# behauptet der Messwert ein besseres Intervall, als tatsaechlich
						# gilt. Ohne Links wird nichts gemessen: dann bleibt $siteActual
						# $null und es wird kein Messwert gesetzt.
						# Damit verschwindet zugleich die in DASHBOARD-VERTRAG-v4.md
						# beschriebene SITE-01-Eigenheit "Unit ohne ActualValue".
						$intervals = @($Data.Sites.Transports | ForEach-Object {
							if ($_.ReplInterval -eq "Default") { 180 } else { [int]$_.ReplInterval }
						})
						if ($intervals.Count -gt 0) {
							$siteActual = [int]($intervals | Measure-Object -Maximum).Maximum
							$siteUnit   = "Minutes"
						}
					}
					# Fuer SITE-03 existierte bisher KEIN case — die Regel stand in
					# recommendations.json, wurde aber nirgends ausgewertet und meldete
					# daher immer PASS. Get-ADSitesInfo liefert das Feld seit jeher
					# (ChangeNotification = options -band 1).
					"ChangeNotification" {
						foreach ($link in $Data.Sites.Transports) {
							if ($link.ChangeNotification -eq "Disabled") {
								$affectedItems += $link.Name
								$displayItems += $affectedItems[-1]
							}
						}

						# Messwert AUCH beim Bestehen (X4). SITE-03 blieb bei X3
						# als einzige Sites-Regel ohne Beleg zurueck -- ein PASS
						# sagte nicht, ob ueberhaupt Site-Links geprueft wurden.
						# Gezaehlt wird GENAU die Liste, die die Regel oben
						# aufbaut. Ohne Site-Links wurde nichts geprueft, dann
						# bleibt der Messwert leer.
						if (@($Data.Sites.Transports).Count -gt 0) {
							$siteActual   = [int]$affectedItems.Count
							$siteUnit     = "SiteLinks"
							$siteExpected = 0
							$siteOperator = "lte"
						}
					}
					"SubnetsWithoutSite" {
						foreach ($sub in $Data.Sites.Subnets) {
							if ($sub.Site -eq "-") {
								$affectedItems += $sub.Name
								$displayItems += $affectedItems[-1]
							}
						}
						# Messwert AUCH beim Bestehen (X3): "0 Subnetze ohne Standort"
						# ist der Nachweis, dass gezaehlt wurde. Der Zaehler ist genau
						# die Liste, die die Regel oben aufbaut -- eine zweite
						# Zaehlschleife koennte auseinanderlaufen.
						# Nur, wenn es ueberhaupt Subnetze gibt: ohne Subnetze ist
						# "0 nicht zugewiesen" keine Messung, sondern die Abwesenheit
						# von Daten -- diesen Sachverhalt meldet SITE-05.
						if (@($Data.Sites.Subnets).Count -gt 0) {
							$siteActual   = [int]$affectedItems.Count
							$siteUnit     = "Subnets"
							$siteExpected = 0
							$siteOperator = "lte"
						}
					}
					"SitesWithoutGC" {
					foreach ($site in $Data.Sites.Sites) {
						# T6: Standorte OHNE Domaenencontroller gehoeren nicht mehr
						# hierher — dafuer gibt es seit T6 die eigene Regel
						# "SitesWithoutServers" (SITE-06). SITE-04 bleibt beim
						# Konfigurationsfehler: Standort HAT DCs, keiner ist GC.
						if ($site.Servers.Count -eq 0) { continue }

						# Prüfen, ob ein Server in der Site die GC-Rolle hat
						$hasGC = $site.Servers | Where-Object { $_.IsGC -eq $true -or $_.IsGC -eq "True" }

						if (-not $hasGC) {
							# hintKey bleibt bestehen, obwohl die Regel-Id die Lage
							# jetzt auch schon eindeutig macht — ein Konsument, der
							# nur AffectedValues liest, soll den Grund weiterhin
							# ohne Blick auf die Id ablesen koennen.
							$affectedItems  += $site.Name
							$displayItems   += "$($site.Name) ($($I18n.Labels.NoGCConfigured))"
							$affectedValues += [PSCustomObject]@{ item = $site.Name; hintKey = "NoGCConfigured" }
							$ruleFired = $true
						}
					}

					# Messwert AUCH beim Bestehen (X3). Der Zaehler zaehlt DIESELBE
					# Menge, die die Regel prueft: nur Standorte, die ueberhaupt
					# Domaenencontroller haben (seit T6 gehoeren Standorte ohne
					# Server zu SITE-06). Bezugsmenge deshalb ebenfalls nur diese
					# Standorte -- gibt es keinen davon, wurde nichts geprueft und
					# es wird kein Messwert gesetzt.
					$sitesWithServers = @($Data.Sites.Sites | Where-Object { $_.Servers.Count -gt 0 })
					if ($sitesWithServers.Count -gt 0) {
						$siteActual   = [int]$affectedItems.Count
						$siteUnit     = "Sites"
						$siteExpected = 0
						$siteOperator = "lte"
					}
				}
					"SitesWithoutServers" {
					# T6: der bislang harmlose Zweig von SITE-04 — Standort ganz
					# ohne Domaenencontroller. Meist eine gewollte Aussenstelle,
					# daher eigene (niedrigere) Prioritaet statt Medium wie beim
					# echten Konfigurationsfehler in SITE-04.
					foreach ($site in $Data.Sites.Sites) {
						if ($site.Servers.Count -eq 0) {
							$affectedItems  += $site.Name
							$displayItems   += "$($site.Name) ($($I18n.Labels.NoServersPresent))"
							$affectedValues += [PSCustomObject]@{ item = $site.Name; hintKey = "NoServersPresent" }
							$ruleFired = $true
						}
					}

					# Messwert AUCH beim Bestehen (X4). Bezugsmenge sind hier ALLE
					# Standorte -- anders als bei SITE-04, das nur Standorte mit
					# Domaenencontrollern prueft: SITE-06 fragt ja gerade, ob es
					# Standorte ohne welche gibt. Ohne Standorte wurde nichts
					# geprueft, dann bleibt der Messwert leer.
					if (@($Data.Sites.Sites).Count -gt 0) {
						$siteActual   = [int]$affectedItems.Count
						$siteUnit     = "Sites"
						$siteExpected = 0
						$siteOperator = "lte"
					}
				}

					"NoSubnetsDefined" {
						$subnetCount = @($Data.Sites.Subnets).Count
						# Messwert statt Platzhalter: "0 Subnetze" ist derselbe
						# Sachverhalt, aber sprachneutral UND ueber die Zeit
						# vergleichbar. AffectedItems bleibt leer — es gibt keine
						# betroffenen Objekte, das ist ja gerade der Befund.
						$siteActual = $subnetCount
						$siteUnit   = "Subnets"
						if ($subnetCount -eq 0) {
							$ruleFired = $true
							# Fuer den BEFUNDSATZ bleibt der lesbare Text noetig:
							# ohne ihn endete der Satz auf "(Details: )" mit leeren
							# Klammern, weil er aus der Liste gebaut wird.
							$displayItems += $I18n.Labels.NoSubnetsDefined
						}
					}
				}

				# Ein Messwert wird AUCH beim Bestehen festgehalten — sonst ist ein
				# PASS nicht von einer Pruefung zu unterscheiden, die nichts
				# gemessen hat (OFFENE-PUNKTE 1.1).
				if ($null -ne $siteActual) {
					Set-ADHCMeasure -Id $rule.Id -ActualValue $siteActual -Unit $siteUnit `
						-ExpectedValue $siteExpected -Operator $siteOperator
				}

				if ($ruleFired -or $affectedItems.Count -gt 0) {
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $rule.Category
						Area        = $I18n.Labels.SitesServices
						AffectedItems = @($affectedItems)
						AffectedValues = if ($affectedValues.Count -gt 0) { @($affectedValues) } else { $null }
						ActualValue    = $siteActual
						Unit           = $siteUnit
						Description    = if ($displayItems) { "$($rule.Recommendation.$LangCode) (Details: $($displayItems -join ', '))" } else { $rule.Recommendation.$LangCode }
						Priority    = $rule.Priority
					}
				}
			}
		}
	
		# --- PRÜFUNG: REPLIKATIONS-LATENZ (Replication) ---
		if ($Settings.ShowRecommendations.Replication -and $Data.Replication) {
			Write-ADHCLog "Analysiere Replikations-Latenz..." -Component "Reporting"

			# Eintraege mit Status "NotApplicable" sind keine Messwerte, sondern die
			# Feststellung, dass es nichts zu messen gibt (einziger DC / kein
			# Replikationspartner). Sie duerfen weder in die Latenzberechnung noch in
			# die Zaehlung nicht erreichbarer DCs einfliessen.
			$replApplicable = @($Data.Replication | Where-Object { $_.Status -ne "NotApplicable" })
			$replSkipped    = @($Data.Replication | Where-Object { $_.Status -eq "NotApplicable" })

			foreach ($rule in $recJson.Replication) {
				$affectedItems = @()
				$worstLatency  = $null
				# Siehe Grundmuster oben: zwei Listen.
				$displayItems   = @()
				$affectedValues = @()

				# Bleibt nach dem Herausfiltern nichts uebrig, ist die REGEL nicht
				# anwendbar — nicht bestanden. Kein Messwert, kein Finding, sondern
				# ein ausgewiesenes "uebersprungen".
				if ($replApplicable.Count -eq 0 -and $replSkipped.Count -gt 0) {
					$skipReasons = @($replSkipped | ForEach-Object {
						$hint = if ($_.HintKey -and $I18n.Labels.$($_.HintKey)) { $I18n.Labels.$($_.HintKey) } else { $I18n.Labels.ReplicationNotApplicable }
						"$($_.Server) — $hint"
					})
					Set-ADHCSkip -Id $rule.Id -Reason $I18n.Labels.ReplicationNotApplicable -AffectedItems $skipReasons
					Write-ADHCLog "$($rule.Id) uebersprungen: keine Replikationspartner vorhanden." -Component "Reporting"
					continue
				}

				# Messwert ueber ALLE Partnerschaften — auch die unauffaelligen.
				# Damit belegt ein PASS, dass tatsaechlich gemessen wurde.
				if ($rule.Id -eq "REP-01") {
					# Der STATUS entsteht in Diag.psm1:1252 aus
					# Settings.Thresholds.ReplicationLatencyMaxMinutes. Der Sollwert im
					# Verdikt muss aus derselben Quelle kommen, sonst nennt der Bericht
					# eine Grenze, gegen die nicht gemessen wurde. Der Katalogwert
					# bleibt als Rueckfall — analog zu $krbtgtLimit (:923).
					$replLimit = if ($Settings.Thresholds.ReplicationLatencyMaxMinutes) {
						[int]$Settings.Thresholds.ReplicationLatencyMaxMinutes
					} else { $rule.Threshold.value }
					$measured = $replApplicable | Where-Object { $null -ne $_.LatencyMinutes }
					$maxAll   = if ($measured) { ($measured | Measure-Object -Property LatencyMinutes -Maximum).Maximum } else { $null }
					Set-ADHCMeasure -Id $rule.Id -ActualValue $(if ($null -ne $maxAll) { [int]$maxAll } else { $null }) `
						-Unit $rule.Threshold.unit -ExpectedValue $replLimit -Operator $rule.Threshold.operator
				} else {
					# REP-02: kein eigener Schwellenwert im Katalog (Threshold.value ist
					# leer) — $replLimit bleibt hier bewusst $null, das ist heutiges
					# Verhalten.
					$replLimit = $rule.Threshold.value
					# REP-02: Anzahl nicht abrufbarer DCs — 0 ist der Nachweis "alle erreicht"
					$unreach = @($replApplicable | Where-Object { $_.Status -eq "Unreachable" })
					Set-ADHCMeasure -Id $rule.Id -ActualValue $unreach.Count -Unit "Servers" -ExpectedValue 0 -Operator "lte"
				}

				foreach ($r in $replApplicable) {
					if ($rule.Condition -notcontains $r.Status) { continue }
					# Der schlechteste Wert ist der aussagekraeftigste Einzelmesswert
					if ($null -ne $r.LatencyMinutes -and ($null -eq $worstLatency -or $r.LatencyMinutes -gt $worstLatency)) {
						$worstLatency = [int]$r.LatencyMinutes
					}
					if ($r.Status -eq "Unreachable") {
						# REP-02: nicht pruefbar — Grund statt Messwert ausweisen
						$eintrag = "$($r.Server)$(if ($r.Reason) { " ($($r.Reason))" })"
						$affectedItems += $eintrag
						$displayItems  += $eintrag
					} else {
						$detailTxt = if ($null -ne $r.LatencyMinutes) {
							"$($r.LatencyMinutes) $($I18n.Labels.Minutes)"
						} else { $r.Status }
						# Bezeichner ist die Partnerschaft; die Latenz wandert als
						# Zahl nach AffectedValues. Ist sie nicht ermittelbar,
						# traegt hintKey $r.Status UNGEPRUEFT — das ist hier kein
						# Zufallstreffer, sondern durch die Schleifenbedingung
						# erzwungen: "if ($rule.Condition -notcontains $r.Status)
						# { continue }" (oben) laesst nur Eintraege durch, deren
						# Status in $rule.Condition steht. Im Replication-Katalog
						# gibt es nur REP-01 (Condition = ["Error"]) und REP-02
						# (Condition = ["Unreachable"]) — und REP-02 geht ohnehin
						# in den Unreachable-Zweig oben, erreicht diesen Code also
						# nie. $r.Status kann an dieser Stelle folglich nur
						# "Error" sein, und $I18n.Labels.Error existiert in BEIDEN
						# Sprachtabellen (i18n.de.json/i18n.en.json). Eine
						# Rueckfall-Pruefung waere hier eine Absicherung gegen
						# einen Fall, der mit dem heutigen Katalog nicht
						# eintreten kann — kaeme eine dritte Replication-Regel mit
						# einer anderen Condition hinzu, muesste dieser Kommentar
						# neu geprueft werden.
						$paar = "$($r.Server) -> $($r.Partner)"
						$affectedItems  += $paar
						$displayItems   += "$paar ($detailTxt)"
						$affectedValues += if ($null -ne $r.LatencyMinutes) {
							[PSCustomObject]@{ item = $paar; value = [int]$r.LatencyMinutes; unit = "Minutes" }
						} else {
							[PSCustomObject]@{ item = $paar; hintKey = $r.Status }
						}
					}
				}

				if ($affectedItems.Count -gt 0) {
					$activeRecs += [PSCustomObject]@{
						Id            = $rule.Id
						Category      = $rule.Category
						Area          = Get-ADHCDisplayTitle -Rule $rule -Lang $LangCode
						ActualValue   = $worstLatency
						Unit          = $rule.Threshold.unit
						ExpectedValue = $replLimit
						Operator      = $rule.Threshold.operator
						AffectedItems = @($affectedItems)
						AffectedValues = if ($affectedValues.Count -gt 0) { @($affectedValues) } else { $null }
						Description   = "$($rule.Recommendation.$LangCode) ($($I18n.Labels.AffectedServers): $($displayItems -join ', '))"
						Priority      = $rule.Priority
					}
				}
			}
		}

		# --- PRÜFUNG: EREIGNISPROTOKOLL-VORHALTEDAUER (EventLog) ---
		if ($Settings.ShowRecommendations.EventLog -and $Data.EventLog) {
			Write-ADHCLog "Analysiere Vorhaltedauer der Ereignisprotokolle..." -Component "Reporting"

			foreach ($rule in $recJson.EventLog) {
				$affectedItems = @()
				$worstDays     = $null
				# Siehe Grundmuster oben: zwei Listen.
				$displayItems   = @()
				$affectedValues = @()

				# Messwert ueber ALLE gelesenen Logs — die KUERZESTE Vorhaltedauer ist
				# der kritischste Wert und belegt zugleich, dass gemessen wurde.
				if ($rule.Id -eq "EVT-01") {
					# Wie oben bei REP-01: der Status kommt aus Diag.psm1:1371 ueber
					# Settings.Thresholds.MaxEventLogAgeDays. Der Sollwert im Verdikt
					# muss aus derselben Quelle kommen. Der Katalogwert bleibt als
					# Rueckfall — analog zu $krbtgtLimit (:923).
					$evtLimit = if ($Settings.Thresholds.MaxEventLogAgeDays) {
						[int]$Settings.Thresholds.MaxEventLogAgeDays
					} else { $rule.Threshold.value }
					$readable = $Data.EventLog | Where-Object { $null -ne $_.RetentionDays }
					$minAll   = if ($readable) { ($readable | Measure-Object -Property RetentionDays -Minimum).Minimum } else { $null }
					Set-ADHCMeasure -Id $rule.Id -ActualValue $(if ($null -ne $minAll) { [int]$minAll } else { $null }) `
						-Unit $rule.Threshold.unit -ExpectedValue $evtLimit -Operator $rule.Threshold.operator
				} else {
					# EVT-02: kein eigener Schwellenwert im Katalog (Threshold.value ist
					# leer) — $evtLimit bleibt hier bewusst $null, das ist heutiges
					# Verhalten.
					$evtLimit = $rule.Threshold.value
					# EVT-02: Anzahl nicht lesbarer Logs — 0 belegt "alle gelesen"
					$unreach = @($Data.EventLog | Where-Object { $_.Status -eq "Unreachable" })
					Set-ADHCMeasure -Id $rule.Id -ActualValue $unreach.Count -Unit "Logs" -ExpectedValue 0 -Operator "lte"
				}

				foreach ($e in $Data.EventLog) {
					if ($rule.Condition -notcontains $e.Status) { continue }
					# Kuerzeste Vorhaltedauer ist der kritischste Wert
					if ($null -ne $e.RetentionDays -and ($null -eq $worstDays -or $e.RetentionDays -lt $worstDays)) {
						$worstDays = [int]$e.RetentionDays
					}
					if ($e.Status -eq "Unreachable") {
						# EVT-02: nicht pruefbar — Grund statt Messwert ausweisen.
						# Der Hinweis kommt als i18n-Schluessel aus dem Collector und
						# wird erst hier aufgeloest, damit er der Reportsprache folgt.
						$hintTxt = if ($e.HintKey -and $I18n.Labels.$($e.HintKey)) { " — $($I18n.Labels.$($e.HintKey))" } else { "" }
						$reasonTxt = if ($e.Reason) { " ($($e.Reason)$hintTxt)" } else { "" }
						$protokoll = "$($e.Server) / $($e.LogName)"
						$affectedItems  += $protokoll
						$displayItems   += "$protokoll$reasonTxt"
						# EVT-02: Der Grund wandert als SCHLUESSEL nach
						# AffectedValues, statt NUR aufgeloest zu werden. Genau
						# das tat der Collector mit HintKey ohnehin schon — er
						# hielt es nur nicht bis ins JSON durch.
						# $e.Reason ist eine Betriebssystem-Ausnahmemeldung
						# ("The RPC server is unavailable") und stammt aus dem
						# Diag-Modul — auf einem deutschsprachigen Server waere
						# sie EBENFALLS uebersetzt und damit nicht wirklich
						# sprachneutral. Wir fuehren sie bewusst als Rohtext
						# mit, als Diagnosedetail, nicht als lokalisierbaren
						# Wert — das ist eine bewusste Grenze, kein Versehen.
						$affectedValues += [PSCustomObject]@{
							item    = $protokoll
							hintKey = $e.HintKey
							reason  = $e.Reason
						}
					} else {
						$protokoll = "$($e.Server) / $($e.LogName)"
						$affectedItems  += $protokoll
						$displayItems   += "$protokoll ($($e.RetentionDays) $($I18n.Labels.Days))"
						$affectedValues += [PSCustomObject]@{
							item  = $protokoll
							value = [int]$e.RetentionDays
							unit  = "Days"
						}
					}
				}

				if ($affectedItems.Count -gt 0) {
					$activeRecs += [PSCustomObject]@{
						Id            = $rule.Id
						Category      = $rule.Category
						Area          = Get-ADHCDisplayTitle -Rule $rule -Lang $LangCode
						ActualValue   = $worstDays
						Unit          = $rule.Threshold.unit
						ExpectedValue = $evtLimit
						Operator      = $rule.Threshold.operator
						AffectedItems = @($affectedItems)
						AffectedValues = if ($affectedValues.Count -gt 0) { @($affectedValues) } else { $null }
						Description   = "$($rule.Recommendation.$LangCode) ($($I18n.Labels.AffectedServers): $($displayItems -join ', '))"
						Priority      = $rule.Priority
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

				# Obergrenze fuer die privilegierten Gruppen aus recommendations.json
				# ("Threshold"). Zaehler-Regeln ohne Threshold feuern ab dem ersten
				# Treffer — dort gibt es keinen einstellbaren Wert.
				$secTh    = $rule.Threshold
				$secLimit = if ($null -ne $secTh.value) { [int]$secTh.value } else { $null }

				# Logische Prüfung (Schema Admins > 1 für Trigger)
				switch ($rule.Property) {
					"DomAdminCount" { $isTriggered = ($val -gt $(if($null -ne $secLimit){$secLimit}else{5})) }
					"EntAdminCount" { $isTriggered = ($val -gt $(if($null -ne $secLimit){$secLimit}else{2})) }
					"SchAdminCount" { $isTriggered = ($val -gt $(if($null -ne $secLimit){$secLimit}else{1})) }
					Default         { $isTriggered = ($val -gt 0) }
				}

				# Zaehler IMMER festhalten — "0 inaktive Konten" ist ein Nachweis,
				# ein leeres Feld waere nicht von "nicht geprueft" zu unterscheiden.
				Set-ADHCMeasure -Id $rule.Id -ActualValue $val -Unit "Users" `
					-ExpectedValue $secLimit -Operator $secTh.operator
		
				if ($isTriggered) {
					# Anzeige-Titel: kuratiertes Title{de,en} bevorzugt, sonst SubCategory
					$translatedArea = Get-ADHCDisplayTitle -Rule $rule -Lang $LangCode
		
					$activeRecs += [PSCustomObject]@{
						Id            = $rule.Id
						Category      = $I18n.Labels.Security
						Area          = $translatedArea
						ActualValue   = $val
						Unit          = "Users"
						ExpectedValue = $secLimit
						Operator      = $secTh.operator
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

				# Schwellenwert kommt aus recommendations.json ("Threshold"), nicht
				# mehr als Literal aus dem Code. Der Fallback haelt die Regel
				# funktionsfaehig, falls der Block in einer aelteren Config fehlt.
				$th    = $rule.Threshold
				$limit = if ($null -ne $th.value) { [int]$th.value } else { $null }
				# Messwert strukturiert mitfuehren (Upload-JSON + Report-Rendering)
				$measured = $null
				$unitKey  = $th.unit

				switch ($rule.Property) {
					"MinPwdLength" {
						if ($null -eq $limit) { $limit = 12 }
						$measured    = [int]$val
						$isTriggered = ($measured -lt $limit)
						$suffix = "$measured $($I18n.Labels.Characters)"
					}
					"Complexity" {
						# Boolesche Regel ohne Schwellenwert. $val -eq $null erfuellt BEIDE
						# Vergleiche ($null -ne $false UND $null -ne "False") und wurde bisher
						# als $measured = $true (also "aktiviert", PASS) gewertet — ein nicht
						# ermittelter Wert sah aus wie eine bestandene Pruefung
						# (docs/OFFENE-PUNKTE.md, Teil 3, PWD-02). $false und "False" bleiben
						# echte Befunde und loesen weiterhin PWD-02 aus.
						if ($null -eq $val) {
							$measured    = $null
							$isTriggered = $false
							Set-ADHCUndetermined -Id $rule.Id -Reason $I18n.Labels.ReasonComplexityUnknown
						} else {
							# TYPBEWUSST statt operatorabhaengig (P1). Vorher stand hier
							#     [bool]($val -ne $false -and $val -ne "False")
							# Steht links ein echtes [bool], wandelt PowerShell den RECHTEN
							# Operanden in [bool] um — und [bool]"False" ist $true, weil die
							# Zeichenkette nicht leer ist. Fuer $val = $true lautet der zweite
							# Vergleich damit "$true -ne $true" und ist falsch: $measured wurde
							# $false und PWD-02 feuerte, OBWOHL die Komplexitaet AKTIVIERT war.
							# Diag.psm1 liefert Complexity = $pwdPolicy.ComplexityEnabled aus
							# Get-ADDefaultDomainPasswordPolicy, also ein echtes [bool] — auf
							# jedem realen Domaenencontroller war das ein Falschbefund. Die
							# Mock-Daten setzen $false (ebenfalls [bool]), den einen Fall, in
							# dem der alte Ausdruck zufaellig richtig lag; deshalb ist es nie
							# aufgefallen.
							# Zeichenketten werden ausdruecklich behandelt: "False"/"false"/"0"
							# und die leere Zeichenkette gelten als deaktiviert, alles andere
							# als aktiviert. Alle uebrigen Typen (z. B. 0/1) ueber den
							# gewohnten [bool]-Cast.
							if ($val -is [string]) {
								$measured = -not ($val.Trim() -in @("", "false", "0"))
							} else {
								$measured = [bool]$val
							}
							$isTriggered = (-not $measured)
						}
						$suffix = if ($isTriggered) { $I18n.Labels.Disabled } else { $I18n.Labels.Enabled }
					}
					"PwdHistory" {
						if ($null -eq $limit) { $limit = 24 }
						$measured    = [int]$val
						$isTriggered = ($measured -lt $limit)
						$suffix = "$measured $($I18n.Labels.Passwords)"
					}
					# Feldname laut Collector und recommendations.json: "LockoutThresh".
					# Hier stand "LockoutThreshold" — das Label matchte nie, wodurch
					# PWD-04 auch bei komplett deaktivierter Kontosperre PASS meldete.
					"LockoutThresh" {
						if ($null -eq $limit) { $limit = 10 }
						$measured = [int]$val
						# 0 bedeutet "keine Sperre" und ist immer ein Befund — das laesst
						# sich nicht als reiner Schwellenwert ausdruecken, deshalb bleibt
						# diese Domaenenlogik im Code.
						$isTriggered = ($measured -eq 0 -or $measured -gt $limit)
						$suffix = "$measured $($I18n.Labels.Attempts)"
					}

					"LockoutDuration" {
						if ($null -eq $limit) { $limit = 15 }
						$measured = [int]$val
						# 0 bedeutet "dauerhaft gesperrt" und ist gewollt, daher ausgenommen
						$isTriggered = ($measured -gt 0 -and $measured -lt $limit)
						$suffix = "$measured $($I18n.Labels.Minutes)"
					}
					"ResetLockoutCount" {
						if ($null -eq $limit) { $limit = 15 }
						$measured    = [int]$val
						$isTriggered = ($measured -lt $limit)
						$suffix = "$measured $($I18n.Labels.Minutes)"
					}
				}
		
				# Messwert IMMER festhalten — auch wenn die Richtlinie in Ordnung ist.
				# Sonst traegt ein PASS keinen Nachweis (siehe $script:ADHCMeasurements).
				Set-ADHCMeasure -Id $rule.Id -ActualValue $measured -Unit $unitKey `
					-ExpectedValue $limit -Operator $th.operator

				if ($isTriggered) {
					$activeRecs += [PSCustomObject]@{
						Id            = $rule.Id
						Category      = $I18n.Labels.Security
						Area          = $I18n.Labels.PasswordPolicy
						ActualValue   = $measured
						Unit          = $unitKey
						ExpectedValue = $limit
						Operator      = $th.operator
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
				# SEC-09 (U3, vormals B3): geschuetzte Teilmenge(n) separat
				# sammeln. Bleibt fuer die anderen beiden Regeln leer und wirkt
				# sich nicht aus.
				$adminSdHolderAccounts = @()   # alle adminCount=1 (aktuell + ehemals), fuer den Gesamtzaehler unten
				$currentMemberAccounts = @()   # adminCount=1 UND aktuell Mitglied -- laufender SDProp-Schutz, erwartet
				$formerMemberAccounts  = @()   # adminCount=1, NICHT mehr Mitglied -- die aktionable Teilmenge (U3)
				$adminSdHolderItems    = @()
				$adminSdHolderValues   = @()

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
						# Die Regel feuert weiterhin auf die GESAMTZAHL (s.o.) --
						# das aendert sich nicht. AdminSDHolder-geschuetzte Konten
						# (SDProp schaltet deren Vererbung selbsttaetig ab, alle
						# 60 Min. neu) werden hier nur zusaetzlich getrennt
						# ausgewiesen, nicht aus der Zaehlung entfernt (B3).
						#
						# U3: adminCount=1 beweist NICHT "aktuell privilegiert" --
						# AD setzt das Attribut beim Gruppenaustritt nicht zurueck.
						# Deshalb DREI statt zwei Lagen (Diag.psm1, CurrentlyProtectedMember):
						#   aktuell Mitglied      -> erwartet, SDProp aktiv, nicht zu beheben
						#   nicht mehr Mitglied   -> die interessante Teilmenge: SDProp
						#                            pflegt sie nicht mehr, dauerhaft bereinigbar
						#   kein adminCount       -> der urspruengliche Befund (B3), unveraendert
						$adminSdHolderAccounts = @($ouSec.DisabledInheritanceUser | Where-Object { $_.AdminSdHolder -eq $true })
						$currentMemberAccounts = @($adminSdHolderAccounts | Where-Object { $_.CurrentlyProtectedMember -eq $true })
						$formerMemberAccounts  = @($adminSdHolderAccounts | Where-Object { $_.CurrentlyProtectedMember -eq $false })
						# Kappung auf die ersten 50, analog zur bestehenden
						# PII-Kappung von DisabledInheritanceUser im Upload-JSON.
						# Reihenfolge wie in DisabledInheritanceUser, damit die Kappung
						# sich nicht anders verhaelt als vor der Aufteilung.
						foreach ($acc in ($adminSdHolderAccounts | Select-Object -First 50)) {
							$adminSdHolderItems += $acc.Name
							# hintKey verengt/erweitert (U3, Dashboard-Vertrag-Nachtrag):
							# "AdminSdHolderProtected" heisst ab jetzt NUR NOCH "aktuell
							# geschuetzt" (SDProp aktiv); der neue Wert
							# "AdminSdHolderFormerMember" traegt die ehemals privilegierten,
							# nicht mehr gepflegten Konten.
							$hk = if ($acc.CurrentlyProtectedMember -eq $false) { "AdminSdHolderFormerMember" } else { "AdminSdHolderProtected" }
							$adminSdHolderValues += [PSCustomObject]@{ item = $acc.Name; hintKey = $hk }
						}
					}
				}

				# Zaehler IMMER festhalten. "0 verwaiste SIDs" ist ein Nachweis;
				# bisher stand der Wert nur im Satz und ActualValue blieb leer.
				$ouUnit = switch ($rule.Property) {
					"OrphanedSIDsCount"       { "OrphanedSIDs" }
					"OUInheritanceDisabled"   { "OUs" }
					"UserInheritanceDisabled" { "Users" }
					Default                   { $null }
				}
				Set-ADHCMeasure -Id $rule.Id -ActualValue ([int]$currentValue) -Unit $ouUnit `
					-ExpectedValue 0 -Operator "lte"

				if ($isTriggered) {
					$ouDescription = "$($rule.Recommendation.$LangCode) ($($I18n.Labels.CurrentValue): $currentValue)"
					if ($rule.Property -eq "UserInheritanceDisabled") {
						# Vollstaendige Aufschluesselung im JSON-Detail (Fliesstext, kein
						# Pillen-Layout) -- anders als in der HTML-Pille (s.o.) ist hier
						# kein Grund, eine der drei Zahlen wegzulassen.
						$ouDescription += " ($($I18n.Labels.OfWhichAdminSdHolder): $($adminSdHolderAccounts.Count), $($I18n.Labels.OfWhichFormerMember): $($formerMemberAccounts.Count))"
					}
					$activeRecs += [PSCustomObject]@{
						Id            = $rule.Id
						Category      = $I18n.Labels.Security
						Area          = $I18n.Labels.ObjectSecurity
						ActualValue   = [int]$currentValue
						Unit          = $ouUnit
						ExpectedValue = 0
						Operator      = "lte"
						AffectedItems  = if ($adminSdHolderItems.Count -gt 0)  { @($adminSdHolderItems) }  else { $null }
						AffectedValues = if ($adminSdHolderValues.Count -gt 0) { @($adminSdHolderValues) } else { $null }
						Description = $ouDescription
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

						# Strukturierter Befund (X4, OFFENE-PUNKTE-PASS-BELEGE,
						# Befund 2). Bis hierher standen Ist- und Soll-Version NUR
						# im Prosasatz ("(1.1.0.0 < 2.4.0.0)") -- ein Konsument
						# konnte weder "Befund"/"Soll" fuellen noch Versionsstaende
						# ueber die Zeit vergleichen.
						#
						# FORMENTSCHEIDUNG: NICHT ActualValue. Der Vertrag legt
						# dieses Feld auf Zahl, bool oder null fest; eine
						# Versionszeichenkette waere ein stiller Typbruch in einem
						# Feld, das der Konsument bereits rendert. Stattdessen die
						# BESTEHENDE AffectedValues-Form {item, hintKey} -- keine
						# neue Form, keine Vertragserweiterung: "item" traegt den
						# sprachneutralen Bezeichner (die Versionszeichenkette
						# selbst), "hintKey" sagt, welche Rolle er spielt. Die
						# uebrigen drei Formen scheiden aus, weil sie alle ueber
						# "value" laufen und value eine ZAHL ist (bzw. null =
						# "nicht ermittelbar"). Zwei Eintraege statt eines: die
						# beiden Versionen sind zwei verschiedene Groessen, kein
						# Wert mit Einheit.
						#
						# Auch beim BESTEHEN gesetzt -- dann belegt das Verdikt,
						# dass die Version tatsaechlich verglichen wurde, statt
						# nur "keine Empfehlung" zu sagen.
						# InstalledVersion kann statt einer Version auch
						# "NotInstalled" oder "Error" tragen (EntraSync.psm1) --
						# beides sprachneutrale Sentinel-Werte, die genau so
						# gemessen wurden und deshalb genau so weitergereicht
						# werden. Leer bleibt der Beleg nur, wenn eine der beiden
						# Angaben gar nicht vorliegt.
						if (-not [string]::IsNullOrWhiteSpace([string]$entra.InstalledVersion) -and
						    -not [string]::IsNullOrWhiteSpace([string]$entra.ExpectedVersion)) {
							Set-ADHCMeasure -Id $rule.Id -AffectedValues @(
								[PSCustomObject]@{ item = [string]$entra.InstalledVersion; hintKey = "EntraVersionInstalled" }
								[PSCustomObject]@{ item = [string]$entra.ExpectedVersion;  hintKey = "EntraVersionExpected"  }
							)
						}
					}
					"ServiceStatus" {
						# Prüfen ob Dienste in ServiceDetails nicht "Running" sind
						$stopped = $entra.ServiceDetails | Where-Object { $_.Status -ne "Running" }
						if ($stopped) {
							$isTriggered = $true
							$detail = "($($stopped.Name -join ', '))"
						}

						# Messwert AUCH beim Bestehen (X3, OFFENE-PUNKTE-PASS-BELEGE 1.1).
						# Muss VOR der Feuer-Entscheidung stehen. Laufende Dienste
						# gegen die Zahl der GEPRUEFTEN Dienste.
						# Bewusst nur, wenn ueberhaupt Dienste erhoben wurden: ohne
						# Entra-Anbindung liefert Get-EntraSyncStatus FoundAnyService
						# = $false und eine leere Liste -- "0 von 0 laufen" waere dann
						# keine Messung, sondern eine Behauptung ueber etwas, das gar
						# nicht existiert.
						$entraServices = @($entra.ServiceDetails)
						if ($entraServices.Count -gt 0) {
							$entraRunning = @($entraServices | Where-Object { $_.Status -eq "Running" }).Count
							Set-ADHCMeasure -Id $rule.Id -ActualValue ([int]$entraRunning) -Unit "Services" `
								-ExpectedValue ([int]$entraServices.Count) -Operator "eq"
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
				# X4: zweite, reine ANZEIGE-Liste -- dasselbe Grundmuster wie in
				# den Bloecken DCSystem/Backup/Sites. $null heisst "die Anzeige
				# folgt AffectedItems" und gilt fuer alle Regeln ausser DNS-07
				# und DNS-06; dort duerfen AffectedItems (alle unsignierten
				# Zonen bzw. der abgefragte Server) und der Befundsatz
				# (hoechstens drei Zonen bzw. gar keine Details) auseinander-
				# gehen, ohne dass sich der Satz aendert.
				$displayItems = $null

				switch ($rule.Property) {
					# 1. Scavenging Mismatch (Teilweise vergessen)
					"ScavengingZoneMismatch" {
						# Genau das, was der Regeltext behauptet: Server aktiv, einzelne Zonen aus.
						# Bis v2.7.5 wurde stattdessen nur abgezaehlt, ohne den Serverzustand je
						# erhoben zu haben.
						$serverScav   = $dns.QuickChecks.ServerScavenging
						$serverScavOn = ($serverScav -and $serverScav.Enabled -eq $true)
						if ($serverScavOn -and $missingScavengingCount -gt 0) {
							$isTriggered = $true
							$affectedItems = $dns.QuickChecks.MissingScavenging
						}

						if ($serverScavOn) {
							# Messwert AUCH beim Bestehen (X3): die Voraussetzung der
							# Regel ist erfuellt, es wurde tatsaechlich abgeglichen.
							Set-ADHCMeasure -Id $rule.Id -ActualValue ([int]$missingScavengingCount) `
								-Unit "Zones" -ExpectedValue 0 -Operator "lte"
						} else {
							# Ohne serverweites Scavenging fehlt die Voraussetzung der
							# Regel: DNS-01 fragt "Server an, einzelne Zonen aus?" --
							# ist der Server aus, gibt es nichts abzugleichen, denn
							# geloescht wird ohnehin nicht. Bis v2.10.1 fiel dieser
							# Fall in den PASS-Zweig und stand im Kundenbericht als
							# "Zonen-Scavenging: bestanden", waehrend in Wahrheit gar
							# nicht bereinigt wurde -- das einzige verbleibende PASS
							# ohne jeden Beleg (R1).
							#
							# NOT_APPLICABLE und nicht NOT_CHECKED: der Zustand IST
							# ermittelbar, die Regel greift bloss nicht. Der Messwert
							# bleibt weiterhin zurueckgehalten (X3) -- ein ActualValue
							# von 0 hiesse "0 Zonen betroffen" und behauptete eine
							# Messung, die nie stattfand.
							#
							# Zwei getrennte Texte, weil es zwei verschiedene Aussagen
							# sind: "nachweislich aus" gegen "nicht ermittelbar". Ein
							# gemeinsamer Satz wuerde dem Leser die Gewissheit nehmen,
							# die im ersten Fall vorhanden ist.
							#
							# -eq $false statt -not: PowerShell wandelt die rechte
							# Seite in den Typ der linken -- damit trifft der Zweig
							# sowohl auf ein echtes [bool] $false als auch auf die
							# Zeichenkette "False", waehrend $null (nicht ermittelbar)
							# richtigerweise NICHT greift.
							$scavReason = if ($serverScav -and $serverScav.Enabled -eq $false) {
								$I18n.Labels.ScavengingServerOffNotApplicable
							} else {
								$I18n.Labels.ScavengingServerUnknownNotApplicable
							}
							# Ohne AffectedItems: betroffen ist keine einzelne Zone,
							# sondern der Server -- den weist DNS-06 aus.
							Set-ADHCSkip -Id $rule.Id -Reason $scavReason
						}
					}
					# 2. Kritische SRV Records
					"MissingSRV" {
						$failedSRV = $dns.QuickChecks.SRVDetails | Where-Object { $_.Status -ne "OK" }
						if ($failedSRV) {
							$isTriggered = $true
							foreach ($srv in $failedSRV) { $affectedItems += $srv.ServiceKey }
						}

						# Messwert AUCH beim Bestehen (X3): geprueft OK gegen geprueft
						# gesamt -- "4 von 4 Records" statt eines leeren Befunds.
						# Wurde kein einziger Record geprueft, wird nichts behauptet.
						$srvAll = @($dns.QuickChecks.SRVDetails)
						if ($srvAll.Count -gt 0) {
							$srvOk = @($srvAll | Where-Object { $_.Status -eq "OK" }).Count
							Set-ADHCMeasure -Id $rule.Id -ActualValue ([int]$srvOk) -Unit "Records" `
								-ExpectedValue ([int]$srvAll.Count) -Operator "eq"
						}
					}
					# 3. Nameserver Erreichbarkeit
					"NSUnreachable" {
						$failedNS = $dns.NSStatus | Where-Object { $_.ICMP -ne "OK" -or $_.Service -ne "Running" }
						if ($failedNS) {
							$isTriggered = $true
							foreach ($ns in $failedNS) { $affectedItems += "$($ns.Name) ($($ns.Service))" }
						}

						# Messwert AUCH beim Bestehen (X3): erreichbare Nameserver
						# gegen alle geprueften. Dieselbe Bedingung wie oben, nur
						# negiert -- damit koennen Zaehler und Regel nicht
						# auseinanderlaufen.
						$nsAll = @($dns.NSStatus)
						if ($nsAll.Count -gt 0) {
							$nsOk = @($nsAll | Where-Object { $_.ICMP -eq "OK" -and $_.Service -eq "Running" }).Count
							Set-ADHCMeasure -Id $rule.Id -ActualValue ([int]$nsOk) -Unit "Servers" `
								-ExpectedValue ([int]$nsAll.Count) -Operator "eq"
						}
					}
					# 4. Nicht AD-integrierte Zonen
					"NonADIntegrated" {
						# Die automatischen Reverse-Zonen 0/127/255.in-addr.arpa sind
						# Standard-Primary-Zonen und koennen NIE AD-integriert sein —
						# ausschliessen, sonst falsche Findings.
						$systemReverseZones = @('0.in-addr.arpa','127.in-addr.arpa','255.in-addr.arpa')
						$nonAD = $allZones | Where-Object { $_.IsADIntegrated -eq $false -and $systemReverseZones -notcontains $_.ZoneName }
						if ($nonAD) {
							$isTriggered = $true
							foreach ($z in $nonAD) { $affectedItems += $z.ZoneName }
						}

						# Messwert AUCH beim Bestehen (X3): Zaehler ueber GENAU
						# dieselbe gefilterte Menge -- die drei Standardzonen bleiben
						# also auch hier aussen vor, sonst zaehlte der Beleg Zonen,
						# die die Regel selbst nie bemaengelt.
						if (@($allZones).Count -gt 0) {
							Set-ADHCMeasure -Id $rule.Id -ActualValue ([int]@($nonAD).Count) `
								-Unit "Zones" -ExpectedValue 0 -Operator "lte"
						}
					}
					# 5. Gestoppte Zonen
					"ZoneStopped" {
						$stopped = $allZones | Where-Object { $_.ZoneStatus -ne "Running" }
						if ($stopped) {
							$isTriggered = $true
							foreach ($z in $stopped) { $affectedItems += $z.ZoneName }
						}

						# Messwert AUCH beim Bestehen (X3): Zahl der gestoppten Zonen,
						# 0 ist der Nachweis "alle Zonen laufen". Ohne Zonen wurde
						# nichts gemessen.
						if (@($allZones).Count -gt 0) {
							Set-ADHCMeasure -Id $rule.Id -ActualValue ([int]@($stopped).Count) `
								-Unit "Zones" -ExpectedValue 0 -Operator "lte"
						}
					}
					# 6. Scavenging Global Aus (Nur Hinweis)
					"ScavengingGloballyDisabled" {
						# Haengt jetzt am serverweiten Schalter statt an "alle Zonen ohne Aging".
						# Ist er nicht ermittelbar ($null), wird nichts behauptet.
						if ($dns.QuickChecks.ServerScavenging -and $dns.QuickChecks.ServerScavenging.Enabled -eq $false) {
							$isTriggered = $true
						}

						# Strukturierter Wert (X4, Befund 2). Gemessen wird der
						# serverweite Schalter selbst -- ein bool, genau die
						# Groesse, ueber die diese Regel entscheidet. Nur, wenn er
						# ermittelbar war: $null heisst "nicht ermittelbar", und
						# daraus $false zu machen waere die Verwechslung, die
						# diese Charge beseitigt.
						$serverScav = $dns.QuickChecks.ServerScavenging
						if ($serverScav -and $null -ne $serverScav.Enabled) {
							Set-ADHCMeasure -Id $rule.Id -ActualValue ([bool]$serverScav.Enabled) `
								-Unit $null -ExpectedValue $true -Operator "eq"
						} else {
							# S1: ohne Schalter feuert die Regel nicht -- und fiel
							# damit in den PASS-Zweig, waehrend der Messwert (oben,
							# richtigerweise) zurueckgehalten wurde. Im Bericht stand
							# "Scavenging serverweit in Ordnung", obwohl niemand
							# nachgesehen hatte: das war das letzte PASS ohne jeden
							# Beleg (docs/OFFENE-PUNKTE-PASS-BELEGE.md).
							#
							# NOT_CHECKED und nicht NOT_APPLICABLE -- darin liegt der
							# Unterschied zu DNS-01 (R1, oben): dort ist die FRAGE
							# gegenstandslos, weil ihre Voraussetzung nachweislich
							# fehlt. Hier ist die Frage sehr wohl anwendbar, allein
							# die Antwort ist unbekannt. Im Unbekannt-Fall stehen
							# beide Regeln folgerichtig auf verschiedenen
							# Nicht-Ergebnissen; das ist kein Widerspruch.
							#
							# EIN Grundtext fuer beide Wege in diesen Zweig (Objekt
							# fehlt ganz gegen Enabled ist $null): fuer den Leser
							# sind sie dasselbe -- der Schalter liegt nicht vor. Ihr
							# Unterschied ist die Form der erhobenen Daten (alter
							# Datenstand gegen fehlgeschlagene Abfrage), keine
							# Aussage ueber die Umgebung; zwei Texte wuerden eine
							# Unterscheidung behaupten, die dem Leser nichts sagt.
							Set-ADHCUndetermined -Id $rule.Id -Reason $I18n.Labels.ReasonScavengingServerUnknown
						}

						# P34: der betroffene Server. Seit P34 legt
						# Get-ADHCServerScavenging den Namen des Abfrageziels im
						# Feld Server ab -- vorher fuehrten die erhobenen Daten
						# ihn ueberhaupt nicht, und $dns.NSStatus (die
						# Nameserver der ZONE) einzutragen hiesse, einen
						# Bezeichner zu erfinden.
						#
						# Ist der Name nicht bekannt -- alte Daten ohne das Feld,
						# oder ein Lauf ohne Zielangabe -- bleibt AffectedItems
						# leer: ein erfundener oder leerer Bezeichner waere
						# schlechter als keiner.
						if ($serverScav -and -not [string]::IsNullOrWhiteSpace([string]$serverScav.Server)) {
							$affectedItems += [string]$serverScav.Server
						}
						# Getrennte, LEERE Anzeigeliste -- dasselbe Muster wie bei
						# DNS-07: AffectedItems ist sprachneutral und traegt
						# Bezeichner, der Befundsatz bleibt dadurch byte-gleich zu
						# vorher (ohne ihn haenge hier neu ein "(Details: ...)" an).
						$displayItems = @()
					}
					# 7. DNSSEC Inaktiv (Nur Hinweis)
					"DNSSECNotConfigured" {
						$unsigned = $allZones | Where-Object { $_.IsSigned -eq $false }
						# X4 (Befund 2): AffectedItems traegt jetzt ALLE
						# unsignierten Zonen -- vorher sah das Verdikt bei vier
						# oder mehr Zonen genauso aus wie bei einer einzigen, und
						# im Referenzexport waren es alle. Der BEFUNDSATZ bleibt
						# unveraendert: er wird aus $displayItems gebaut, und das
						# bleibt die bisherige Auswahl "hoechstens drei, sonst
						# gar keine", damit der Bericht nicht geflutet wird.
						$displayItems = @()
						if ($unsigned) {
							$isTriggered = $true
							foreach ($z in $unsigned) { $affectedItems += $z.ZoneName }
							# Wir listen hier nicht alle Zonen auf, um den Report nicht zu fluten, außer es sind wenige
							if (@($unsigned).Count -le 3) { foreach ($z in $unsigned) { $displayItems += $z.ZoneName } }
						}

						# Messwert AUCH beim Bestehen (X4): Zahl der unsignierten
						# Zonen, 0 ist der Nachweis "alle Zonen signiert". Ohne
						# Zonen wurde nichts gemessen.
						if (@($allZones).Count -gt 0) {
							Set-ADHCMeasure -Id $rule.Id -ActualValue ([int]@($unsigned).Count) `
								-Unit "Zones" -ExpectedValue 0 -Operator "lte"
						}
					}
				}

				# Regelfall: die Anzeige folgt den Bezeichnern. Eigene Listen
				# setzen oben nur DNS-07 (gekuerzt) und DNS-06 (leer).
				if ($null -eq $displayItems) { $displayItems = $affectedItems }

				if ($isTriggered) {
					$activeRecs += [PSCustomObject]@{
						Id          = $rule.Id
						Category    = $I18n.Labels.Infrastructure
						Area        = $I18n.Labels.DNSZoneHealth
						AffectedItems = @($affectedItems)
						Description = if ($displayItems) { "$($rule.Recommendation.$LangCode) (Details: $($displayItems -join ', '))" } else { $rule.Recommendation.$LangCode }
						Priority    = $rule.Priority
					}
				}
			}
		}
		
			# Stash der gefeuerten Regeln für den Verdikt-Export (WP1 / Dashboard-Upload,
			# siehe Block "Upload-JSON (Dashboard)" am Ende von New-ADHCReport)
			$script:ADHCLastActiveRecs = $activeRecs

			# Regel-Nachschlagewerk ueber die Id. Damit kommen die neuen
			# Katalogfelder ins HTML, OHNE einen der 19 Auswertungsbloecke
			# anzufassen — jeder von ihnen setzt bereits Id. VOR die
			# Befund-Tabelle gezogen (U1): der Nicht-ermittelbar-Abschnitt
			# unten braucht Titel/Kategorie je Id ebenso, unabhaengig davon,
			# ob $activeRecs leer ist.
			$ruleById = @{}
			foreach ($secName in $recJson.PSObject.Properties.Name) {
				foreach ($r in $recJson.$secName) { $ruleById[$r.Id] = $r }
			}

			# Texte werden als REINER TEXT gerendert (siehe OFFENE-PUNKTE 0.6),
			# also escapen. Ein "&" im Katalog darf nicht als Entity enden.
			function Convert-ADHCHtmlText {
				param([string]$Text)
				if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
				# Nur die vier HTML-Sonderzeichen maskieren, NICHT ueber
				# WebUtility.HtmlEncode: das maskiert zusaetzlich den ganzen
				# Latin-1-Bereich (u.a. ae/oe/ue) zu &#NNN;-Entities, obwohl
				# der Bericht sonst ueberall literale Umlaute fuehrt. "&" MUSS
				# zuerst ersetzt werden, sonst werden &lt;/&gt;/&quot; gleich
				# nochmal escaped.
				return $Text.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
			}

			# --- HTML GENERIERUNG: BEFUND-TABELLE ---
			$html = ""
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

					# Sollwert aus den strukturierten Feldern anhaengen — EINE Stelle
					# fuer alle Regeln mit Threshold, statt in jedem Auswertungsblock.
					# Operator wird als Zeichen dargestellt, damit der Satz in beiden
					# Sprachen aus denselben Daten entsteht: "(empfohlen: >= 12 Zeichen)".
					$recText = $rec.Description
					if ($null -ne $rec.ExpectedValue) {
						$opSign = switch ($rec.Operator) {
							"gte"   { [char]0x2265 }   # >=
							"lte"   { [char]0x2264 }   # <=
							"gt"    { ">" }
							"lt"    { "<" }
							default { "" }
						}
						$unitTxt = if ($rec.Unit -and $I18n.Labels.$($rec.Unit)) { " $($I18n.Labels.$($rec.Unit))" } else { "" }
						$recText += " ($($I18n.Labels.Recommended): $opSign$($rec.ExpectedValue)$unitTxt)"
					}

					$html += "<tr class='rec-row'>
								<td class='rec-id text-center'>$($rec.Id)</td>
								<td class='rec-cat text-left'>$(Get-ADHCCategoryText -Category $rec.Category -Lang $LangCode)</td>
								<td class='rec-sub text-left'>$($rec.Area)</td>
								<td class='rec-text text-left'>$recText</td>
								<td class='text-center'><span class='$prioClass'>$($rec.Priority.ToUpper())</span></td>
							</tr>"

					# ACHTUNG — Namenskollision: $rec.Description ist der GERENDERTE
					# Befundsatz, $rule.Description der neue Hintergrundtext. Sie
					# haben denselben Namen auf VERSCHIEDENEN Objekten. Die drei
					# Katalogtexte bekommen deshalb eigene Variablennamen; auf
					# $rec.Description wird hier nie geschrieben.
					$catRule    = $ruleById[$rec.Id]
					$reqText    = if ($catRule) { Convert-ADHCHtmlText $catRule.Requirement.$LangCode } else { "" }
					$bgText     = if ($catRule) { Convert-ADHCHtmlText $catRule.Description.$LangCode } else { "" }
					$impactText = if ($catRule) { Convert-ADHCHtmlText $catRule.Impact.$LangCode }      else { "" }

					# Fehlt ein Feld, entfaellt NUR dessen dt/dd-Paar. Fehlen alle
					# drei (aeltere Konfiguration, neu ergaenzte Regel), entfaellt
					# die ganze Zeile — der Bericht sieht dann aus wie zuvor.
					$metaRows = ""
					if ($reqText)    { $metaRows += "<dt>$($I18n.Labels.Requirement)</dt><dd>$reqText</dd>" }
					if ($bgText)     { $metaRows += "<dt>$($I18n.Labels.Background)</dt><dd>$bgText</dd>" }
					if ($impactText) { $metaRows += "<dt>$($I18n.Labels.Impact)</dt><dd>$impactText</dd>" }

					if ($metaRows) {
						# <details open>: ohne JavaScript, standardmaessig offen,
						# damit auch ein Ausdruck vollstaendig ist. Das open-Attribut
						# ist DOM-Zustand, kein Stil — klappt der Leser im Browser
						# manuell zu, kann kein Druck-CSS das rueckgaengig machen.
						# report.style.css erzwingt fuer @media print zusaetzlich
						# display:block auf dem Inhalt (unabhaengig vom Attribut) —
						# das eine schuetzt den Normalfall, das andere den Leser,
						# der vor dem Drucken zugeklappt hat.
						$html += "<tr class='rec-detail'><td colspan='5'>
									<details open>
										<summary>$($I18n.Labels.CheckDetails)</summary>
										<dl class='rec-meta'>$metaRows</dl>
									</details>
								</td></tr>"
					}
				}
				$html += "</tbody></table></div>"
			}

			# --- HTML GENERIERUNG: NICHT ERMITTELBARE REGELN (U1) ---
			# Eine Regel im Undetermined-Stash ist WEDER Befund noch Bestehen —
			# sie darf deshalb nicht in $activeRecs (Befund-Tabelle, ggf. mit
			# HIGH-Kachel) landen, aber auch nicht kommentarlos verschwinden
			# (Schlussprüfung W3: AD-04 kam bisher im HTML gar nicht vor).
			# Eigener, zurueckgenommener Abschnitt unterhalb der Empfehlungen
			# (Alternative aus dem Auftrag) statt eines vierten Zustands INNER-
			# HALB der Befund-Tabelle: die Tabelle ist nach Prioritaet sortiert
			# und mit Prio-Kacheln versehen — ein Element ohne Befund darin
			# waere selbst mit neutraler Kachel schwer von einem echten Befund
			# zu unterscheiden. Der Grund kommt AUSSCHLIESSLICH aus dem bereits
			# lokalisierten Stash-Eintrag (Set-ADHCUndetermined, oben) bzw. aus
			# $I18n.Labels — kein hartcodierter Text.
			if ($script:ADHCUndetermined.Count -gt 0) {
				$html += "<div class='card rec-undetermined'><h2>$($I18n.Sections.NotDetermined)</h2>"
				$html += "<p class='rec-undetermined-intro'>$($I18n.Labels.NotDeterminedIntro)</p>"
				$html += "<table class='rec-matrix'><thead><tr>"
				$html += "<th class='text-center'>ID</th>"
				$html += "<th class='text-left'>$($I18n.Labels.Category)</th>"
				$html += "<th class='text-left'>$($I18n.Labels.Area)</th>"
				$html += "<th class='text-left'>$($I18n.Labels.Reason)</th>"
				$html += "<th class='text-center'>$($I18n.Labels.Status)</th>"
				$html += "</tr></thead><tbody>"

				foreach ($ndId in ($script:ADHCUndetermined.Keys | Sort-Object)) {
					$ndEntry = $script:ADHCUndetermined[$ndId]
					$ndRule  = $ruleById[$ndId]
					$ndTitle = if ($ndRule) { Get-ADHCDisplayTitle -Rule $ndRule -Lang $LangCode } else { $ndId }
					$ndCat   = if ($ndRule) { Get-ADHCCategoryText -Category $ndRule.Category -Lang $LangCode } else { "" }
					$ndReason = Convert-ADHCHtmlText $ndEntry.Reason

					# U2: eigene Badge-Klasse 'prio-undetermined' statt 'prio-info' --
					# vorher trug "nicht ermittelbar" dieselbe Klasse wie ein echter
					# (harmloser) Info-Befund (DNS-06/DNS-07); Farbe, Form und Rahmen
					# waren identisch, unterschieden wurde nur ueber Text. Siehe
					# templates/report.style.css fuer die Herkunft der Werte.
					$html += "<tr class='rec-row rec-row-undetermined'>
								<td class='rec-id text-center'>$ndId</td>
								<td class='rec-cat text-left'>$ndCat</td>
								<td class='rec-sub text-left'>$ndTitle</td>
								<td class='rec-text text-left'>$ndReason</td>
								<td class='text-center'><span class='prio-badge prio-undetermined'>$($I18n.Labels.NotDetermined)</span></td>
							</tr>"
				}
				$html += "</tbody></table></div>"
			}

			return $html
		}

	# Empfehlungen generieren
	# EINMAL berechnet und an alle Evaluator-Aufrufe durchgereicht: sonst
	# koennen zwei Aufrufe desselben Laufs verschiedene Altersangaben liefern.
	$evalNow = Get-Date
	$htmlRec = Get-ADHCRecommendations -Data $Data -Settings $Settings -I18n $I18n -LangCode $LangCode -Now $evalNow

	# === Upload-JSON (Dashboard) — Metadaten + Verdikte + Rohdaten mit minimierter PII ===
	# Das Ergebnis ist NICHT PII-frei: Security.RawExportData wird entfernt, aber
	# DisabledInheritanceUser liefert bewusst Name + DN der ersten 50 Konten (seit
	# v2.4.6). Die Datei unter output/data/ ist entsprechend zu behandeln.
	# Verdikte über ALLE Sektionen (ShowRecommendations-Toggles bewusst ignoriert, damit
	# das Dashboard vollständig bewertet): Evaluator mit allen Sektionen=$true erneut
	# aufrufen; die gefeuerten Regeln kommen via $script:ADHCLastActiveRecs (Stash).
	$recSections = @('DomainOverview','FSMO','DCDIag','DCSystem','Backup','Services','Sites','Security','OUAccountSecurity','PasswordPolicy','Entra','DNS','Replication','EventLog')
	$allOn = @{}; foreach ($s in $recSections) { $allOn[$s] = $true }
	# Thresholds MUSS mit: der Evaluator liest ausserhalb der Toggles DREI
	# Settings-Werte direkt — Thresholds.KrbtgtPasswordAgeDays (:943),
	# Thresholds.ReplicationLatencyMaxMinutes (:1499) und
	# Thresholds.MaxEventLogAgeDays (:1596). Deshalb wird hier bewusst das
	# GANZE Thresholds-Objekt durchgereicht statt einzelner Felder: kuenftige
	# Ergaenzungen um weitere Schwellenwerte kommen so automatisch mit, ohne
	# dass dieser Aufruf angepasst werden muss.
	# Ohne Thresholds fiel dieser Aufruf auf die eingebauten Standardwerte
	# zurueck, waehrend der HTML-Lauf darueber die konfigurierte Schwelle
	# benutzte — dieselbe Regel meldete im Bericht FAIL und im Upload-JSON PASS.
	$settingsAllOn = [PSCustomObject]@{
		ShowRecommendations = $allOn
		Thresholds          = $Settings.Thresholds
	}
	# --- Zweisprachigkeit (schemaVersion 4) ---------------------------------
	# Die Messwerte sind sprachneutral, die PROSA nicht: Detail und SkipReason
	# entstehen zur Laufzeit aus Recommendation.$LangCode plus $I18n.Labels.
	# Ein Konsument, der den Bericht in der ANDEREN Sprache anzeigt, hatte
	# diese Texte bisher nicht — gemessen waren 10 von 30 Befunden in beiden
	# Sprachen identisch deutsch.
	#
	# Weg: derselbe Evaluator ein zweites Mal, mit der Gegensprache. Das setzt
	# voraus, dass er ueber denselben $Data deterministisch ist — dafuer gibt es
	# den Test "Determinismus des Evaluators" und den Parameter -Now.
	#
	# ACHTUNG REIHENFOLGE: Alle drei Stashes werden bei JEDEM Aufruf
	# zurueckgesetzt bzw. ueberschrieben. Der LETZTE Aufruf muss deshalb der in
	# Berichtssprache sein — sonst steht still die falsche Sprache im Detail,
	# und weder ein Durchlauf noch ein Test bemerkt es.
	$altLang = if ($LangCode -eq 'de') { 'en' } else { 'de' }
	$i18nDirAlt = Join-Path $PSScriptRoot "..\config"

	# Faellt die Gegensprache aus (fehlende Datei, aeltere Installation), bleibt
	# das JSON einsprachig statt leer: besser ein Text in einer Sprache als gar
	# keiner. Das Feld traegt dann in beiden Zweigen denselben Satz.
	# ACHTUNG: Get-ADHCI18n selbst faellt bei fehlender Sprachdatei still auf
	# i18n.de.json zurueck und gibt NIE $null zurueck (Utils.psm1) — eine
	# Pruefung "if (-not $altI18n)" nach dem Aufruf wuerde eine fehlende
	# Gegensprachdatei deshalb NIE erkennen und still deutschen Text unter dem
	# Schluessel 'en' ablegen. Deshalb hier die Datei direkt pruefen.
	$altI18nFile = Join-Path $i18nDirAlt "i18n.$altLang.json"
	if (-not (Test-Path $altI18nFile)) {
		Write-ADHCLog "i18n fuer '$altLang' nicht gefunden — Verdikte bleiben einsprachig." -Level Warning -Component "Reporting"
		$altI18n = $I18n
		$altLang = $LangCode
	} else {
		$altI18n = Get-ADHCI18n -Path $i18nDirAlt -Lang $altLang
	}

	# 1) Gegensprache
	$null = Get-ADHCRecommendations -Data $Data -Settings $settingsAllOn -I18n $altI18n -LangCode $altLang -Now $evalNow
	$altDetailById = @{}
	foreach ($r in @($script:ADHCLastActiveRecs)) { $altDetailById[$r.Id] = $r.Description }
	$altSkipById = @{}
	foreach ($k in $script:ADHCSkipped.Keys) { $altSkipById[$k] = $script:ADHCSkipped[$k].Reason }
	$altUndeterminedById = @{}
	foreach ($k in $script:ADHCUndetermined.Keys) { $altUndeterminedById[$k] = $script:ADHCUndetermined[$k].Reason }

	# 2) Berichtssprache — DIESER Zustand gilt fuer alles Weitere
	$null = Get-ADHCRecommendations -Data $Data -Settings $settingsAllOn -I18n $I18n -LangCode $LangCode -Now $evalNow
	$firedRecs = @($script:ADHCLastActiveRecs)
	$firedIds  = @($firedRecs.Id)

	$recPathV = Join-Path $PSScriptRoot "..\config\recommendations.json"
	# Beide Stashes werden in Get-ADHCRecommendations gefuellt. Faellt der Aufruf
	# frueh aus (fehlende recommendations.json), sind sie $null — der Index-Zugriff
	# unten wuerde dann werfen.
	if ($null -eq $script:ADHCMeasurements)  { $script:ADHCMeasurements  = @{} }
	if ($null -eq $script:ADHCSkipped)       { $script:ADHCSkipped       = @{} }
	if ($null -eq $script:ADHCUndetermined)  { $script:ADHCUndetermined  = @{} }
	# Baut ein {de,en}-Objekt aus zwei fertig gerenderten Saetzen. Ist einer
	# nicht vorhanden, tritt der andere an seine Stelle — ein Text in EINER
	# Sprache ist brauchbarer als eine Leerstelle. Sind beide leer, kommt $null
	# zurueck, damit sich am heutigen Verhalten fuer Regeln ohne Befund nichts
	# aendert.
	function Get-ADHCBilingual {
		param([string]$Primary, [string]$Alternate, [string]$PrimaryLang, [string]$AlternateLang)
		if ([string]::IsNullOrWhiteSpace($Primary) -and [string]::IsNullOrWhiteSpace($Alternate)) { return $null }
		$p = if ($Primary)   { $Primary }   else { $Alternate }
		$a = if ($Alternate) { $Alternate } else { $Primary }
		# KEIN Hash-LITERAL (@{ $PrimaryLang = $p; $AlternateLang = $a }): faellt
		# die Gegensprache aus, setzt die Ausfallsicherung oben PrimaryLang UND
		# AlternateLang auf denselben Sprachcode. Ein Hash-Literal mit zwei
		# gleichen Schluesseln wirft "Duplicate keys '...' are not allowed in
		# hash literals" — ein TERMINIERENDER Fehler, der die gesamte
		# Berichtserstellung abbricht. Eine leere Hashtable mit anschliessenden
		# Zuweisungen kennt dieses Problem nicht: die zweite Zuweisung auf
		# denselben Schluessel ueberschreibt einfach.
		$map = @{}
		$map[$PrimaryLang] = $p
		# Sind Primary- und AlternateLang identisch (Ausfallpfad: nur EINE
		# Sprache verfuegbar), bekommt das Objekt bewusst nur EINEN Schluessel
		# statt denselben Text unter zwei Schluesseln zu duplizieren. Ein
		# Konsument, der z. B. Detail.en liest und $null bekommt, sieht damit,
		# dass die Gegensprache fehlt — einer, der unbemerkt deutschen Text
		# unter 'en' faende, saehe es nicht (genau das Fehlerbild, vor dem
		# dieser Code an anderer Stelle warnt).
		if ($AlternateLang -ne $PrimaryLang) {
			$map[$AlternateLang] = $a
		}
		# Eigenschaftsreihenfolge bewusst sprachunabhaengig (alphabetisch nach
		# Schluessel), NICHT nach PrimaryLang: sonst serialisiert derselbe
		# Verdikt im de- und im en-Lauf mit vertauschter Property-Reihenfolge
		# ({"de":..,"en":..} vs. {"en":..,"de":..}) — inhaltlich identisch, aber
		# ein stringbasierter JSON-Vergleich (Compare-ADHCVerdicts) meldete das
		# faelschlich als Abweichung.
		$o = [ordered]@{}
		foreach ($k in ($map.Keys | Sort-Object)) { $o[$k] = $map[$k] }
		return [PSCustomObject]$o
	}

	$verdicts = @()
	if (Test-Path $recPathV) {
		$recAll = Get-Content $recPathV -Raw -Encoding UTF8 | ConvertFrom-Json
		$sectionData = @{ DomainOverview='DomainStats'; FSMO='FSMO'; DCDIag='DCDiag'; DCSystem='Discovery'; Backup='Backup'; Services='Services'; Sites='Sites'; Security='Security'; OUAccountSecurity='OUAccountSecurity'; PasswordPolicy='Security'; Entra='Entra'; DNS='DNS'; Replication='Replication'; EventLog='EventLog' }
		foreach ($sec in $recAll.PSObject.Properties.Name) {
			$dataKey = $sectionData[$sec]
			$hasData = $dataKey -and $Data.$dataKey
			foreach ($rule in $recAll.$sec) {
				# NOT_APPLICABLE steht VOR allem anderen: eine Regel, die auf die
				# Umgebung gar nicht zutrifft (z.B. Replikation bei genau EINEM
				# Domaenencontroller), darf weder als bestanden noch als
				# fehlgeschlagen gezaehlt werden. NOT_CHECKED bleibt davon getrennt
				# und heisst weiterhin "keine Daten erhoben".
				$skip          = $script:ADHCSkipped[$rule.Id]
				$undetermined  = $script:ADHCUndetermined[$rule.Id]
				# NOT_CHECKED wird hier fuer ZWEI verschiedene Faelle vergeben, die
				# beide keinen neuen Statuswert bekommen sollen (kein schemaVersion-
				# Bump, docs/OFFENE-PUNKTE.md Teil 3): "keine Daten erhoben" (der
				# bisherige else-Zweig) UND "Wert war nicht ermittelbar"
				# ($undetermined). Der Undetermined-Zweig steht NACH FAIL (eine
				# Regel, die trotzdem gefeuert hat, ist ein Befund, kein unbekannter
				# Wert) und VOR PASS (sonst gewinnt PASS und die Luecke bleibt
				# unsichtbar).
				$status = if ($skip)                          { 'NOT_APPLICABLE' }
				          elseif ($firedIds -contains $rule.Id) { 'FAIL' }
				          elseif ($undetermined)              { 'NOT_CHECKED' }
				          elseif ($hasData)                   { 'PASS' }
				          else                                { 'NOT_CHECKED' }
				$hit = $firedRecs | Where-Object { $_.Id -eq $rule.Id } | Select-Object -First 1
				# ActualValue/Unit/AffectedItems/ExpectedValue/Operator sind seit
				# schemaVersion 2 dabei. Sie ergaenzen Detail (den fertig gerenderten
				# Satz) um die MESSWERTE, damit ein Konsument sie in eigener Sprache
				# und eigenem Format darstellen und ueber die Zeit vergleichen kann.
				# Nicht jede Regel hat einen Skalar: listenartige Befunde (betroffene
				# Server, Partitionen, Subnetze) landen in AffectedItems.
				# Messwert-Stash: liefert den gemessenen Wert AUCH fuer PASS-Regeln.
				# Vorher war ein PASS im JSON nicht von einer Pruefung zu
				# unterscheiden, die gar nichts gemessen hatte — beides ActualValue=null.
				$meas = $script:ADHCMeasurements[$rule.Id]

				$expected = if ($hit -and $null -ne $hit.ExpectedValue) { $hit.ExpectedValue }
				            elseif ($meas -and $null -ne $meas.ExpectedValue) { $meas.ExpectedValue }
				            elseif ($null -ne $rule.Threshold.value) { $rule.Threshold.value }
				            else { $null }
				$operator = if ($hit -and $hit.Operator) { $hit.Operator }
				            elseif ($meas -and $meas.Operator) { $meas.Operator }
				            else { $rule.Threshold.operator }
				$unit     = if ($hit -and $hit.Unit) { $hit.Unit }
				            elseif ($meas -and $meas.Unit) { $meas.Unit }
				            else { $rule.Threshold.unit }
				$actual   = if ($skip) { $null }
				            elseif ($hit -and $null -ne $hit.ActualValue) { $hit.ActualValue }
				            elseif ($meas) { $meas.ActualValue }
				            else { $null }

				# WICHTIG: Der Rueckgabewert eines if-Blocks wird von PowerShell
				# ENUMERIERT — ein einelementiges Array wird dabei zum Skalar.
				# Dadurch stand im JSON mal ["a","b"], mal "a". Typisierte Zuweisung
				# VOR dem Objektbau haelt den Array-Typ in jedem Fall.
				[string[]]$affectedOut = $null
				if ($skip -and $skip.AffectedItems) { $affectedOut = [string[]]@($skip.AffectedItems) }
				elseif ($hit -and $hit.AffectedItems) { $affectedOut = [string[]]@($hit.AffectedItems) }
				elseif ($undetermined -and $undetermined.AffectedItems) { $affectedOut = [string[]]@($undetermined.AffectedItems) }
				elseif ($meas -and $meas.AffectedItems) { $affectedOut = [string[]]@($meas.AffectedItems) }

				# Gleiche Reihenfolge wie bei AffectedItems: Skip vor Treffer vor
				# Messwert. Bleibt $null, wenn die Regel keine Werte fuehrt — dann
				# steht die Information wie bisher allein in AffectedItems.
				$affectedValsOut = $null
				if     ($skip -and $skip.AffectedValues) { $affectedValsOut = @($skip.AffectedValues) }
				elseif ($hit  -and $hit.AffectedValues)  { $affectedValsOut = @($hit.AffectedValues) }
				elseif ($undetermined -and $undetermined.AffectedValues) { $affectedValsOut = @($undetermined.AffectedValues) }
				elseif ($meas -and $meas.AffectedValues) { $affectedValsOut = @($meas.AffectedValues) }

				$verdicts += [PSCustomObject]@{
					Id            = $rule.Id
					Section       = $sec
					Category      = $rule.Category
					SubCategory   = $rule.SubCategory
					Priority      = $rule.Priority
					Status        = $status
					# Detail und SkipReason sind seit schemaVersion 4 {de,en}.
					# ACHTUNG: $hit.Description ist der GERENDERTE Befundsatz, nicht
					# das Katalogfeld $rule.Description. Gleicher Name, anderes
					# Objekt — eine Verwechslung erzeugt keinen Fehler, sondern
					# still den falschen Text.
					Detail        = Get-ADHCBilingual -Primary $(if ($skip) { $skip.Reason } elseif ($hit) { $hit.Description } elseif ($undetermined) { $undetermined.Reason } else { $null }) `
					                                  -Alternate $(if ($skip) { $altSkipById[$rule.Id] } elseif ($hit) { $altDetailById[$rule.Id] } elseif ($undetermined) { $altUndeterminedById[$rule.Id] } else { $null }) `
					                                  -PrimaryLang $LangCode -AlternateLang $altLang
					# Begruendung maschinenlesbar getrennt vom Fliesstext in Detail.
					# SkipReason traegt seit T1 (docs/OFFENE-PUNKTE.md, Teil 3) auch bei
					# NOT_CHECKED einen Grund, wenn der Wert nicht ERMITTELBAR war (nicht
					# nur bei NOT_APPLICABLE) — additiv, siehe Nachtrag in
					# docs/DASHBOARD-VERTRAG-v4.md.
					SkipReason    = Get-ADHCBilingual -Primary $(if ($skip) { $skip.Reason } elseif ($undetermined) { $undetermined.Reason } else { $null }) `
					                                  -Alternate $(if ($skip) { $altSkipById[$rule.Id] } elseif ($undetermined) { $altUndeterminedById[$rule.Id] } else { $null }) `
					                                  -PrimaryLang $LangCode -AlternateLang $altLang
					ActualValue   = $actual
					Unit          = $unit
					AffectedItems = $affectedOut
					AffectedValues = $affectedValsOut
					ExpectedValue = $expected
					Operator      = $operator
				}
			}
		}
	} else {
		Write-ADHCLog "recommendations.json nicht gefunden — Verdikte werden übersprungen." -Level Warning -Component "Reporting"
	}

	# -------------------------------------------------------------------
	# scoreSummary (Aufgabe V1): der Collector rechnet dem Dashboard die
	# score-relevanten Kennzahlen vor, statt dass jeder Konsument selbst nach
	# Priority=Info filtert (bisher Dashboard-Arbeit, siehe
	# docs/DASHBOARD-UEBERGABE.md, B1). Gebaut aus DERSELBEN $verdicts-
	# Liste, aus der oben "assessment" entsteht — keine parallele Zaehlung,
	# sonst koennte der Block eine andere Wahrheit sagen als die Verdikte
	# darunter (siehe Nachtrag "scoreSummary" in DASHBOARD-VERTRAG-v4.md).
	#
	# Drei Gruende zaehlen ein Verdikt aus der Bewertung heraus: Priority
	# Info (die Regel ist laut eigenem Katalogtext ein Hinweis, kein
	# Mangel — unabhaengig davon, ob sie gerade FAIL oder PASS meldet),
	# Status NOT_APPLICABLE und Status NOT_CHECKED (beide sind weder
	# bestanden noch fehlgeschlagen). Ein Verdikt kann MEHRERE dieser
	# Gruende gleichzeitig tragen (z. B. SITE-06 mit Priority Info UND
	# Status NOT_APPLICABLE, wenn die Sites-Sektion fehlt) — "excluded.total"
	# zaehlt daher ENTDOPPELT (wie viele Verdikte betroffen sind), waehrend
	# "excluded.byReason" je Grund zaehlt (kann in Summe hoeher liegen als
	# excluded.total). scoreRelevant.total ist immer total - excluded.total.
	$scoreByStatus   = [ordered]@{ PASS = 0; FAIL = 0; NOT_APPLICABLE = 0; NOT_CHECKED = 0 }
	$scoreByPriority = [ordered]@{ High = 0; Medium = 0; Low = 0; Info = 0 }
	$scoreReasonInfo = 0
	$scoreReasonNA   = 0
	$scoreReasonNC   = 0
	$scoreExcluded   = 0
	$scorePassed     = 0
	$scoreFailed     = 0
	foreach ($v in $verdicts) {
		if ($scoreByStatus.Contains($v.Status))     { $scoreByStatus[$v.Status]++ }
		if ($scoreByPriority.Contains($v.Priority)) { $scoreByPriority[$v.Priority]++ }

		$isInfo = ($v.Priority -eq 'Info')
		$isNA   = ($v.Status -eq 'NOT_APPLICABLE')
		$isNC   = ($v.Status -eq 'NOT_CHECKED')

		if ($isInfo) { $scoreReasonInfo++ }
		if ($isNA)   { $scoreReasonNA++ }
		if ($isNC)   { $scoreReasonNC++ }

		if ($isInfo -or $isNA -or $isNC) {
			$scoreExcluded++
		} elseif ($v.Status -eq 'PASS') {
			$scorePassed++
		} elseif ($v.Status -eq 'FAIL') {
			$scoreFailed++
		}
	}
	$scoreSummary = [ordered]@{
		total         = $verdicts.Count
		byStatus      = $scoreByStatus
		byPriority    = $scoreByPriority
		excluded      = [ordered]@{
			total    = $scoreExcluded
			byReason = [ordered]@{
				priorityInfo        = $scoreReasonInfo
				statusNotApplicable = $scoreReasonNA
				statusNotChecked    = $scoreReasonNC
			}
		}
		scoreRelevant = [ordered]@{
			total  = $scorePassed + $scoreFailed
			passed = $scorePassed
			failed = $scoreFailed
		}
	}

	# Rohdaten deep-clone (JSON-Roundtrip) und PII entfernen/minimieren
	$dataClone = $Data | ConvertTo-Json -Depth 15 | ConvertFrom-Json
	# (a) Benutzer-Detailliste (Klarnamen/UPNs) — bleibt nur in der CSV, nicht im Upload
	if ($dataClone.Security -and $dataClone.Security.PSObject.Properties['RawExportData']) {
		$dataClone.Security.PSObject.Properties.Remove('RawExportData')
	}
	# (b) Konten mit deaktivierter Vererbung: volle Anzahl behalten UND die Liste
	#     (Name/DN) auf die ersten 50 kappen — Paritaet zum HTML-Report (Select-Object -First 50).
	#     Bewusste Re-Aufnahme der Klarnamen/DNs fuer den Dashboard-/PDF-Report.
	if ($dataClone.OUAccountSecurity -and $dataClone.OUAccountSecurity.PSObject.Properties['DisabledInheritanceUser']) {
		$duAll   = @($dataClone.OUAccountSecurity.DisabledInheritanceUser)
		$duCount = $duAll.Count
		$duTop   = @($duAll | Select-Object -First 50 | ForEach-Object {
			[PSCustomObject]@{ Name = $_.Name; DN = $_.DN; AdminSdHolder = $_.AdminSdHolder }
		})
		$dataClone.OUAccountSecurity.PSObject.Properties.Remove('DisabledInheritanceUser')
		$dataClone.OUAccountSecurity | Add-Member -NotePropertyName 'DisabledInheritanceUser' -NotePropertyValue $duTop -Force
		$dataClone.OUAccountSecurity | Add-Member -NotePropertyName 'DisabledInheritanceUserCount' -NotePropertyValue $duCount -Force
	}

	# (c) Listenfelder auf Array-Form bringen — LETZTER Schritt vor dem
	#     Serialisieren, damit auch die Umbauten oben davon erfasst sind.
	#     Begruendung an $script:ADHCJsonListPaths.
	$null = Set-ADHCJsonListShape -Data $dataClone -Path $script:ADHCJsonListPaths

	$exportData = [ordered]@{
		# 2 = Verdikte fuehren zusaetzlich ActualValue, Unit, AffectedItems,
		#     ExpectedValue und Operator. Rein additiv — Konsumenten von
		#     schemaVersion 1 funktionieren unveraendert weiter.
		# 3 = Neues Feld SkipReason UND ein neuer Status-Wert NOT_APPLICABLE.
		#     Der Status-Wert ist NICHT rein additiv: ein Konsument, der nur
		#     PASS/FAIL/NOT_CHECKED kennt, sieht einen unbekannten Wert. Er ist wie
		#     NOT_CHECKED zu behandeln — nicht bestanden, aber auch KEIN Fehler.
		#     Betrifft aktuell REP-01/REP-02 in Domaenen mit nur einem DC.
		# 4 = Detail, SkipReason und Category sind {de,en}-Objekte statt Strings.
		#     NICHT additiv: ein Konsument von schemaVersion 3 liest dort etwas
		#     anderes als bisher. Dazu neu: AffectedValues ({item,value,unit}
		#     oder {item,hintKey}) und die Regel, dass AffectedItems
		#     ausschliesslich sprachneutrale Bezeichner enthaelt.
		#
		#     BEDEUTUNG VON language: sagt ab hier NICHT mehr, in welcher Sprache
		#     die Verdikte vorliegen — die liegen in beiden vor. Es sagt, in
		#     welcher Sprache der HTML-Bericht desselben Laufs erzeugt wurde.
		#     Fuer ein auswertendes System ist es damit hoechstens noch ein
		#     Vorgabewert fuer die Anzeige, keine Aussage ueber den Inhalt.
		#
		#     scoreSummary (Aufgabe V1, additiv): score-relevante Kennzahlen,
		#     vom Collector vorgerechnet (Priority=Info, NOT_APPLICABLE und
		#     NOT_CHECKED bereits herausgerechnet). Ein Konsument, der das
		#     Feld nicht kennt, ignoriert es unveraendert — siehe Nachtrag
		#     "scoreSummary" in docs/DASHBOARD-VERTRAG-v4.md.
		schemaVersion    = 4
		collectorVersion = $CollectorVersion
		collectedAt      = (Get-Date).ToString('o')
		language         = $LangCode
		domainFQDN       = $Data.DomainStats.DomainFQDN
		assessment       = $verdicts
		scoreSummary     = $scoreSummary
		data             = $dataClone
	}

	$jsonOut = $exportData | ConvertTo-Json -Depth 15
	# PS 5.1 emittiert DateTime als WCF (/Date(ms)/) → auf ISO-8601 (UTC) normalisieren.
	# Epoch-Berechnung statt FromUnixTimeMilliseconds (letzteres erst ab .NET 4.6).
	$jsonOut = [regex]::Replace($jsonOut, '\\?/Date\((\d+)\)\\?/', {
		param($m)
		([datetime]::new(1970,1,1,0,0,0,[System.DateTimeKind]::Utc)).AddMilliseconds([double]$m.Groups[1].Value).ToString('o')
	})
	$jsonOut | Out-File -FilePath $jsonFile -Encoding utf8
	Write-ADHCLog -Message "Upload-JSON (Dashboard): $jsonFile ($($verdicts.Count) Verdikte)" -Component "Reporting"

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

Export-ModuleMember -Function New-ADHCReport, Set-ADHCJsonListShape