# MODULE: ADHealthCheck.Diag.psm1

function Get-ADHCMockData {
    param($I18n, $Settings)
    Write-ADHCLog "Generiere Worst-Case Mock-Daten für Sample-Report..." -Component "Discovery"

    $mockDCs = @("MOCK-DC-01", "MOCK-DC-02")

    $mockData = @{
        # Domain Stats (WICHTIG: DomainName statt DomainFQDN und Zahlen für Levels)
        DomainStats = [PSCustomObject]@{
            DomainNetBIOS = "CONTOSO"
            DomainFQDN    = "contoso.local"
            ForestLevel   = 6
            DomainLevel   = 6
            RecycleBin    = $false
            KrbtgtLastSet = (Get-Date).AddDays(-400)
            UserCount = 1250; SecGroupCount = 300; DistGroupCount = 50; ContactCount = 10
        }

        # FSMO (Ein DC ist offline)
        FSMO = @(
            [PSCustomObject]@{ RoleID="PdcEmulator"; Role="PDC Emulator"; Owner="MOCK-DC-01"; Erreichbar="OK" }
            [PSCustomObject]@{ RoleID="InfrastructureMaster"; Role="Infrastructure Master"; Owner="MOCK-DC-02"; Erreichbar="Error" }
        )

        # DC Health (Wenig Speicherplatz)
        Discovery = @(
            [PSCustomObject]@{ Server="MOCK-DC-01"; OS="Windows Server 2019"; IPv4="10.0.0.1"; UptimeHrs=2400; FreeDiskGB=2; FreeDiskPct="2 %"; Status="Error" }
        )

        # DCDIAG (Alles Failed)
        DCDiag = @(
            [PSCustomObject]@{ Server="MOCK-DC-01"; Connectivity="Error"; Replications="Error"; Advertising="Error"; NetLogons="Error" }
        )

        # Services (Kritische Dienste gestoppt)
        Services = @(
            [PSCustomObject]@{ Server="MOCK-DC-01"; Service="NTDS"; Status="Error"; StartType="Automatic" }
            [PSCustomObject]@{ Server="MOCK-DC-01"; Service="DNS"; Status="Error"; StartType="Automatic" }
        )

        # Backup (Über 30 Tage alt)
        Backup = @(
            [PSCustomObject]@{ Partition="DC=contoso,DC=local"; LastBackup=(Get-Date).AddDays(-35).ToString(); Days=35; Status="Critical" }
        )

        # Sicherheit (Viele inaktive Accounts)
        Security = [PSCustomObject]@{
            InactiveUsers = 45; NoPwdExpiryUsers = 80; ExpiredPwdUsers = 12; DisabledUsers = 150
            DomAdminCount = 25; EntAdminCount = 10; SchAdminCount = 5
            Complexity = $false; MinPwdLength = 5; MaxPwdAge = 0; PwdHistory = 0
            LockoutThresh = 0; LockoutDuration = 0; RawExportData = @()
        }

        # OU & ACL Audit (Verwaiste SIDs gefunden)
        OUAccountSecurity = [PSCustomObject]@{
            UniqueOrphanCount = 51
            TopOrphanedSIDs = @([PSCustomObject]@{ Name="S-1-5-21-999-888-777-512"; Count=2400 })
            DisabledInheritanceOU = @([PSCustomObject]@{ Name="Admins"; DN="OU=Admins,DC=contoso,DC=local" })
            DisabledInheritanceUser = foreach($i in 1..15) { [PSCustomObject]@{ Name="User_$i"; DN="CN=User_$i,DC=contoso" } }
        }

        # Entra ID (Version veraltet)
        Entra = [PSCustomObject]@{
            Server           = "SRVAPP02 (MOCK)"
            InstalledVersion = "1.1.0.0" # Veraltet
            ExpectedVersion  = $Settings.EntraID.ExpectedAgentVersion
            FoundAnyService  = $true
            ServiceDetails   = @(
                [PSCustomObject]@{ Name = "Microsoft Entra Connect Sync"; Status = "Stopped" }
            )
        }

        # DNS Health (Fehlerhaft)
        DNS = @()
    }

    # Dummy Export Daten generieren
    for ($i=1; $i -le 10; $i++) {
        $mockData.Security.RawExportData += [PSCustomObject]@{
            "Nachname" = "Mustermann_$i"; "Vorname" = "Max"; "UPN" = "max$i@contoso.local"; "Aktiv" = "Ja"; "Grund" = "Inaktiv"
        }
    }

    return $mockData
}

