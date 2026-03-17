# GPO Analyzer ++

GPO Analyzer ++ is a modern tool for analyzing, comparing, and auditing Group Policy Objects (GPO).

## Features
- **Backup Parsing**: Reads standard GPMC Backups directly.
- **Deep Analysis**: Parses `Registry.pol` (Administrative Templates) and `Preferences` XMLs.
- **Diff Engine**: Compares two GPOs to find Added, Removed, and Modified settings.
- **Tattooing Risk**: Identifies settings that might persist (tattoo) the registry based on heuristics.
- **Reporting**: Exports rich HTML reports with search and filter capabilities.
- **eServices (Beta)**:
    - **GPC vs GPT Consistency Check**: Compares GPO metadata in Active Directory (GPC) with files in SYSVOL (GPT) to detect version mismatches or orphaned objects. Supports scoped (loaded GPOs) and full domain scans.
    - **Domain Controllers Inventory**: Automatically discovers all DCs in the domain and collects operational metadata (OS, .NET version, DNS roles, Network config, Patch level, and Services) into a CSV report.

> [!IMPORTANT]
> **Beta Features**: The features under the **eServices** menu are currently in development and require further testing in diverse production environments to be considered complete and fully stable.

## Requirements
- PowerShell 5.1 or 7.x
- .NET Framework 4.7.2+ (included in modern Windows)

## Usage

### GUI Mode
Run the main script to launch the interface:
```powershell
.\Main.ps1
```

1. Click **Load GPOs** and select a folder containing GPO backups.
2. Click **Analyze**:
   - If 1 GPO is loaded: Runs a single audit for Tattooing Risks.
   - If 2+ GPOs are loaded: Compares the first two GPOs found.
3. Click **Export** to save an HTML or CSV report.

### Troubleshooting
A debug log is generated at `gpoanalyzer_debug.log` in the parent directory during UI sessions.

## Directory Structure
- `Core/`: Logic modules (Parsers, Diff, Risk Analyzer).
- `UI/`: WPF Interface and Controller.
- `Models/`: Data structures.
- `Export/`: Reporting modules.
- `Tests/`: Integration and Unit tests.
