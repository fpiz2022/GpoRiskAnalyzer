# GPO Analyzer ++ Integration Test (Headless)

$ErrorActionPreference = "Stop"

$root = "$PSScriptRoot\GPOAnalyzer++"
$mockDir = "$PSScriptRoot\MockGPOBackup"

Write-Host "[INIT] Loading Modules..."
Try {
    Import-Module "$root\Core\GPOBackupParser.psm1" -Force -ErrorAction Stop
    Import-Module "$root\Core\RegistryPolParser.psm1" -Force -ErrorAction Stop
    Import-Module "$root\Core\GPPXmlParser.psm1" -Force -ErrorAction Stop
    Import-Module "$root\Core\DiffEngine.psm1" -Force -ErrorAction Stop
    Import-Module "$root\Core\TattooingAnalyzer.psm1" -Force -ErrorAction Stop
    Import-Module "$root\Export\ExportHtml.psm1" -Force -ErrorAction Stop
}
Catch {
    Write-Error "Failed to load modules: $_"
    exit 1
}

# 1. Setup Mock Data
Write-Host "[SETUP] Creating Mock Environment..."
if (Test-Path $mockDir) { Remove-Item $mockDir -Recurse -Force }
New-Item -Path $mockDir -ItemType Directory | Out-Null

# GPO 1: Base Policy
$gpo1Path = Join-Path $mockDir "{GUID-111}"
New-Item -Path "$gpo1Path\DomainSysvol\GPO\Machine" -ItemType Directory -Force | Out-Null
Set-Content "$gpo1Path\Backup.xml" -Value '<GroupPolicyBackup><GroupPolicyObject><GroupPolicyCoreSettings><DisplayName>Base Security</DisplayName><ID>{GUID-111}</ID><Domain>test.local</Domain></GroupPolicyCoreSettings></GroupPolicyObject></GroupPolicyBackup>'

# Create a valid Pol file for GPO 1 manually (binary safe)
$polPath = "$gpo1Path\DomainSysvol\GPO\Machine\registry.pol"
$fs = [System.IO.File]::Create($polPath)
$bw = New-Object System.IO.BinaryWriter($fs)

# Header: PReg (0x50 0x52 0x65 0x67)
$bw.Write([byte]0x50); $bw.Write([byte]0x52); $bw.Write([byte]0x65); $bw.Write([byte]0x67)
# Version: 1 (DWORD)
$bw.Write([int]1)

# Body:
# Key: [Software\Policies\Test] (WCHAR + null)
$keyBytes = [System.Text.Encoding]::Unicode.GetBytes("Software\Policies\Test")
$bw.Write($keyBytes); $bw.Write([int16]0)
# Val: [SafeSetting] (WCHAR + null)
$valBytes = [System.Text.Encoding]::Unicode.GetBytes("SafeSetting")
$bw.Write($valBytes); $bw.Write([int16]0)
# Type: REG_SZ (1)
$bw.Write([int]1)
# Size: Data Length (Bytes) + 2 (null)
$dataBytes = [System.Text.Encoding]::Unicode.GetBytes("1")
$bw.Write([int]($dataBytes.Length + 2))
# Data: [1] (WCHAR + null)
$bw.Write($dataBytes); $bw.Write([int16]0)

$bw.Close(); $fs.Close()


# GPO 2: Tattooing Policy
$gpo2Path = Join-Path $mockDir "{GUID-222}"
New-Item -Path "$gpo2Path\DomainSysvol\GPO\Machine" -ItemType Directory -Force | Out-Null
New-Item -Path "$gpo2Path\DomainSysvol\GPO\Machine\Preferences" -ItemType Directory -Force | Out-Null
Set-Content "$gpo2Path\Backup.xml" -Value '<GroupPolicyBackup><GroupPolicyObject><GroupPolicyCoreSettings><DisplayName>Tattooing Risky</DisplayName><ID>{GUID-222}</ID><Domain>test.local</Domain></GroupPolicyCoreSettings></GroupPolicyObject></GroupPolicyBackup>'

# GPO 2 has a GPP XML
Set-Content "$gpo2Path\DomainSysvol\GPO\Machine\Preferences\Groups.xml" -Value '<?xml version="1.0" encoding="utf-8"?><RegistrySettings><Registry name="BadKey" action="U"><Properties hive="HKEY_LOCAL_MACHINE" key="Software\Bad" name="TattooMe" type="REG_SZ" value="PersistForever"/></Registry></RegistrySettings>'

# 2. Test Parser
Write-Host "[TEST] Parsing GPOs..."
$gpo1Settings = Get-GPOFromBackup -Path $gpo1Path
$gpo2Settings = Get-GPOFromBackup -Path $gpo2Path

Write-Host "  > GPO 1 Settings: $(@($gpo1Settings).Count) (Expected 1)"
if (@($gpo1Settings).Count -ne 1) { 
    Write-Warning "Parser returned empty for GPO 1. Debugging RegistryPolParser logic may be needed." 
    # Try parsing pol directly to see error
    Parse-RegistryPol -Path $polPath
    throw "GPO 1 parsing failed." 
}

Write-Host "  > GPO 2 Settings: $(@($gpo2Settings).Count) (Expected 1)"
if (@($gpo2Settings).Count -ne 1) { throw "GPO 2 parsing failed." }

# 3. Test Diff & Risk Analysis
Write-Host "[TEST] Comparing GPOs..."
$diff = Compare-GPO -ReferenceSettings $gpo1Settings -DifferenceSettings $gpo2Settings
Write-Host "  > Diff Result Count: $($diff.Count) (Expected 2)"
if ($diff.Count -ne 2) { 
   $diff | Format-Table 
   throw "Diff failed count check" 
}

$analyzed = $diff | Get-TattooingRisk

$riskHigh = $analyzed | Where-Object { $_.TattooingRisk -eq "High" }
Write-Host "  > High Risk Count: $($riskHigh.Count) (Expected 1)"
if (@($riskHigh).Count -ne 1) { $analyzed | Format-Table -AutoSize; throw "Risk Analysis failed." }

# 4. Test Export
Write-Host "[TEST] Exporting HTML..."
Export-ToHtml -Data $analyzed -Path "$PSScriptRoot\TestReport.html"
if (Test-Path "$PSScriptRoot\TestReport.html") {
    Write-Host "  > Export Success: TestReport.html created." -ForegroundColor Green
} else {
    throw "Export failed."
}

Write-Host "ALL TESTS PASSED" -ForegroundColor Cyan


