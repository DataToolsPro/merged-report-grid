# Merged Report Grid

A Salesforce Lightning Web Component that merges 2-5 reports into a single unified grid.

![Salesforce](https://img.shields.io/badge/Salesforce-00A1E0?style=flat&logo=salesforce&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)
![Version](https://img.shields.io/badge/version-1.3.0-blue)

## Overview

This component allows Salesforce users to combine multiple reports into a single view, supporting:

- **Horizontal merges** (OUTER_JOIN, INNER_JOIN) - Compare data side-by-side
- **Vertical stacks** (UNION) - Stack rows with subtotals
- **Dimension Constants** - Merge reports with different grouping levels
- **Calculated Fields** - Add formula columns
- **Smart Caching** - Optimized for App Builder and runtime

## Documentation

| Document | Audience | Contents |
|----------|----------|----------|
| **[ADMIN_GUIDE.md](ADMIN_GUIDE.md)** | Salesforce Admins | Installation, deployment, configuration, usage, troubleshooting |
| **README.md** (this file) | Developers | Architecture, development setup, contributing |

---

## Project Structure

```
force-app/main/default/
├── classes/
│   ├── MergedReportController.cls      # Main Apex controller
│   ├── MergedReportController.cls-meta.xml
│   ├── MergedReportControllerTest.cls  # Unit tests (90%+ coverage)
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

---

## Architecture

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

## Development Setup

### Prerequisites

- Salesforce CLI (`sf`)
- Git
- A Salesforce org (Sandbox recommended for development)

### Local Development

```bash
# Clone the repository
git clone https://github.com/DataToolsPro/merged-report-grid.git
cd merged-report-grid

# Authenticate to a sandbox
sf org login web -a DevSandbox --instance-url https://test.salesforce.com

# Deploy code
sf project deploy start -o DevSandbox

# Watch for changes (optional - requires VS Code Salesforce Extension)
# Use VS Code's "SFDX: Deploy This Source to Org" on save
```

### Running Tests

```bash
# Run Apex tests
sf apex run test -n MergedReportControllerTest -o DevSandbox -r human -w 5

# Run with code coverage
sf apex run test -n MergedReportControllerTest -o DevSandbox -r human -w 5 -c
```

### Debugging

1. Enable **Debug Mode** in the component properties
2. Check browser console for LWC logs (prefixed with `[MergedReportGrid]`)
3. Use Salesforce Developer Console for Apex debug logs

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

## Package Management

The component uses Salesforce Unlocked Packages for distribution.

### Current Package Info

| Property | Value |
|----------|-------|
| Package Name | `MergedReportGrid` |
| Package ID | `0HoPU000000k9k6WAA` |
| Latest Version | `04tPU000002A02PYAS` (v1.3.0) |

### Creating a New Version

```bash
# Ensure DevHub is authenticated
sf config set target-dev-hub=DevHub

# Create new package version
sf package version create \
  --package MergedReportGrid \
  --installation-key-bypass \
  --wait 10 \
  --target-dev-hub DevHub \
  --code-coverage

# List versions
sf package version list --packages MergedReportGrid --target-dev-hub DevHub
```

See [ADMIN_GUIDE.md](ADMIN_GUIDE.md) for full deployment workflow.

---

## API Limits

| Limit | Value | Impact |
|-------|-------|--------|
| Reports API | 500 calls / 60 min / user | Each component load = 1 call per report |
| Response rows | 2,000 max | Set `maxRows` property accordingly |
| Grouping dimensions | 2 max | Summary reports only |

---

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

MIT License - see [LICENSE](LICENSE) file.

---

**Version:** 1.3.0  
**API Version:** 59.0  
**Maintainer:** DataTools Pro
