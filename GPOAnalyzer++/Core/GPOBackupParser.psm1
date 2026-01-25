# GPOBackupParser.psm1
function Get-GPOFromBackup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Path
    )

    Process {
        if (-not (Test-Path $Path)) {
            Write-Error "Path not found: $Path"
            return
        }

        # 1. Identify GPO Metadata
        $backupXmlPath = Join-Path $Path "Backup.xml"
        $gpoName = "Unknown GPO"
        $gpoGuid = "Unknown GUID"
        $domain = "Unknown Domain"

        if (Test-Path $backupXmlPath) {
            try {
                [xml]$xml = Get-Content $backupXmlPath
                # Handle varying root elements (GroupPolicyBackupScheme vs GroupPolicyBackup)
                $gpoObj = $xml.GroupPolicyBackupScheme.GroupPolicyObject
                if (-not $gpoObj) { $gpoObj = $xml.GroupPolicyBackup.GroupPolicyObject }
                
                if ($gpoObj) {
                    # Use InnerText to correctly handle CDATA sections within the elements
                    $gpoName = $gpoObj.GroupPolicyCoreSettings.DisplayName.InnerText
                    if ([string]::IsNullOrEmpty($gpoName)) { 
                        # Fallback for simple nodes if InnerText is empty (though unlikely for Elements)
                        $gpoName = $gpoObj.GroupPolicyCoreSettings.DisplayName 
                    }
                    
                    $gpoGuid = $gpoObj.GroupPolicyCoreSettings.ID.InnerText
                    if ([string]::IsNullOrEmpty($gpoGuid)) { $gpoGuid = $gpoObj.GroupPolicyCoreSettings.ID }
                    
                    $domain = $gpoObj.GroupPolicyCoreSettings.Domain.InnerText
                }
            }
            catch {
                Write-Warning "Failed to parse Backup.xml in $Path"
            }
        }
        else {
            $folderName = Split-Path $Path -Leaf
            if ($folderName -match '\{[a-fA-F0-9-]{36}\}') {
                $gpoGuid = $folderName
            }
        }

        Write-Verbose "Analyzing GPO: $gpoName ($gpoGuid)"
        $allSettings = @()

        # 2. Parse Administrative Templates (Registry.pol)
        
        # Computer Configuration
        $computerPol = Join-Path $Path "DomainSysvol\GPO\Machine\registry.pol"
        if (Test-Path $computerPol) {
            Write-Verbose "Found Computer Registry.pol at $computerPol"
            try {
                $polSettings = @(Import-RegistryPol -Path $computerPol)
                if ($null -eq $polSettings) { Write-Verbose "  > Parse returned null" }
                else { Write-Verbose "  > Parse returned $($polSettings.Count) entries" }

                foreach ($s in $polSettings) {
                    $settingObj = [PSCustomObject]@{
                        GPOName      = $gpoName
                        GPOGuid      = $gpoGuid
                        SettingType  = "Policy"
                        Category     = "Administrative Templates"
                        SubCategory  = "Registry"
                        RegistryHive = "HKLM"
                        RegistryPath = $s.RegistryPath
                        ValueName    = $s.ValueName
                        ValueData    = $s.ValueData
                        SourceFile   = $s.SourceFile
                        Context      = "Computer"
                    }
                    $allSettings += $settingObj
                }
            }
            catch {
                Write-Warning "Error parsing Computer Registry.pol: $_"
            }
        }

        # User Configuration
        $userPol = Join-Path $Path "DomainSysvol\GPO\User\registry.pol"
        if (Test-Path $userPol) {
            Write-Verbose "Found User Registry.pol at $userPol"
            try {
                $polSettings = @(Import-RegistryPol -Path $userPol)
                foreach ($s in $polSettings) {
                    $settingObj = [PSCustomObject]@{
                        GPOName      = $gpoName
                        GPOGuid      = $gpoGuid
                        SettingType  = "Policy"
                        Category     = "Administrative Templates"
                        SubCategory  = "Registry"
                        RegistryHive = "HKCU"
                        RegistryPath = $s.RegistryPath
                        ValueName    = $s.ValueName
                        ValueData    = $s.ValueData
                        SourceFile   = $s.SourceFile
                        Context      = "User"
                    }
                    $allSettings += $settingObj
                }
            }
            catch {
                Write-Warning "Error parsing User Registry.pol: $_"
            }
        }

        # 3. Parse Group Policy Preferences (XML)
        $prefPaths = @(
            @{ Path = "DomainSysvol\GPO\Machine\Preferences"; Context = "Computer" },
            @{ Path = "DomainSysvol\GPO\User\Preferences"; Context = "User" }
        )

        foreach ($loc in $prefPaths) {
            $fullPath = Join-Path $Path $loc.Path
            if (Test-Path $fullPath) {
                Write-Verbose "Checking preferences at $fullPath"
                $xmlFiles = Get-ChildItem -Path $fullPath -Recurse -Filter "*.xml"
                foreach ($file in $xmlFiles) {
                    if (Get-Command "Import-GPPXml" -ErrorAction SilentlyContinue) {
                        try {
                            $gppSettings = Import-GPPXml -Path $file.FullName -Context $loc.Context
                            foreach ($s in $gppSettings) {
                                # Re-create object to enforce property order with GPOName first
                                $orderedProps = [ordered]@{
                                    GPOName = $gpoName
                                    GPOGuid = $gpoGuid
                                }
                                # Add valid properties from original object
                                foreach ($prop in $s.PSObject.Properties) {
                                    $orderedProps[$prop.Name] = $prop.Value
                                }
                                $allSettings += [PSCustomObject]$orderedProps
                            }
                        }
                        catch {
                            Write-Verbose "GPP Parsing failed for $($file.Name): $_"
                        }
                    }
                }
            }
        }

        return $allSettings
    }
}
Export-ModuleMember -Function Get-GPOFromBackup

