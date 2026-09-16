# MODULE: ADHealthCheck.Diag.psm1

function Get-ADHCMockData {
    param($I18n, $Settings, [string]$LangCode = "de")
    Write-ADHCLog "Generiere Worst-Case Mock-Daten fuer Sample-Report (alle Empfehlungen aktiv)..." -Component "Discovery"

    # -----------------------------------------------------------------------
    # DOMAIN STATS
    # Ausgeloeste Regeln:
    #   AD-01: ForestLevel = 5 (< 7 = Windows2016) -> Low
    #   AD-02: DomainLevel = 5 (< 7)               -> Low
    #   AD-03: RecycleBin  = $false                 -> High
    #   AD-04: KrbtgtLastSet vor 400 Tagen          -> High
    # -----------------------------------------------------------------------
    $domainStats = [PSCustomObject]@{
        DomainNetBIOS  = "CONTOSO"
        DomainFQDN     = "contoso.local"
        ForestLevel    = 5           # Windows2012R2 -> triggert AD-01
        DomainLevel    = 5           # Windows2012R2 -> triggert AD-02
        RecycleBin     = $false      # Deaktiviert   -> triggert AD-03
        KrbtgtLastSet  = (Get-Date).AddDays(-400)  # > 180 Tage -> triggert AD-04
        UserCount      = 1250
        SecGroupCount  = 300
        DistGroupCount = 50
        ContactCount   = 10
        # U3/AD-FSMO-07: Single-Domain-Gesamtstruktur -- die verteilten FSMO-Rollen
        # unten (3 DCs) sollen im Mock weiterhin AD-FSMO-07 ausloesen.
        DomainCount    = 1
    }

    # -----------------------------------------------------------------------
    # FSMO ROLLEN
    # Ausgeloeste Regeln:
    #   AD-FSMO-01..05: Alle 5 Rollen auf verschiedenen DCs -> mehrere Error
    #   AD-FSMO-06: Schema != NamingMaster (verschiedene DCs) -> Low
    #   AD-FSMO-07: Rollen verteilt auf 3 DCs -> Low
    #   AD-FSMO-08: InfraMaster ist GC und RecycleBin=false -> High
    # -----------------------------------------------------------------------
    $fsmoData = @(
        [PSCustomObject]@{ RoleID="SchemaMaster";         Role="Schema-Master";              Owner="MOCK-DC-01"; Erreichbar="Error" }
        [PSCustomObject]@{ RoleID="DomainNamingMaster";   Role="Domaenenbenennungs-Master";  Owner="MOCK-DC-02"; Erreichbar="Error" }
        [PSCustomObject]@{ RoleID="PdcEmulator";          Role="PDC-Emulator";               Owner="MOCK-DC-01"; Erreichbar="Error" }
        [PSCustomObject]@{ RoleID="RidMaster";            Role="RID-Master";                 Owner="MOCK-DC-02"; Erreichbar="Error" }
        [PSCustomObject]@{ RoleID="InfrastructureMaster"; Role="Infrastruktur-Master";       Owner="MOCK-DC-03"; Erreichbar="Error" }
    )

    # -----------------------------------------------------------------------
    # DCDIAG — alle 18 Tests auf Error setzen
    # Ausgeloeste Regeln: DC-DFSR, DC-SYSV, DC-KCC, DC-ROLE, DC-MACH,
    #   DC-NCSD, DC-LOGN, DC-OBJR, DC-REPL, DC-RIDM, DC-SVCS, DC-SYSL,
    #   DC-VREF, DC-SDREF, DC-CRVAL, DC-LOCAT, DC-INTER, DC-FSMOC
    # -----------------------------------------------------------------------
    $dcdiagData = @(
        [PSCustomObject]@{
            Server             = "MOCK-DC-01"
            Connectivity       = "Error"
            Advertising        = "Error"
            FrsEvent           = "Error"
            DFSREvent          = "Error"    # -> DC-DFSR
            SysVolCheck        = "Error"    # -> DC-SYSV
            KccEvent           = "Error"    # -> DC-KCC
            KnowsOfRoleHolders = "Error"    # -> DC-ROLE
            MachineAccount     = "Error"    # -> DC-MACH
            NCSecDesc          = "Error"    # -> DC-NCSD
            NetLogons          = "Error"    # -> DC-LOGN
            ObjectsReplicated  = "Error"    # -> DC-OBJR
            Replications       = "Error"    # -> DC-REPL
            RidManager         = "Error"    # -> DC-RIDM
            Services           = "Error"    # -> DC-SVCS
            SystemLog          = "Error"    # -> DC-SYSL
            VerifyReferences   = "Error"    # -> DC-VREF
            CheckSDRefDom      = "Error"    # -> DC-SDREF
            CrossRefValidation = "Error"    # -> DC-CRVAL
            LocatorCheck       = "Error"    # -> DC-LOCAT
            Intersite          = "Error"    # -> DC-INTER
            FsmoCheck          = "Error"    # -> DC-FSMOC
        }
        [PSCustomObject]@{
            Server             = "MOCK-DC-02"
            Connectivity       = "Error"
            Advertising        = "Error"
            FrsEvent           = "Error"
            DFSREvent          = "Error"
            SysVolCheck        = "Error"
            KccEvent           = "Error"
            KnowsOfRoleHolders = "Error"
            MachineAccount     = "Error"
            NCSecDesc          = "Error"
            NetLogons          = "Error"
            ObjectsReplicated  = "Error"
            Replications       = "Error"
            RidManager         = "Error"
            Services           = "Error"
            SystemLog          = "Error"
            VerifyReferences   = "Error"
            CheckSDRefDom      = "Error"
            CrossRefValidation = "Error"
            LocatorCheck       = "Error"
            Intersite          = "Error"
            FsmoCheck          = "Error"
        }
    )

    # -----------------------------------------------------------------------
    # DC SYSTEM HEALTH
    # Ausgeloeste Regeln:
    #   OS-01:   OSSupportStatus = "OutOfSupport"  -> High
    #   SRV-01-E: DiskSpace = "Error" (< 5%)       -> High
    #   SRV-01-W: DiskSpace = "Warning" (< 15%)    -> Medium (zweiter DC)
    #   SRV-02:  Status = "Error" (nicht erreichbar) -> High
    # -----------------------------------------------------------------------
    $discoveryData = @(
        [PSCustomObject]@{
            Server           = "MOCK-DC-01"
            OS               = "Windows Server 2012 R2"   # OutOfSupport
            OSSupportStatus  = "OutOfSupport"              # -> OS-01
            IPv4             = "10.0.0.1"
            UptimeHrs        = 8760
            FreeDiskGB       = 1.2
            FreeDiskPct      = "2 %"
            Status           = "Error"                     # -> SRV-01-E + SRV-02
        }
        [PSCustomObject]@{
            Server           = "MOCK-DC-02"
            OS               = "Windows Server 2016"       # OutOfMainstream
            OSSupportStatus  = "OutOfMainstream"           # -> OS-01
            IPv4             = "10.0.0.2"
            UptimeHrs        = 4380
            FreeDiskGB       = 8.5
            FreeDiskPct      = "12 %"
            Status           = "Warning"                   # -> SRV-01-W
        }
        [PSCustomObject]@{
            Server           = "MOCK-DC-03"
            # OS = "Unreachable" ist das Kennzeichen, an dem SRV-02 einen nicht
            # erreichbaren DC erkennt (so setzt es auch Get-ADHealthDiscovery).
            # Vorher stand hier ein regulaerer OS-Name, weshalb SRV-02 im
            # Sample-Report fehlte, obwohl Status bereits "Error" war.
            OS               = "Unreachable"
            OSSupportStatus  = "OK"
            IPv4             = "-"
            UptimeHrs        = "-"
            FreeDiskGB       = "-"
            FreeDiskPct      = "-"
            Status           = "Error"                     # -> SRV-02 (nicht erreichbar)
        }
    )

    # -----------------------------------------------------------------------
    # BACKUP
    # Ausgeloeste Regeln:
    #   BK-01: Status = "Warning" (> 24h, <= 7 Tage)  -> Medium
    #   BK-02: Status = "Critical" (> 7 Tage)          -> High
    # -----------------------------------------------------------------------
    $backupData = @(
        [PSCustomObject]@{
            Partition  = "DC=contoso,DC=local"
            LastBackup = (Get-Date).AddDays(-35).ToString("dd.MM.yyyy HH:mm")
            Days       = 35
            Hours      = 0
            Status     = "Critical"   # -> BK-02
        }
        [PSCustomObject]@{
            Partition  = "CN=Configuration,DC=contoso,DC=local"
            LastBackup = (Get-Date).AddDays(-3).ToString("dd.MM.yyyy HH:mm")
            Days       = 3
            Hours      = 0
            Status     = "Warning"    # -> BK-01
        }
        [PSCustomObject]@{
            Partition  = "CN=Schema,CN=Configuration,DC=contoso,DC=local"
            LastBackup = $null
            Days       = 0
            Hours      = 0
            Status     = "Error"      # -> BK-02
        }
    )

    # -----------------------------------------------------------------------
    # REPLIKATIONS-LATENZ
    # Ausgeloeste Regeln:
    #   REP-01: LatencyMinutes > ReplicationLatencyMaxMinutes (45) -> High
    # -----------------------------------------------------------------------
    $replData = @(
        [PSCustomObject]@{ Server="MOCK-DC-01"; Partner="MOCK-DC-02"; Partition="DC=contoso,DC=local"
                           LastSuccess=(Get-Date).AddMinutes(-15);  LatencyMinutes=15;  Failures=0; LastResult=0; Status="OK"; PartitionScope="AllPartitions"; PartitionsFound=[string[]]@("DC=contoso,DC=local","CN=Configuration,DC=contoso,DC=local") }
        [PSCustomObject]@{ Server="MOCK-DC-01"; Partner="MOCK-DC-03"; Partition="DC=contoso,DC=local"
                           LastSuccess=(Get-Date).AddMinutes(-320); LatencyMinutes=320; Failures=7; LastResult=1722; Status="Error"; PartitionScope="AllPartitions"; PartitionsFound=[string[]]@("DC=contoso,DC=local","CN=Configuration,DC=contoso,DC=local") }  # -> REP-01
        [PSCustomObject]@{ Server="MOCK-DC-02"; Partner="MOCK-DC-01"; Partition="DC=contoso,DC=local"
                           LastSuccess=(Get-Date).AddMinutes(-90);  LatencyMinutes=90;  Failures=2; LastResult=8524; Status="Error"; PartitionScope="AllPartitions"; PartitionsFound=[string[]]@("DC=contoso,DC=local","CN=Configuration,DC=contoso,DC=local") }  # -> REP-01
        [PSCustomObject]@{ Server="MOCK-DC-03"; Partner="-"; Partition="-"
                           LastSuccess=$null; LatencyMinutes=$null; Failures=0; LastResult="-"; Status="Unreachable"                    # -> REP-02
                           Reason="The RPC server is unavailable"; PartitionScope="AllPartitions"; PartitionsFound=[string[]]@() }
    )

    # -----------------------------------------------------------------------
    # EREIGNISPROTOKOLL-VORHALTEDAUER
    # Ausgeloeste Regeln:
    #   EVT-01: RetentionDays < MaxEventLogAgeDays (30) -> Medium
    # Gemessen wird, wie weit das Log ZURUECKREICHT — ein Log, das nur 3 Tage
    # vorhaelt, taugt nicht zur Vorfallanalyse.
    # -----------------------------------------------------------------------
    $evtData = @(
        [PSCustomObject]@{ Server="MOCK-DC-01"; LogName="Directory Service"; OldestEntry=(Get-Date).AddDays(-3)
                           RetentionDays=3;  Status="Error" }   # -> EVT-01
        [PSCustomObject]@{ Server="MOCK-DC-01"; LogName="System";            OldestEntry=(Get-Date).AddDays(-45)
                           RetentionDays=45; Status="OK" }
        [PSCustomObject]@{ Server="MOCK-DC-02"; LogName="Directory Service"; OldestEntry=(Get-Date).AddDays(-11)
                           RetentionDays=11; Status="Error" }   # -> EVT-01
        [PSCustomObject]@{ Server="MOCK-DC-02"; LogName="System";            OldestEntry=(Get-Date).AddDays(-60)
                           RetentionDays=60; Status="OK" }
        # Nicht abrufbar — genau der Fall aus dem ersten Feldtest: RPC blockiert.
        # Ohne EVT-02 waere dieser DC im Report unsichtbar geblieben.
        [PSCustomObject]@{ Server="MOCK-DC-03"; LogName="Directory Service"; OldestEntry=$null
                           RetentionDays=$null; Status="Unreachable"                                  # -> EVT-02
                           Reason="The RPC server is unavailable"; HintKey="HintRpcFirewall" }
        [PSCustomObject]@{ Server="MOCK-DC-03"; LogName="System";            OldestEntry=$null
                           RetentionDays=$null; Status="Unreachable"
                           Reason="The RPC server is unavailable"; HintKey="HintRpcFirewall" }
    )

    # -----------------------------------------------------------------------
    # SERVICES
    # Ausgeloeste Regeln:
    #   SVC-NTDS: NTDS  Status=Error -> High
    #   SVC-NET:  Netlogon Status=Error -> High
    #   SVC-DNS:  DNS Status=Error -> High
    #   SVC-KDC:  Kdc Status=Error -> High
    # -----------------------------------------------------------------------
    $svcData = @(
        [PSCustomObject]@{ Server="MOCK-DC-01"; Service="NTDS";    Status="Error"; StartType="Automatic" }
        [PSCustomObject]@{ Server="MOCK-DC-01"; Service="Netlogon"; Status="Error"; StartType="Automatic" }
        [PSCustomObject]@{ Server="MOCK-DC-01"; Service="DNS";     Status="Error"; StartType="Automatic" }
        [PSCustomObject]@{ Server="MOCK-DC-01"; Service="Kdc";     Status="Error"; StartType="Automatic" }
        [PSCustomObject]@{ Server="MOCK-DC-02"; Service="NTDS";    Status="Error"; StartType="Automatic" }
        [PSCustomObject]@{ Server="MOCK-DC-02"; Service="DNS";     Status="Error"; StartType="Automatic" }
    )

    # -----------------------------------------------------------------------
    # SITES & SERVICES
    # Ausgeloeste Regeln:
    #   SITE-01: ReplInterval > 15 Min         -> Medium
    #   SITE-02: Subnet ohne Site-Zuweisung    -> High
    #   SITE-03: ChangeNotification = Disabled -> Medium
    #   SITE-04: Site ohne GC                  -> Medium
    #   SITE-05: Keine Subnetze definiert      -> (Site mit leeren Subnets triggert SITE-02)
    # -----------------------------------------------------------------------
    $sitesData = [PSCustomObject]@{
        Transports = @(
            [PSCustomObject]@{
                Name               = "DEFAULTIPSITELINK"
                Type               = "Site Link"
                Description        = "Standard Site Link (MOCK)"
                Cost               = 100
                ReplInterval       = 180    # 180 Min -> triggert SITE-01 (> 15)
                ChangeNotification = "Disabled"  # -> triggert SITE-03
            }
            [PSCustomObject]@{
                Name               = "BRANCH-HQ-LINK"
                Type               = "Site Link"
                Description        = "Branch Office zu HQ"
                Cost               = 200
                ReplInterval       = 60     # 60 Min -> triggert SITE-01
                ChangeNotification = "Disabled"
            }
        )
        Subnets = @(
            [PSCustomObject]@{ Name = "10.0.0.0/24";  Site = "Default-First-Site-Name" }
            [PSCustomObject]@{ Name = "192.168.1.0/24"; Site = "-" }   # Kein Site -> SITE-02
            [PSCustomObject]@{ Name = "172.16.0.0/16";  Site = "-" }   # Kein Site -> SITE-02
        )
        Sites = @(
            [PSCustomObject]@{
                Name        = "Default-First-Site-Name"
                Servers     = @(
                    [PSCustomObject]@{ Name = "MOCK-DC-01"; IsGC = $true  }
                    [PSCustomObject]@{ Name = "MOCK-DC-02"; IsGC = $false }
                )
                Connections = @(
                    [PSCustomObject]@{ Source="MOCK-DC-02"; Transport="IP"; Enabled="Enabled"; DestinationServer="MOCK-DC-01" }
                )
            }
            [PSCustomObject]@{
                Name        = "BackOffice"
                Servers     = @()    # Keine Server -> triggert SITE-04 (kein GC)
                Connections = @()
            }
            [PSCustomObject]@{
                Name        = "BranchOffice"
                Servers     = @(
                    # IsGC = $true, damit AD-FSMO-08 greift: MOCK-DC-03 haelt die
                    # Infrastruktur-Master-Rolle, und ein GC in dieser Rolle ist bei
                    # mehreren DCs ohne AD-Papierkorb genau der zu meldende Konflikt.
                    # SITE-04 feuert weiterhin ueber die Site "BackOffice" (0 Server).
                    [PSCustomObject]@{ Name = "MOCK-DC-03"; IsGC = $true }
                )
                Connections = @()
            }
        )
    }

    # -----------------------------------------------------------------------
    # SECURITY (Accounts & Kennwortrichtlinie)
    # Ausgeloeste Regeln:
    #   SEC-01: InactiveUsers > 0    -> High
    #   SEC-02: NoPwdExpiryUsers > 0 -> High
    #   SEC-03: ExpiredPwdUsers > 0  -> Medium
    #   SEC-04: DomAdminCount > 5    -> High
    #   SEC-05: EntAdminCount > 2    -> High  (Condition ist >5 aber wir nehmen > 5 = 10)
    #   SEC-06: SchAdminCount > 1    -> Medium
    #   PWD-01: MinPwdLength < 12    -> High
    #   PWD-02: Complexity = false   -> High
    #   PWD-03: PwdHistory < 24      -> Medium
    #   PWD-04: LockoutThresh = 0    -> High
    #   PWD-05: LockoutDuration < 15 -> Medium
    #   PWD-06: ResetLockoutCount < 15 -> Medium
    # -----------------------------------------------------------------------
    $secData = [PSCustomObject]@{
        InactiveUsers         = 72      # > 0 -> SEC-01
        NoPwdExpiryUsers      = 102     # > 0 -> SEC-02
        ExpiredPwdUsers       = 38      # > 0 -> SEC-03
        DisabledUsers         = 215
        DomAdminCount         = 18      # > 5 -> SEC-04
        EntAdminCount         = 8       # > 5 -> SEC-05
        SchAdminCount         = 3       # > 1 -> SEC-06
        Complexity            = $false  # Deaktiviert -> PWD-02
        MinPwdLength          = 6       # < 12 -> PWD-01
        MinPwdAge             = 0
        MaxPwdAge             = 42
        PwdHistory            = 5       # < 24 -> PWD-03
        LockoutThresh         = 0       # = 0  -> PWD-04
        LockoutDuration       = 5       # < 15 -> PWD-05
        ResetLockoutCount     = 5       # < 15 -> PWD-06
        InactiveThresholdDays = $Settings.Thresholds.InactiveAccountDays
        RawExportData         = @()
    }

    # -----------------------------------------------------------------------
    # OU & ACL AUDIT
    # Ausgeloeste Regeln:
    #   SEC-07: UniqueOrphanCount > 0       -> Medium
    #   SEC-08: DisabledInheritanceOU > 0   -> High
    #   SEC-09: DisabledInheritanceUser > 0 -> Medium
    # -----------------------------------------------------------------------
    $ouSecData = [PSCustomObject]@{
        TotalOrphanCount  = 847
        UniqueOrphanCount = 51    # > 0 -> SEC-07
        TopOrphanedSIDs   = @(
            [PSCustomObject]@{ Name = "S-1-5-21-999-888-777-1001"; Count = 2400 }
            [PSCustomObject]@{ Name = "S-1-5-21-999-888-777-1145"; Count = 891 }
            [PSCustomObject]@{ Name = "S-1-5-21-999-888-777-2210"; Count = 312 }
        )
        DisabledInheritanceOU = @(
            [PSCustomObject]@{ Name = "Tier0-Admins";  DN = "OU=Tier0-Admins,DC=contoso,DC=local" }
            [PSCustomObject]@{ Name = "ServiceAccounts"; DN = "OU=ServiceAccounts,DC=contoso,DC=local" }
            [PSCustomObject]@{ Name = "Workstations";  DN = "OU=Workstations,DC=contoso,DC=local" }
        )   # > 0 -> SEC-08
        DisabledInheritanceUser = foreach ($i in 1..20) {
            # Realistische Mischung fuer SEC-09 (U3): alle DREI Lagen kommen vor,
            # Tests haengen an dieser genauen Aufteilung.
            #   i = 1..9   (9 Konten): adminCount=1 UND aktuell Mitglied einer
            #                geschuetzten Gruppe -- laufender SDProp-Schutz, erwartet.
            #   i = 10..14 (5 Konten): adminCount=1, aber NICHT mehr Mitglied --
            #                die interessante Teilmenge (U3): SDProp pflegt sie nicht
            #                mehr, die Vererbung liesse sich dauerhaft bereinigen.
            #   i = 15..20 (6 Konten): kein adminCount -- von Hand abgeschaltet,
            #                der urspruengliche Befund (B3), unveraendert.
            $isAdminSdHolder = ($i -le 14)
            $currentlyMember = if ($isAdminSdHolder) { ($i -le 9) } else { $false }
            [PSCustomObject]@{
                Name                     = "svc_app$i"
                DN                       = "CN=svc_app$i,OU=ServiceAccounts,DC=contoso,DC=local"
                AdminSdHolder            = $isAdminSdHolder
                CurrentlyProtectedMember = $currentlyMember
            }
        }   # > 0 -> SEC-09; davon 14 adminCount=1 (9 aktuell, 5 ehemals), 6 manuell
    }

    # -----------------------------------------------------------------------
    # ENTRA ID SYNC
    # Ausgeloeste Regeln:
    #   ENT-01: InstalledVersion < ExpectedVersion -> Medium
    #   ENT-02: ServiceStatus = Stopped           -> High
    # -----------------------------------------------------------------------
    $entraData = [PSCustomObject]@{
        Server           = "SRVSYNC01 (MOCK)"
        InstalledVersion = "1.1.0.0"    # Veraltet -> ENT-01
        ExpectedVersion  = $Settings.EntraID.ExpectedAgentVersion
        FoundAnyService  = $true
        ServiceDetails   = @(
            [PSCustomObject]@{ Name = "Microsoft Entra Connect Sync";          Status = "Stopped" }  # -> ENT-02
            [PSCustomObject]@{ Name = "Microsoft Azure AD Connect Agent Updater"; Status = "Stopped" }
        )
    }

    # -----------------------------------------------------------------------
    # DNS HEALTH
    # Ausgeloeste Regeln:
    #   DNS-01: ScavengingZoneMismatch (einige Zonen ohne Scavenging) -> Medium
    #   DNS-02: SRV-Record fehlt (PDC Critical)                       -> High
    #   DNS-03: Nameserver nicht erreichbar                            -> High
    #   DNS-04: Nicht AD-integrierte Zone                              -> Low
    #   DNS-05: Zone gestoppt                                          -> High
    #   DNS-06: Scavenging global deaktiviert (alle Zonen fehlen)     -> Low
    #   DNS-07: DNSSEC nicht konfiguriert                              -> Low
    # -----------------------------------------------------------------------
    $dnsData = [PSCustomObject]@{
        ForwardZones = @(
            [PSCustomObject]@{
                ZoneName         = "contoso.local"
                ZoneType         = "Primary"
                IsADIntegrated   = $true
                ZoneStatus       = "Running"
                ReplicationScope = "Domain"
                IsSigned         = $false    # -> DNS-07 (DNSSEC fehlt)
                AgingEnabled     = $false    # -> DNS-01 (Zone ohne Scavenging)
                RefreshHours     = $null
                NoRefreshHours   = $null
            }
            [PSCustomObject]@{
                ZoneName         = "legacy.contoso.local"
                ZoneType         = "Primary"
                IsADIntegrated   = $false    # -> DNS-04 (nicht AD-integriert)
                ZoneStatus       = "Stopped" # -> DNS-05 (Zone gestoppt)
                ReplicationScope = "None"
                IsSigned         = $false
                AgingEnabled     = $null     # Secondary/Stub: nicht ermittelbar
                RefreshHours     = $null
                NoRefreshHours   = $null
            }
        )
        ReverseZones = @(
            [PSCustomObject]@{
                ZoneName         = "0.0.10.in-addr.arpa"
                ZoneType         = "Primary"
                IsADIntegrated   = $true
                ZoneStatus       = "Running"
                ReplicationScope = "Domain"
                IsSigned         = $false
                AgingEnabled     = $true     # gemessen: aktiv
                RefreshHours     = 168
                NoRefreshHours   = 168
            }
        )
        # Rein informativ, wird NICHT geprueft und fliesst in keine Empfehlung ein.
        # Insbesondere nicht in TotalZoneCount, DNSSEC- oder Scavenging-Bewertung.
        TrustAnchors = [PSCustomObject]@{
            ZonePresent      = $true
            ZoneName         = "TrustAnchors"
            ZoneType         = "Primary"
            IsADIntegrated   = $true
            ReplicationScope = "Forest"
            NSRecordCount    = 22
            TrustPoints      = @()
        }
        NSStatus = @(
            [PSCustomObject]@{ Name = "mock-dc-01.contoso.local"; IP = "10.0.0.1"; Service = "Running"; ICMP = "OK"   }
            [PSCustomObject]@{ Name = "mock-dc-02.contoso.local"; IP = "10.0.0.2"; Service = "Stopped"; ICMP = "Fail" }  # -> DNS-03
            [PSCustomObject]@{ Name = "mock-dc-03.contoso.local"; IP = "-";        Service = "NotFound"; ICMP = "Fail" } # -> DNS-03
        )
        QuickChecks = @{
            NSCondition       = @(
                [PSCustomObject]@{ Name = "mock-dc-01.contoso.local"; Status = "OK"   }
                [PSCustomObject]@{ Name = "mock-dc-02.contoso.local"; Status = "Fail" }
                [PSCustomObject]@{ Name = "mock-dc-03.contoso.local"; Status = "Fail" }
            )
            # Gemessene Werte: eine Zone nachweislich ohne Aging, eine nicht
            # ermittelbar, eine aktiv. Server-Schalter AN -> DNS-01 feuert und
            # listet die betroffene Zone. DNS-06 kann dann nicht feuern: seit
            # v2.7.6 schliessen sich beide Regeln gegenseitig aus (serverweit
            # aus ODER serverweit an mit einzelnen Zonen aus).
            MissingScavenging  = @("contoso.local")
            ScavengingUnknown  = @("legacy.contoso.local")
            ScavengingMeasured = 2
            # Server: seit P34 legt Get-ADHCServerScavenging den Namen des
            # Abfrageziels ab -- ohne das Feld bildeten die Mock-Daten die
            # Erhebung nicht mehr vollstaendig ab. Reine Datentreue: der
            # Schalter bleibt AN, DNS-06 feuert im Beispielbericht also nicht,
            # und AffectedItems wird nur beim Feuern gefuellt.
            ServerScavenging   = [PSCustomObject]@{ Enabled = $true; IntervalHours = 168; Server = "mock-dc-01.contoso.local" }
            TotalZoneCount     = 3
            SRVDetails        = @(
                [PSCustomObject]@{ ServiceKey = "LDAP";     Status = "OK"       }
                [PSCustomObject]@{ ServiceKey = "Kerberos"; Status = "OK"       }
                [PSCustomObject]@{ ServiceKey = "GC";       Status = "OK"       }
                [PSCustomObject]@{ ServiceKey = "PDC";      Status = "Critical" }  # -> DNS-02
            )
        }
    }

    # -----------------------------------------------------------------------
    # CSV Export-Daten (lokalisiert via I18n)
    # -----------------------------------------------------------------------
    $rawExport = @()
    for ($i = 1; $i -le 15; $i++) {
        $rawExport += [PSCustomObject]@{
            ($I18n.CsvHeaders.Surname)             = "Mustermann_$i"
            ($I18n.CsvHeaders.GivenName)           = "Max"
            ($I18n.CsvHeaders.UPN)                 = "max$i@contoso.local"
            ($I18n.CsvHeaders.Active)              = if ($LangCode -eq "de") { "Ja" } else { "Yes" }
            ($I18n.CsvHeaders.LastLogin)           = (Get-Date).AddDays(-($i * 30)).ToString("dd.MM.yyyy")
            ($I18n.CsvHeaders.PasswordSet)         = (Get-Date).AddDays(-($i * 45)).ToString("dd.MM.yyyy")
            ($I18n.CsvHeaders.PasswordNeverExpires) = if ($i % 3 -eq 0) { "Ja" } else { "Nein" }
            ($I18n.CsvHeaders.Reason)              = $I18n.Reasons.Inactive -f $Settings.Thresholds.InactiveAccountDays
        }
    }
    $secData.RawExportData = $rawExport

    # -----------------------------------------------------------------------
    # MOCK-DATEN ZUSAMMENSTELLEN
    # -----------------------------------------------------------------------
    $mockData = @{
        DomainStats       = $domainStats
        FSMO              = $fsmoData
        Replication       = $replData
        EventLog          = $evtData
        Discovery         = $discoveryData
        DCDiag            = $dcdiagData
        Services          = $svcData
        Backup            = $backupData
        Sites             = $sitesData
        Security          = $secData
        OUAccountSecurity = $ouSecData
        Entra             = $entraData
        DNS               = $dnsData
    }

    Write-ADHCLog "Mock-Daten generiert: 72 von 73 Empfehlungsregeln aktiv. DNS-06 (Scavenging serverweit aus) schliesst DNS-01 (einzelne Zonen aus) aus - im Sample feuert DNS-01." -Component "Discovery"
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

function ConvertFrom-DcdiagOutput {
    <#
        .SYNOPSIS
        Wertet die Textausgabe von dcdiag.exe aus und ermittelt je erwarteten
        Test das Ergebnis "OK", "Error" oder "Unknown" (nicht erkannt).

        .DESCRIPTION
        Schneller Pfad (unveraendert gegenueber der bisherigen Logik): die
        englischen Muster "passed test <Name>" / "failed test <Name>".

        Rueckfall — nur fuer Tests, die danach noch "Unknown" sind: ein
        sprachunabhaengiges Muster, das auf dem (laut Recherche englisch
        bleibenden) Testnamen als Anker aufsetzt und die deutsche Formulierung
        "hat den Test <Name> [nicht] bestanden" erkennt.

        WARNUNG: Das deutsche Muster ist eine ANNAHME auf Basis oeffentlich
        einsehbarer Forenbeispiele (siehe t4-report.md), nicht an einem
        deutschsprachigen Server nachgewiesen. Tests, die auch danach nicht
        erkannt werden, bleiben "Unknown" — das Sicherheitsnetz in den Regeln
        meldet das als NOT_CHECKED statt als bestanden.

        .PARAMETER Output
        Die vollstaendige Standardausgabe von dcdiag.exe fuer einen Server.

        .PARAMETER TestNames
        Die Liste der erwarteten Testnamen (englische dcdiag-Bezeichner).

        .PARAMETER DCName
        Optional. Servername fuer die bestehende Connectivity-Sonderauswertung
        (unveraendert uebernommen). Ohne Angabe wird nur ueber die generischen
        Muster ausgewertet.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Output,

        [Parameter(Mandatory)]
        [string[]]$TestNames,

        [string]$DCName
    )

    $result = [ordered]@{}
    foreach ($t in $TestNames) { $result[$t] = "Unknown" }

    $lines = $Output -split "`r`n"
    foreach ($line in $lines) {
        if ($line -match "passed test\s+(?<TestName>\w+)") {
            $tName = $Matches.TestName
            if ($result.Contains($tName)) { $result[$tName] = "OK" }
        }
        elseif ($line -match "failed test\s+(?<TestName>\w+)") {
            $tName = $Matches.TestName
            if ($result.Contains($tName)) { $result[$tName] = "Error" }
        }
    }
    if ($DCName -and $result.Contains("Connectivity") -and $result["Connectivity"] -eq "Unknown") {
        if ($Output -match "$DCName failed test Connectivity") { $result["Connectivity"] = "Error" }
        elseif ($Output -match "$DCName passed test Connectivity") { $result["Connectivity"] = "OK" }
    }

    # Sprachunabhaengiger Rueckfall — nur fuer noch nicht erkannte Tests (ANNAHME, s.o.).
    foreach ($t in $TestNames) {
        if ($result[$t] -ne "Unknown") { continue }
        $escaped = [regex]::Escape($t)
        if ($Output -match "hat den Test\s+$escaped\s+nicht bestanden") {
            $result[$t] = "Error"
        }
        elseif ($Output -match "hat den Test\s+$escaped\s+bestanden") {
            $result[$t] = "OK"
        }
    }

    return $result
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

            $parsed = ConvertFrom-DcdiagOutput -Output $output -TestNames $testsToRun -DCName $dc
            foreach ($t in $testsToRun) { $serverResult[$t] = $parsed[$t] }
        } catch {
            Write-ADHCLog "Fehler bei DCDIAG auf ${dc}: $_" -Level Error
            foreach ($t in $testsToRun) { $serverResult[$t] = "Error" }
        }
        $matrixResults += [PSCustomObject]$serverResult
    }
    return $matrixResults
}