function Get-ADHealthDiscovery {
    [CmdletBinding()]
    param([string[]]$DCList, $Settings)

    $results = @()
    foreach ($dc in $DCList) {
        Write-ADHCLog -Message "Analysiere DC: $dc" -Component "Discovery"
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ComputerName $dc -ErrorAction Stop
            $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ComputerName $dc -ErrorAction Stop
            
            $freePct = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)
            $status = "OK"
            if ($freePct -lt $Settings.Thresholds.DiskFreePercentCritical) { $status = "Error" }
            elseif ($freePct -lt $Settings.Thresholds.DiskFreePercentWarning) { $status = "Warning" }

            $ip = "N/A"
            if (Test-Connection $dc -Count 1 -Quiet) {
                $ping = Test-Connection $dc -Count 1 -ErrorAction SilentlyContinue
                if ($ping) { $ip = $ping.IPv4Address.ToString() }
            }

            $results += [PSCustomObject]@{
                Server      = $dc
                OS          = $os.Caption
                IPv4        = $ip
                UptimeHrs   = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
                FreeDiskGB  = [math]::Round($disk.FreeSpace / 1GB, 2)
                FreeDiskPct = "$freePct %"
                Status      = $status
            }
        } catch {
            Write-ADHCLog -Message "Verbindung zu $dc fehlgeschlagen: $_" -Level Error -Component "Discovery"
            $results += [PSCustomObject]@{ Server=$dc; Status="Error"; OS="Unreachable"; IPv4="-"; UptimeHrs="-"; FreeDiskGB="-"; FreeDiskPct="-" }
        }
    }
    return $results
}

function Get-ADServiceStatus {
    param($DCList)
    $servicesToCheck = "NTDS", "Netlogon", "DNS", "Kdc" 
    $res = @()
    foreach ($dc in $DCList) {
        try {
            $svcs = Get-Service -ComputerName $dc -Name $servicesToCheck -ErrorAction SilentlyContinue
            foreach ($s in $svcs) {
                $status = if ($s.Status -eq "Running") { "OK" } else { "Error" }
                $res += [PSCustomObject]@{
                    Server = $dc
                    Service = $s.Name
                    Status = $status
                    StartType = $s.StartType
                }
            }
        } catch {
            $res += [PSCustomObject]@{ Server=$dc; Service="Check Failed"; Status="Error"; StartType="-" }
        }
    }
    return $res
}

function Invoke-DetailedDcdiag {
    param([string[]]$DCList)
    $testsToRun = @(
        "Connectivity", "Advertising", "FrsEvent", "DFSREvent", "SysVolCheck", 
        "KccEvent", "KnowsOfRoleHolders", "MachineAccount", "NCSecDesc", 
        "NetLogons", "ObjectsReplicated", "Replications", "RidManager", 
        "Services", "SystemLog", "VerifyReferences", "CheckSDRefDom", 
        "CrossRefValidation", "LocatorCheck", "Intersite", "FsmoCheck"
    )

    $matrixResults = @()

    foreach ($dc in $DCList) {
        Write-ADHCLog -Message "Führe DCDIAG Checks auf $dc aus..." -Component "DCDIAG"
        $serverResult = [ordered]@{ Server = $dc }
        foreach ($t in $testsToRun) { $serverResult[$t] = "Unknown" }

        try {
            $argsList = "/s:$dc"
            foreach ($t in $testsToRun) { $argsList += " /test:$t" }
            
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = "dcdiag.exe"
            $pinfo.Arguments = $argsList
            $pinfo.RedirectStandardOutput = $true
            $pinfo.UseShellExecute = $false
            $pinfo.CreateNoWindow = $true
            $p = New-Object System.Diagnostics.Process
            $p.StartInfo = $pinfo
            $p.Start() | Out-Null
            $output = $p.StandardOutput.ReadToEnd()
            $p.WaitForExit()

            $lines = $output -split "`r`n"
            foreach ($line in $lines) {
                if ($line -match "passed test\s+(?<TestName>\w+)") {
                    $tName = $Matches.TestName
                    if ($serverResult.Contains($tName)) { $serverResult[$tName] = "OK" }
                }
                elseif ($line -match "failed test\s+(?<TestName>\w+)") {
                    $tName = $Matches.TestName
                    if ($serverResult.Contains($tName)) { $serverResult[$tName] = "Error" }
                }
            }
            if ($serverResult["Connectivity"] -eq "Unknown") {
                 if ($output -match "$dc failed test Connectivity") { $serverResult["Connectivity"] = "Error" }
                 elseif ($output -match "$dc passed test Connectivity") { $serverResult["Connectivity"] = "OK" }
            }
        } catch {
            Write-ADHCLog "Fehler bei DCDIAG auf ${dc}: $_" -Level Error
            foreach ($t in $testsToRun) { $serverResult[$t] = "Error" }
        }
        $matrixResults += [PSCustomObject]$serverResult
    }
    return $matrixResults
}

