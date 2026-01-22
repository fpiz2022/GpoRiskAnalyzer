Import-Module "$PSScriptRoot\GPOAnalyzer++\Core\RegistryPolParser.psm1" -Force

# Helper to create a Pol file
function New-MockPolFile {
    param($Path)
    
    $stream = [System.IO.File]::Create($Path)
    $writer = New-Object System.IO.BinaryWriter($stream)

    # Header: PReg + Version 1
    $writer.Write([char[]]"PReg")
    $writer.Write([int]1)

    # Entry 1: REG_SZ
    $key = "Software\TestParams"
    $val = "TestValue"
    $data = "Hello World"
    
    # Write Key
    $writer.Write([System.Text.Encoding]::Unicode.GetBytes($key))
    $writer.Write([int16]0) # Null terminator
    
    # Write Value Name
    $writer.Write([System.Text.Encoding]::Unicode.GetBytes($val))
    $writer.Write([int16]0)
    
    # Write Type (REG_SZ = 1)
    $writer.Write([int]1)
    
    # Write Size
    $dataBytes = [System.Text.Encoding]::Unicode.GetBytes($data)
    $writer.Write([int]($dataBytes.Length + 2)) # +2 for null
    
    # Write Data
    $writer.Write($dataBytes)
    $writer.Write([int16]0)
    
    # Entry 2: REG_DWORD
    $key2 = "Software\TestParams"
    $val2 = "DwordValue"
    $data2 = 12345
    
    $writer.Write([System.Text.Encoding]::Unicode.GetBytes($key2))
    $writer.Write([int16]0)
    
    $writer.Write([System.Text.Encoding]::Unicode.GetBytes($val2))
    $writer.Write([int16]0)
    
    $writer.Write([int]4) # REG_DWORD
    $writer.Write([int]4) # Size
    $writer.Write([int]$data2)

    $writer.Close()
    $stream.Close()
}

$mockPath = "$PSScriptRoot\mock.pol"
New-MockPolFile -Path $mockPath

Write-Host "Parsing mock file..."
$results = Parse-RegistryPol -Path $mockPath

$results | Format-Table -AutoSize

# Cleanup
Remove-Item $mockPath
