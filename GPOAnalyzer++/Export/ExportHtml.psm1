function Export-ToHtml {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Data,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # Convert Data to JSON and then to Base64
    $jsonData = ConvertTo-Json -InputObject @($Data) -Depth 10 -Compress
    $jsonBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($jsonData))

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $htmlTemplate = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GPO Analyzer ++ | Analysis Report</title>
    <link href="https://fonts.googleapis.com/css2?family=Segoe+UI:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --primary: #3b82f6;
            --bg-dark: #0f172a;
            --bg-card: #1e293b;
            --text-main: #f1f5f9;
            --text-muted: #94a3b8;
            --border: #334155;
            --risk-high: #ef4444;
            --risk-medium: #f59e0b;
            --risk-low: #10b981;
        }

        body {
            font-family: 'Segoe UI', system-ui, sans-serif;
            background-color: var(--bg-dark);
            color: var(--text-main);
            margin: 0;
            padding: 20px;
        }

        .container { width: 100%; max-width: 1600px; margin: 0 auto; }

        header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px 0 20px 0;
            border-bottom: 2px solid var(--border);
            margin-bottom: 20px;
        }

        h1 { margin: 0; font-size: 24px; color: var(--primary); font-weight: 700; }
        .meta { color: var(--text-muted); font-size: 13px; }

        .search-container {
            position: relative;
            margin-bottom: 20px;
        }

        .search-box {
            width: 100%;
            padding: 14px 20px;
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 10px;
            color: white;
            font-size: 16px;
            outline: none;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.2);
        }
        .search-box:focus { border-color: var(--primary); }

        .count-badge {
            position: absolute;
            right: 15px;
            top: 50%;
            transform: translateY(-50%);
            background: rgba(59, 130, 246, 0.2);
            color: var(--primary);
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 700;
        }

        .card {
            background: var(--bg-card);
            border-radius: 12px;
            border: 1px solid var(--border);
            overflow: hidden;
            box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.3);
        }

        .table-container {
            overflow-x: auto;
            max-height: 75vh;
            overflow-y: auto;
        }

        table {
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            font-size: 13px;
        }

        th {
            background: #2d3748;
            padding: 15px 20px;
            text-align: left;
            font-weight: 600;
            position: sticky;
            top: 0;
            z-index: 10;
            border-bottom: 2px solid var(--border);
            cursor: pointer;
            white-space: nowrap;
        }
        th:hover { background: #4a5568; }

        td {
            padding: 12px 20px;
            border-bottom: 1px solid var(--border);
            white-space: nowrap;
            max-width: 500px;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        tr:hover td { background: rgba(255, 255, 255, 0.05); }

        .badge {
            padding: 3px 8px;
            border-radius: 4px;
            font-size: 11px;
            font-weight: 800;
            text-transform: uppercase;
        }
        .risk-High { background: var(--risk-high); color: white; }
        .risk-Medium { background: var(--risk-medium); color: black; }
        .risk-Low { background: var(--risk-low); color: white; }
        .risk-None { background: #475569; color: white; }

        code {
            background: rgba(0, 0, 0, 0.4);
            padding: 2px 6px;
            border-radius: 4px;
            font-family: 'Consolas', monospace;
            color: #93c5fd;
            font-size: 12px;
        }

        /* Styling matching GPO Analyzer ++ UI */
        .status-IDENTICAL { color: var(--text-muted); opacity: 0.7; }
        .status-DIFFERENT { color: var(--risk-medium); font-weight: bold; }
        .status-ONLY_IN_REF, .status-ONLY_IN_DIFF { font-weight: bold; }

    </style>
</head>
<body>

<div class="container">
    <header>
        <div>
            <h1>GPO Analyzer ++ | Final Report</h1>
            <div class="meta">Analysis Date: TIMESTAMP_PLACEHOLDER</div>
        </div>
    </header>

    <div class="search-container">
        <input type="text" id="filterInput" class="search-box" placeholder="Search for anything (Key, Status, Value, Parameter)...">
        <div id="resultCount" class="count-badge">0 Results</div>
    </div>

    <div class="card">
        <div class="table-container">
            <table>
                <thead><tr id="headerRow"></tr></thead>
                <tbody id="dataBody"></tbody>
            </table>
        </div>
    </div>
</div>

<script>
    try {
        const base64Data = "BASE64_DATA_PLACEHOLDER";
        const jsonString = decodeURIComponent(escape(atob(base64Data)));
        const data = JSON.parse(jsonString);

        if (!data || data.length === 0) {
            document.getElementById('dataBody').innerHTML = "<tr><td style='padding:40px;text-align:center'>No results found.</td></tr>";
        } else {
            const allKeys = Object.keys(data[0]);
            const ignoreKeys = ['RefObject', 'DiffObject', 'RefSource', 'DiffSource', 'DiffGPOName', 'RefGPOName', 'SourceFile'];
            const columns = allKeys.filter(k => !ignoreKeys.includes(k));
            
            const headerRow = document.getElementById('headerRow');
            columns.forEach(col => {
                const th = document.createElement('th');
                th.innerText = col;
                th.onclick = () => sortTable(col);
                headerRow.appendChild(th);
            });

            function renderTable(displayData) {
                const tbody = document.getElementById('dataBody');
                tbody.innerHTML = "";
                document.getElementById('resultCount').innerText = `${displayData.length} of ${data.length} results shown`;

                displayData.forEach(row => {
                    const tr = document.createElement('tr');
                    columns.forEach(col => {
                        const td = document.createElement('td');
                        const val = (row[col] === null || row[col] === undefined) ? "" : row[col];
                        
                        if (col === 'TattooingRisk') {
                            td.innerHTML = `<span class="badge risk-${val}">${val}</span>`;
                        } else if (col === 'Status') {
                            td.innerHTML = `<span class="status-${val}">${val}</span>`;
                        } else if (['Key', 'Path', 'RefValue', 'DiffValue', 'Parameter'].includes(col)) {
                            td.innerHTML = `<code>${val}</code>`;
                            td.title = val;
                        } else {
                            td.innerText = val;
                        }
                        tr.appendChild(td);
                    });
                    tbody.appendChild(tr);
                });
            }

            renderTable(data);

            document.getElementById('filterInput').addEventListener('input', function() {
                const term = this.value.toLowerCase();
                const filtered = data.filter(row => 
                    columns.some(col => String(row[col] || "").toLowerCase().includes(term))
                );
                renderTable(filtered);
            });

            let sortDir = 1;
            function sortTable(col) {
                sortDir *= -1;
                data.sort((a,b) => String(a[col]).localeCompare(String(b[col]), undefined, {numeric: true}) * sortDir);
                renderTable(data);
            }
        }
    } catch (e) {
        document.body.innerHTML = "<div style='color:red;padding:40px'>Error: " + e.message + "</div>";
    }
</script>
</body>
</html>
'@

    $finalHtml = $htmlTemplate.Replace("BASE64_DATA_PLACEHOLDER", $jsonBase64)
    $finalHtml = $finalHtml.Replace("TIMESTAMP_PLACEHOLDER", $timestamp)

    $finalHtml | Set-Content -Path $Path -Encoding UTF8
}

Export-ModuleMember -Function Export-ToHtml