function Get-ADFSMORoles {
    param($I18n)
    try {
        $domain = Get-ADDomain
        $forest = Get-ADForest
        
        # Rollen-Mapping mit festen IDs für die Logik
        $rolesMapping = @(
            @{ ID = "SchemaMaster";          Name = $I18n.Labels.SchemaMaster;         Owner = $forest.SchemaMaster },
            @{ ID = "DomainNamingMaster";    Name = $I18n.Labels.DomainNamingMaster;   Owner = $forest.DomainNamingMaster },
            @{ ID = "PdcEmulator";           Name = $I18n.Labels.PdcEmulator;          Owner = $domain.PDCEmulator },
            @{ ID = "RidMaster";             Name = $I18n.Labels.RidMaster;           Owner = $domain.RIDMaster },
            @{ ID = "InfrastructureMaster";  Name = $I18n.Labels.InfrastructureMaster; Owner = $domain.InfrastructureMaster }
        )

        $roles = @()
        foreach ($r in $rolesMapping) {
            $pingSuccess = Test-Connection -ComputerName $r.Owner -Count 1 -Quiet
            $status = if ($pingSuccess) { "OK" } else { "Error" }

            $roles += [PSCustomObject]@{ 
                RoleID     = $r.ID   # Interner Key für Recommendations
                Role       = $r.Name # Anzeigename (lokalisiert)
                Owner      = $r.Owner
                Erreichbar = $status 
            }
        }
        return $roles
    } catch {
        Write-ADHCLog "Fehler beim Abrufen der FSMO Rollen: $_" -Level Error
        return @()
    }
}

# DEBUG
#function Get-ADFSMORoles {
#    param($I18n)
#    try {
#        $domain = Get-ADDomain
#        $forest = Get-ADForest
#        
#        $rolesMapping = @(
#            @{ ID = "SchemaMaster";          Name = $I18n.Labels.SchemaMaster;         Owner = $forest.SchemaMaster },
#            @{ ID = "DomainNamingMaster";    Name = $I18n.Labels.DomainNamingMaster;   Owner = $forest.DomainNamingMaster },
#            @{ ID = "PdcEmulator";           Name = $I18n.Labels.PdcEmulator;          Owner = $domain.PDCEmulator },
#            @{ ID = "RidMaster";             Name = $I18n.Labels.RidMaster;           Owner = $domain.RIDMaster },
#            @{ ID = "InfrastructureMaster";  Name = $I18n.Labels.InfrastructureMaster; Owner = $domain.InfrastructureMaster }
#        )
#
#        $roles = @()
#        foreach ($r in $rolesMapping) {
#            # --- START SIMULATION ---
#            if ($r.ID -eq "InfrastructureMaster") {
#                Write-ADHCLog "DEBUG-SIMULATION: Setze $($r.Name) künstlich auf ERROR!" -Level Warning
#                $status = "Error"
#            } else {
#                # Echter Check für alle anderen
#                $pingSuccess = Test-Connection -ComputerName $r.Owner -Count 1 -Quiet
#                $status = if ($pingSuccess) { "OK" } else { "Error" }
#            }
#            # --- ENDE SIMULATION ---
#
#            $roles += [PSCustomObject]@{ 
#                RoleID     = $r.ID
#                Role       = $r.Name
#                Owner      = $r.Owner
#                Erreichbar = $status 
#            }
#        }
#        return $roles
#    } catch {
#        Write-ADHCLog "Fehler beim Abrufen der FSMO Rollen: $_" -Level Error
#        return @()
#    }
#}

