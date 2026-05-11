# MODULE: ADHealthCheck.DNS.psm1

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
    
    try {
        # Alle DNS Zonen vom Zielserver abrufen
        $allZones = Get-DnsServerZone -ComputerName $TargetServer -ErrorAction Stop
        
        # --- Forward Lookup Zonen aufbereiten ---
        $forwardZones = foreach ($zone in ($allZones | Where-Object { $_.ZoneType -ne "Forwarder" -and $_.IsReverseLookupZone -eq $false })) {
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
        $nsList = New-Object System.Collections.Generic.HashSet[string]
        foreach ($zone in $allZones) {
            $nsRecords = Get-DnsServerResourceRecord -ComputerName $TargetServer -ZoneName $zone.ZoneName -RRType "NS" -ErrorAction SilentlyContinue
            foreach ($record in $nsRecords) {
                $name = $record.RecordData.NameServer.TrimEnd('.')
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    [void]$nsList.Add($name.ToLower())
                }
            }
        }

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
                        $aRecord = Get-DnsServerResourceRecord -ComputerName $TargetServer -ZoneName $z.ZoneName -Name $shortName -RRType A -ErrorAction SilentlyContinue
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

Export-ModuleMember -Function Get-ADDNSHealthStatus