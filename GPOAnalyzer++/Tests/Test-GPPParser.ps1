Import-Module "$PSScriptRoot\GPOAnalyzer++\Core\GPPXmlParser.psm1" -Force

# Helper to create a Mock GPP XML
function New-MockGPPFile {
    param($Path)
    
    $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<RegistrySettings clsid="{3222D897-D901-4A47-A0E7-4F6262985F2C}">
  <Registry clsid="{9CD4B2F4-923D-47f5-A062-E897DD1DAD50}" name="TestValue" status="TestStatus" image="11" changed="2022-01-01 12:00:00" uid="{GUID}">
    <Properties action="U" displayDecimal="1" default="0" hive="HKEY_LOCAL_MACHINE" key="Software\Policies\Test" name="TestGPP" type="REG_SZ" value="MyValue"/>
  </Registry>
  <File clsid="{71F27E94-9686-45a7-9346-4B85994269CA}" name="TestFile" status="TestStatus" image="0" changed="2022-01-01 12:00:00" uid="{GUID2}">
    <Properties action="C" fromPath="\\Server\Share\File.txt" targetPath="C:\Temp\File.txt" readOnly="0" archive="1" hidden="0" />
  </File>
</RegistrySettings>
"@
    Set-Content -Path $Path -Value $xmlContent
}

$mockPath = "$PSScriptRoot\mock-gpp.xml"
New-MockGPPFile -Path $mockPath

Write-Host "Parsing mock GPP file..."
$results = Parse-GPPXml -Path $mockPath -Context "Computer"

$results | Format-Table -AutoSize

# Cleanup
Remove-Item $mockPath
