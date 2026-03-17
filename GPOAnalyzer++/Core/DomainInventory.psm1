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

    Log-Message "Found $($dcs.Count) Domain Controllers."

    foreach ($dc in $dcs) {
        $dcName = $dc.HostName
        Log-Message "Processing DC: $dcName"

        # Initialize record with AD-available data
        $dcData = [ordered]@{
            HostName               = $dc.Name
            Status                 = "OK"
            FQDN                   = $dc.HostName
            Forest                 = $adForest.Name
            Domain                 = $adDomain.Name
            Site_AD                = $dc.Site
            ReadOnly               = $dc.IsReadOnly
            GlobalCatalog          = $dc.IsGlobalCatalog
            FSMORolesOwner         = ($dc.OperationMasterRoles -join ";")
            OSVersion              = "$($dc.OperatingSystem) $($dc.OperatingSystemVersion)"
            NetFrameworkVersion    = "N/A"
            TimeZone               = "N/A"
            DiskC_Free_GB          = "N/A"
            UptimeDays             = "N/A"
            DomainFunctionalLevel  = $adDomain.DomainMode
            ForestFunctionalLevel  = $adForest.ForestMode
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
            Log-Message "DC $dcName is unreachable."
            $dcData.Status = "Unreachable"
            $results += [PSCustomObject]$dcData
            continue
        }

        $session = $null
        try {
            # Remote Data Collection via CIM/WMI
            $cimOptions = New-CimSessionOption -ConnectTimeout (New-TimeSpan -Seconds 5)
            $session = New-CimSession -ComputerName $dcName -SessionOption $cimOptions -ErrorAction Stop

            # 1. OS Info & Uptime & TimeZone
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -CimSession $session -ErrorAction SilentlyContinue
            if ($os) {
                $dcData.OSVersion = "$($os.Caption) ($($os.Version))"
                $dcData.TimeZone = $os.CurrentTimeZone
                if ($os.LastBootUpTime) {
                    $uptime = (Get-Date) - $os.LastBootUpTime
                    $dcData.UptimeDays = [math]::Round($uptime.TotalDays, 2)
                }
            }

            # 2. Disk Info
            $diskC = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -CimSession $session -ErrorAction SilentlyContinue
            if ($diskC) {
                $dcData.DiskC_Free_GB = [math]::Round($diskC.FreeSpace / 1GB, 2)
            }

            # 3. DNS Role & Basic Config
            $dnsService = Get-CimInstance -ClassName Win32_Service -Filter "Name='DNS'" -CimSession $session -ErrorAction SilentlyContinue
            if ($dnsService -and $dnsService.State -eq 'Running') {
                $dcData.DNSRole = "True"

                # Try to get DNS info via WMI if possible (MicrosoftDNS namespace)
                try {
                    $dnsServer = Get-CimInstance -Namespace root\MicrosoftDNS -ClassName MicrosoftDNS_Server -CimSession $session -ErrorAction SilentlyContinue
                    if ($dnsServer) {
                        $dcData.DNSServerScavenging = $dnsServer.ScavengingInterval
                        if ($dnsServer.Forwarders) {
                            $dcData.DNS_Forwarders = ($dnsServer.Forwarders -join ";")
                        }
                    }
                } catch {
                    Log-Message "Could not access MicrosoftDNS namespace on $dcName"
                }
            }

            # 4. Network Info
            $nics = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -CimSession $session -ErrorAction SilentlyContinue
            if ($nics) {
                $dcData.NIC_Name = ($nics.Description -unique) -join ";"
                $dcData.NIC_MAC = ($nics.MACAddress -unique) -join ";"

                $ips = @()
                $masks = @()
                $gateways = @()
                foreach($n in $nics) {
                    $ips += $n.IPAddress
                    $masks += $n.IPSubnet
                    if ($n.DefaultIPGateway) { $gateways += $n.DefaultIPGateway }
                }
                $dcData.NIC_IP = ($ips -unique) -join ";"
                $dcData.NIC_SubnetMask = ($masks -unique) -join ";"
                $dcData.NIC_Gateway = ($gateways -unique) -join ";"
            }

            # 5. Hotfixes
            $qfe = Get-CimInstance -ClassName Win32_QuickFixEngineering -CimSession $session -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending
            if ($qfe) {
                $last = $qfe[0]
                $dcData.LastHotfixKB = $last.HotFixID
                $dcData.LastHotfixDate = $last.InstalledOn
            }

            # 6. Running Services
            $running = Get-CimInstance -ClassName Win32_Service -Filter "State='Running'" -CimSession $session -ErrorAction SilentlyContinue
            if ($running) {
                $dcData.Running_services = ($running.Name) -join ";"
            }

            # 7. .NET Framework (via WMI/CIM StdRegProv)
            try {
                $reg = Get-CimInstance -Namespace root\default -ClassName StdRegProv -CimSession $session -ErrorAction SilentlyContinue
                if ($reg) {
                    # HKLM = 2147483650
                    $res = Invoke-CimMethod -CimSession $session -Namespace root\default -ClassName StdRegProv -MethodName GetStringValue -Arguments @{
                        hDefKey = [uint32]2147483650
                        sSubKeyName = "SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
                        sValueName = "Version"
                    } -ErrorAction SilentlyContinue
                    if ($res.ReturnValue -eq 0 -and $res.sValue) {
                        $dcData.NetFrameworkVersion = $res.sValue
                    }
                }
            } catch {
                Log-Message "Failed to read .NET version on $dcName"
            }
        }
        catch {
            if ($_.Exception.Message -match "Access is denied" -or $_.Exception.Message -match "0x80070005") {
                $dcData.Status = "AccessDenied"
            } else {
                $dcData.Status = "Partial"
            }
            Log-Message "WARNING: Issue during data collection for $dcName : $_"
        }
        finally {
            if ($null -ne $session) {
                Remove-CimSession $session -ErrorAction SilentlyContinue
            }
        }

        $results += [PSCustomObject]$dcData
    }

    return $results
}

Export-ModuleMember -Function Get-DomainControllersInventory