function Get-ADDomainStats {
    Write-ADHCLog -Message "Sammle Domain-Statistiken..." -Component "Discovery"
    try {
        $domain = Get-ADDomain
        $forest = Get-ADForest
        
        # --- KRBTGT CHECK (NEU) ---
        $krbtgtUser = Get-ADUser "krbtgt" -Properties PasswordLastSet -ErrorAction SilentlyContinue
        $krbtgtDate = if ($krbtgtUser) { $krbtgtUser.PasswordLastSet } else { $null }
        # --------------------------

        # Recycle Bin Logik
        $isRecycleBinEnabled = $false
        
        # Wir suchen gezielt nach dem Feature und laden die EnabledScopes explizit
        $rbFeature = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'" -ErrorAction SilentlyContinue
        
        if ($rbFeature -and $rbFeature.EnabledScopes) {
            # WICHTIG: EnabledScopes kann eine Liste von Distinguished Names sein.
            # Wir prüfen, ob der DN des Forest (oder der Partition) in den Scopes enthalten ist.
            foreach ($scope in $rbFeature.EnabledScopes) {
                # Manche Umgebungen geben Objekte zurück, andere Strings. Wir erzwingen String-Vergleich.
                $scopeStr = "$scope" 
                if ($scopeStr -eq $forest.DistinguishedName -or $scopeStr -match $forest.DistinguishedName) {
                    $isRecycleBinEnabled = $true
                    break
                }
            }
        }

        $userCount = (Get-ADUser -Filter * -ResultPageSize 1000).Count
        $secGroupCount = (Get-ADGroup -Filter "GroupCategory -eq 'Security'" -ResultPageSize 1000).Count
        $distGroupCount = (Get-ADGroup -Filter "GroupCategory -eq 'Distribution'" -ResultPageSize 1000).Count
        $contactCount = (Get-ADObject -LDAPFilter "(objectClass=contact)" -ResultPageSize 1000).Count

        return [PSCustomObject]@{
            DomainNetBIOS   = $domain.Name
            DomainFQDN      = $domain.DNSRoot
            ForestLevel     = $forest.ForestMode
            DomainLevel     = $domain.DomainMode
            RecycleBin      = $isRecycleBinEnabled
            KrbtgtLastSet   = $krbtgtDate
            UserCount       = $userCount
            SecGroupCount   = $secGroupCount
            DistGroupCount  = $distGroupCount
            ContactCount    = $contactCount
        }
    } catch {
        Write-ADHCLog "Fehler bei Domain Statistiken: $_" -Level Error
        return $null
    }
}

function Get-ADSitesInfo {
    Write-ADHCLog -Message "Sammle Sites & Services Informationen..." -Component "Discovery"
    try {
        $configNC = (Get-ADRootDSE).ConfigurationNamingContext
        
        # 1. Site Links
        $transports = @()
		$siteLinks = Get-ADObject -SearchBase ("CN=Sites," + $configNC) -Filter "objectClass -eq 'siteLink'" -Properties description,cost,replInterval,options
        
        foreach ($link in $siteLinks) {
		$transports += [PSCustomObject]@{
			Name = $link.Name
			Type = "Site Link"
			Description = if ($link.description) { $link.description } else { "-" }
			Cost = if ($link.cost) { $link.cost } else { "Default" }
			ReplInterval = if ($link.replInterval) { $link.replInterval } else { "Default" }
			# NEU: Change Notification Status ermitteln (Bit 1 gesetzt = Enabled)
			ChangeNotification = if ($link.options -band 1) { "Enabled" } else { "Disabled" }
			}
		}

        # 2. Subnets
        $rawSubnets = Get-ADReplicationSubnet -Filter * -Properties Site
        $subnets = @()
        foreach ($sub in $rawSubnets) {
            $siteName = "-"
            if ($sub.Site) {
                if ($sub.Site -is [string]) {
                    $siteName = ($sub.Site -split ",")[0].Replace("CN=","")
                } elseif ($sub.Site.Name) {
                    $siteName = $sub.Site.Name
                }
            }
            
            $subnets += [PSCustomObject]@{
                Name = $sub.Name
                Site = $siteName
            }
        }

        # 3. Sites, Servers & Connections
        $allDCs = Get-ADDomainController -Filter *
        $sitesData = @()
        
        # Get-ADReplicationSite MUSS separat stehen  
        $sites = Get-ADReplicationSite -Filter *
        
        foreach ($site in $sites) {
            
            $serverObjs = Get-ADObject -SearchBase $site.DistinguishedName -Filter "objectClass -eq 'server'"
            
            $serverList = @()
            $connections = @()

            foreach ($srv in $serverObjs) {
                $dcInfo = $allDCs | Where-Object { $_.Name -eq $srv.Name }
                $isGC = if ($dcInfo) { $dcInfo.IsGlobalCatalog } else { "Unknown" }
                
                $serverList += [PSCustomObject]@{
                    Name = $srv.Name
                    IsGC = $isGC
                }

                # Connections finden
                try {
                    $rawLinks = Get-ADObject -SearchBase $srv.DistinguishedName -SearchScope Subtree -Filter "objectClass -eq 'nTDSConnection'" -Properties fromServer, options, enabledConnection
                    
                    foreach ($l in $rawLinks) {
                        $sourceName = "Unknown"
                        if ($l.fromServer) {
                            $parts = $l.fromServer -split ","
                            if ($parts.Count -gt 1) {
                                $sourceName = $parts[1].Replace("CN=","")
                            }
                        }
                        
                        $connStatus = if ($l.enabledConnection -eq $false) { "Disabled" } else { "Enabled" }

                        $connections += [PSCustomObject]@{
                            Source = $sourceName
                            Transport = "IP"
                            Enabled = $connStatus
                            DestinationServer = $srv.Name
                        }
                    }
                } catch {
                     Write-ADHCLog "Fehler bei Connections für $($srv.Name): $_" -Level Debug
                }
            }

            $sitesData += [PSCustomObject]@{
                Name = $site.Name
                Servers = $serverList
                Connections = $connections
            }
        }

        return [PSCustomObject]@{
            Transports = $transports
            Subnets = $subnets
            Sites = $sitesData
        }

    } catch {
        Write-ADHCLog "Fehler bei Sites & Services: $_" -Level Error
        return $null
    }
}

