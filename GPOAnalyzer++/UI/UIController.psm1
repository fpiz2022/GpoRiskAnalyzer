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

    # Helper for async execution
    function Run-Async {
        param(
            [scriptblock]$Job,
            [scriptblock]$OnComplete,
            [string]$StatusMsg = "Processing..."
        )
        $txtStatus.Text = $StatusMsg
        $window.Cursor = [System.Windows.Input.Cursors]::Wait

        # We use a BackgroundWorker or simple Job for PS context.
        # For WPF in PS, a simpler approach is to use the Dispatcher but jobs are truly async.
        Start-ThreadJob -ScriptBlock {
            param($b, $ctx)
            try { return & $b } catch { throw $_ }
        } -ArgumentList $Job, $PSScriptRoot | Wait-Job | Receive-Job | ForEach-Object {
            $result = $_
            $window.Dispatcher.Invoke([Action]{
                & $OnComplete $result
                $window.Cursor = [System.Windows.Input.Cursors]::Arrow
                $txtStatus.Text = "Ready"
            })
        }
    }

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

            # Run Load in Background
            $script:loadedSettings = @()
            $job = {
                param($p)
                Import-Module "$p\Core\GPOBackupParser.psm1" -Force
                Import-Module "$p\Core\RegistryPolParser.psm1" -Force
                Import-Module "$p\Core\GPPXmlParser.psm1" -Force

                $data = @()
                if ((Test-Path "$using:path\Backup.xml") -or (Test-Path "$using:path\DomainSysvol")) {
                    $data += Get-GPOFromBackup -Path $using:path
                }
                else {
                    $subfolders = Get-ChildItem -Path $using:path -Directory
                    foreach ($dir in $subfolders) {
                        if ((Test-Path "$($dir.FullName)\Backup.xml") -or (Test-Path "$($dir.FullName)\DomainSysvol")) {
                            $data += Get-GPOFromBackup -Path $dir.FullName
                        }
                    }
                }
                return $data
            }

            Start-ThreadJob -ScriptBlock $job -ArgumentList $PSScriptRoot | ForEach-Object {
                $results = $_ | Wait-Job | Receive-Job
                $window.Dispatcher.Invoke([Action]{
                    $script:loadedSettings = $results
                    $count = $script:loadedSettings.Count
                    $txtStatus.Text = "Loaded $count settings."
                    $gridResults.ItemsSource = $script:loadedSettings
                    Update-FilterColumns -Data $script:loadedSettings
                    Log-Message "Loaded $count items."
                    $window.Cursor = [System.Windows.Input.Cursors]::Arrow
                })
            }
        })

    # --- ANALYZE ---
    $btnAnalyze.Add_Click({
            if ($script:loadedSettings.Count -eq 0) {
                [System.Windows.MessageBox]::Show("Load GPOs first.", "Warning")
                return
            }

            $txtStatus.Text = "Analyzing..."
            $window.Cursor = [System.Windows.Input.Cursors]::Wait

            $job = {
                param($p, $settings)
                Import-Module "$p\Core\DiffEngine.psm1" -Force
                Import-Module "$p\Core\TattooingAnalyzer.psm1" -Force

                $uniqueGPOs = $settings | Select-Object -ExpandProperty GPOName -Unique

                if ($uniqueGPOs.Count -gt 1) {
                    $gpo1 = $uniqueGPOs[0]
                    $gpo2 = $uniqueGPOs[1]
                    $set1 = $settings | Where-Object { $_.GPOName -eq $gpo1 }
                    $set2 = $settings | Where-Object { $_.GPOName -eq $gpo2 }

                    $diff = Compare-GPO -ReferenceSettings $set1 -DifferenceSettings $set2
                    $res = $diff | Get-TattooingRisk

                    $finalList = @()
                    foreach ($r in $res) {
                        $props = [ordered]@{
                            Status          = $r.Status
                            SettingType     = $r.SettingType
                            Parameter       = $r.Parameter
                            Key             = $r.Path
                            RefValue        = $r.RefValue
                            DiffValue       = $r.DiffValue
                            Context         = $r.Context
                            Path            = $r.RefSource
                            TattooingRisk   = $r.TattooingRisk
                            TattooingReason = $r.TattooingReason
                        }
                        foreach ($p in $r.PSObject.Properties) {
                            if (-not $props.Contains($p.Name)) { $props[$p.Name] = $p.Value }
                        }
                        $finalList += [PSCustomObject]$props
                    }
                    return @{ List = $finalList; Msg = "Comparison Complete ($gpo1 vs $gpo2)." }
                }
                else {
                    $res = @()
                    foreach ($item in $settings) {
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
                    return @{ List = $res; Msg = "Audit Complete." }
                }
            }

            Start-ThreadJob -ScriptBlock $job -ArgumentList $PSScriptRoot, $script:loadedSettings | ForEach-Object {
                $out = $_ | Wait-Job | Receive-Job
                $window.Dispatcher.Invoke([Action]{
                    $script:analysisResults = $out.List
                    $gridResults.ItemsSource = $out.List
                    Update-FilterColumns -Data $out.List
                    $txtStatus.Text = $out.Msg
                    $window.Cursor = [System.Windows.Input.Cursors]::Arrow
                })
            }
        })

    # --- GRID COLUMN AUTO-GENERATE ---
    $gridResults.add_AutoGeneratingColumn({
            param($s, $e)
            $e.Column.MaxWidth = 450
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

    function Update-FilterColumns {
        param($Data)
        if ($null -eq $Data -or $Data.Count -eq 0) { return }
        $currentSelection = $cmbFilterColumn.Text
        $cmbFilterColumn.Items.Clear()
        $ignore = @("RefObject", "DiffObject", "RefSource", "DiffSource", "DiffGPOName", "RefGPOName")
        $props = $Data[0].PSObject.Properties | Where-Object { $_.Name -notin $ignore } | Select-Object -ExpandProperty Name
        foreach ($p in $props) {
            $item = New-Object System.Windows.Controls.ComboBoxItem
            $item.Content = $p
            if ($p -eq $currentSelection) { $item.IsSelected = $true }
            $cmbFilterColumn.Items.Add($item)
        }
        if ([string]::IsNullOrWhiteSpace($cmbFilterColumn.Text) -and $cmbFilterColumn.Items.Count -gt 0) {
            $cmbFilterColumn.SelectedIndex = 0
        }
    }

    function Apply-Filter {
        $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($gridResults.ItemsSource)
        if (-not $view) { return }
        $text = $txtFilter.Text
        if ([string]::IsNullOrWhiteSpace($text)) { $view.Filter = $null }
        else {
            $colName = $cmbFilterColumn.Text
            if ($null -eq $colName) { $colName = "Status" }
            $view.Filter = [Predicate[object]] { 
                param($item) 
                if ($null -eq $item) { return $false }
                $val = $item.$colName
                if ($null -eq $val) { return $false }
                return [string]$val -match [regex]::Escape($text)
            }
        }
        $view.Refresh()
    }

    $txtFilter.Add_TextChanged({ Apply-Filter })
    $cmbFilterColumn.Add_SelectionChanged({ Apply-Filter })
    
    $gridResults.Add_CurrentCellChanged({
            if ([string]::IsNullOrWhiteSpace($txtFilter.Text)) {
                if ($gridResults.CurrentCell -and $gridResults.CurrentCell.Column) {
                    $header = $gridResults.CurrentCell.Column.Header
                    if ($header -is [string]) { $cmbFilterColumn.Text = $header }
                }
            }
        })

    $txtCellDetail = $window.FindName("txtCellDetail")
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
        param([Parameter(Mandatory=$true)]$Data, [string]$Title = "Consistency Check Results")
        $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="$Title" Height="400" Width="800" Background="#1e293b">
    <Grid Margin="10">
        <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <DataGrid Name="grid" AutoGenerateColumns="True" IsReadOnly="True" Background="#0f172a" Foreground="#e2e8f0" RowBackground="#1e293b" AlternatingRowBackground="#334155"/>
        <Button Name="btnClose" Grid.Row="1" Content="Close" Width="100" HorizontalAlignment="Right" Margin="0,10,0,0" Padding="5"/>
    </Grid>
</Window>
"@
        $win = [Windows.Markup.XamlReader]::Parse($xaml)
        $win.FindName("grid").ItemsSource = $Data
        $win.FindName("btnClose").Add_Click({ $win.Close() })
        $win.ShowDialog() | Out-Null
    }

    $menuCheckConsistencyLoaded.Add_Click({
        if ($script:loadedSettings.Count -eq 0) {
            [System.Windows.MessageBox]::Show("nessuna GPO caricata per la comparazione`nimpossibile eseguire il controllo scoped", "Warning")
            return
        }
        $guids = $script:loadedSettings | Select-Object -ExpandProperty GPOGuid -Unique
        $window.Cursor = [System.Windows.Input.Cursors]::Wait
        $txtStatus.Text = "Checking consistency..."

        Start-ThreadJob -ScriptBlock {
            param($p, $g)
            Import-Module "$p\Core\ConsistencyEngine.psm1" -Force
            return Get-GPCGPTConsistency -TargetGuids $g
        } -ArgumentList $PSScriptRoot, $guids | ForEach-Object {
            $res = $_ | Wait-Job | Receive-Job
            $window.Dispatcher.Invoke([Action]{
                Show-ConsistencyResults -Data $res -Title "Scoped Consistency Check"
                $txtStatus.Text = "Ready"
                $window.Cursor = [System.Windows.Input.Cursors]::Arrow
            })
        }
    })

    $menuCheckConsistencyAll.Add_Click({
        $window.Cursor = [System.Windows.Input.Cursors]::Wait
        $txtStatus.Text = "Performing full domain consistency check..."

        Start-ThreadJob -ScriptBlock {
            param($p)
            Import-Module "$p\Core\ConsistencyEngine.psm1" -Force
            return Get-GPCGPTConsistency
        } -ArgumentList $PSScriptRoot | ForEach-Object {
            $res = $_ | Wait-Job | Receive-Job
            $window.Dispatcher.Invoke([Action]{
                $total = $res.Count
                $ok = ($res | Where-Object { $_.Status -eq "OK" }).Count
                $missingSysvol = ($res | Where-Object { $_.Status -eq "Missing_SYSVOL" }).Count
                $orphanSysvol = ($res | Where-Object { $_.Status -eq "Orphan_SYSVOL" }).Count
                $mismatch = ($res | Where-Object { $_.Status -eq "Version_Mismatch" }).Count
                $gppSecrets = ($res | Where-Object { $_.HasGPPSecrets -eq $true }).Count

                $summary = "Full Domain Consistency Check Summary:`n`nTotal: $total`nOK: $ok`nMissing: $missingSysvol`nOrphan: $orphanSysvol`nMismatch: $mismatch`nGPP Secrets: $gppSecrets"
                [System.Windows.MessageBox]::Show($summary, "Summary")

                $reportPath = Join-Path $PSScriptRoot "..\ConsistencyReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
                $res | Export-Csv -Path $reportPath -NoTypeInformation
                Show-ConsistencyResults -Data $res -Title "Full Domain Consistency Check"
                $txtStatus.Text = "Ready"
                $window.Cursor = [System.Windows.Input.Cursors]::Arrow
            })
        }
    })

    $menuExportDCInventory.Add_Click({
        $window.Cursor = [System.Windows.Input.Cursors]::Wait
        $txtStatus.Text = "Inventorying Domain Controllers..."

        Start-ThreadJob -ScriptBlock {
            param($p)
            Import-Module "$p\Core\DomainInventory.psm1" -Force
            # Note: Get-DomainControllersInventory now internally uses parallel jobs
            return Get-DomainControllersInventory
        } -ArgumentList $PSScriptRoot | ForEach-Object {
            $inventory = $_ | Wait-Job | Receive-Job
            $window.Dispatcher.Invoke([Action]{
                if ($inventory.Count -eq 0) { [System.Windows.MessageBox]::Show("No DC found.", "Info"); return }

                $dlg = New-Object System.Windows.Forms.SaveFileDialog
                $dlg.Filter = "CSV File|*.csv"
                if ($dlg.ShowDialog() -eq 'OK') {
                    $inventory | Export-Csv -Path $dlg.FileName -NoTypeInformation -Encoding utf8
                    [System.Windows.MessageBox]::Show("Inventory exported to $($dlg.FileName)", "Success")
                }
                $txtStatus.Text = "Ready"
                $window.Cursor = [System.Windows.Input.Cursors]::Arrow
            })
        }
    })

    # --- EXPORT ---
    $btnExport.Add_Click({
            if ($null -eq $script:analysisResults -or $script:analysisResults.Count -eq 0) { return }
            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Filter = "HTML Report|*.html|CSV|*.csv"
            if ($dlg.ShowDialog() -eq 'OK') {
                if ($dlg.FileName.EndsWith(".html")) { Export-ToHtml -Data $script:analysisResults -Path $dlg.FileName }
                else { $script:analysisResults | Export-Csv -Path $dlg.FileName -NoTypeInformation }
                [System.Windows.MessageBox]::Show("Exported.", "Success")
            }
        })

    $window.ShowDialog() | Out-Null
}
Export-ModuleMember -Function Show-UI
