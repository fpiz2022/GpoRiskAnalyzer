function Compare-GPO {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Object[]]$ReferenceSettings,

        [Parameter(Mandatory = $true)]
        [Object[]]$DifferenceSettings
    )

    $results = @()
    
    # Helper to generate unique key for comparison
    function Get-ObjectKey ($obj) {
        if ($null -eq $obj) { return "" }
        # Base key components: Context + Hive + Path + ValueName
        # This covers most Registry/GPP Registry scenarios
        
        # Determine Path/Name for non-registry items based on common props
        $path = $obj.RegistryPath
        if ([string]::IsNullOrEmpty($path)) { $path = $obj.SubCategory } # Fallback
        
        $valName = $obj.ValueName
        
        $k = "$($obj.Context)|$($obj.RegistryHive)|$path|$valName"
        return $k.ToLower() # Case insensitive comparison
    }

    $refMap = @{}
    foreach ($item in $ReferenceSettings) {
        $key = Get-ObjectKey $item
        if (-not $refMap.ContainsKey($key)) {
            $refMap[$key] = $item
        }
    }

    $diffMap = @{}
    foreach ($item in $DifferenceSettings) {
        $key = Get-ObjectKey $item
        if (-not $diffMap.ContainsKey($key)) {
            $diffMap[$key] = $item
        }
    }

    # 1. Check Reference items against Difference
    foreach ($key in $refMap.Keys) {
        $refItem = $refMap[$key]
        $diffItem = $diffMap[$key]

        $status = "UNKNOWN"
        
        if ($null -eq $diffItem) {
            $status = "ONLY_IN_REF"
            
            $res = [PSCustomObject]@{
                Key = $key
                Parameter = $refItem.ValueName
                Path = $refItem.RegistryPath
                RefValue = $refItem.ValueData
                DiffValue = $null
                Status = $status
                RefSource = $refItem.SourceFile
                DiffSource = $null
                Context = $refItem.Context
                # Keep original object for tattooing analysis
                RefObject = $refItem
                DiffObject = $null
            }
            $results += $res
        }
        else {
            # Normalize values for string comparison
            $v1 = "$($refItem.ValueData)"
            $v2 = "$($diffItem.ValueData)"

            if ($v1 -eq $v2) {
                $status = "IDENTICAL"
            } else {
                $status = "DIFFERENT"
            }

            $res = [PSCustomObject]@{
                Key = $key
                Parameter = $refItem.ValueName
                Path = $refItem.RegistryPath
                RefValue = $refItem.ValueData
                DiffValue = $diffItem.ValueData
                Status = $status
                RefSource = $refItem.SourceFile
                DiffSource = $diffItem.SourceFile
                Context = $refItem.Context
                RefObject = $refItem
                DiffObject = $diffItem
            }
            $results += $res
        }
    }

    # 2. Check Difference items not in Reference
    foreach ($key in $diffMap.Keys) {
        if (-not $refMap.ContainsKey($key)) {
             $diffItem = $diffMap[$key]
             $status = "ONLY_IN_DIFF"

             $res = [PSCustomObject]@{
                Key = $key
                Parameter = $diffItem.ValueName
                Path = $diffItem.RegistryPath
                RefValue = $null
                DiffValue = $diffItem.ValueData
                Status = $status
                RefSource = $null
                DiffSource = $diffItem.SourceFile
                Context = $diffItem.Context
                RefObject = $null
                DiffObject = $diffItem
            }
            $results += $res
        }
    }

    return $results
}

Export-ModuleMember -Function Compare-GPO
