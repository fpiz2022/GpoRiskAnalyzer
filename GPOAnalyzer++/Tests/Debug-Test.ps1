# GPO Analyzer ++ Integration Test (Headless)

$ErrorActionPreference = "Stop"
$root = "$PSScriptRoot\GPOAnalyzer++"
$mockDir = "$PSScriptRoot\MockGPOBackup"

Import-Module "$root\Core\GPOBackupParser.psm1" -Force
Import-Module "$root\Core\RegistryPolParser.psm1" -Force
Import-Module "$root\Core\GPPXmlParser.psm1" -Force
Import-Module "$root\Core\DiffEngine.psm1" -Force
Import-Module "$root\Core\TattooingAnalyzer.psm1" -Force
Import-Module "$root\Export\ExportHtml.psm1" -Force

# (Mock Setup is assumed present from previous run to save time, unless deleted)
# Re-creating Mock just in case to be safe, fast enough.
if (Test-Path $mockDir) { Remove-Item $mockDir -Recurse -Force }
New-Item -Path $mockDir -ItemType Directory | Out-Null
$gpo1Path = Join-Path $mockDir "{GUID-111}"
New-Item -Path "$gpo1Path\DomainSysvol\GPO\Machine" -ItemType Directory -Force | Out-Null
Set-Content "$gpo1Path\Backup.xml" -Value '<GroupPolicyBackup><GroupPolicyObject><GroupPolicyCoreSettings><DisplayName>Base Security</DisplayName><ID>{GUID-111}</ID><Domain>test.local</Domain></GroupPolicyCoreSettings></GroupPolicyObject></GroupPolicyBackup>'
$polPath = "$gpo1Path\DomainSysvol\GPO\Machine\registry.pol"
$fs = [System.IO.File]::Create($polPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([byte]0x50); $bw.Write([byte]0x52); $bw.Write([byte]0x65); $bw.Write([byte]0x67)
$bw.Write([int]1)
$keyBytes = [System.Text.Encoding]::Unicode.GetBytes("Software\Policies\Test"); $bw.Write($keyBytes); $bw.Write([int16]0)
$valBytes = [System.Text.Encoding]::Unicode.GetBytes("SafeSetting"); $bw.Write($valBytes); $bw.Write([int16]0)
$bw.Write([int]1)
$dataBytes = [System.Text.Encoding]::Unicode.GetBytes("1"); $bw.Write([int]($dataBytes.Length + 2)); $bw.Write($dataBytes); $bw.Write([int16]0)
$bw.Close(); $fs.Close()

Write-Host "[TEST] Debugging GPO 1 Parsing..."
$gpo1Settings = Get-GPOFromBackup -Path $gpo1Path -Verbose
Write-Host "Count: $($gpo1Settings.Count)"

if ($gpo1Settings.Count -eq 0) {
    Write-Error "Still 0. Check Verbose output above."
}
