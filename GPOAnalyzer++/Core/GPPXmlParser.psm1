function Parse-GPPXml {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$Context = "Unknown"
    )

    if (-not (Test-Path $Path)) {
        Write-Error "File not found: $Path"
        return
    }

    try {
        [xml]$xml = Get-Content $Path
    }
    catch {
        Write-Error "Failed to parse XML: $_"
        return
    }

    $filename = Split-Path $Path -Leaf
    $category = "Preferences"
    $subCategory = $filename.Replace(".xml", "")
    
    $settings = @()

    # Generic recursive processor to find setting nodes
    # GPP XMLs usually have a hierarchy like <RegistrySettings><Registry ...><Properties .../></Registry></RegistrySettings>
    # We look for specific node types known to be items.

    # Mapping of Node Names to "meaningful" types
    $nodeTypes = @("Registry", "File", "Service", "ScheduledTask", "Shortcut", "DriveMap", "EnvironmentVariable", "Folder")

    $nodes = $xml.SelectNodes("//*[contains(' Registry File Service ScheduledTask Shortcut DriveMap EnvironmentVariable Folder ', concat(' ', local-name(), ' '))]")

    foreach ($node in $nodes) {
        # Determine specific attributes based on node type
        $nodeName = $node.LocalName
        $props = $node.Properties
        
        $action = $props.action
        if ([string]::IsNullOrEmpty($action)) { $action = $node.action } # Sometimes on the node itself
        
        $cstatus = "Active"
        if ($node.disabled -eq "1") { $cstatus = "Disabled" }

        # Base Object
        $obj = [PSCustomObject]@{
            SettingType      = "Preference"
            Category         = $category
            SubCategory      = $subCategory
            SourceFile       = $Path
            Context          = $Context
            Action           = $action
            RemoveWhenNotApplied = "False"
        }

        # Check for Common Options (RemoveWhenNotApplied is often in common:Options)
        # XML structure varies slightly, checking generic Filters/Options location if needed
        # Often it is not directly exposed in simple attributes, skipping complex common tab parsing for v1
        
        switch ($nodeName) {
            "Registry" {
                $obj | Add-Member -MemberType NoteProperty -Name "RegistryHive" -Value $props.hive -Force
                $obj | Add-Member -MemberType NoteProperty -Name "RegistryPath" -Value $props.key -Force
                $obj | Add-Member -MemberType NoteProperty -Name "ValueName" -Value $props.name -Force
                $obj | Add-Member -MemberType NoteProperty -Name "ValueType" -Value $props.type -Force
                $obj | Add-Member -MemberType NoteProperty -Name "ValueData" -Value $props.value -Force
                
                # Check for "removePolicy" which acts like tattooing prevention
                if ($node.removePolicy -eq "1") {
                   $obj.RemoveWhenNotApplied = "True"
                }
            }
            "File" {
                $obj | Add-Member -MemberType NoteProperty -Name "Source" -Value $props.fromPath -Force
                $obj | Add-Member -MemberType NoteProperty -Name "Destination" -Value $props.targetPath -Force
                $obj | Add-Member -MemberType NoteProperty -Name "ValueName" -Value "File Copy" -Force
                $obj | Add-Member -MemberType NoteProperty -Name "ValueData" -Value "$($props.fromPath) -> $($props.targetPath)" -Force
            }
            "Service" {
                $obj | Add-Member -MemberType NoteProperty -Name "ServiceName" -Value $props.serviceName -Force
                $obj | Add-Member -MemberType NoteProperty -Name "Startup" -Value $props.startup -Force
                $obj | Add-Member -MemberType NoteProperty -Name "ValueName" -Value $props.serviceName -Force
                $obj | Add-Member -MemberType NoteProperty -Name "ValueData" -Value "Startup: $($props.startup)" -Force
            }
            "DriveMap" {
                $obj | Add-Member -MemberType NoteProperty -Name "DriveLetter" -Value $props.letter -Force
                $obj | Add-Member -MemberType NoteProperty -Name "Path" -Value $props.path -Force
                $obj | Add-Member -MemberType NoteProperty -Name "ValueName" -Value "Drive Map $($props.letter)" -Force
                $obj | Add-Member -MemberType NoteProperty -Name "ValueData" -Value $props.path -Force
            }
            "EnvironmentVariable" {
                $obj | Add-Member -MemberType NoteProperty -Name "VarName" -Value $props.name -Force
                $obj | Add-Member -MemberType NoteProperty -Name "Value" -Value $props.value -Force
                $obj | Add-Member -MemberType NoteProperty -Name "ValueName" -Value $props.name -Force
                $obj | Add-Member -MemberType NoteProperty -Name "ValueData" -Value $props.value -Force
            }
            default {
                # Generic fallback
                $obj | Add-Member -MemberType NoteProperty -Name "ValueName" -Value $props.name -Force
                $obj | Add-Member -MemberType NoteProperty -Name "ValueData" -Value "See XML" -Force
            }
        }

        $settings += $obj
    }

    return $settings
}

Export-ModuleMember -Function Parse-GPPXml
