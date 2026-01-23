function Import-RegistryPol {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Error "File not found: $Path"
        return
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
    }
    catch {
        Write-Error "Failed to read file: $_"
        return
    }

    # Header Check (PReg)
    if ($bytes.Length -lt 8) {
        Write-Error "File is too short to be a valid Registry.pol file."
        return
    }

    $signature = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4)
    if ($signature -ne "PReg") {
        Write-Error "Invalid file signature. Expected 'PReg', found '$signature'."
        return
    }

    # Version Check (1.0)
    $version = [BitConverter]::ToUInt32($bytes, 4)
    if ($version -ne 1) {
        Write-Warning "Unknown version: $version. Parsing may fail."
    }

    $offset = 8
    $entries = @()

    while ($offset -lt $bytes.Length) {
        # 1. Read Key (WCHAR, null-terminated)
        $keyStart = $offset
        while ($offset -lt $bytes.Length -1 -and -not ($bytes[$offset] -eq 0 -and $bytes[$offset+1] -eq 0)) {
            $offset += 2
        }
        $keyLength = $offset - $keyStart
        $key = [System.Text.Encoding]::Unicode.GetString($bytes, $keyStart, $keyLength)
        $offset += 2 # Skip null terminator

        # 2. Read Value Name (WCHAR, null-terminated)
        if ($offset -ge $bytes.Length) { break }
        
        $valStart = $offset
        while ($offset -lt $bytes.Length -1 -and -not ($bytes[$offset] -eq 0 -and $bytes[$offset+1] -eq 0)) {
            $offset += 2
        }
        $valLength = $offset - $valStart
        $valueName = [System.Text.Encoding]::Unicode.GetString($bytes, $valStart, $valLength)
        $offset += 2 # Skip null terminator

        # 3. Read Type (DWORD)
        if ($offset + 4 -gt $bytes.Length) { break }
        $type = [BitConverter]::ToUInt32($bytes, $offset)
        $offset += 4

        # 4. Read Size (DWORD)
        if ($offset + 4 -gt $bytes.Length) { break }
        $size = [BitConverter]::ToUInt32($bytes, $offset)
        $offset += 4

        # 5. Read Data
        if ($offset + $size -gt $bytes.Length) { break }
        $rawData = $bytes[$offset..($offset + $size - 1)]
        $offset += $size

        # Expand Data based on Type
        $dataValue = $null
        switch ($type) {
            1 { # REG_SZ
                # Remove trailing nulls if present for display consistency
                $str = [System.Text.Encoding]::Unicode.GetString($rawData)
                $dataValue = $str.Trim([char]0)
            }
            2 { # REG_EXPAND_SZ
                $str = [System.Text.Encoding]::Unicode.GetString($rawData)
                $dataValue = $str.Trim([char]0)
            }
            3 { # REG_BINARY
                $dataValue = [BitConverter]::ToString($rawData)
            }
            4 { # REG_DWORD
                if ($rawData.Length -ge 4) {
                    $dataValue = [BitConverter]::ToUInt32($rawData, 0)
                } else {
                    $dataValue = $rawData # Fallback
                }
            }
            7 { # REG_MULTI_SZ
                $str = [System.Text.Encoding]::Unicode.GetString($rawData)
                $dataValue = $str.Split([char]0) | Where-Object { $_ -ne "" }
            }
            11 { # REG_QWORD
                if ($rawData.Length -ge 8) {
                    $dataValue = [BitConverter]::ToUInt64($rawData, 0)
                }
            }
            default {
                $dataValue = [BitConverter]::ToString($rawData)
            }
        }
        
        # Mappa i valori al modello GPOSetting (se disponibile) o PSCustomObject
        # Nota: GPO Name/Guid non sono nel file .pol, vanno arricchiti esternamente
        $entry = [PSCustomObject]@{
            RegistryPath = $key
            ValueName    = $valueName
            ValueData    = $dataValue
            ValueType    = $type
            ValueSize    = $size
            SourceFile   = $Path
            RegistryHive = "HKLM/HKCU" # Dipende da dove si trova il file (Machine/User)
            Category     = "Registry"
        }
        
        $entries += $entry
    }

    return $entries
}

Export-ModuleMember -Function Import-RegistryPol
