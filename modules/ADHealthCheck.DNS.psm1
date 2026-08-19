# MODULE: ADHealthCheck.DNS.psm1

# Name der DNSSEC-Systemzone. An einer Stelle definiert, weil sowohl der
# Nameserver-Filter als auch der Informationsblock darauf zugreifen.
$script:ADHCTrustAnchorZone = 'trustanchors'

function Get-ADHCTrustAnchorInfo {
    <#
    .SYNOPSIS
        Sammelt rein informative Angaben zu DNSSEC Trust Anchors.
    .DESCRIPTION
        Bewusst OHNE Bewertung: Es gibt kein Statusfeld, aus dem das Reporting ein
        Verdikt ableiten koennte. Die Zone "TrustAnchors" wird forestweit repliziert
        und nie bereinigt — ihre NS-Records erlauben keine Aussage ueber den Zustand
        der Umgebung. Deshalb wird nur ihre Existenz und die ANZAHL der NS-Records
        gemeldet, nicht deren Erreichbarkeit.

        Gibt $null zurueck, wenn weder die Zone noch Trust Points vorhanden sind.
    .PARAMETER Zone
        Die bereits abgerufene Zonenliste des Zielservers (Get-DnsServerZone).
    .PARAMETER CimArgs
        Splatting-Hashtable fuer -ComputerName (leer bei lokalem Zielserver).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Zone,

        [Parameter(Mandatory=$false)]
        [hashtable]$CimArgs = @{}
    )

    $taZone = @($Zone | Where-Object {
        $_ -and ("$($_.ZoneName)").Trim().ToLower() -eq $script:ADHCTrustAnchorZone
    }) | Select-Object -First 1

    # NS-Records nur zaehlen, nicht pruefen.
    $nsCount = 0
    if ($taZone) {
        $nsCount = @(Get-DnsServerResourceRecord @CimArgs -ZoneName $taZone.ZoneName -RRType "NS" -ErrorAction SilentlyContinue).Count
    }

    # Get-DnsServerTrustPoint existiert nicht auf jedem Server-Level — ein Fehler
    # hier darf den Zonenteil nicht verschlucken.
    $trustPoints = @()
    try {
        foreach ($tp in @(Get-DnsServerTrustPoint @CimArgs -ErrorAction Stop)) {
            $anchorCount = 0
            try {
                $anchorCount = @(Get-DnsServerTrustAnchor @CimArgs -Name $tp.TrustPointName -ErrorAction Stop).Count
            } catch {
                $anchorCount = 0
            }
            $trustPoints += [PSCustomObject]@{
                Name        = $tp.TrustPointName
                State       = $tp.TrustPointState
                AnchorCount = $anchorCount
            }
        }
    } catch {
        Write-ADHCLog -Message "Trust Points nicht abfragbar (nur informativ): $($_.Exception.Message)" -Component "DNS-Check"
    }

    if (-not $taZone -and $trustPoints.Count -eq 0) { return $null }

    return [PSCustomObject]@{
        ZonePresent      = [bool]$taZone
        ZoneName         = if ($taZone) { $taZone.ZoneName } else { $null }
        ZoneType         = if ($taZone) { $taZone.ZoneType } else { $null }
        IsADIntegrated   = if ($taZone) { ($taZone.ReplicationScope -ne "None") } else { $false }
        ReplicationScope = if ($taZone) { $taZone.ReplicationScope } else { $null }
        NSRecordCount    = $nsCount
        TrustPoints      = @($trustPoints)
    }
}

function Select-ADHCNameserverZone {
    <#
    .SYNOPSIS
        Filtert die Zonenliste auf jene Zonen, deren NS-Records tatsaechlich die
        Nameserver der eigenen AD-Umgebung beschreiben.
    .DESCRIPTION
        Nicht jede Zone auf einem DNS-Server trifft eine gueltige Aussage darueber,
        welche Nameserver die Umgebung betreibt. Ausgeschlossen werden:
          - TrustAnchors: forestweit replizierte DNSSEC-Systemzone. Ihre NS-Records
            werden nie bereinigt und listen auch laengst entfernte DCs auf, obwohl
            Get-DnsServerTrustPoint gar keine Trust Points meldet. Das erzeugte im
            Report Geister-Nameserver, die per ICMP/Dienst natuerlich "Fail" sind.
          - "." (Root Hints): NS zeigen auf die Internet-Rootserver.
          - 0/127/255.in-addr.arpa: automatisch angelegte Reverse-Systemzonen.
          - Stub- und Forwarder-Zonen: halten per Definition NS fremder Server.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Zone
    )

    $systemZones     = @($script:ADHCTrustAnchorZone, '.', '0.in-addr.arpa', '127.in-addr.arpa', '255.in-addr.arpa')
    $foreignZoneType = @('stub', 'forwarder')

    return @($Zone | Where-Object {
        $_ -and
        $systemZones     -notcontains ("$($_.ZoneName)").Trim().ToLower() -and
        $foreignZoneType -notcontains ("$($_.ZoneType)").Trim().ToLower()
    })
}

