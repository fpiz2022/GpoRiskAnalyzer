function Get-TattooingRisk {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $ComparisonItem
    )

    Process {
        $risk = "None"
        $reason = ""
        $severity = "Info"

        # Case 1: Item Removed (Only in Reference/Old)
        if ($ComparisonItem.Status -eq "ONLY_IN_REF") {
            # If the OLD policy had a setting, and the NEW one doesn't...
            # Did the old policy ensure removal? 
            # Imprecise check without history, but generally "Removal of a GPO" is a tattooing event.
            $risk = "Medium"
            $reason = "Setting removed from scope. Verify if previous GPO ensured cleanup."
            $severity = "Warning"
            
            # Special check: If it was a Policy (Admin Template), the OS *usually* cleans it up.
            if ($ComparisonItem.RefObject.SettingType -eq "Policy") {
                $risk = "Low"
                $reason = "Policies (Admin Templates) are usually reverted by OS."
                $severity = "Info"
            }
        }
        # Case 2: Item Active (Present in Diff/New)
        elseif ($null -ne $ComparisonItem.DiffObject) {
            $obj = $ComparisonItem.DiffObject
            
            if ($obj.SettingType -eq "Preference") {
                # GPP Logic
                if ($obj.Action -eq "D" -or $obj.Action -eq "Delete") {
                    $risk = "None"
                    $reason = "Explicit Delete Action."
                }
                elseif ($obj.RemoveWhenNotApplied -eq "True") {
                    $risk = "Low"
                    $reason = "RemoveWhenNotApplied is active."
                }
                else {
                    # Standard GPP Create/Update/Replace without auto-remove
                    $risk = "High"
                    $reason = "GPP $($obj.Action) without RemoveWhenNotApplied. Will tattoo registry."
                    $severity = "High"
                }
            }
            elseif ($obj.SettingType -eq "Policy") {
                # Admin Template Logic
                # Standard Policies are safe.
                # "Tattooing" in Policies usually refers to modifying keys outside the managed keys (Policy branches).
                # Checking path (Basic heuristic)
                
                $safePaths = @("Software\Policies", "Software\Microsoft\Windows\CurrentVersion\Policies")
                $isSafe = $false
                foreach ($p in $safePaths) {
                    if ($obj.RegistryPath -like "*$p*") { $isSafe = $true }
                }

                if ($isSafe) {
                    $risk = "None"
                    $reason = "Native Policy Key (Managed)."
                } else {
                    $risk = "Medium"
                    $reason = "Policy affects non-standard policy key. May persist."
                    $severity = "Warning"
                }
            }
        }

        # Enrich the object
        $ComparisonItem | Add-Member -MemberType NoteProperty -Name "TattooingRisk" -Value $risk -Force
        $ComparisonItem | Add-Member -MemberType NoteProperty -Name "TattooingReason" -Value $reason -Force
        $ComparisonItem | Add-Member -MemberType NoteProperty -Name "Severity" -Value $severity -Force

        return $ComparisonItem
    }
}

Export-ModuleMember -Function Get-TattooingRisk