# AD-FSMO-01..05: Erreichbarkeit ueber einen TCP-Verbindungsaufbau statt ICMP-
# Ping. Ping wird in gehaerteten Umgebungen haeufig per Firewall/GPO
# blockiert (-> Fehlalarm), und ein Host, der auf ICMP antwortet, sagt nichts
# darueber aus, ob der Verzeichnisdienst laeuft (-> geschoentes Ergebnis).
# Eigene, testbare Funktion statt Inline-Aufruf: die Zeitgrenze bindet
# Namensaufloesung UND Verbindungsaufbau zusammen (Test-NetConnection wartet
# ungebremst und fuehrt zusaetzliche Routendiagnose durch), und die Funktion
# laesst sich in Pester ohne AD/RSAT gegen einen echten TcpListener auf
# Loopback pruefen.
function Test-ADHCPortReachable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMs = 1000,
        # U3/LDAPS-Rueckfall: schlaegt $Port fehl, wird $FallbackPort (z.B. 636
        # fuer LDAPS statt 389/LDAP) versucht, BEVOR der Host als nicht erreichbar
        # gilt. Nicht gesetzt (Default) -> unveraendertes Verhalten, ein Versuch.
        [int]$FallbackPort = 0
    )
    # TcpClient.BeginConnect(string,...) loest den Namen SYNCHRON auf, BEVOR der
    # asynchrone Verbindungsversuch beginnt -- WaitOne($TimeoutMs) haette danach nur
    # die Verbindungsphase gebunden, nicht die Namensaufloesung davor. In genau den
    # gehaerteten Umgebungen, die diese Pruefung motivieren, ist auch DNS oft langsam
    # oder haengt. Deshalb wird zuerst asynchron aufgeloest (GetHostAddressesAsync +
    # Wait) und die BeginConnect(IPAddress[], ...)-Ueberladung mit den fertigen
    # Adressen aufgerufen -- TimeoutMs ist damit die GESAMTE Zeitgrenze fuer
    # Namensaufloesung UND ALLE Verbindungsversuche (Primaer- + ggf. Rueckfall-Port)
    # ZUSAMMEN, nicht je Versuch eine eigene. Damit verdoppelt der Rueckfall das
    # Zeitbudget nicht. Antwortet der Primaer-Port, wird der Rueckfall gar nicht
    # erst versucht (Normalfall bleibt unveraendert schnell, ein Verbindungsaufbau).
    #
    # U3: Ein "geschlossener" Port in genau den gehaerteten Umgebungen, die diese
    # Pruefung motivieren, antwortet oft NICHT mit einem schnellen Reset, sondern
    # laesst das SYN-Paket verwerfen (Firewall-DROP) -- der Verbindungsversuch
    # haengt dann bis zur Zeitgrenze, statt schnell zu scheitern. Wuerde der
    # Primaer-Port in diesem Fall die GESAMTE Restzeit fuer sich beanspruchen
    # duerfen, bekaeme der Rueckfall-Port real NIE eine Chance -- genau der Fall,
    # fuer den der Rueckfall gedacht ist. Deshalb wird die nach DNS verbleibende
    # Zeit bei gesetztem FallbackPort VORAB in zwei Haelften geteilt: der
    # Primaer-Port darf hoechstens die Haelfte der Restzeit beanspruchen, der Rest
    # (mindestens die andere Haelfte, ggf. mehr, falls der Primaer-Port schneller
    # scheitert) steht dem Rueckfall-Port zur Verfuegung. Ohne FallbackPort
    # aendert sich nichts: der Primaer-Port bekommt wie bisher die volle Restzeit.
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $dnsTask = [System.Net.Dns]::GetHostAddressesAsync($ComputerName)
        if (-not $dnsTask.Wait($TimeoutMs)) {
            return $false
        }
        # Wirft, wenn der Name nicht aufloesbar ist -- vom aeusseren catch als
        # "Error" behandelt, keine durchschlagende Ausnahme (siehe Kommentar dort).
        $addresses = $dnsTask.GetAwaiter().GetResult()
        if (-not $addresses -or $addresses.Count -eq 0) {
            return $false
        }

        $portsToTry = @($Port)
        if ($FallbackPort -gt 0) { $portsToTry += $FallbackPort }

        $remainingAfterDns = $TimeoutMs - [int]$stopwatch.ElapsedMilliseconds
        if ($remainingAfterDns -le 0) { return $false }
        # Budget je Versuch: bei zwei Ports die Haelfte der nach DNS verbleibenden
        # Zeit (mind. 1ms), bei nur einem Port unveraendert die volle Restzeit.
        $perAttemptCapMs = if ($portsToTry.Count -gt 1) {
            [Math]::Max(1, [int]($remainingAfterDns / 2))
        } else {
            $remainingAfterDns
        }

        foreach ($p in $portsToTry) {
            $remainingMs = $TimeoutMs - [int]$stopwatch.ElapsedMilliseconds
            if ($remainingMs -le 0) { return $false }
            $waitMs = [Math]::Min($remainingMs, $perAttemptCapMs)

            $client = $null
            try {
                $client = New-Object System.Net.Sockets.TcpClient
                $async  = $client.BeginConnect($addresses, $p, $null, $null)
                $signaled = $async.AsyncWaitHandle.WaitOne($waitMs)
                if ($signaled -and $client.Connected) {
                    $client.EndConnect($async)
                    return $true
                }
            } catch {
                # dieser Port ist gescheitert -- bei vorhandenem Rueckfall den
                # naechsten versuchen, statt sofort abzubrechen.
            } finally {
                if ($client) { $client.Dispose() }
            }
        }
        return $false
    } catch {
        return $false
    }
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
            # Port 389 (LDAP) statt ICMP: belegt, dass der Verzeichnisdienst
            # selbst antwortet, nicht nur der Netzwerkstapel des Servers.
            # TimeoutMs 1000 begrenzt Namensaufloesung UND ALLE Verbindungsversuche
            # ZUSAMMEN (siehe Test-ADHCPortReachable) auf maximal 1 Sekunde je Rolle,
            # also weiterhin maximal 5 Sekunden zusaetzlich fuer alle fuenf Rollen,
            # selbst wenn keine erreichbar ist und die Namensaufloesung haengt --
            # das Zeitbudget je Rolle verdoppelt sich durch den Rueckfall NICHT.
            #
            # U3: Schlaegt 389 fehl, wird 636 (LDAPS) als Rueckfall versucht, BEVOR
            # die Rolle als nicht erreichbar gilt. Vorher meldete diese Pruefung in
            # einer Umgebung, die ausschliesslich LDAPS anbietet und 389 geschlossen
            # hat, den Rolleninhaber faelschlich als nicht erreichbar, obwohl der
            # Verzeichnisdienst lief. Laufzeitfolge: antwortet 389, aendert sich
            # nichts (636 wird nie versucht, weiterhin max. 1s je Rolle). Ist 389
            # zu, teilt sich dieselbe 1-Sekunden-Grenze je Rolle auf DNS +
            # 389-Versuch + 636-Versuch auf: 389 bekommt hoechstens die Haelfte der
            # nach DNS verbleibenden Zeit, der Rest steht 636 zur Verfuegung
            # (Test-ADHCPortReachable) -- damit der Rueckfall auch dann noch eine
            # Chance hat, wenn 389 per Firewall-DROP bis zur Grenze haengt, statt
            # schnell abgelehnt zu werden. Gesamtbudget bleibt bei max. 1s je Rolle,
            # also weiterhin max. 5s zusaetzlich fuer alle fuenf Rollen -- es
            # verdoppelt sich nicht, teilt sich nur intern anders auf.
            $reachable = Test-ADHCPortReachable -ComputerName $r.Owner -Port 389 -FallbackPort 636 -TimeoutMs 1000
            $status = if ($reachable) { "OK" } else { "Error" }

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
        # S4: Startwert $null, NICHT $false. Vorher stand hier $false und wurde
        # nur im Erfolgsfall gehoben -- eine fehlgeschlagene Abfrage (fehlendes
        # Leserecht, Domaenencontroller nicht erreichbar) war damit von einem
        # echten "Papierkorb ist aus" nicht zu unterscheiden und erzeugte ueber
        # AD-03 einen FALSCHBEFUND der Prioritaet High. Dieselbe Fehlerklasse
        # wie AD-04/PWD-02 in 2cdff84; AD-03 war dort uebersehen worden.
        $isRecycleBinEnabled = $null

        # Wir suchen gezielt nach dem Feature und laden die EnabledScopes explizit.
        # -ErrorAction Stop statt SilentlyContinue: ein geschluckter Fehler liefe
        # sonst still in den Erfolgspfad weiter und sein Ergebnis ($null) waere
        # von "kein Treffer" nicht mehr zu trennen. Der catch haelt den Wert
        # ausdruecklich auf $null = "nicht ermittelbar".
        $rbFeature = $null
        try {
            $rbFeature = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'" -ErrorAction Stop
        } catch {
            Write-ADHCLog "Papierkorb-Status nicht ermittelbar: $_" -Level Warning -Component "Discovery"
            $rbFeature = $null
        }

        # Ab hier ist die Abfrage nachweislich gelaufen und hat das Feature
        # geliefert -- ein leeres oder nicht passendes EnabledScopes ist damit
        # eine AUSSAGE ("der Papierkorb ist aus"), keine Wissensluecke. Nur der
        # Fall "Feature gar nicht bekommen" bleibt $null.
        if ($rbFeature) {
            $isRecycleBinEnabled = $false
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

        # ⚠ @() um die Abfrage ist Pflicht. Liefert sie GENAU EIN Objekt, greift
        # .Count nicht auf die Anzahl zu, sondern auf das gleichnamige
        # AD-Attribut dieses Objekts -- das es nicht gibt. Im Export stand dann
        # eine leere Liste, wo eine Zahl stehen muss. An einer echten Umgebung
        # beobachtet: DistGroupCount kam als [] statt als 1 an, waehrend
        # ContactCount (null Treffer) korrekt 0 lieferte. $domainCount unten
        # macht es seit jeher richtig.
        $userCount = @(Get-ADUser -Filter * -ResultPageSize 1000).Count
        $secGroupCount = @(Get-ADGroup -Filter "GroupCategory -eq 'Security'" -ResultPageSize 1000).Count
        $distGroupCount = @(Get-ADGroup -Filter "GroupCategory -eq 'Distribution'" -ResultPageSize 1000).Count
        $contactCount = @(Get-ADObject -LDAPFilter "(objectClass=contact)" -ResultPageSize 1000).Count

        # U3/AD-FSMO-07: Anzahl Domaenen der Gesamtstruktur. $forest liegt an
        # dieser Stelle bereits vor (kein zusaetzlicher AD-Aufruf); scheitert das
        # Auslesen von .Domains dennoch (z.B. unvollstaendiges Forest-Objekt in
        # exotischen Umgebungen), bleibt DomainCount $null -- "nicht ermittelbar",
        # nicht "eine Domaene angenommen".
        $domainCount = $null
        try { $domainCount = @($forest.Domains).Count } catch { $domainCount = $null }

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
            DomainCount     = $domainCount
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
        # U3/SEC-09: DNs der AKTUELLEN Mitglieder der drei geschuetzten Gruppen
        # zusaetzlich festhalten (bisher wurde nur .Count behalten und der Rest
        # verworfen). Get-ADOUAndAccountSecurity braucht diese Menge, um
        # adminCount=1-Konten in "aktuell geschuetzt" und "ehemals privilegiert"
        # zu trennen -- AD setzt adminCount beim Gruppenaustritt NICHT zurueck.
        $protectedMemberDNs = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($g in $groupsToCheck) {
            $groupObj = Get-ADGroup -Identity $g.SID -ErrorAction SilentlyContinue
            if ($groupObj) {
                $members = Get-ADUser -Filter "MemberOf -RecursiveMatch '$($groupObj.DistinguishedName)'" -Properties GivenName, Surname, UserPrincipalName, LastLogonDate, PasswordLastSet, PasswordNeverExpires, Enabled
                Add-ToExport -SourceList $members -Reason "Mitglied: $($groupObj.Name)"
                $groupResults[$g.Name] = @{ Name = $groupObj.Name; Count = @($members).Count }
                foreach ($m in $members) { [void]$protectedMemberDNs.Add($m.DistinguishedName) }
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
            InactiveUsers           = @($listInactive).Count
            DisabledUsers           = @($listDisabled).Count
            NoPwdExpiryUsers        = @($listNoExpiry).Count
            ExpiredPwdUsers         = @($listExpired).Count
            
            DomAdminName            = $groupResults["DomAdmin"].Name
            DomAdminCount           = $groupResults["DomAdmin"].Count
            EntAdminName            = $groupResults["EntAdmin"].Name
            EntAdminCount           = $groupResults["EntAdmin"].Count
            SchAdminName            = $groupResults["SchAdmin"].Name
            SchAdminCount           = $groupResults["SchAdmin"].Count
            
            RawExportData           = $rawExport
            # U3/SEC-09: Array statt HashSet, damit spaetere JSON-Serialisierung
            # (Export/Debug) nicht am Typ scheitert.
            ProtectedGroupMemberDNs = [string[]]@($protectedMemberDNs)
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
        [scriptblock]$ProgressCallback = $null,
        # U3/SEC-09: DNs der AKTUELL geschuetzten Mitglieder (Get-ADSecurityInfo,
        # ProtectedGroupMemberDNs). $null, wenn die Security-Sektion nicht lief --
        # dann bleibt die Unterscheidung "aktuell/ehemals" nicht ermittelbar.
        [string[]]$ProtectedGroupMemberDNs = $null
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
        param($syncHash, $ProtectedGroupMemberDNs)

        # Als HashSet fuer O(1)-Nachschlag; $null bleibt $null (nicht ermittelbar).
        $protectedSet = if ($ProtectedGroupMemberDNs) {
            New-Object System.Collections.Generic.HashSet[string]([string[]]$ProtectedGroupMemberDNs, [System.StringComparer]::OrdinalIgnoreCase)
        } else { $null }

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
                          @(Get-ADUser -Filter 'Enabled -eq $true'  -Properties nTSecurityDescriptor, Name, ObjectClass, adminCount)

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
                    if ($obj.ObjectClass -eq "organizationalUnit") {
                        # SDProp/AdminSDHolder schuetzt keine OUs -- adminCount gibt es
                        # hier nicht, das Feld bleibt bei OU-Eintraegen bewusst aus.
                        $lite = [PSCustomObject]@{ Name = $obj.Name; DN = $obj.DistinguishedName }
                        $disabledInheritanceOU.Add($lite)
                    } else {
                        # adminCount ist bei normalen Konten $null -- "$null -eq 1" ist
                        # in PowerShell $false, dadurch werten wir $null korrekt als
                        # "nicht AdminSDHolder-geschuetzt" (B3).
                        $isAdminSdHolder = ($obj.adminCount -eq 1)
                        # U3/SEC-09: adminCount=1 beweist NICHT "aktuell privilegiert" --
                        # AD setzt es beim Gruppenaustritt nicht zurueck. Nur der Abgleich
                        # gegen die AKTUELLE Mitgliederliste der drei geschuetzten Gruppen
                        # (Get-ADSecurityInfo) trennt "aktuell geschuetzt" von "ehemals
                        # privilegiert, SDProp pflegt nicht mehr". $null = nicht ermittelbar
                        # (Security-Sektion nicht gelaufen) -- konservative Annahme: als
                        # aktuell geschuetzt behandeln, NICHT als bereinigbaren Fund
                        # ausweisen (siehe u3-report.md).
                        $currentlyMember = if (-not $isAdminSdHolder) {
                            $false
                        } elseif ($null -eq $protectedSet) {
                            $true
                        } else {
                            $protectedSet.Contains($obj.DistinguishedName)
                        }
                        $lite = [PSCustomObject]@{
                            Name                      = $obj.Name
                            DN                        = $obj.DistinguishedName
                            AdminSdHolder             = $isAdminSdHolder
                            CurrentlyProtectedMember  = $currentlyMember
                        }
                        $disabledInheritanceUser.Add($lite)
                    }
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
    $ps.AddScript($scriptBlock).AddArgument($syncHash).AddArgument($ProtectedGroupMemberDNs) | Out-Null

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

function Get-ADReplicationLatency {
<#
.SYNOPSIS
    Ermittelt je DC und Replikationspartner die Zeit seit der letzten
    ERFOLGREICHEN Replikation.
.DESCRIPTION
    Grundlage ist Get-ADReplicationPartnerMetadata (-Scope Server). Bewertet wird
    LastReplicationSuccess: liegt der Zeitpunkt weiter zurueck als
    Thresholds.ReplicationLatencyMaxMinutes, gilt die Partnerschaft als
    rueckstaendig. ConsecutiveReplicationFailures und LastReplicationResult
    werden zur Diagnose mitgefuehrt.

    Nicht erreichbare DCs erzeugen einen Eintrag mit Status "Unreachable",
    damit sie im Report sichtbar bleiben statt still zu verschwinden.

    SONDERFALL "keine Replikationspartner": Existiert nur EIN Domaenencontroller,
    gibt es nichts zu replizieren — die Pruefung ist dann nicht "bestanden" und
    auch nicht "fehlgeschlagen", sondern NICHT ANWENDBAR. Solche Eintraege tragen
    Status "NotApplicable" und werden von REP-01/REP-02 uebersprungen. Die
    Unterscheidung ist bewusst NICHT allein an der DC-Anzahl festgemacht: in
    einem Forest mit mehreren Domaenen repliziert auch ein einzelner Domaenen-DC
    die Configuration-/Schema-Partition mit DCs anderer Domaenen. Massgeblich ist
    daher, ob die Abfrage tatsaechlich Partner geliefert hat.
#>
    param($DCList, $Settings)

    # Nur EIN DC bekannt: ein Fehlschlag der Metadaten-Abfrage ist dann nicht von
    # "es gibt schlicht keinen Partner" zu unterscheiden — und waere ohnehin nicht
    # behebbar, weil ohne zweiten DC keine Replikation stattfindet.
    $soloDC = (@($DCList).Count -lt 2)

    $maxMin = if ($Settings.Thresholds.ReplicationLatencyMaxMinutes) {
        [int]$Settings.Thresholds.ReplicationLatencyMaxMinutes
    } else { 45 }

    # Ohne Partitions-Parameter liefert das Cmdlet NUR die Standard-Partition
    # (die Domaene). Replikationsprobleme auf Configuration, Schema,
    # ForestDnsZones oder DomainDnsZones blieben dadurch unsichtbar.
    #
    # Der Parametername unterscheidet sich je nach RSAT-Version, und ein falscher
    # Name laesst den GESAMTEN Aufruf fehlschlagen (so geschehen in v2.7.1 mit
    # "-PartitionFilter", das es nicht gibt). Deshalb wird zur Laufzeit ermittelt,
    # was das installierte Cmdlet tatsaechlich kennt — und die erreichte Abdeckung
    # wird im Ergebnis ausgewiesen, statt sie stillschweigend anzunehmen.
    $cmd          = Get-Command Get-ADReplicationPartnerMetadata -ErrorAction SilentlyContinue
    $partParam    = $null
    if ($cmd) {
        foreach ($cand in @('Partition','PartitionFilter')) {
            if ($cmd.Parameters.ContainsKey($cand)) { $partParam = $cand; break }
        }
    }
    # PartitionScope beschreibt, was ABGEFRAGT wurde — nicht, was zurueckkam.
    # Beides zu verwechseln waere ein Ueberversprechen: im Feldtest lieferte
    # "AllPartitions" drei von fuenf bekannten Partitionen. Was tatsaechlich
    # geantwortet hat, steht je DC in PartitionsFound.
    $partitionScope = if ($partParam) { "AllPartitions" } else { "DefaultPartitionOnly" }
    Write-ADHCLog -Message "Replikations-Abfrage: Partitions-Scope = $partitionScope$(if ($partParam) { " (via -$partParam)" })" -Component "Replication"

    $res = @()
    foreach ($dc in $DCList) {
        Write-ADHCLog -Message "Ermittle Replikations-Latenz auf $dc..." -Component "Replication"
        try {
            $callArgs = @{ Target = $dc; Scope = 'Server'; ErrorAction = 'Stop' }
            if ($partParam) { $callArgs[$partParam] = '*' }
            $partners = Get-ADReplicationPartnerMetadata @callArgs

            # Welche Partitionen haben TATSAECHLICH geantwortet? Typisiert, damit
            # einelementige Listen im JSON nicht zum Skalar kollabieren.
            [string[]]$partitionsFound = @($partners | ForEach-Object { [string]$_.Partition } |
                                           Where-Object { $_ } | Sort-Object -Unique)
            Write-ADHCLog -Message "$dc : $($partitionsFound.Count) Partition(en) beantwortet — $($partitionsFound -join ', ')" -Component "Replication"

            # Abfrage erfolgreich, aber KEIN Partner vorhanden: es gibt nichts zu
            # bewerten. Ein "OK" waere hier eine Behauptung ueber etwas, das gar
            # nicht existiert.
            if (@($partners).Count -eq 0) {
                Write-ADHCLog -Message "$dc : keine Replikationspartner vorhanden — Replikationspruefung nicht anwendbar" -Component "Replication"
                $res += [PSCustomObject]@{
                    Server = $dc; Partner = "-"; Partition = "-"; LastSuccess = $null
                    LatencyMinutes = $null; Failures = 0; LastResult = "-"; Status = "NotApplicable"
                    Reason = $null
                    HintKey = "ReplicationNoPartner"
                    PartitionScope = $partitionScope
                    PartitionsFound = [string[]]@()
                }
            }

            foreach ($p in $partners) {
                $lastOk = $p.LastReplicationSuccess
                # Kein Erfolgszeitpunkt = noch nie erfolgreich repliziert
                if (-not $lastOk -or $lastOk -eq [datetime]::MinValue) {
                    $ageMin = $null
                    $status = "Error"
                } else {
                    $ageMin = [int]((Get-Date) - $lastOk).TotalMinutes
                    $status = if ($ageMin -gt $maxMin) { "Error" } else { "OK" }
                }

                $res += [PSCustomObject]@{
                    Server         = $dc
                    Partner        = $p.PartnerAddress
                    Partition      = $p.Partition
                    LastSuccess    = $lastOk
                    LatencyMinutes = $ageMin
                    Failures       = [int]$p.ConsecutiveReplicationFailures
                    LastResult     = $p.LastReplicationResult
                    Status         = $status
                    Reason         = $null
                    HintKey         = $null
                    PartitionScope  = $partitionScope
                    PartitionsFound = $partitionsFound
                }
            }
        } catch {
            # Einziger DC der Domaene: der Fehlschlag ist hier kein Befund, sondern
            # die erwartete Antwort auf "zeig mir Partner, die es nicht gibt".
            if ($soloDC) {
                Write-ADHCLog -Message "$dc ist einziger Domaenencontroller — Replikationspruefung nicht anwendbar ($($_.Exception.Message))" -Component "Replication"
                $res += [PSCustomObject]@{
                    Server = $dc; Partner = "-"; Partition = "-"; LastSuccess = $null
                    LatencyMinutes = $null; Failures = 0; LastResult = "-"; Status = "NotApplicable"
                    # Der Originalfehler bleibt erhalten, damit die Einstufung
                    # nachvollziehbar ist und nicht als Tatsache erscheint.
                    Reason = $_.Exception.Message
                    HintKey = "ReplicationSingleDC"
                    PartitionScope = $partitionScope
                    PartitionsFound = [string[]]@()
                }
            } else {
                Write-ADHCLog -Message "Replikations-Metadaten von $dc nicht abrufbar: $($_.Exception.Message)" -Level Warning -Component "Replication"
                $res += [PSCustomObject]@{
                    Server = $dc; Partner = "-"; Partition = "-"; LastSuccess = $null
                    LatencyMinutes = $null; Failures = 0; LastResult = "-"; Status = "Unreachable"
                    Reason = $_.Exception.Message
                    HintKey = $null
                    PartitionScope = $partitionScope
                    # Nichts beantwortet — leere Liste statt $null, damit der Typ stabil bleibt
                    PartitionsFound = [string[]]@()
                }
            }
        }
    }
    return $res
}

function Get-ADEventLogRetention {
<#
.SYNOPSIS
    Prueft, wie weit die Ereignisprotokolle auf den DCs zurueckreichen.
.DESCRIPTION
    ACHTUNG — Auslegung von Thresholds.MaxEventLogAgeDays: Geprueft wird die
    VORHALTEDAUER, nicht das Alter einzelner Ereignisse. Reicht der aelteste
    Eintrag eines Logs WENIGER weit zurueck als MaxEventLogAgeDays, ist das
    Protokoll zu klein bzw. rotiert zu schnell, um einen Vorfall im Nachhinein
    noch analysieren zu koennen. Genau das ist der zu meldende Befund.

    Geprueft werden "Directory Service" und "System" — die beiden Logs, die bei
    AD-Vorfaellen zuerst gebraucht werden.
#>
    param($DCList, $Settings)

    $minDays = if ($Settings.Thresholds.MaxEventLogAgeDays) {
        [int]$Settings.Thresholds.MaxEventLogAgeDays
    } else { 30 }

    $logsToCheck = @("Directory Service", "System")
    $res = @()

    foreach ($dc in $DCList) {
        Write-ADHCLog -Message "Pruefe Ereignisprotokoll-Vorhaltedauer auf $dc..." -Component "EventLog"
        # Ist der erste Zugriff am RPC gescheitert, sind weitere Logs auf
        # DEMSELBEN DC aussichtslos — jeder Versuch kostet rund 20 Sekunden
        # Timeout. Nach einem Transportfehler die restlichen Logs ueberspringen.
        $dcUnreachable = $false
        $dcReason      = $null
        $dcHintKey     = $null

        foreach ($logName in $logsToCheck) {
            if ($dcUnreachable) {
                $res += [PSCustomObject]@{
                    Server = $dc; LogName = $logName; OldestEntry = $null
                    RetentionDays = $null; Status = "Unreachable"
                    Reason = $dcReason; HintKey = $dcHintKey
                }
                continue
            }

            try {
                # -Oldest liefert den aeltesten noch vorhandenen Eintrag; ein
                # einzelnes Event genuegt, das ist auch auf grossen Logs schnell.
                $oldest = Get-WinEvent -ComputerName $dc -LogName $logName -MaxEvents 1 -Oldest -ErrorAction Stop
                $days   = [int]((Get-Date) - $oldest.TimeCreated).TotalDays
                $res += [PSCustomObject]@{
                    Server        = $dc
                    LogName       = $logName
                    OldestEntry   = $oldest.TimeCreated
                    RetentionDays = $days
                    Status        = if ($days -lt $minDays) { "Error" } else { "OK" }
                    Reason        = $null
                    HintKey       = $null
                }
            } catch {
                $msg = $_.Exception.Message
                # Der Hinweis wird als i18n-SCHLUESSEL abgelegt, nicht als Text —
                # sonst stuende deutscher Hilfetext im englischen Report. Aufgeloest
                # wird er beim Rendern (siehe Reporting: $I18n.Labels.<Key>).
                $hintKey = if ($msg -match 'RPC server is unavailable|RPC-Server ist nicht verf') {
                    "HintRpcFirewall"
                } elseif ($msg -match 'Access is denied|Zugriff verweigert') {
                    "HintEventLogReaders"
                } else { $null }

                Write-ADHCLog -Message "Ereignisprotokoll '$logName' auf $dc nicht lesbar: $msg" -Level Warning -Component "EventLog"

                $dcUnreachable = $true
                $dcReason      = $msg
                $dcHintKey     = $hintKey
                $res += [PSCustomObject]@{
                    Server = $dc; LogName = $logName; OldestEntry = $null
                    RetentionDays = $null; Status = "Unreachable"
                    Reason = $dcReason; HintKey = $hintKey
                }
            }
        }
    }
    return $res
}

Export-ModuleMember -Function Get-ADHealthDiscovery, Get-ADServiceStatus, Invoke-DetailedDcdiag, Get-ADSecurityInfo, Get-ADFSMORoles, Get-ADDomainStats, Get-ADSitesInfo, Get-ADBackupStatus, Get-ADOUAndAccountSecurity, Get-ADHCMockData, Get-ADReplicationLatency, Get-ADEventLogRetention, Test-ADHCPortReachable