function Show-UI {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Windows.Forms

    $logPath = "$PSScriptRoot\..\gpoanalyzer_debug.log"
    function Log-Message {
        param($Msg)
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $line = "[$timestamp] $Msg"
        Add-Content -Path $logPath -Value $line -ErrorAction SilentlyContinue
        Write-Host $line
    }

    try {
        [xml]$xaml = Get-Content -Path "$PSScriptRoot\MainWindow.xaml"
        $reader = (New-Object System.Xml.XmlNodeReader $xaml)
        $window = [Windows.Markup.XamlReader]::Load($reader)
    }
    catch {
        Write-Error "Failed to load XAML: $_"
        return
    }

    # Controls
    $txtPath = $window.FindName("txtPath")
    $btnBrowse = $window.FindName("btnBrowse")
    $btnLoad = $window.FindName("btnLoad")
    $btnAnalyze = $window.FindName("btnAnalyze")
    $btnExport = $window.FindName("btnExport")
    $gridResults = $window.FindName("gridResults")
    $txtStatus = $window.FindName("txtStatus")

    $script:loadedSettings = @()
    $script:analysisResults = @()

    # --- BROWSE ---
    $btnBrowse.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Select GPO Backup Folder"
        $dialog.RootFolder = [System.Environment+SpecialFolder]::MyComputer
        
        if ($dialog.ShowDialog() -eq 'OK') {
            $txtPath.Text = $dialog.SelectedPath
        }
    })

    # --- LOAD ---
    $btnLoad.Add_Click({
        $path = $txtPath.Text
        if ([string]::IsNullOrWhiteSpace($path)) {
            [System.Windows.MessageBox]::Show("Please enter or select a path.", "Info")
            return
        }
        
        if (-not (Test-Path $path)) {
            [System.Windows.MessageBox]::Show("Path does not exist.", "Error")
            return
        }

        Log-Message "Loading from: $path"
        $txtStatus.Text = "Loading..."
        $window.Cursor = [System.Windows.Input.Cursors]::Wait

        # Using Start-Job or simple async would be better, but keeping sync for stability in this script scope
        try {
             $script:loadedSettings = @()
             
             # Single GPO Check
             if ((Test-Path "$path\Backup.xml") -or (Test-Path "$path\DomainSysvol")) {
                 $script:loadedSettings += Get-GPOFromBackup -Path $path
             }
             else {
                 # Multi GPO Check
                 $subfolders = Get-ChildItem -Path $path -Directory
                 foreach ($dir in $subfolders) {
                    if ((Test-Path "$($dir.FullName)\Backup.xml") -or (Test-Path "$($dir.FullName)\DomainSysvol")) {
                        $s = Get-GPOFromBackup -Path $dir.FullName
                        $script:loadedSettings += $s
                    }
                 }
             }
             
             $count = $script:loadedSettings.Count
             $txtStatus.Text = "Loaded $count settings."
             $gridResults.ItemsSource = $script:loadedSettings
             Log-Message "Loaded $count items."
        }
        catch {
             [System.Windows.MessageBox]::Show("Error: $_", "Error")
             Log-Message "Error: $_"
        }
        finally {
             $window.Cursor = [System.Windows.Input.Cursors]::Arrow
        }
    })

    # --- ANALYZE ---
    $btnAnalyze.Add_Click({
        if ($script:loadedSettings.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Load GPOs first.", "Warning")
            return
        }

        $txtStatus.Text = "Analyzing..."
        $uniqueGPOs = $script:loadedSettings | Select-Object -ExpandProperty GPOName -Unique

        if ($uniqueGPOs.Count -gt 1) {
            # Diff
            $gpo1 = $uniqueGPOs[0]
            $gpo2 = $uniqueGPOs[1]
            $set1 = $script:loadedSettings | Where-Object { $_.GPOName -eq $gpo1 }
            $set2 = $script:loadedSettings | Where-Object { $_.GPOName -eq $gpo2 }
            
            $diff = Compare-GPO -ReferenceSettings $set1 -DifferenceSettings $set2
            $res = $diff | Get-TattooingRisk
            
            $script:analysisResults = $res
            $gridResults.ItemsSource = $res
            $txtStatus.Text = "Comparison Complete ($gpo1 vs $gpo2)."
        }
        else {
            # Audit
            $res = @()
            foreach ($item in $script:loadedSettings) {
                $w = [PSCustomObject]@{ Status="ACTIVE"; RefObject=$null; DiffObject=$item }
                $risk = Get-TattooingRisk -ComparisonItem $w
                $flat = [PSCustomObject]@{
                    GPOName=$item.GPOName; Category=$item.Category; Path=$item.RegistryPath; 
                    ValueName=$item.ValueName; ValueData=$item.ValueData; 
                    TattooingRisk=$risk.TattooingRisk; RiskReason=$risk.TattooingReason
                }
                $res += $flat
            }
            $script:analysisResults = $res
            $gridResults.ItemsSource = $res
            $txtStatus.Text = "Audit Complete."
        }
    })

    # --- EXPORT ---
    $btnExport.Add_Click({
        if ($null -eq $script:analysisResults -or $script:analysisResults.Count -eq 0) { return }
        
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = "HTML Report|*.html|CSV|*.csv"
        if ($dlg.ShowDialog() -eq 'OK') {
            if ($dlg.FileName.EndsWith(".html")) {
                Export-ToHtml -Data $script:analysisResults -Path $dlg.FileName
            } else {
                $script:analysisResults | Export-Csv -Path $dlg.FileName -NoTypeInformation
            }
            [System.Windows.MessageBox]::Show("Exported.", "Success")
        }
    })

    $window.ShowDialog() | Out-Null
}
Export-ModuleMember -Function Show-UI
