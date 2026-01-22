function Export-ToHtml {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Data,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # Convert Data to JSON for client-side rendering
    # Depth 2 is usually enough for flat objects
    $jsonData = ConvertTo-Json -InputObject @($Data) -Depth 2 -Compress

    $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GPO Analysis Report</title>
    <style>
        :root {
            --bg-body: #121212;
            --bg-card: #1e1e1e;
            --bg-header: #2d2d2d;
            --text-main: #e0e0e0;
            --text-muted: #a0a0a0;
            --accent: #3b82f6;
            --border: #333;
            
            --risk-high: #ef4444;
            --risk-med: #f59e0b;
            --risk-low: #10b981;
            --risk-none: #3b82f6; # Blue for info
        }

        body {
            font-family: 'Segoe UI', Inter, Roboto, sans-serif;
            background-color: var(--bg-body);
            color: var(--text-main);
            margin: 0;
            padding: 20px;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
        }

        header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
            border-bottom: 1px solid var(--border);
            padding-bottom: 20px;
        }

        h1 { margin: 0; font-weight: 300; letter-spacing: 1px; }
        .meta { font-size: 0.9em; color: var(--text-muted); }

        .controls {
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
        }

        input[type="text"] {
            background: var(--bg-card);
            border: 1px solid var(--border);
            color: white;
            padding: 10px 15px;
            border-radius: 4px;
            flex-grow: 1;
            font-size: 1rem;
        }

        input[type="text"]:focus {
            outline: none;
            border-color: var(--accent);
        }

        .card {
            background: var(--bg-card);
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.3);
            overflow: hidden;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.9rem;
        }

        th, td {
            padding: 12px 15px;
            text-align: left;
            border-bottom: 1px solid var(--border);
        }

        th {
            background-color: var(--bg-header);
            font-weight: 600;
            cursor: pointer;
            user-select: none;
            white-space: nowrap;
        }
        
        th:hover { background-color: #3d3d3d; }

        tr:hover { background-color: #2a2a2a; }

        /* Severity Badges */
        .badge {
            padding: 2px 8px;
            border-radius: 12px;
            font-size: 0.8em;
            font-weight: bold;
            color: #fff;
            text-transform: uppercase;
        }
        .risk-High { background-color: var(--risk-high); }
        .risk-Medium { background-color: var(--risk-med); color: #000; }
        .risk-Low { background-color: var(--risk-low); color: #000; }
        .risk-None { background-color: var(--bg-header); color: var(--text-muted); border: 1px solid var(--border); }
        .risk-Info { background-color: var(--accent); }

        .status-DIFFERENT { color: var(--risk-med); }
        .status-ONLY_IN_REF { color: var(--risk-high); }
        .status-ONLY_IN_DIFF { color: var(--risk-low); }

        code {
            background: #111;
            padding: 2px 4px;
            border-radius: 3px;
            font-family: Consolas, monospace;
            word-break: break-all;
        }
    </style>
</head>
<body>

<div class="container">
    <header>
        <div>
            <h1>GPO Analyzer ++ Report</h1>
            <div class="meta">Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm")</div>
        </div>
        <div>
            <span class="badge risk-Info" id="total-count">0 Items</span>
        </div>
    </header>

    <div class="controls">
        <input type="text" id="searchInput" placeholder="Search settings, paths, values...">
    </div>

    <div class="card">
        <div style="overflow-x:auto;">
            <table id="dataTable">
                <thead>
                    <tr id="tableHeader"></tr>
                </thead>
                <tbody id="tableBody"></tbody>
            </table>
        </div>
    </div>
</div>

<script>
    const data = $jsonData;

    // Determine columns dynamically from first object
    // Assuming uniform objects
    if (data.length === 0) {
        document.getElementById('tableBody').innerHTML = '<tr><td colspan="5">No data available</td></tr>';
    }

    // Define priority columns to show first
    const priorityCols = ['Status', 'TattooingRisk', 'Category', 'Path', 'ValueName', 'RefValue', 'DiffValue', 'ValueData'];
    
    // Get all unique keys
    let allKeys = new Set();
    data.forEach(obj => Object.keys(obj).forEach(k => allKeys.add(k)));
    
    // Filter out internal or complex object keys if necessary (like 'RefObject')
    const ignoreKeys = ['RefObject', 'DiffObject', 'SourceFile', 'RefSource', 'DiffSource'];
    
    let columns = [];
    
    // Add priority cols if they exist
    priorityCols.forEach(c => {
        if (allKeys.has(c)) {
            columns.push(c);
            allKeys.delete(c);
        }
    });
    
    // Add remaining
    allKeys.forEach(c => {
        if (!ignoreKeys.includes(c)) columns.push(c);
    });

    const thead = document.getElementById('tableHeader');
    columns.forEach(col => {
        let th = document.createElement('th');
        th.innerText = col;
        th.onclick = () => sortTable(col);
        thead.appendChild(th);
    });

    const tbody = document.getElementById('tableBody');
    const searchInput = document.getElementById('searchInput');
    const totalCount = document.getElementById('total-count');

    function renderTable(displayData) {
        tbody.innerHTML = '';
        totalCount.innerText = displayData.length + " Items";

        // Limit rendering for performance if massive? 
        // For now, render all (assuming < 2000 items usually)
        
        displayData.forEach(row => {
            let tr = document.createElement('tr');
            
            columns.forEach(col => {
                let td = document.createElement('td');
                let val = row[col] === null || row[col] === undefined ? '' : row[col];
                
                // Formatting
                if (col === 'TattooingRisk' || col === 'Severity') {
                    td.innerHTML = `<span class="badge risk-${val}">${val}</span>`;
                }
                else if (col === 'Status') {
                    td.innerHTML = `<span class="status-${val}">${val}</span>`;
                }
                else if (col === 'Path' || col === 'ValueName' || col.includes('Value')) {
                    td.innerHTML = `<code>${val}</code>`;
                }
                else {
                    td.innerText = val;
                }
                tr.appendChild(td);
            });
            tbody.appendChild(tr);
        });
    }

    // Initial Render
    renderTable(data);

    // Search Logic
    searchInput.addEventListener('input', (e) => {
        const term = e.target.value.toLowerCase();
        const filtered = data.filter(row => {
            return columns.some(col => {
                const val = String(row[col] || '').toLowerCase();
                return val.includes(term);
            });
        });
        renderTable(filtered);
    });

    // Sorting Logic
    let currentSort = { col: null, dir: 1 };
    
    function sortTable(col) {
        // Toggle direction
        if (currentSort.col === col) {
            currentSort.dir *= -1;
        } else {
            currentSort.col = col;
            currentSort.dir = 1;
        }
        
        data.sort((a, b) => {
            let valA = a[col] || '';
            let valB = b[col] || '';
            
            // Numeric check?
            
            if (valA < valB) return -1 * currentSort.dir;
            if (valA > valB) return 1 * currentSort.dir;
            return 0;
        });
        
        // Re-render based on current search
        searchInput.dispatchEvent(new Event('input')); 
    }

</script>
</body>
</html>
"@

    $htmlContent | Set-Content -Path $Path -Encoding UTF8
}

Export-ModuleMember -Function Export-ToHtml

