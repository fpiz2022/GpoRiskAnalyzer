# DomainInventory.psm1
# Module for Domain Controllers Inventory and Reporting

function Get-DomainControllersInventory {
    [CmdletBinding()]
    param(
        [string]$DomainName
    )

    $results = @()

    Log-Message "Starting Domain Controllers Inventory..."

    try {
        if ([string]::IsNullOrWhiteSpace($DomainName)) {
            $adDomain = Get-ADDomain
            $adForest = Get-ADForest
        } else {
            $adDomain = Get-ADDomain -Identity $DomainName
            $adForest = Get-ADForest -Identity $adDomain.Forest
        }

        Log-Message "Domain detected: $($adDomain.Name)"
        $dcs = Get-ADDomainController -Filter * -Server $adDomain.DNSRoot
    }
    catch {
        $msg = "Failed to enumerate Domain Controllers: $_"
        Log-Message "ERROR: $msg"
        Write-Error $msg
        return $results
    }

    Log-Message "Found $($dcs.Count) Domain Controllers. Starting parallel collection..."

    # Prepare data for parallel execution
    $jobs = @()
    foreach ($dc in $dcs) {
        $dcInfo = @{
            Name = $dc.Name
            HostName = $dc.HostName
            Site = $dc.Site
            IsReadOnly = $dc.IsReadOnly
            IsGlobalCatalog = $dc.IsGlobalCatalog
            OperationMasterRoles = $dc.OperationMasterRoles
            OperatingSystem = $dc.OperatingSystem
            OperatingSystemVersion = $dc.OperatingSystemVersion
            DomainName = $adDomain.Name
            ForestName = $adForest.Name
            DomainMode = $adDomain.DomainMode
            ForestMode = $adForest.ForestMode
        }

        # Start-ThreadJob is better for performance if available, falling back to Start-Job or manual processing
        # In this environment we'll simulate parallel logic or use a script block for a potential ForEach -Parallel
        $jobs += Start-Job -ScriptBlock {
            param($info)
            $dcName = $info.HostName

            # Initialize record
            $dcData = [ordered]@{
                HostName               = $info.Name
                Status                 = "OK"
                FQDN                   = $info.HostName
                Forest                 = $info.ForestName
                Domain                 = $info.DomainName
                Site_AD                = $info.Site
                ReadOnly               = $info.IsReadOnly
                GlobalCatalog          = $info.IsGlobalCatalog
                FSMORolesOwner         = ($info.OperationMasterRoles -join ";")
                OSVersion              = "$($info.OperatingSystem) $($info.OperatingSystemVersion)"
                NetFrameworkVersion    = "N/A"
                TimeZone               = "N/A"
                DiskC_Free_GB          = "N/A"
                UptimeDays             = "N/A"
                DomainFunctionalLevel  = $info.DomainMode
                ForestFunctionalLevel  = $info.ForestMode
                DNSRole                = "False"
                DNSServerScavenging    = "N/A"
                DNS_Forwarders         = "N/A"
                NIC_Name               = "N/A"
                NIC_MAC                = "N/A"
                NIC_IP                 = "N/A"
                NIC_SubnetMask         = "N/A"
                NIC_Gateway            = "N/A"
                LastHotfixKB           = "N/A"
                LastHotfixDate         = "N/A"
                Running_services       = "N/A"
            }

            # Connectivity Check
            if (-not (Test-Connection -ComputerName $dcName -Count 1 -Quiet)) {
                $dcData.Status = "Unreachable"
                return [PSCustomObject]$dcData
            }

            $session = $null
            try {
                $cimOptions = New-CimSessionOption -ConnectTimeout (New-TimeSpan -Seconds 5)
                $session = New-CimSession -ComputerName $dcName -SessionOption $cimOptions -ErrorAction Stop

                # OS & Uptime
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -CimSession $session -ErrorAction SilentlyContinue
                if ($os) {
                    $dcData.OSVersion = "$($os.Caption) ($($os.Version))"
                    $dcData.TimeZone = $os.CurrentTimeZone
                    if ($os.LastBootUpTime) {
                        $uptime = (Get-Date) - $os.LastBootUpTime
                        $dcData.UptimeDays = [math]::Round($uptime.TotalDays, 2)
                    }
                }

                # Disk
                $diskC = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -CimSession $session -ErrorAction SilentlyContinue
                if ($diskC) {
                    $dcData.DiskC_Free_GB = [math]::Round($diskC.FreeSpace / 1GB, 2)
                }

                # DNS
                $dnsService = Get-CimInstance -ClassName Win32_Service -Filter "Name='DNS'" -CimSession $session -ErrorAction SilentlyContinue
                if ($dnsService -and $dnsService.State -eq 'Running') {
                    $dcData.DNSRole = "True"
                    try {
                        $dnsServer = Get-CimInstance -Namespace root\MicrosoftDNS -ClassName MicrosoftDNS_Server -CimSession $session -ErrorAction SilentlyContinue
                        if ($dnsServer) {
                            $dcData.DNSServerScavenging = $dnsServer.ScavengingInterval
                            if ($dnsServer.Forwarders) { $dcData.DNS_Forwarders = ($dnsServer.Forwarders -join ";") }
                        }
                    } catch {}
                }

                # Network
                $nics = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -CimSession $session -ErrorAction SilentlyContinue
                if ($nics) {
                    $dcData.NIC_Name = ($nics.Description -unique) -join ";"
                    $dcData.NIC_MAC = ($nics.MACAddress -unique) -join ";"
                    $ips = @(); $masks = @(); $gateways = @()
                    foreach($n in $nics) {
                        $ips += $n.IPAddress; $masks += $n.IPSubnet
                        if ($n.DefaultIPGateway) { $gateways += $n.DefaultIPGateway }
                    }
                    $dcData.NIC_IP = ($ips -unique) -join ";"
                    $dcData.NIC_SubnetMask = ($masks -unique) -join ";"
                    $dcData.NIC_Gateway = ($gateways -unique) -join ";"
                }

                # Hotfixes
                $qfe = Get-CimInstance -ClassName Win32_QuickFixEngineering -CimSession $session -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending
                if ($qfe) {
                    $last = $qfe[0]
                    $dcData.LastHotfixKB = $last.HotFixID
                    $dcData.LastHotfixDate = $last.InstalledOn
                }

                # Services
                $running = Get-CimInstance -ClassName Win32_Service -Filter "State='Running'" -CimSession $session -ErrorAction SilentlyContinue
                if ($running) {
                    $dcData.Running_services = ($running.Name) -join ";"
                }

                # .NET
                try {
                    $res = Invoke-CimMethod -CimSession $session -Namespace root\default -ClassName StdRegProv -MethodName GetStringValue -Arguments @{
                        hDefKey = [uint32]2147483650
                        sSubKeyName = "SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
                        sValueName = "Version"
                    } -ErrorAction SilentlyContinue
                    if ($res.ReturnValue -eq 0 -and $res.sValue) { $dcData.NetFrameworkVersion = $res.sValue }
                } catch {}
            }
            catch {
                if ($_.Exception.Message -match "Access is denied" -or $_.Exception.Message -match "0x80070005") {
                    $dcData.Status = "AccessDenied"
                } else {
                    $dcData.Status = "Partial"
                }
            }
            finally {
                if ($session) { Remove-CimSession $session -ErrorAction SilentlyContinue }
            }
            return [PSCustomObject]$dcData
        } -ArgumentList $dcInfo
    }

    # Wait for all jobs and collect results
    $results = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job

    return $results
}

Export-ModuleMember -Function Get-DomainControllersInventory