function Get-ADDNSHealthStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$TargetServer = $env:COMPUTERNAME
    )

    # Prüfen, ob DNS-Modul (RSAT) verfügbar ist
    if (-not (Get-Module -ListAvailable DNSServer)) {
        Write-ADHCLog -Message "FEHLER: DNS-Modul (RSAT) nicht installiert. DNS-Check wird übersprungen." -Level Error
        return $null
    }

    Write-ADHCLog -Message "Analysiere DNS Zonen und Server Status auf '$TargetServer'..." -Component "DNS-Check"

    # Lokalen Zielserver erkennen. Bei einem lokalen DC erzwingt -ComputerName mit dem
    # FQDN eine Remote-CIM-Sitzung ueber WinRM, die auf einem Single DC oft nicht
    # erreichbar ist. In dem Fall ohne -ComputerName arbeiten (lokale CIM-Sitzung).
    $localNames = @(
        $env:COMPUTERNAME,
        "$env:COMPUTERNAME.$env:USERDNSDOMAIN",
        'localhost', '.', '127.0.0.1'
    )
    $dnsCn = @{}
    if ($localNames -notcontains $TargetServer) {
        $dnsCn = @{ ComputerName = $TargetServer }
    }

    try {
        # Alle DNS Zonen vom Zielserver abrufen
        $allZones = Get-DnsServerZone @dnsCn -ErrorAction Stop
        
        # --- Forward Lookup Zonen aufbereiten ---
        # Die DNSSEC-Systemzone "TrustAnchors" bleibt aussen vor: sie wird separat
        # und rein informativ ausgegeben. Nur so bleibt sie aus TotalZoneCount,
        # DNSSEC- und Scavenging-Bewertung heraus, die alle aus Forward+Reverse
        # abgeleitet werden.
        $forwardZones = foreach ($zone in ($allZones | Where-Object {
            $_.ZoneType -ne "Forwarder" -and
            $_.IsReverseLookupZone -eq $false -and
            ("$($_.ZoneName)").Trim().ToLower() -ne $script:ADHCTrustAnchorZone
        })) {
            # Kombinierten Typ erstellen (z.B. Primary, AD-Integrated)
            $typeStr = if ($zone.ReplicationScope -ne "None") { 
                "$($zone.ZoneType), AD-Integrated" 
            } else { 
                $zone.ZoneType 
            }

            [PSCustomObject]@{
                ZoneName         = $zone.ZoneName
                FullType         = $typeStr
                ZoneType         = $zone.ZoneType
				IsADIntegrated   = ($zone.ReplicationScope -ne "None")
                ZoneStatus       = if ($zone.Paused) { "Stopped" } else { "Running" }
                ReplicationScope = $zone.ReplicationScope
                IsSigned         = $zone.IsSigned				
            }
        }

        # --- Reverse Lookup Zonen aufbereiten ---
        $reverseZones = foreach ($zone in ($allZones | Where-Object { $_.IsReverseLookupZone -eq $true })) {
            $typeStr = if ($zone.ReplicationScope -ne "None") { 
                "$($zone.ZoneType), AD-Integrated" 
            } else { 
                $zone.ZoneType 
            }

            [PSCustomObject]@{
                ZoneName         = $zone.ZoneName
                FullType         = $typeStr
				ZoneType         = $zone.ZoneType 
				IsADIntegrated   = ($zone.ReplicationScope -ne "None")
                ZoneStatus       = if ($zone.Paused) { "Stopped" } else { "Running" }
                ReplicationScope = $zone.ReplicationScope
                IsSigned         = $zone.IsSigned

            }
        }

        # Eindeutige Nameserver (NS) sammeln (Abfrage am TargetServer)
        # Nur Zonen heranziehen, die die eigenen Nameserver beschreiben. Ohne diesen
        # Filter landen u. a. die Eintraege der DNSSEC-Systemzone "TrustAnchors" im
        # Report — veraltete, laengst entfernte DCs, die dann als "Fail" erscheinen.
        $nsList = New-Object System.Collections.Generic.HashSet[string]
        foreach ($zone in (Select-ADHCNameserverZone -Zone $allZones)) {
            $nsRecords = Get-DnsServerResourceRecord @dnsCn -ZoneName $zone.ZoneName -RRType "NS" -ErrorAction SilentlyContinue
            foreach ($record in $nsRecords) {
                $name = $record.RecordData.NameServer.TrimEnd('.')
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    [void]$nsList.Add($name.ToLower())
                }
            }
        }

        # Trust Anchors rein informativ erfassen (keine Pruefung, kein Verdikt)
        $trustAnchorInfo = Get-ADHCTrustAnchorInfo -Zone $allZones -CimArgs $dnsCn

        # Status der Nameserver prüfen (inkl. IP-Auflösung)
        $serverStatus = @()
        foreach ($server in $nsList) {
            $ip = "-"
            $dnsService = "Stopped"
            $icmp = "Fail"

            # ICMP Prüfung (Ping an den gefundenen Nameserver)
            if (Test-Connection -ComputerName $server -Count 1 -Quiet) {
                $icmp = "OK"
                
                # --- IP AUFLÖSUNG FIX ---
                try {
                    # Versuch 1: System DNS Auflösung
                    $addr = [System.Net.Dns]::GetHostAddresses($server) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
                    if ($addr) { 
                        $ip = $addr.IPAddressToString 
                    }
                } catch {
                    # Versuch 2: Direkte Abfrage der Resource Records am TargetServer
                    foreach ($z in $forwardZones) {
                        $shortName = $server.Split('.')[0]
                        $aRecord = Get-DnsServerResourceRecord @dnsCn -ZoneName $z.ZoneName -Name $shortName -RRType A -ErrorAction SilentlyContinue
                        if ($aRecord) {
                            $ip = $aRecord.RecordData.IPv4Address.IPAddressToString
                            break
                        }
                    }
                }

                # --- REMOTE DIENST PRÜFUNG ---
                try {
                    $svc = Get-CimInstance -ComputerName $server -ClassName Win32_Service -Filter "Name = 'DNS'" -ErrorAction SilentlyContinue
                    if ($svc -and $svc.State -eq "Running") { 
                        $dnsService = "Running" 
                    } elseif ($svc) {
                        $dnsService = "Stopped"
                    } else {
                        $dnsService = "NotFound"
                    }
                } catch { 
                    $dnsService = "AccessDenied" 
                }
            }

            $serverStatus += [PSCustomObject]@{
                Name    = $server
                IP      = $ip
                Service = $dnsService
                ICMP    = $icmp
            }
        }
		
		# --- Quick Check: Scavenging Status ---
		# Fix: $allTestedZones (nur Forward+Reverse) statt $allZones (enthält Forwarder)
		# Konsistent mit TotalZoneCount in Reporting
		$zonesWithoutScavenging = @()
		$allTestedZones = @($forwardZones) + @($reverseZones)
		foreach ($zone in $allTestedZones) {
			if ($null -eq $zone.Aging -or $zone.Aging.AgingState -eq $false) {
				$zonesWithoutScavenging += $zone.ZoneName
			}
		}
		
		# --- Quick Check: Nameserver Erreichbarkeit ---
		$nsSummary = foreach ($ns in $serverStatus) {
			[PSCustomObject]@{
				Name   = $ns.Name
				Status = $ns.ICMP # "OK" oder "Fail"
			}
		}
		
		# --- Quick Check: AD SRV Validierung ---
		$srvResults = @()
		$dnsDomain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()).Name
		$srvChecks = @(
			@{ Key = "LDAP";     Query = "_ldap._tcp.dc._msdcs.$dnsDomain" },
			@{ Key = "Kerberos"; Query = "_kerberos._tcp.dc._msdcs.$dnsDomain" },
			@{ Key = "GC";       Query = "_gc._tcp.$dnsDomain" },
			@{ Key = "PDC";      Query = "_ldap._tcp.pdc._msdcs.$dnsDomain" }
		)
		
		foreach ($check in $srvChecks) {
			$status = "Critical"
			try {
				$lookup = Resolve-DnsName -Name $check.Query -Type SRV -Server $TargetServer -ErrorAction SilentlyContinue -DnsOnly
				if ($lookup -and ($lookup | Where-Object { $_.NameTarget -ne $null })) {
					$status = "OK"
				}
			} catch { $status = "Error" }
			
			$srvResults += [PSCustomObject]@{
				ServiceKey = $check.Key
				Status     = $status
			}
		}
		
		# Rückgabe-Objekt vervollständigen
		return [PSCustomObject]@{
			ForwardZones = $forwardZones
			ReverseZones = $reverseZones
			NSStatus     = $serverStatus
			TrustAnchors = $trustAnchorInfo
			QuickChecks  = @{
				NSCondition       = $nsSummary
				MissingScavenging  = $zonesWithoutScavenging
				TotalZoneCount     = $allTestedZones.Count
				SRVDetails        = $srvResults
			}
		}
    } catch {
        Write-ADHCLog -Message "Kritischer Fehler bei DNS Analyse auf ${TargetServer}: $($_.Exception.Message)" -Level Error
        return $null
    }
}

Export-ModuleMember -Function Get-ADDNSHealthStatus, Select-ADHCNameserverZone, Get-ADHCTrustAnchorInfo