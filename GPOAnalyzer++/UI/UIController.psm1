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

    $menuCheckConsistencyLoaded = $window.FindName("menuCheckConsistencyLoaded")
    $menuCheckConsistencyAll = $window.FindName("menuCheckConsistencyAll")
    $menuExportDCInventory = $window.FindName("menuExportDCInventory")

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
                Update-FilterColumns -Data $script:loadedSettings
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
            
                # Reorder and map columns
                $finalList = @()
                foreach ($r in $res) {
                    $props = [ordered]@{
                        Status          = $r.Status
                        SettingType     = $r.SettingType
                        Parameter       = $r.Parameter
                        Key             = $r.Path  # Map internal Path (RegistryPath) to UI 'Key'
                        RefValue        = $r.RefValue
                        DiffValue       = $r.DiffValue
                        Context         = $r.Context
                        Path            = $r.RefSource # Map internal RefSource to UI 'Path' (Source File)
                        TattooingRisk   = $r.TattooingRisk
                        TattooingReason = $r.TattooingReason
                    }
                    # Add remaining properties dynamically if not already present
                    foreach ($p in $r.PSObject.Properties) {
                        if (-not $props.Contains($p.Name)) {
                            $props[$p.Name] = $p.Value
                        }
                    }
                    $finalList += [PSCustomObject]$props
                }

                $script:analysisResults = $finalList
                $gridResults.ItemsSource = $finalList
                Update-FilterColumns -Data $finalList
                $txtStatus.Text = "Comparison Complete ($gpo1 vs $gpo2)."
            }
            else {
                # Audit
                $res = @()
                foreach ($item in $script:loadedSettings) {
                    $w = [PSCustomObject]@{ Status = "ACTIVE"; RefObject = $null; DiffObject = $item }
                    $risk = Get-TattooingRisk -ComparisonItem $w
                    
                    $flat = [ordered]@{
                        Status          = "ACTIVE"
                        SettingType     = $item.SettingType
                        Parameter       = $item.ValueName
                        Key             = $item.RegistryPath
                        RefValue        = $item.ValueData
                        DiffValue       = $null
                        Context         = $item.Context
                        Path            = $item.SourceFile
                        TattooingRisk   = $risk.TattooingRisk
                        TattooingReason = $risk.TattooingReason
                        
                        Category        = $item.Category
                        GPOName         = $item.GPOName
                    }
                    $res += [PSCustomObject]$flat
                }
                $script:analysisResults = $res
                $gridResults.ItemsSource = $res
                Update-FilterColumns -Data $res
                $txtStatus.Text = "Audit Complete."
            }
        })

    # --- GRID COLUMN AUTO-GENERATE ---
    $gridResults.add_AutoGeneratingColumn({
            param($s, $e)
        
            # Set a MaxWidth to prevent long text from making columns too wide
            $e.Column.MaxWidth = 450
        
            # Specific widths for known columns
            switch ($e.PropertyName) {
                "Status" { $e.Column.Width = 100 }
                "SettingType" { $e.Column.Width = 120 }
                "Parameter" { $e.Column.Width = 200 }
                "Key" { $e.Column.Width = 350 }
                "RefValue" { $e.Column.Width = 120 }
                "DiffValue" { $e.Column.Width = 120 }
                "Context" { $e.Column.Width = 100 }
                "Path" { $e.Column.Width = 300 }
                "TattooingRisk" { $e.Column.Width = 120 }
                "TattooingReason" { $e.Column.Width = 300 }
                default { $e.Column.Width = 150 }
            }
        })

    $txtFilter = $window.FindName("txtFilter")
    $cmbFilterColumn = $window.FindName("cmbFilterColumn")

    # Helper to update filter columns based on current data
    function Update-FilterColumns {
        param($Data)
        if ($null -eq $Data -or $Data.Count -eq 0) { return }
        
        $currentSelection = $cmbFilterColumn.Text
        $cmbFilterColumn.Items.Clear()
        
        # Get properties from the first item, excluding internal properties
        $ignore = @("RefObject", "DiffObject", "RefSource", "DiffSource", "DiffGPOName", "RefGPOName")
        $firstItem = $Data[0]
        $props = $firstItem.PSObject.Properties | 
        Where-Object { $_.Name -notin $ignore } | 
        Select-Object -ExpandProperty Name
        
        foreach ($p in $props) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $p
            if ($p -eq $currentSelection) { $item.IsSelected = $true }
            $cmbFilterColumn.Items.Add($item)
        }
        
        # Default selection if nothing selected
        if ([string]::IsNullOrWhiteSpace($cmbFilterColumn.Text) -and $cmbFilterColumn.Items.Count -gt 0) {
            $cmbFilterColumn.SelectedIndex = 0
        }
    }

    # Helper to apply filter
    function Apply-Filter {
        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($gridResults.ItemsSource)
        if (-not $view) { return }
        
        $text = $txtFilter.Text
        if ([string]::IsNullOrWhiteSpace($text)) {
            $view.Filter = $null
        }
        else {
            $colName = $cmbFilterColumn.Text
            if ($null -eq $colName) { $colName = "Status" } # Fallback
            
            $view.Filter = [Predicate[object]] { 
                param($item) 
                if ($null -eq $item) { return $false }
                
                # Dynamic property access
                $val = $item.$colName
                if ($null -eq $val) { return $false }
                return [string]$val -match [regex]::Escape($text)
            }
        }
        $view.Refresh()
    }

    $txtFilter.Add_TextChanged({ Apply-Filter })
    $cmbFilterColumn.Add_SelectionChanged({ Apply-Filter })
    
    # Auto-select column on click (sync DataGrid selection to ComboBox)
    $gridResults.Add_CurrentCellChanged({
            # Only change column automatically if the search box is empty
            # to avoid breaking current search results
            if ([string]::IsNullOrWhiteSpace($txtFilter.Text)) {
                if ($gridResults.CurrentCell -and $gridResults.CurrentCell.Column) {
                    $header = $gridResults.CurrentCell.Column.Header
                    if ($header -is [string]) {
                        $cmbFilterColumn.Text = $header
                    }
                }
            }
        })

    # Get Cell Detail TextBox
    $txtCellDetail = $window.FindName("txtCellDetail")

    # Double-click to show full cell value in detail box
    $gridResults.Add_MouseDoubleClick({
            if ($gridResults.CurrentCell -and $gridResults.CurrentCell.Column -and $gridResults.CurrentItem) {
                $columnName = $gridResults.CurrentCell.Column.Header
                $item = $gridResults.CurrentItem
            
                if ($columnName -and $item) {
                    $value = $item.$columnName
                    if ($null -eq $value) { $value = "(null)" }
                
                    $txtCellDetail.Text = "[$columnName]: $value"
                }
            }
        })

    # --- ESERVICES ---
    function Show-ConsistencyResults {
        param(
            [Parameter(Mandatory=$true)]
            $Data,
            [string]$Title = "Consistency Check Results"
        )

        $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="$Title" Height="400" Width="800" Background="#1e293b">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <DataGrid Name="grid" AutoGenerateColumns="True" IsReadOnly="True" Background="#0f172a" Foreground="#e2e8f0" RowBackground="#1e293b" AlternatingRowBackground="#334155"/>
        <Button Name="btnClose" Grid.Row="1" Content="Close" Width="100" HorizontalAlignment="Right" Margin="0,10,0,0" Padding="5"/>
    </Grid>
</Window>
"@
        $win = [Windows.Markup.XamlReader]::Parse($xaml)
        $grid = $win.FindName("grid")
        $grid.ItemsSource = $Data

        $btnClose = $win.FindName("btnClose")
        $btnClose.Add_Click({ $win.Close() })

        $win.ShowDialog() | Out-Null
    }

    $menuCheckConsistencyLoaded.Add_Click({
        Log-Message "Action: Check GPC/GPT Consistency for Loaded GPOs"
        if ($script:loadedSettings.Count -eq 0) {
            [System.Windows.MessageBox]::Show("nessuna GPO caricata per la comparazione`nimpossibile eseguire il controllo scoped", "Warning")
            return
        }

        $uniqueGuids = $script:loadedSettings | Select-Object -ExpandProperty GPOGuid -Unique
        $txtStatus.Text = "Checking consistency for loaded GPOs..."

        try {
            $res = Get-GPCGPTConsistency -TargetGuids $uniqueGuids
            Show-ConsistencyResults -Data $res -Title "Scoped Consistency Check"
            $txtStatus.Text = "Scoped consistency check complete."
        }
        catch {
            Log-Message "Error in Scoped Consistency Check: $_"
            [System.Windows.MessageBox]::Show("Error: $_", "Error")
        }
    })

    $menuCheckConsistencyAll.Add_Click({
        Log-Message "Action: Check GPC/GPT Consistency for All Domain GPOs"
        $txtStatus.Text = "Performing full domain consistency check..."

        try {
            $res = Get-GPCGPTConsistency

            # Summary Calculation
            $total = $res.Count
            $ok = ($res | Where-Object { $_.Status -eq "OK" }).Count
            $missingSysvol = ($res | Where-Object { $_.Status -eq "Missing_SYSVOL" }).Count
            $orphanSysvol = ($res | Where-Object { $_.Status -eq "Orphan_SYSVOL" }).Count
            $mismatch = ($res | Where-Object { $_.Status -eq "Version_Mismatch" }).Count

            $summary = "Full Domain Consistency Check Summary:`n`n" +
                       "Total GPOs analyzed: $total`n" +
                       "OK: $ok`n" +
                       "Missing in SYSVOL: $missingSysvol`n" +
                       "Orphan in SYSVOL: $orphanSysvol`n" +
                       "Version Mismatch: $mismatch"

            [System.Windows.MessageBox]::Show($summary, "Consistency Check Summary")

            # Save detailed report
            $reportPath = Join-Path $PSScriptRoot "..\ConsistencyReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $res | Export-Csv -Path $reportPath -NoTypeInformation
            Log-Message "Detailed report saved to: $reportPath"

            Show-ConsistencyResults -Data $res -Title "Full Domain Consistency Check"
            $txtStatus.Text = "Full domain consistency check complete. Report saved."
        }
        catch {
            Log-Message "Error in Full Domain Consistency Check: $_"
            [System.Windows.MessageBox]::Show("Error: $_", "Error")
        }
    })

    $menuExportDCInventory.Add_Click({
        Log-Message "Action: Export Domain Controllers Inventory triggered."
        $txtStatus.Text = "Inventorying Domain Controllers..."
        $window.Cursor = [System.Windows.Input.Cursors]::Wait

        try {
            $inventory = Get-DomainControllersInventory
            if ($inventory.Count -eq 0) {
                [System.Windows.MessageBox]::Show("No Domain Controllers found or error during discovery.", "Information")
                return
            }

            # Summary Calculation
            $total = $inventory.Count
            $ok = ($inventory | Where-Object { $_.Status -eq "OK" }).Count
            $partial = ($inventory | Where-Object { $_.Status -eq "Partial" }).Count
            $unreachable = ($inventory | Where-Object { $_.Status -eq "Unreachable" }).Count
            $others = $total - $ok - $partial - $unreachable

            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $defaultPath = Join-Path $PSScriptRoot "..\DC_Inventory_$timestamp.csv"

            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Title = "Save Domain Controllers Inventory"
            $dlg.Filter = "CSV File|*.csv"
            $dlg.FileName = $defaultPath

            if ($dlg.ShowDialog() -eq 'OK') {
                $inventory | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding utf8

                $summary = "Domain Controllers Inventory Complete.`n`n" +
                           "Total DC found: $total`n" +
                           "Successfully processed: $ok`n" +
                           "Partial data: $partial`n" +
                           "Unreachable: $unreachable`n" +
                           "Other errors: $others`n`n" +
                           "Report saved to: $($dlg.FileName)"

                [System.Windows.MessageBox]::Show($summary, "Inventory Summary")
                Log-Message "Inventory exported to $($dlg.FileName)"
            }
        }
        catch {
            Log-Message "ERROR during DC Inventory: $_"
            [System.Windows.MessageBox]::Show("An error occurred: $_", "Error")
        }
        finally {
            $window.Cursor = [System.Windows.Input.Cursors]::Arrow
            $txtStatus.Text = "Ready"
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
                }
                else {
                    $script:analysisResults | Export-Csv -Path $dlg.FileName -NoTypeInformation
                }
                [System.Windows.MessageBox]::Show("Exported.", "Success")
            }
        })

    $window.ShowDialog() | Out-Null
}
Export-ModuleMember -Function Show-UI
