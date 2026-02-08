# Merged Report Grid - Salesforce Admin Guide

A Lightning Web Component that merges 2-5 Salesforce reports into a single unified grid.

**Version:** 1.3.0  
**Package ID:** 04tPU000002A02PYAS

---

## Table of Contents

1. [Installation & Deployment](#installation--deployment)
   - [Quick Install (URL)](#option-1-quick-install-url)
   - [Salesforce CLI Package Install](#option-2-salesforce-cli-package-install)
   - [Deploy from Source](#option-3-deploy-from-source)
   - [Full Package Workflow (Enterprise)](#full-package-workflow-for-enterprise)
2. [Adding to Lightning Pages](#adding-to-lightning-pages)
3. [Configuration Properties](#configuration-properties)
4. [Merge Modes](#merge-modes)
5. [JSON Configuration Properties](#json-configuration-properties)
   - [Dimension Constants](#dimension-constants-json)
   - [Column Aliases](#column-aliases-json)
   - [Calculated Fields](#calculated-fields-json)
6. [Working with Different Dimensions](#working-with-different-dimensions)
7. [Viewing Source Reports](#viewing-source-reports)
8. [Troubleshooting](#troubleshooting)
9. [Limitations](#limitations)
10. [Best Practices](#best-practices)

---

## Installation & Deployment

### Prerequisites

For CLI-based installation, you'll need:

1. **Salesforce CLI** - Download from [developer.salesforce.com/tools/sfdxcli](https://developer.salesforce.com/tools/sfdxcli)
2. Verify installation:
```bash
sf --version
```

---

### Option 1: Quick Install (URL)

The fastest way to install. Simply click the appropriate link:

**Sandbox Installation:**
```
https://test.salesforce.com/packaging/installPackage.apexp?p0=04tPU000002A02PYAS
```

**Production Installation:**
```
https://login.salesforce.com/packaging/installPackage.apexp?p0=04tPU000002A02PYAS
```

> ⚠️ **Note:** Production installs require a promoted (released) package version. If the URL doesn't work for production, the package may need to be promoted first.

---

### Option 2: Salesforce CLI Package Install

Install the pre-built package via command line:

```bash
# 1. Authenticate to your org
# For Sandbox:
sf org login web -a MySandbox --instance-url https://test.salesforce.com

# For Production:
sf org login web -a MyProd --instance-url https://login.salesforce.com

# 2. Install the package
sf package install -p 04tPU000002A02PYAS -o MySandbox -w 10

# 3. Verify installation
sf package installed list --target-org MySandbox
```

---

### Option 3: Deploy from Source

Use this when you have access to the source code repository and want to deploy directly without package management.

```bash
# 1. Clone the repository (or download source)
git clone https://github.com/DataToolsPro/merged-report-grid.git
cd merged-report-grid

# 2. Authenticate to your org
sf org login web -a MySandbox --instance-url https://test.salesforce.com

# 3. Deploy the code
sf project deploy start -o MySandbox

# 4. (Optional) Run tests to verify
sf apex run test -n MergedReportControllerTest -o MySandbox -r human -w 5
```

**For Production (Direct Deploy):**
```bash
# Production requires passing Apex tests
sf project deploy start -o MyProd --test-level RunSpecifiedTests --tests MergedReportControllerTest

# Verify deployment
sf project deploy report -o MyProd
```

---

### Full Package Workflow (For Enterprise)

Use unlocked packages for version control, easier upgrades, and multi-org deployments. This is the recommended approach for managing deployments across multiple orgs.

#### Prerequisites for Packaging

1. **DevHub Enabled** in your production org:
   - Setup → Dev Hub → Enable
   
2. **Authenticate to DevHub:**
```bash
sf org login web -a DevHub --instance-url https://login.salesforce.com
sf config set target-dev-hub=DevHub
```

#### Step 1: Create a Package (One-Time)

Skip if the package already exists in your DevHub.

```bash
sf package create \
  --name MergedReportGrid \
  --package-type Unlocked \
  --path force-app \
  --target-dev-hub DevHub \
  --description "Merged Report Grid - Combines 2-5 Salesforce reports"
```

This creates a package ID (starts with `0Ho`) stored in `sfdx-project.json`.

#### Step 2: Create a Package Version

Run this whenever you need to deploy updates:

```bash
# Create a beta package version
sf package version create \
  --package MergedReportGrid \
  --installation-key-bypass \
  --wait 10 \
  --target-dev-hub DevHub \
  --code-coverage

# Note the version ID (04t...) from the output
```

The `--code-coverage` flag ensures tests pass and coverage is calculated.

#### Step 3: Install in Sandbox for Testing

```bash
# List package versions to get the ID:
sf package version list --packages MergedReportGrid --target-dev-hub DevHub

# Install in sandbox (replace 04tXXX with your version ID)
sf package install \
  --package 04tXXXXXXXXXXXXXXX \
  --target-org MySandbox \
  --wait 10

# Verify installation
sf package installed list --target-org MySandbox
```

#### Step 4: Test in Sandbox

1. Open the sandbox
2. Navigate to a Lightning page in App Builder
3. Add the "Merged Report Grid" component
4. Configure with test reports
5. Verify functionality

#### Step 5: Promote for Production

Once testing is complete, promote the package version to "Released" status:

```bash
# Promote the version (required before production install)
sf package version promote \
  --package 04tXXXXXXXXXXXXXXX \
  --target-dev-hub DevHub

# Verify promotion (should show IsReleased = true)
sf package version list --packages MergedReportGrid --released --target-dev-hub DevHub
```

> ⚠️ **Important:** Only promoted (released) versions can be installed in production orgs.

#### Step 6: Install in Production

```bash
# Authenticate to production
sf org login web -a MyProd --instance-url https://login.salesforce.com

# Install the promoted package
sf package install \
  --package 04tXXXXXXXXXXXXXXX \
  --target-org MyProd \
  --wait 10

# Verify installation
sf package installed list --target-org MyProd
```

#### Generate Installation URLs

For admins who prefer URL-based installation, construct URLs using the package version ID:

```
Sandbox:    https://test.salesforce.com/packaging/installPackage.apexp?p0=04tXXXXXXXXXXXXXXX
Production: https://login.salesforce.com/packaging/installPackage.apexp?p0=04tXXXXXXXXXXXXXXX
```

---

### Upgrade Existing Installation

To upgrade an org that already has the package installed:

```bash
sf package install \
  --package 04tNEWVERSIONID \
  --target-org MyOrg \
  --wait 10 \
  --upgrade-type Mixed
```

---

### Deployment Workflow Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                     DEPLOYMENT WORKFLOW                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. CREATE VERSION                                               │
│     └── sf package version create ... (creates 04t ID)          │
│                                                                  │
│  2. TEST IN SANDBOX                                              │
│     └── sf package install ... --target-org Sandbox             │
│     └── Manual testing in App Builder                           │
│                                                                  │
│  3. PROMOTE                                                      │
│     └── sf package version promote ... (marks as released)      │
│                                                                  │
│  4. DEPLOY TO PRODUCTION                                         │
│     └── sf package install ... --target-org Production          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Adding to Lightning Pages

1. Navigate to **Setup → Lightning App Builder**
2. Edit or create a Lightning page (App Page, Home Page, or Record Page)
3. Find **"Merged Report Grid"** in the Components panel
4. Drag the component onto your page
5. Configure the properties in the right panel
6. Save and Activate the page

### Multiple Instances

You can add **multiple Merged Report Grid components** to the same Lightning page. Each instance operates independently with its own configuration.

### User-Specific Data

To show data specific to the viewing user:
1. Set **Data Visibility** to `MY_RECORDS` (current user only) or `MY_TEAM` (user + subordinates)
2. This overrides the report's saved filter scope

---

## Configuration Properties

### Required Settings

| Property | Description |
|----------|-------------|
| **Report 1 ID** | 18-character Salesforce Report ID (required) |
| **Report 2 ID** | 18-character Salesforce Report ID (required) |
| Report 3-5 ID | Optional additional report IDs |

> **Finding Report IDs:** Open the report in Salesforce, look at the URL. The ID is the 18-character string after `/Report/` (e.g., `00OVD000005bq812AA`).

### Merge Mode

| Property | Options | Description |
|----------|---------|-------------|
| **Merge Mode** | `OUTER_JOIN`, `INNER_JOIN`, `UNION` | How reports are combined |

### Data Visibility

| Property | Options | Description |
|----------|---------|-------------|
| **Data Visibility** | `ALL`, `MY_RECORDS`, `MY_TEAM` | Override report scope |

- **ALL** - Use the report's saved filter scope (default)
- **MY_RECORDS** - Only show current user's records
- **MY_TEAM** - Show current user + subordinates in role hierarchy

### Display Options

| Property | Default | Description |
|----------|---------|-------------|
| **Show Missing as Zero** | `false` | Display `0` instead of `—` for missing values |
| **Sort By** | `KEY` | Initial sort column |
| **Sort Direction** | `ASC` | `ASC` or `DESC` |
| **Maximum Rows** | `200` | Row limit (max 2000) |
| **Show Grand Total** | `true` | Display totals row at bottom |
| **Component Title** | _(empty)_ | Custom header text |

### UNION Mode Options

| Property | Description |
|----------|-------------|
| **Dimension Constants (JSON)** | Fill missing dimensions for reports with fewer groupings |
| **Show Subtotals** | Add subtotal row after each primary group |
| **Subtotal Label** | Label for subtotal rows (default: `SUBTOTAL`) |
| **Fill Missing Categories** | Show all dimension combinations even if no data |
| **Sort Groups By Column** | Sort groups by aggregate sum |

### Column Configuration

| Property | Description |
|----------|-------------|
| **Column Aliases (JSON)** | Rename columns for display |
| **Calculated Fields (JSON)** | Add formula columns |

### Debug & Development

| Property | Description |
|----------|-------------|
| **🔧 Debug Mode** | Shows raw configuration, API responses, and recommendations |
| **🔄 Refresh Key** | Legacy property - no longer needed for cache management |

---

## Merge Modes

### OUTER_JOIN (Default)

Combines reports **horizontally**. All keys from all reports are included. Missing values show as `—` or `0`.

**Use when:** You want to compare the same entities across different reports side-by-side.

```
Report 1: Alice=100, Bob=200
Report 2: Bob=50, Carol=75

Result:
| Key   | Report 1 Value | Report 2 Value |
|-------|----------------|----------------|
| Alice | 100            | —              |
| Bob   | 200            | 50             |
| Carol | —              | 75             |
```

### INNER_JOIN

Like OUTER_JOIN but **only includes keys present in ALL reports**.

**Use when:** You only want entities that appear in every report.

```
Result:
| Key | Report 1 Value | Report 2 Value |
|-----|----------------|----------------|
| Bob | 200            | 50             |
```

### UNION

Stacks reports **vertically**. Supports up to 2 grouping dimensions. Columns with matching names are merged.

**Use when:** You want to stack different data sets with similar structure, or create grouped views with subtotals.

```
Report 1: Sales by Owner
Report 2: Pipeline by Owner

Result:
| Owner | Category | Amount |
|-------|----------|--------|
| Alice | Sales    | 1000   |
| Alice | Pipeline | 500    |
| Alice | SUBTOTAL | 1500   |
| Bob   | Sales    | 800    |
| Bob   | Pipeline | 300    |
| Bob   | SUBTOTAL | 1100   |
```

---

## JSON Configuration Properties

This section explains the three properties that require JSON input, with exact syntax and use cases.

---

### Dimension Constants (JSON)

**Property Name:** `Dimension Constants (JSON)`

**What it does:** Assigns a constant value to the "second dimension" for reports that only have one grouping level. This allows you to merge reports that have different numbers of grouping fields.

**Why you need it:** 
- Report 1 is grouped by **Owner** only (1 dimension)
- Report 2 is grouped by **Owner → Product** (2 dimensions)
- Without a constant, these can't be merged because their structures don't match
- With a constant, Report 1 rows get a fixed second dimension value like "Total"

**Exact Syntax:**
```json
{"REPORT_NUMBER": "CONSTANT_VALUE"}
```

**Rules:**
- Must be valid JSON (use double quotes `"`, not single quotes `'`)
- Keys are **report numbers as strings** (`"1"`, `"2"`, `"3"`, `"4"`, `"5"`)
- Report numbers are **1-based** (first report = "1", not "0")
- Values are the constant text that will appear in the second dimension column
- Only set constants for reports that have **fewer dimensions** than others

**Examples:**

*Single report needs a constant:*
```json
{"1": "Total"}
```
Means: Report 1 rows will have "Total" as their second dimension value.

*Multiple reports need constants:*
```json
{"1": "Summary", "3": "Combined"}
```
Means: Report 1 gets "Summary", Report 3 gets "Combined" as second dimension values.

*With special characters (must escape quotes):*
```json
{"2": "Q1 - All Products"}
```

**Common Mistakes:**
```json
// ❌ WRONG - Using single quotes
{'1': 'Total'}

// ❌ WRONG - Using 0-based index
{"0": "Total"}

// ❌ WRONG - Missing quotes around number
{1: "Total"}

// ✅ CORRECT
{"1": "Total"}
```

**Before/After Example:**

| Without Constant | With `{"1": "Total"}` |
|------------------|----------------------|
| Can't merge (dimension mismatch error) | ✅ Merges successfully |
| — | Report 1 rows show "Total" in Category column |

---

### Column Aliases (JSON)

**Property Name:** `Column Aliases (JSON)`

**What it does:** Renames columns in the output grid. The original column names from your reports are replaced with friendlier display names.

**Why you need it:**
- Salesforce report columns have technical names like "Sum of Amount" or "Record Count"
- You want cleaner labels like "Revenue" or "Total Deals"
- Column names include report suffixes like "(2)" that you want to hide

**Exact Syntax:**
```json
{"ORIGINAL_NAME": "NEW_NAME", "ORIGINAL_NAME_2": "NEW_NAME_2"}
```

**Rules:**
- Must be valid JSON (use double quotes)
- Keys must **exactly match** the original column name (case-sensitive)
- Use Debug Mode to see the exact original column names
- You can alias any number of columns
- Columns not listed keep their original names

**Examples:**

*Basic renaming:*
```json
{"Record Count": "Total Deals", "Sum of Amount": "Revenue"}
```

*Handling duplicate column names (Salesforce adds suffixes):*
```json
{
  "Record Count": "Closed Deals",
  "Record Count (2)": "Open Pipeline",
  "Sum of Amount": "Closed Revenue",
  "Sum of Amount (2)": "Pipeline Value"
}
```

*Single column rename:*
```json
{"Sum of Probability": "Win Rate %"}
```

**Finding Original Column Names:**
1. Enable **Debug Mode** on the component
2. Look at the "Columns & Data" section
3. The `columnLabel` shows the exact name to use as your key

**Common Mistakes:**
```json
// ❌ WRONG - Name doesn't match exactly (missing "Sum of")
{"Amount": "Revenue"}

// ❌ WRONG - Case mismatch
{"record count": "Total"}

// ❌ WRONG - Forgot the (2) suffix for second report's column
{"Record Count": "Pipeline"}  // This only renames Report 1's column

// ✅ CORRECT - Exact match including suffix
{"Record Count (2)": "Pipeline Count"}
```

---

### Calculated Fields (JSON)

**Property Name:** `Calculated Fields (JSON)`

**What it does:** Creates new columns that calculate values from existing columns using math formulas. The calculated column appears after all report columns.

**Why you need it:**
- Calculate conversion rates (Won / Total)
- Compute differences between reports (Report 1 - Report 2)
- Create averages (Amount / Count)
- Show percentages or ratios

**Exact Syntax:**
```json
[
  {"label": "COLUMN_NAME", "formula": "MATH_EXPRESSION"}
]
```

**Rules:**
- Must be a JSON **array** (starts with `[`, ends with `]`)
- Each calculated field is an **object** with `label` and `formula`
- `label` = the name shown in the column header
- `formula` = math expression using existing column names
- Column names in formulas must **exactly match** (use original names or aliases)
- Supported operators: `+` `-` `*` `/`
- Multiple calculated fields are separated by commas

**Examples:**

*Single calculated field:*
```json
[{"label": "Win Rate", "formula": "Sum of Won / Record Count"}]
```

*Multiple calculated fields:*
```json
[
  {"label": "Win Rate", "formula": "Sum of Won / Record Count"},
  {"label": "Avg Deal Size", "formula": "Sum of Amount / Record Count"},
  {"label": "Variance", "formula": "Sum of Amount - Sum of Amount (2)"}
]
```

*Using parentheses for order of operations:*
```json
[{"label": "Margin %", "formula": "(Sum of Revenue - Sum of Cost) / Sum of Revenue * 100"}]
```

*Comparing values across reports:*
```json
[
  {"label": "Difference", "formula": "Record Count - Record Count (2)"},
  {"label": "Growth %", "formula": "(Sum of Amount - Sum of Amount (2)) / Sum of Amount (2) * 100"}
]
```

**Finding Column Names for Formulas:**
1. Enable **Debug Mode** on the component
2. Look at the "Columns & Data" section
3. Use either `columnLabel` (display name) or `columnKey` (internal key like `r1_s_Amount`)

**Common Mistakes:**
```json
// ❌ WRONG - Not an array (missing square brackets)
{"label": "Rate", "formula": "Won / Total"}

// ❌ WRONG - Missing required "label" property
[{"formula": "A / B"}]

// ❌ WRONG - Missing required "formula" property
[{"label": "My Column"}]

// ❌ WRONG - Column name doesn't exist
[{"label": "Rate", "formula": "Wins / Losses"}]

// ✅ CORRECT
[{"label": "Rate", "formula": "Sum of Won / Record Count"}]
```

**Division by Zero:**
If a formula divides by a column that has 0 in some rows, those cells will show `—` (blank) instead of an error.

---

## Working with Different Dimensions

### The Problem

Reports may have different numbers of grouping fields:
- **Report 1:** Grouped by Owner (1 dimension)
- **Report 2:** Grouped by Owner → Product (2 dimensions)

### The Solution

Use **Dimension Constants (JSON)** to give reports with fewer dimensions a constant value. See the [Dimension Constants](#dimension-constants-json) section above for syntax.

**Result in JOIN mode:**
| Owner | Category | R1: Count | R2: Amount |
|-------|----------|-----------|------------|
| Alice | Total    | 5         | —          |
| Alice | Widgets  | —         | 1000       |
| Alice | Gadgets  | —         | 500        |

**Result in UNION mode:**
| Owner | Category | Count | Amount |
|-------|----------|-------|--------|
| Alice | Total    | 5     | —      |
| Alice | Widgets  | —     | 1000   |
| Alice | Gadgets  | —     | 500    |
| Alice | SUBTOTAL | 5     | 1500   |

---

## Viewing Source Reports

### Report Details Popover

Click on the subtitle text (e.g., "UNION from 2 reports") to see details about the source reports:

- **Report names** - The actual names from Salesforce
- **Clickable links** - Opens each report in a new browser tab
- **Dimension constants** - Shows as badges next to reports that have them configured
- **Merge mode** - Displayed at the bottom of the popover

This makes it easy to:
- Verify which reports are being merged
- Navigate directly to the source reports for editing
- See which reports have dimension constants applied

---

## Troubleshooting

### "Report not found" Error

- Verify the Report ID is exactly 18 characters
- Ensure the running user has access to view the report
- Check that the report hasn't been deleted

### "JOIN mode requires all reports to have the same number of dimensions"

**Cause:** Reports have different numbers of grouping fields.

**Solutions:**
1. Set **Dimension Constants** for reports with fewer dimensions
2. Change **Merge Mode** to `UNION`
3. Modify the reports to have the same number of groupings

### Calculated field shows blank/null

**Cause:** The formula references a column that doesn't exist.

**Solution:** Check the column names in Debug Mode. Use the exact label shown.

### Missing data in grid

- **JOIN mode:** Only matching keys appear (especially INNER_JOIN)
- **UNION mode:** Check that reports have compatible structures
- Verify **Data Visibility** setting isn't filtering out data

### "Can't run more than 500 reports" Error

**Cause:** Salesforce limits report API calls to 500 per user per 60 minutes.

**Solutions:**
1. Wait 60 minutes for the limit to reset
2. Reduce the number of page refreshes during development
3. Consider using fewer reports in the component

### App Builder Edit Mode Issues

The component behaves differently in **App Builder edit mode** vs **runtime mode**:

- **Edit mode:** Caching is disabled to ensure you always see fresh data when testing configurations
- **Runtime mode:** Caching is enabled for better performance

If you see unexpected behavior in edit mode:
1. Save the page and view it in runtime mode
2. Check Debug Mode - it shows `isInDesignMode: true/false` and `cachingMode`

### Debug Mode

Enable **Debug Mode** in the component configuration to see:
- Raw configuration being sent to Apex
- Parsed options after validation
- Response metadata (row count, errors, warnings)
- Column definitions and data types
- Design mode detection status
- Caching mode (enabled/disabled)

---

## Limitations

| Limitation | Value |
|------------|-------|
| Maximum reports | 5 |
| Maximum rows | 2,000 |
| Maximum grouping dimensions | 2 |
| Report types supported | Summary reports only |
| Report API calls | 500 per user per 60 minutes |

### Not Supported

- ❌ Joined Reports
- ❌ Matrix Reports  
- ❌ Tabular Reports
- ❌ Reports with 3+ groupings
- ❌ Cross-object formulas in calculated fields

---

## Best Practices

### Setup & Configuration

1. **Start simple** - Begin with 2 reports and OUTER_JOIN before adding complexity
2. **Use Debug Mode** - Enable it during setup to understand data flow
3. **Match dimensions first** - Ensure reports have compatible grouping structures
4. **Test with small data** - Use filtered reports during configuration
5. **Save frequently** - Save your page after each configuration change in App Builder

### Performance

1. **Limit rows** - Use reasonable `Maximum Rows` values (start with 200)
2. **Minimize refreshes** - Avoid excessive page refreshes during development to stay within API limits
3. **Use caching** - In runtime mode, caching improves performance automatically

### User Experience

1. **Name columns clearly** - Use Column Aliases for user-friendly labels
2. **Set appropriate visibility** - Use `MY_RECORDS` or `MY_TEAM` for personalized views
3. **Add a title** - Set `Component Title` for clarity when multiple grids are on a page
4. **Document your setup** - Note which reports and settings you used

### Multiple Instances

When using multiple Merged Report Grid components on the same page:
1. Give each a unique **Component Title**
2. Each instance is completely independent
3. API limits apply across all instances per user

---

## Support

For issues or feature requests, contact your Salesforce administrator or the DataTools Pro team.

---

**Version:** 1.3.0  
**Package ID:** 04tPU000002A02PYAS  
**Last Updated:** February 2026
