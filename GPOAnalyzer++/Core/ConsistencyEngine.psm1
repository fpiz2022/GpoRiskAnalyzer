# ConsistencyEngine.psm1
# Logic for GPC vs GPT Consistency Check

function Get-GPCGPTConsistency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$TargetGuids,

        [Parameter(Mandatory = $false)]
        [string]$DomainName
    )

    $results = @()

    # 1. Determine Domain and SYSVOL Path
    try {
        if ([string]::IsNullOrWhiteSpace($DomainName)) {
            $DomainName = $env:USERDNSDOMAIN
            if ([string]::IsNullOrWhiteSpace($DomainName)) {
                # Fallback to local machine domain if possible
                $DomainName = (Get-WmiObject Win32_ComputerSystem).Domain
            }
        }

        $sysvolPoliciesPath = "\\$DomainName\SYSVOL\$DomainName\Policies"
    }
    catch {
        Write-Warning "Could not determine Domain or SYSVOL path: $_"
        return $results
    }

    # 2. Gather GPC Data (Active Directory)
    $gpcData = @{}
    try {
        $gpos = @()
        if ($TargetGuids -and $TargetGuids.Count -gt 0) {
            foreach ($guid in $TargetGuids) {
                # Ensure GUID is in {GUID} format
                $formattedGuid = $guid
                if ($guid -notmatch '^\{.*\}$') { $formattedGuid = "{$guid}" }

                $g = Get-ADGPO -Guid $formattedGuid -ErrorAction SilentlyContinue
                if ($g) { $gpos += $g }
            }
        }
        else {
            $gpos = Get-ADGPO -All -ErrorAction SilentlyContinue
        }

        foreach ($g in $gpos) {
            $id = $g.Id.ToString("B").ToUpper() # {GUID} format
            $gpcData[$id] = @{
                GPOName = $g.DisplayName
                Version = $g.VersionNumber
                Present = $true
            }
        }
    }
    catch {
        Write-Warning "Failed to retrieve GPC data from Active Directory: $_. Ensure ActiveDirectory module is installed and you are domain-joined."
    }

    # 3. Gather GPT Data (SYSVOL)
    $gptData = @{}
    if (Test-Path $sysvolPoliciesPath) {
        try {
            $folders = Get-ChildItem -Path $sysvolPoliciesPath -Directory
            foreach ($f in $folders) {
                if ($f.Name -match '\{[a-fA-F0-9-]{36}\}') {
                    $id = $f.Name.ToUpper()

                    # Optimization: if TargetGuids is set, skip folders not in target
                    if ($TargetGuids -and $TargetGuids.Count -gt 0) {
                        $match = $false
                        foreach ($tg in $TargetGuids) {
                            if ($id -eq $tg.ToUpper() -or $id -eq "{$($tg.ToUpper())}") {
                                $match = $true
                                break
                            }
                        }
                        if (-not $match) { continue }
                    }

                    $gptIni = Join-Path $f.FullName "gpt.ini"
                    $version = $null
                    if (Test-Path $gptIni) {
                        try {
                            $iniContent = Get-Content $gptIni -ErrorAction SilentlyContinue
                            foreach ($line in $iniContent) {
                                if ($line -match '^Version\s*=\s*(\d+)') {
                                    $version = [int]$Matches[1]
                                    break
                                }
                            }
                        }
                        catch {
                            Write-Warning "Failed to parse $gptIni"
                        }
                    }

                    # GPP Secret Audit (Scan XMLs for 'cpassword')
                    $hasGppSecrets = $false
                    try {
                        $xmlFiles = Get-ChildItem -Path $f.FullName -Recurse -Filter "*.xml" -ErrorAction SilentlyContinue
                        foreach ($xml in $xmlFiles) {
                            # Using Select-String for performance instead of full XML parsing
                            if (Select-String -Path $xml.FullName -Pattern 'cpassword="' -Quiet) {
                                $hasGppSecrets = $true
                                break
                            }
                        }
                    } catch {}

                    $gptData[$id] = @{
                        Version = $version
                        Present = $true
                        Path    = $f.FullName
                        HasGppSecrets = $hasGppSecrets
                    }
                }
            }
        }
        catch {
            Write-Warning "Failed to retrieve GPT data from SYSVOL: $_"
        }
    }
    else {
        Write-Warning "SYSVOL Policies path not found: $sysvolPoliciesPath"
    }

    # 4. Correlation and Result Generation
    # Combine all unique GUIDs from both sets
    $allGuids = ($gpcData.Keys + $gptData.Keys) | Select-Object -Unique

    foreach ($guid in $allGuids) {
        $gpc = $gpcData[$guid]
        $gpt = $gptData[$guid]

        $gpcPresent = if ($gpc) { $true } else { $false }
        $gptPresent = if ($gpt) { $true } else { $false }

        $gpoName = if ($gpc) { $gpc.GPOName } else { "Unknown_OrphanGPT" }

        $versionMatch = "Unknown"
        $status = "OK"
        $gppSecretsFound = if ($gpt) { $gpt.HasGppSecrets } else { $false }

        if ($gpcPresent -and $gptPresent) {
            if ($null -ne $gpc.Version -and $null -ne $gpt.Version) {
                if ($gpc.Version -eq $gpt.Version) {
                    $versionMatch = "True"
                    $status = "OK"
                }
                else {
                    $versionMatch = "False"
                    $status = "Version_Mismatch"
                }
            }
            else {
                $versionMatch = "Unknown"
                $status = "Version_Mismatch"
            }
        }
        elseif ($gpcPresent -and -not $gptPresent) {
            $versionMatch = "Unknown"
            $status = "Missing_SYSVOL"
        }
        elseif (-not $gpcPresent -and $gptPresent) {
            $versionMatch = "Unknown"
            $status = "Orphan_SYSVOL"
        }

        $results += [PSCustomObject]@{
            GPOName       = $gpoName
            GUID          = $guid
            GPC_Present   = $gpcPresent
            GPT_Present   = $gptPresent
            VersionMatch  = $versionMatch
            Status        = $status
            HasGPPSecrets = $gppSecretsFound
        }
    }

    return $results
}

Export-ModuleMember -Function Get-GPCGPTConsistency
