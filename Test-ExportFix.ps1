Import-Module "$PSScriptRoot\GPOAnalyzer++\Export\ExportHtml.psm1" -Force

# Case 1: Single Object (The breaking case)
$singleData = @(
    [PSCustomObject]@{
        Status = "TEST_SINGLE";
        TattooingRisk = "High";
        Category = "Test";
        Path = "HKLM\Software\Test";
        ValueName = "SingleItem";
        ValueData = "1"
    }
)

Write-Host "Exporting Single Item..."
Export-ToHtml -Data $singleData -Path "$PSScriptRoot\TestReport_Single.html"

# Case 2: Multiple Objects
$multiData = @(
    [PSCustomObject]@{ Status = "TEST_MULTI_1"; TattooingRisk = "Low"; Category = "Test"; Path = "P1"; ValueName = "V1"; ValueData = "1" },
    [PSCustomObject]@{ Status = "TEST_MULTI_2"; TattooingRisk = "High"; Category = "Test"; Path = "P2"; ValueName = "V2"; ValueData = "2" }
)

Write-Host "Exporting Multiple Items..."
Export-ToHtml -Data $multiData -Path "$PSScriptRoot\TestReport_Multi.html"
