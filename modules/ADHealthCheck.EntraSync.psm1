# MODULE: ADHealthCheck.EntraSync.psm1

function Get-EntraSyncStatus {
    param($Settings)

    # Zugriff auf den korrekten Pfad in der settings.json (EntraID statt Entra)
    $serverName = $Settings.EntraID.SyncServer
    $servicesToCheck = $Settings.EntraID.ServicesToCheck
    
    Write-ADHCLog -Message "Prüfe Entra Connect Status auf '$serverName'..." -Component "EntraSync"

    if ([string]::IsNullOrWhiteSpace($serverName)) {
        Write-ADHCLog "FEHLER: SyncServer Name ist leer." -Level Error
        return $null
    }

    try {
        # Remote Abfrage via WinRM
        $result = Invoke-Command -ComputerName $serverName -ArgumentList (,$servicesToCheck) -ErrorAction Stop -ScriptBlock {
            param($svcNames)
            
            $svcStatus = @()
            $foundAny = $false

            foreach ($name in $svcNames) {
                $s = Get-Service | Where-Object { $_.DisplayName -eq $name -or $_.Name -eq $name }
                if ($s) {
                    $foundAny = $true
                    $svcStatus += [PSCustomObject]@{
                        Name   = $s.DisplayName
                        Status = $s.Status.ToString() # "Running" oder "Stopped"
                    }
                }
            }
            
            # Version aus Registry auslesen
            $version = "NotInstalled" # Standardmäßig auf nicht installiert setzen
            $uninstallKeys = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue
            
            $entraConnect = $uninstallKeys | Where-Object { 
                $_.DisplayName -like "*Microsoft Entra Connect Sync*" -or 
                $_.DisplayName -like "*Microsoft Azure AD Connect Sync*" 
            } | Select-Object -First 1
            
            if ($entraConnect) {
                $version = $entraConnect.DisplayVersion
            }

            return [PSCustomObject]@{
                Services         = $svcStatus
                InstalledVersion = $version
                FoundAnyService  = $foundAny
            }
        }

        # Rückgabe an das Hauptskript
        return [PSCustomObject]@{
            Server           = $serverName
            InstalledVersion = $result.InstalledVersion
            ExpectedVersion  = $Settings.EntraID.ExpectedAgentVersion
            ServiceDetails   = $result.Services
            FoundAnyService  = $result.FoundAnyService # Wichtig für die Logik im Report
        }

    } catch {
        Write-ADHCLog "Fehler bei Verbindung zu Entra Sync Server ($serverName): $_" -Level Error
        return [PSCustomObject]@{
            Server           = $serverName
            InstalledVersion = "Error"
            ExpectedVersion  = $Settings.EntraID.ExpectedAgentVersion
            ServiceDetails   = @()
            FoundAnyService  = $false
            Error            = $_.Exception.Message
        }
    }
}

Export-ModuleMember -Function Get-EntraSyncStatus