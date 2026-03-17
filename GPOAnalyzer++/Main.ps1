# GPO Analyzer ++ Main Entry Point

# Set script root
$scriptRoot = $PSScriptRoot

# Import Models
# Classes should be dot-sourced or creating a module manifest (.psd1) is better, but dot-sourcing for simplicity here
Import-Module "$scriptRoot\Models\GPOSetting.psm1" -Force

# Import Core Modules
Import-Module "$scriptRoot\Core\GPOBackupParser.psm1" -Force
Import-Module "$scriptRoot\Core\RegistryPolParser.psm1" -Force
Import-Module "$scriptRoot\Core\GPPXmlParser.psm1" -Force
Import-Module "$scriptRoot\Core\DiffEngine.psm1" -Force
Import-Module "$scriptRoot\Core\TattooingAnalyzer.psm1" -Force
Import-Module "$scriptRoot\Core\ConsistencyEngine.psm1" -Force

# Import Export Modules
Import-Module "$scriptRoot\Export\ExportExcel.psm1" -Force
Import-Module "$scriptRoot\Export\ExportHtml.psm1" -Force

# Import UI
Import-Module "$scriptRoot\UI\UIController.psm1" -Force

# Launch UI
Write-Host "Starting GPO Analyzer ++..."
Show-UI
