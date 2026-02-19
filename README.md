# Merged Report Grid

A Salesforce Lightning Web Component that merges 2-5 Salesforce reports into a single unified grid.

![Salesforce](https://img.shields.io/badge/Salesforce-00A1E0?style=flat&logo=salesforce&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)
![Version](https://img.shields.io/badge/version-1.4.0-blue)

## What Is This?

The Merged Report Grid is a Lightning Web Component that allows you to combine 2-5 Salesforce reports into a single, interactive grid view. This is perfect for:

- **Comparing data across multiple reports** - See sales vs pipeline side-by-side
- **Creating unified dashboards** - Combine different report types into one view
- **Building custom analytics** - Merge reports with different groupings and add calculated fields
- **Simplifying complex reporting** - Present multiple data sources in a single, easy-to-read format

## What's Included

This repository contains everything you need to deploy the component to your Salesforce org:

### Apex Classes (4 classes)
- `MergedReportController` - Main controller that fetches and merges reports via the Reports API
- `MergedReportControllerTest` - Unit tests with 90%+ code coverage (required for production deployment)
- `MergeOptions` - Configuration data transfer object
- `MergedGridDTO` - Response data transfer object with nested classes

### Lightning Web Component (1 component)
- `mergedReportGrid` - The UI component that displays the merged grid in Lightning pages

### Features

- **Horizontal merges** (OUTER_JOIN, INNER_JOIN) - Compare data side-by-side
- **Vertical stacks** (UNION) - Stack rows with subtotals
- **Dimension Constants** - Merge reports with different grouping levels
- **Column Aliases with Custom Formatting** - Rename columns and override number formats (currency, percent, decimals)
- **Calculated Fields** - Add formula columns
- **Smart Caching** - Optimized for App Builder and runtime
- **Change Set Compatible** - Can be deployed via change sets from sandbox to production

## Quick Start for Salesforce Admins

### Prerequisites

1. **Salesforce CLI** - Download from [developer.salesforce.com/tools/sfdxcli](https://developer.salesforce.com/tools/sfdxcli)
2. **Access to this repository** - Either clone it or download as ZIP

### Installation (Windows CMD)

```cmd
REM 1. Clone or download this repository
git clone <repository-url>
cd merged-report-grid

REM 2. Authenticate to your Salesforce org
REM For Sandbox:
sf org login web -a MySandbox --instance-url https://test.salesforce.com

REM For Production:
sf org login web -a MyProd --instance-url https://login.salesforce.com

REM 3. Deploy to your org
sf project deploy start -o MySandbox

REM 4. Verify deployment (run tests)
sf apex run test -n MergedReportControllerTest -o MySandbox -r human -w 5
```

### Installation (Windows PowerShell)

```powershell
# 1. Clone or download this repository
git clone <repository-url>
cd merged-report-grid

# 2. Authenticate to your Salesforce org
# For Sandbox:
sf org login web -a MySandbox --instance-url https://test.salesforce.com

# For Production:
sf org login web -a MyProd --instance-url https://login.salesforce.com

# 3. Deploy to your org
sf project deploy start -o MySandbox

# 4. Verify deployment (run tests)
sf apex run test -n MergedReportControllerTest -o MySandbox -r human -w 5
```

### Can This Be Deployed via Change Sets?

**Yes!** This component can be deployed to a sandbox first, then moved to production using change sets. This is the traditional Salesforce deployment method.

**Steps:**
1. Deploy to sandbox using the CLI commands above
2. In sandbox: Setup → Outbound Change Sets → Create change set
3. Add all components (Apex classes and Lightning component)
4. Upload change set to production
5. In production: Setup → Inbound Change Sets → Deploy

See the [ADMIN_GUIDE.md](ADMIN_GUIDE.md) for detailed change set instructions.

## Documentation

| Document | Audience | Contents |
|----------|----------|----------|
| **[ADMIN_GUIDE.md](ADMIN_GUIDE.md)** | Salesforce Admins | Complete installation guide, deployment options (CLI & change sets), configuration, usage, troubleshooting |
| **README.md** (this file) | Everyone | Overview, what's included, quick start, project structure |

---

## For Developers

If you're contributing to this project or need to understand the architecture:

### Data Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                         LWC Component                             │
│  ┌─────────────┐   ┌──────────────┐   ┌────────────────────────┐ │
│  │ Properties  │ → │ Options JSON │ → │ @wire getMergedData()  │ │
│  │ (App Builder)│   │ (built in JS)│   │ (calls Apex)           │ │
│  └─────────────┘   └──────────────┘   └────────────────────────┘ │
└────────────────────────────────────────│─────────────────────────┘
                                         ↓
┌──────────────────────────────────────────────────────────────────┐
│                    MergedReportController.cls                     │
│  ┌─────────────┐   ┌──────────────┐   ┌────────────────────────┐ │
│  │ Parse       │ → │ Fetch Reports│ → │ Merge Data             │ │
│  │ Options     │   │ (Reports API)│   │ (JOIN or UNION)        │ │
│  └─────────────┘   └──────────────┘   └────────────────────────┘ │
└────────────────────────────────────────│─────────────────────────┘
                                         ↓
┌──────────────────────────────────────────────────────────────────┐
│                         MergedGridDTO                             │
│  columns[], rows[], totals, errors[], warnings[], sourceReports[] │
└──────────────────────────────────────────────────────────────────┘
```

### Key Classes

| Class | Purpose |
|-------|---------|
| `MergedReportController` | Entry point. Fetches reports via Reports API, parses data, applies merge logic |
| `MergeOptions` | Configuration DTO. Parses JSON options, exposes merge mode helpers |
| `MergedGridDTO` | Response structure with nested classes for columns, rows, errors |
| `MergedGridDTO.ColumnDefinition` | Column metadata (key, label, type, alignment) |
| `MergedGridDTO.GridRow` | Row data with keyed cell values |
| `MergedGridDTO.SourceReportInfo` | Report metadata for the details popover |

### LWC Design Patterns

1. **Smart Caching**: Detects App Builder design mode via URL; disables cache in edit mode, enables in runtime
2. **Debounced Property Loading**: 100-500ms delay before API calls to ensure all properties are set
3. **Popover for Report Details**: Click subtitle to view source reports with links

---

## Project Structure

```
force-app/main/default/
├── classes/
│   ├── MergedReportController.cls      # Main Apex controller
│   ├── MergedReportController.cls-meta.xml
│   ├── MergedReportControllerTest.cls  # Unit tests (90%+ coverage)
│   ├── MergedReportControllerTest.cls-meta.xml
│   ├── MergeOptions.cls                # Configuration DTO
│   ├── MergeOptions.cls-meta.xml
│   ├── MergedGridDTO.cls               # Response DTOs
│   └── MergedGridDTO.cls-meta.xml
└── lwc/
    └── mergedReportGrid/
        ├── mergedReportGrid.html       # Template
        ├── mergedReportGrid.js         # Controller (wire + imperative Apex)
        ├── mergedReportGrid.css        # Styles
        └── mergedReportGrid.js-meta.xml # Lightning App Builder config
```

## Deployment Options

### Option 1: Salesforce CLI (Recommended)
Fastest method. Works for both sandbox and production. See Quick Start section above.

### Option 2: Change Sets
Traditional Salesforce deployment method. Deploy to sandbox first, then create an outbound change set. See [ADMIN_GUIDE.md](ADMIN_GUIDE.md) for detailed steps.

### Option 3: VS Code with Salesforce Extensions
If you use VS Code, you can deploy individual files or the entire project using the Salesforce Extensions.

## After Deployment

Once deployed, you can add the component to any Lightning page:

1. Navigate to **Setup → Lightning App Builder**
2. Edit or create a Lightning page
3. Find **"Merged Report Grid"** in the Components panel
4. Drag it onto your page
5. Configure with your report IDs and settings
6. Save and Activate

See [ADMIN_GUIDE.md](ADMIN_GUIDE.md) for complete configuration instructions.

---

## Key Algorithms

### JOIN Merge (OUTER/INNER)

1. Parse all reports, extract grouping keys and aggregates
2. Build a composite key from dimension values (supports 1-2 dimensions)
3. Create column definitions with report-prefixed names
4. Iterate all keys; for OUTER include all, for INNER only common keys
5. Handle dimension constants by injecting constant values for missing dimensions

### UNION Merge

1. Parse all reports into a flat list of rows
2. Merge columns with matching names (case-sensitive)
3. Group by primary dimension
4. Optionally add subtotal rows per group
5. Calculate grand totals across all rows

### Dimension Constants

Reports with fewer dimensions than others get a constant value injected:
- Report 1 (1 dimension) + `{"1": "Total"}` → treated as 2 dimensions with "Total" as second key
- Enables merging reports with 1D and 2D groupings

---


---

## API Limits

| Limit | Value | Impact |
|-------|-------|--------|
| Reports API | 500 calls / 60 min / user | Each component load = 1 call per report |
| Response rows | 2,000 max | Set `maxRows` property accordingly |
| Grouping dimensions | 2 max | Summary reports only |

---

## Support & Troubleshooting

For detailed troubleshooting, configuration examples, and best practices, see the [ADMIN_GUIDE.md](ADMIN_GUIDE.md).

Common issues:
- **"Report not found"** - Verify the 18-character report ID is correct
- **"JOIN mode requires same dimensions"** - Use Dimension Constants or switch to UNION mode
- **Missing data** - Check Data Visibility settings and report filters

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make changes and add tests
4. Ensure tests pass with >75% coverage
5. Submit a pull request

### Code Style

- **Apex**: Follow Salesforce Apex best practices; use meaningful variable names
- **LWC**: Use camelCase for JS, kebab-case for HTML attributes
- **Comments**: Document complex logic; avoid obvious comments

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Version:** 1.4.0  
**API Version:** 59.0

---

## Need Help?

- **Installation & Deployment**: See [ADMIN_GUIDE.md](ADMIN_GUIDE.md)
- **Configuration & Usage**: See [ADMIN_GUIDE.md](ADMIN_GUIDE.md)
- **Troubleshooting**: See [ADMIN_GUIDE.md](ADMIN_GUIDE.md)