function Get-ADBackupStatus {
    Write-ADHCLog -Message "Analysiere AD Backup Status..." -Component "Discovery"
    try {
        $rootDSE = Get-ADRootDSE
        $partitions = $rootDSE.namingContexts
        $results = @()
        $dc = $rootDSE.dnsHostName

        foreach ($partition in $partitions) {
            $metadata = Get-ADReplicationAttributeMetadata -Object $partition -Server $dc | 
                        Where-Object { $_.AttributeName -eq "dsaSignature" }

            $lastBackup = if ($metadata) { $metadata.LastOriginatingChangeTime } else { $null }
            
            $days = 0
            $hours = 0
            $status = "OK"

            if ($null -ne $lastBackup) {
                $diff = (Get-Date) - $lastBackup
                $days = [math]::Floor($diff.TotalDays)
                $hours = $diff.Hours

                if ($diff.TotalDays -lt 1) { $status = "OK" }
                elseif ($diff.TotalDays -le 7) { $status = "Warning" }
                else { $status = "Critical" }
            } else {
                $status = "Error"
            }

            $results += [PSCustomObject]@{
                Partition  = $partition
                LastBackup = if ($lastBackup) { $lastBackup.ToString("dd.MM.yyyy HH:mm") } else { $null }
                Days       = $days
                Hours      = $hours
                Status     = $status
            }
        }
        return $results
    } catch {
        Write-ADHCLog "Fehler beim AD Backup Check: $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Get-ADSecurityInfo {
    param(
        $Settings,
        $I18n,
        [string]$LangCode = "de"
    )
    # AUFRUF (ADHealthCheck.ps1) muss lauten:
    #   Get-ADSecurityInfo -Settings $Settings -I18n $I18n -LangCode $LangCode

    Write-ADHCLog -Message "Analysiere Sicherheit & bereite Export-Listen vor..." -Component "Discovery"

    try {
        # 1. Kennwortrichtlinien auslesen
        $pwdPolicy = Get-ADDefaultDomainPasswordPolicy
        $maxAgeDays = $pwdPolicy.MaxPasswordAge.Days
        $thresholdDays = if ($Settings.Thresholds.InactiveAccountDays) { $Settings.Thresholds.InactiveAccountDays } else { 90 }
        
        $now = Get-Date
        $cutoffDateInactive = $now.AddDays(-$thresholdDays)
        $cutoffDatePwdExpired = $now.AddDays(-$maxAgeDays)
		
		$lockoutDurationMins = [int]$pwdPolicy.LockoutDuration.TotalMinutes
        $resetCountMins      = [int]$pwdPolicy.LockoutObservationWindow.TotalMinutes

        # 2. Alle User laden
        $allUsers = Get-ADUser -Filter * -Properties LastLogonDate, PasswordNeverExpires, PasswordLastSet, WhenCreated, Enabled, GivenName, Surname, UserPrincipalName

        # Export-Liste initialisieren
        $rawExport = New-Object System.Collections.Generic.List[PSObject]

        # --- Filterung & Zählung ---
        
        # Inaktive Konten
        $listInactive = $allUsers | Where-Object { 
            $_.Enabled -eq $true -and (
                ($_.LastLogonDate -lt $cutoffDateInactive -and $_.LastLogonDate -ne $null) -or 
                ($_.LastLogonDate -eq $null -and $_.WhenCreated -lt $cutoffDateInactive)
            )
        }
        
        # Ohne Passwortablauf
        $listNoExpiry = $allUsers | Where-Object { $_.Enabled -eq $true -and $_.PasswordNeverExpires -eq $true }
        
        # Passwort älter als Richtlinie
        $listExpired = $allUsers | Where-Object {
            $_.Enabled -eq $true -and $_.PasswordNeverExpires -eq $false -and $_.PasswordLastSet -ne $null -and $_.PasswordLastSet -lt $cutoffDatePwdExpired
        }

        # Deaktivierte Konten
        $listDisabled = $allUsers | Where-Object { $_.Enabled -eq $false }

        # Hilfsfunktion zum Befüllen der Export-Liste (Vermeidung von AddRange-Fehlern)
        function Add-ToExport {
			param($SourceList, $Reason)
			
			# Header-Namen sicherstellen
			$hSurname    = if ($I18n.CsvHeaders.Surname) { $I18n.CsvHeaders.Surname } else { "Nachname" }
			$hGivenName  = if ($I18n.CsvHeaders.GivenName) { $I18n.CsvHeaders.GivenName } else { "Vorname" }
			$hUPN        = if ($I18n.CsvHeaders.UPN) { $I18n.CsvHeaders.UPN } else { "UPN" }
			$hActive     = if ($I18n.CsvHeaders.Active) { $I18n.CsvHeaders.Active } else { "Aktiv" }
			$hLastLogin  = if ($I18n.CsvHeaders.LastLogin) { $I18n.CsvHeaders.LastLogin } else { "LetzterLogin" }
			$hPwdSet     = if ($I18n.CsvHeaders.PasswordSet) { $I18n.CsvHeaders.PasswordSet } else { "PasswortGesetzt" }
			$hPwdNever   = if ($I18n.CsvHeaders.PasswordNeverExpires) { $I18n.CsvHeaders.PasswordNeverExpires } else { "PasswortNieAblauf" }
			$hReason     = if ($I18n.CsvHeaders.Reason) { $I18n.CsvHeaders.Reason } else { "Grund" }
		
			$txtJa   = if ($LangCode -eq "de") { "Ja" } else { "Yes" }
			$txtNein = if ($LangCode -eq "de") { "Nein" } else { "No" }
		
			foreach ($u in $SourceList) {
				$isActive   = if ($u.Enabled) { $txtJa } else { $txtNein }
				$isNeverExp = if ($u.PasswordNeverExpires) { $txtJa } else { $txtNein }
		
				# Erstellung des Objekts
				$obj = [PSCustomObject]@{
					$hSurname  = $u.Surname
					$hGivenName = $u.GivenName
					$hUPN       = $u.UserPrincipalName
					$hActive    = $isActive
					$hLastLogin = $u.LastLogonDate
					$hPwdSet    = $u.PasswordLastSet
					$hPwdNever  = $isNeverExp
					$hReason    = $Reason # Der Wert aus dem Parameter wird hier gesetzt
				}
				$rawExport.Add($obj)
			}
		}

        # Daten in den Export schreiben
		# Inaktive Konten
		$reasonInactive = if ($I18n.Reasons.Inactive) { $I18n.Reasons.Inactive -f $thresholdDays } else { "Inaktiv (> $thresholdDays Tage)" }
		Add-ToExport -SourceList $listInactive -Reason $reasonInactive
		
		# Passwort läuft nie ab
		$reasonNoExpiry = if ($I18n.Reasons.NoExpiry) { $I18n.Reasons.NoExpiry } else { "Passwort läuft nie ab" }
		Add-ToExport -SourceList $listNoExpiry -Reason $reasonNoExpiry
		
		# Passwort abgelaufen
		$reasonExpired = if ($I18n.Reasons.Expired) { $I18n.Reasons.Expired } else { "Passwort älter als Richtlinie" }
		Add-ToExport -SourceList $listExpired -Reason $reasonExpired
		
		# Deaktivierte Konten
		$reasonDisabled = if ($I18n.Reasons.Disabled) { $I18n.Reasons.Disabled } else { "Konto deaktiviert" }
		Add-ToExport -SourceList $listDisabled -Reason $reasonDisabled

        # --- Privilegierte Gruppen (via dynamischer SID) ---
        $domSID = (Get-ADDomain).DomainSID.Value
        $groupsToCheck = @(
            @{ Name = "DomAdmin"; SID = "$domSID-512" },
            @{ Name = "EntAdmin"; SID = "$domSID-519" },
            @{ Name = "SchAdmin"; SID = "$domSID-518" }
        )

        $groupResults = @{}
        foreach ($g in $groupsToCheck) {
            $groupObj = Get-ADGroup -Identity $g.SID -ErrorAction SilentlyContinue
            if ($groupObj) {
                $members = Get-ADUser -Filter "MemberOf -RecursiveMatch '$($groupObj.DistinguishedName)'" -Properties GivenName, Surname, UserPrincipalName, LastLogonDate, PasswordLastSet, PasswordNeverExpires, Enabled
                Add-ToExport -SourceList $members -Reason "Mitglied: $($groupObj.Name)"
                $groupResults[$g.Name] = @{ Name = $groupObj.Name; Count = ($members.Count) }
            } else {
                $groupResults[$g.Name] = @{ Name = "Nicht gefunden"; Count = 0 }
            }
        }

        # 3. Das finale Objekt für den Report zusammenbauen
        return [PSCustomObject]@{
            Complexity              = $pwdPolicy.ComplexityEnabled
            MinPwdLength            = $pwdPolicy.MinPasswordLength
            MinPwdAge               = $pwdPolicy.MinPasswordAge.Days
            MaxPwdAge               = $maxAgeDays
            PwdHistory              = $pwdPolicy.PasswordHistoryCount
            LockoutThresh           = $pwdPolicy.LockoutThreshold
			LockoutDuration         = [int]$pwdPolicy.LockoutDuration.TotalMinutes
			ResetLockoutCount       = [int]$pwdPolicy.LockoutObservationWindow.TotalMinutes
            InactiveThresholdDays   = $thresholdDays
            InactiveUsers           = ($listInactive.Count)
            DisabledUsers           = ($listDisabled.Count)
            NoPwdExpiryUsers        = ($listNoExpiry.Count)
            ExpiredPwdUsers         = ($listExpired.Count)
            
            DomAdminName            = $groupResults["DomAdmin"].Name
            DomAdminCount           = $groupResults["DomAdmin"].Count
            EntAdminName            = $groupResults["EntAdmin"].Name
            EntAdminCount           = $groupResults["EntAdmin"].Count
            SchAdminName            = $groupResults["SchAdmin"].Name
            SchAdminCount           = $groupResults["SchAdmin"].Count
            
            RawExportData           = $rawExport
        }
    } catch {
        Write-ADHCLog "Fehler bei der Sicherheitsanalyse: $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Get-ADOUAndAccountSecurity {
    param(
        $Settings,
        # Optionaler Callback: scriptblock { param($current, $total, $message) }
        # Wird aus der GUI aufgerufen um den Fortschritt anzuzeigen, ohne den UI-Thread zu blockieren.
        [scriptblock]$ProgressCallback = $null
    )
    Write-ADHCLog "Analysiere ACLs auf echte verwaiste SIDs und Vererbung (async)..." -Component "Discovery"

    # ---------------------------------------------------------------------------
    # Synchronized Hashtable: Thread-sicherer Kanal zwischen Runspace und UI-Thread
    # ---------------------------------------------------------------------------
    $syncHash = [hashtable]::Synchronized(@{
        Progress  = 0       # Aktueller Fortschritt (Anzahl verarbeiteter Objekte)
        Total     = 0       # Gesamtanzahl Objekte (wird vom Runspace gesetzt)
        Message   = ""      # Aktuelles Status-Label
        Done      = $false  # Runspace signalisiert Fertigstellung
        Error     = $null   # Fehlertext falls Exception im Runspace
        Result    = $null   # Rückgabeobjekt des Runspace
    })

    # ---------------------------------------------------------------------------
    # ScriptBlock der im Hintergrund-Runspace läuft
    # ---------------------------------------------------------------------------
    $scriptBlock = {
        param($syncHash)

        try {
            # Well-Known SID Prefixes (im Runspace lokal definiert, da kein Scope-Zugriff)
            $wellKnownPrefixes = @(
                "S-1-1-0", "S-1-3-0", "S-1-3-1",
                "S-1-5-1", "S-1-5-2", "S-1-5-3", "S-1-5-4",
                "S-1-5-6", "S-1-5-7", "S-1-5-9", "S-1-5-10",
                "S-1-5-11","S-1-5-12","S-1-5-13","S-1-5-18",
                "S-1-5-19","S-1-5-20","S-1-5-32-"
            )

            function Is-OrphanedSID {
                param($sidRef)
                $sidValue = $sidRef.Value
                foreach ($prefix in $wellKnownPrefixes) {
                    if ($sidValue -eq $prefix -or $sidValue.StartsWith($prefix)) { return $false }
                }
                try {
                    $null = $sidRef.Translate([System.Security.Principal.NTAccount])
                    return $false
                } catch {
                    return $true
                }
            }

            # AD-Objekte laden
            $syncHash.Message = "Lade AD-Objekte..."
            $allObjects = @(Get-ADOrganizationalUnit -Filter * -Properties nTSecurityDescriptor, Name, ObjectClass) +
                          @(Get-ADUser -Filter 'Enabled -eq $true'  -Properties nTSecurityDescriptor, Name, ObjectClass)

            $syncHash.Total   = $allObjects.Count
            $syncHash.Message = "Analysiere ACLs ($($allObjects.Count) Objekte)..."

            # Ergebnis-Listen als threadsichere generische Listen
            $orphanedSIDs          = New-Object System.Collections.Generic.List[PSObject]
            $disabledInheritanceOU = New-Object System.Collections.Generic.List[PSObject]
            $disabledInheritanceUser = New-Object System.Collections.Generic.List[PSObject]

            $i = 0
            foreach ($obj in $allObjects) {
                $i++
                $syncHash.Progress = $i

                $acl = $obj.nTSecurityDescriptor
                if ($null -eq $acl) { continue }

                # Vererbung prüfen
                if ($acl.AreAccessRulesProtected) {
                    $lite = [PSCustomObject]@{ Name = $obj.Name; DN = $obj.DistinguishedName }
                    if ($obj.ObjectClass -eq "organizationalUnit") { $disabledInheritanceOU.Add($lite) }
                    else { $disabledInheritanceUser.Add($lite) }
                }

                # SIDs prüfen (nur explizite Regeln)
                $rules = $acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier])
                foreach ($rule in $rules) {
                    if (Is-OrphanedSID -sidRef $rule.IdentityReference) {
                        $orphanedSIDs.Add([PSCustomObject]@{
                            ObjectName = $obj.Name
                            SID        = $rule.IdentityReference.Value
                        })
                    }
                }
            }

            $uniqueSIDs = $orphanedSIDs | Select-Object -ExpandProperty SID -Unique

            $syncHash.Result = [PSCustomObject]@{
                TotalOrphanCount        = $orphanedSIDs.Count
                UniqueOrphanCount       = @($uniqueSIDs).Count
                TopOrphanedSIDs         = ($orphanedSIDs | Group-Object SID | Sort-Object Count -Descending | Select-Object -First 10)
                DisabledInheritanceOU   = $disabledInheritanceOU
                DisabledInheritanceUser = $disabledInheritanceUser
            }
        } catch {
            $syncHash.Error = $_.Exception.Message
        } finally {
            $syncHash.Done = $true
        }
    }

    # ---------------------------------------------------------------------------
    # Runspace starten
    # ---------------------------------------------------------------------------
    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions  = "ReuseThread"
    $runspace.Open()

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $runspace
    $ps.AddScript($scriptBlock).AddArgument($syncHash) | Out-Null

    $asyncHandle = $ps.BeginInvoke()
    Write-ADHCLog "ACL-Analyse läuft im Hintergrund-Runspace..." -Component "Discovery"

    # ---------------------------------------------------------------------------
    # UI-Thread: Polling-Schleife — GUI bleibt responsive
    # Ruft den optionalen ProgressCallback auf, damit die aufrufende GUI
    # einen Fortschrittsbalken oder Label aktualisieren kann.
    # ---------------------------------------------------------------------------
    while (-not $syncHash.Done) {
        if ($ProgressCallback) {
            try {
                & $ProgressCallback $syncHash.Progress $syncHash.Total $syncHash.Message
            } catch { <# Callback-Fehler dürfen die Analyse nicht stoppen #> }
        }
        # GUI-Pump: Windows.Forms-Events verarbeiten (verhindert "Nicht reagiert")
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 200
    }

    # ---------------------------------------------------------------------------
    # Aufräumen
    # ---------------------------------------------------------------------------
    $ps.EndInvoke($asyncHandle) | Out-Null
    $ps.Dispose()
    $runspace.Close()
    $runspace.Dispose()

    # Fehlerbehandlung aus dem Runspace
    if ($syncHash.Error) {
        Write-ADHCLog "Fehler in ACL-Analyse (Runspace): $($syncHash.Error)" -Level Error
        return $null
    }

    Write-ADHCLog "ACL-Analyse abgeschlossen. $($syncHash.Result.TotalOrphanCount) Orphan-Einträge gefunden." -Component "Discovery"
    return $syncHash.Result
}

Export-ModuleMember -Function Get-ADHealthDiscovery, Get-ADServiceStatus, Invoke-DetailedDcdiag, Get-ADSecurityInfo, Get-ADFSMORoles, Get-ADDomainStats, Get-ADSitesInfo, Get-ADBackupStatus, Get-ADOUAndAccountSecurity, Get-ADHCMockData