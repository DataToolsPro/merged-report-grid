# Merged Report Grid - Salesforce Admin Guide

A Lightning Web Component that merges 2-5 Salesforce reports into a single unified grid.

**Version:** 1.5.0

---

## Table of Contents

1. [Installation & Deployment](#installation--deployment)
2. [Adding to Lightning Pages](#adding-to-lightning-pages)
3. [Configuration Properties](#configuration-properties)
4. [Merge Modes](#merge-modes)
5. [JSON Configuration Properties](#json-configuration-properties)
   - [Dimension Constants](#dimension-constants-json)
   - [Column Aliases](#column-aliases-json)
   - [Calculated Fields](#calculated-fields-json)
   - [Tier Lookups](#tier-lookups-json)
6. [Working with Different Dimensions](#working-with-different-dimensions)
7. [Viewing Source Reports](#viewing-source-reports)
8. [Troubleshooting](#troubleshooting)
9. [Limitations](#limitations)
10. [Best Practices](#best-practices)

---

## Installation & Deployment

This guide provides deployment instructions for deploying the component directly to your Salesforce org using one of these methods:

### Prerequisites

1. **Salesforce CLI** - Download from [developer.salesforce.com/tools/sfdxcli](https://developer.salesforce.com/tools/sfdxcli)
2. **Git** (optional, if cloning the repository)
3. Verify CLI installation:
```bash
sf --version
```

### Method 1: Deploy via Salesforce CLI (Recommended)

This is the fastest method for deploying to a sandbox or production org.

#### Windows (CMD/PowerShell)

```cmd
REM 1. Clone the repository (or download and extract the ZIP)
git clone <repository-url>
cd merged-report-grid

REM 2. Authenticate to your org
REM For Sandbox:
sf org login web -a MySandbox --instance-url https://test.salesforce.com

REM For Production:
sf org login web -a MyProd --instance-url https://login.salesforce.com

REM 3. Deploy the code
sf project deploy start -o MySandbox

REM 4. (Optional) Run tests to verify
sf apex run test -n MergedReportControllerTest -o MySandbox -r human -w 5
```

#### Windows (PowerShell)

```powershell
# 1. Clone the repository (or download and extract the ZIP)
git clone <repository-url>
cd merged-report-grid

# 2. Authenticate to your org
# For Sandbox:
sf org login web -a MySandbox --instance-url https://test.salesforce.com

# For Production:
sf org login web -a MyProd --instance-url https://login.salesforce.com

# 3. Deploy the code
sf project deploy start -o MySandbox

# 4. (Optional) Run tests to verify
sf apex run test -n MergedReportControllerTest -o MySandbox -r human -w 5
```

#### Mac/Linux (Bash)

```bash
# 1. Clone the repository (or download and extract the ZIP)
git clone <repository-url>
cd merged-report-grid

# 2. Authenticate to your org
# For Sandbox:
sf org login web -a MySandbox --instance-url https://test.salesforce.com

# For Production:
sf org login web -a MyProd --instance-url https://login.salesforce.com

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

### Method 2: Deploy via Change Sets (Sandbox to Production)

**Yes, this can be deployed to a sandbox and moved via change sets!** This is the traditional Salesforce deployment method that many admins prefer.

#### Step 1: Deploy to Sandbox First

Use Method 1 above to deploy to your sandbox, or use VS Code with Salesforce Extensions.

#### Step 2: Create an Outbound Change Set

1. In your **Sandbox**, navigate to **Setup → Outbound Change Sets**
2. Click **New** to create a new change set
3. Give it a name (e.g., "Merged Report Grid v1.4.0")
4. Add the following components:

   **Apex Classes:**
   - `MergedReportController`
   - `MergedReportControllerTest`
   - `MergeOptions`
   - `MergedGridDTO`

   **Lightning Components:**
   - `mergedReportGrid`

5. Click **Upload** to upload the change set
6. Select your **Production** org as the target
7. Click **Upload**

#### Step 3: Deploy Change Set to Production

1. In your **Production** org, navigate to **Setup → Inbound Change Sets**
2. Find the change set you just uploaded
3. Click **Deploy**
4. Review the components and click **Deploy**
5. Monitor the deployment status

> ⚠️ **Important:** Change sets require all Apex tests to pass. The `MergedReportControllerTest` class will run automatically during deployment.

### What's Included

This repository contains:

- **4 Apex Classes:**
  - `MergedReportController` - Main controller that fetches and merges reports
  - `MergedReportControllerTest` - Unit tests (90%+ code coverage)
  - `MergeOptions` - Configuration data transfer object
  - `MergedGridDTO` - Response data transfer object

- **1 Lightning Web Component:**
  - `mergedReportGrid` - The UI component that displays the merged grid

- **Metadata Files:**
  - All required `.cls-meta.xml` and `.js-meta.xml` files for deployment

### Deployment Checklist

- [ ] Deploy to sandbox first
- [ ] Run Apex tests: `sf apex run test -n MergedReportControllerTest -o MySandbox`
- [ ] Test the component in App Builder with sample reports
- [ ] Verify all functionality works as expected
- [ ] Deploy to production (via CLI or change set)
- [ ] Add component to Lightning pages

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
| **Tier Lookups (JSON)** | Tier-based rate lookups (usable in formulas) |

### Debug & Development

| Property | Description |
|----------|-------------|
| **🔧 Debug Mode** | Shows raw configuration, API responses, and recommendations |
| **🔄 Refresh Key** | Legacy property - no longer needed for cache management |

---

## Merge Modes

### OUTER_JOIN (Default)

Combines reports **horizontally**. All keys from all reports are included. Each report keeps its **own columns**—if both have "Sum of Amount", you get `r1_Sum_of_Amount` and `r2_Sum_of_Amount` as separate columns (shown as "Sum of Amount" and "Sum of Amount (2)"). Missing values show as `—` or `0`.

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

Stacks reports **vertically**. Supports up to 2 grouping dimensions. Columns with matching names are **merged** into a single column—values from all reports are stacked by row (e.g., "Sum of Amount" from Report 1 and "Sum of Amount" from Report 2 become one `merged_Sum_of_Amount` column).

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

**What it does:** Renames columns and optionally overrides their number formatting. The original column names from your reports are replaced with friendlier display names, and you can control how numbers are displayed (currency symbols, decimal places, etc.).

**Why you need it:**
- Salesforce report columns have technical names like "Sum of Amount" or "Record Count"
- You want cleaner labels like "Revenue" or "Total Deals"
- Column names include report suffixes like "(2)" that you want to hide
- You want to control number formatting (add/remove currency symbols, change decimal places)

---

#### Simple Syntax (Rename Only)

```json
{"ORIGINAL_NAME": "NEW_NAME"}
```

**Examples:**

*Basic renaming:*
```json
{"Record Count": "Total Deals", "Sum of Amount": "Revenue"}
```

*Handling duplicate column names:*
```json
{
  "Record Count": "Closed Deals",
  "Record Count (2)": "Open Pipeline"
}
```

---

#### Extended Syntax (Rename + Format)

```json
{
  "ORIGINAL_NAME": {
    "label": "NEW_NAME",
    "format": "FORMAT_TYPE",
    "decimals": NUMBER
  }
}
```

**Format Options:**

| Format | Output | Description |
|--------|--------|-------------|
| `currency` | `$1,234.56` | Currency with org's default symbol |
| `currency:EUR` | `€1,234.56` | Currency with specific symbol |
| `currency:GBP` | `£1,234.56` | British Pounds |
| `percent` | `45.50%` | Percentage |
| `percent:0` | `46%` | Percentage, no decimals |
| `percent:1` | `45.5%` | Percentage, 1 decimal |
| `number` | `1,234` | Number with thousand separators |
| `number:2` | `1,234.56` | Number with 2 decimal places |
| `number:0` | `1,234` | Whole number |
| `none` | `1234.56` | Raw number, no formatting |

**Extended Examples:**

*Rename and format as currency:*
```json
{
  "Sum of Amount": {
    "label": "Revenue",
    "format": "currency"
  }
}
```
Output: `$1,234.56`

*Format with specific currency:*
```json
{
  "Sum of Amount": {
    "label": "Revenue (EUR)",
    "format": "currency:EUR"
  }
}
```
Output: `€1,234.56`

*Percentage with custom decimals:*
```json
{
  "Sum of Probability": {
    "label": "Win Rate",
    "format": "percent",
    "decimals": 1
  }
}
```
Output: `45.5%`

*Remove currency formatting (show raw number):*
```json
{
  "Sum of Amount": {
    "label": "Amount",
    "format": "none"
  }
}
```
Output: `1234.56`

*Mixed simple and extended:*
```json
{
  "Record Count": "Total Deals",
  "Sum of Amount": {
    "label": "Revenue",
    "format": "currency"
  },
  "Sum of Probability": {
    "label": "Win Rate",
    "format": "percent:1"
  }
}
```

---

#### Rules

- Must be valid JSON (use double quotes)
- Keys must **exactly match** the original column name (case-sensitive)
- Use Debug Mode to see the exact original column names
- Values can be either:
  - A **string** (just renames the column)
  - An **object** with `label`, `format`, and/or `decimals` (renames and formats)
- Columns not listed keep their original names and default formatting

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

// ❌ WRONG - Invalid format type
{"Sum of Amount": {"label": "Revenue", "format": "money"}}

// ✅ CORRECT - Valid format
{"Sum of Amount": {"label": "Revenue", "format": "currency"}}
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
  {"label": "COLUMN_NAME", "formula": "MATH_EXPRESSION", "format": "percent", "decimals": 1}
]
```

**Rules:**
- Must be a JSON **array** (starts with `[`, ends with `]`)
- Each calculated field is an **object** with required `label` and `formula`
- `label` = the name shown in the column header
- `formula` = math expression using existing column names (use display labels; if you alias a column, use the alias)
- Column names in formulas must **exactly match** (use original names or aliases)
- Supported operators: `+` `-` `*` `/`
- Optional `format`, `decimals`, `currencyCode` control display
- Multiple calculated fields are separated by commas

**Optional format properties:**
| Property | Values | Purpose |
|----------|--------|---------|
| `format` | `percent`, `currency`, `number`, `none` | How to display the value |
| `decimals` | `1`, `2`, etc. | Decimal places (default 2) |
| `currencyCode` | `USD`, `EUR`, etc. | When format is `currency` |

**Percent format:** Use ratios 0–1 in your formula. Example: `Record Count / 100` gives 0.05 for 5 → displays as 5.0% with 1 decimal. Use `decimals: 1` for 4.3%, `decimals: 2` for 4.30%.

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

*Percent format with explicit decimals:*
```json
[
  {"label": "% Gone", "formula": "Record Count / Sum of Stage Duration", "format": "percent", "decimals": 1}
]
```

*Shorthand for decimals (percent:1 = 1 decimal):*
```json
[
  {"label": "Conversion Rate", "formula": "Won / Total", "format": "percent:1"}
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

// ✅ CORRECT - Percent with 1 decimal place
[{"label": "% Gone", "formula": "Record Count / Sum of Stage Duration", "format": "percent", "decimals": 1}]
```

**Division by Zero:**
If a formula divides by a column that has 0 in some rows, those cells will show `—` (blank) instead of an error.

**JOIN Mode: Duplicate Base Labels**

In JOIN mode, when both reports have the same column (e.g., "Sum of Amount"), they appear as separate columns. When a formula uses the base label (e.g., "Sum of Amount" without a suffix), the component resolves it to the column with the **larger total**. That way ratio formulas like `Sum of Gross Margin / Sum of Funded Amount` use both values from the same report instead of mixing reports. (In UNION mode this doesn't apply—same-name columns are merged into one, so there's no ambiguity.)

**Tier Lookups in Formulas:**
Tier lookup columns are added *before* calculated fields, so you can reference them in formulas. Example: `Rate * Funded Amount` where "Rate" is a tier lookup column.

---

### Tier Lookups (JSON)

**Property Name:** `Tier Lookups (JSON)`

**What it does:** Creates columns with tier-based rate values instead of complex nested IF logic. Each tier lookup evaluates an input formula, then selects a value from a list of thresholds. The resulting column can be used in calculated fields (e.g., `Rate * Funded Amount`).

**Why you need it:**
- Commission rates that vary by conversion rate (e.g., 13% above 33.5%, 10% above 26.5%, 4% default)
- Fee tiers based on ratios or percentages
- Cleaner, maintainable configuration than nested IF formulas

**Exact Syntax:**
```json
[
  {
    "label": "COLUMN_NAME",
    "inputFormula": "FORMULA_FOR_INPUT",
    "nullWhenZero": true,
    "tiers": [
      {"min": 0.335, "value": 0.13},
      {"min": 0.265, "value": 0.10},
      {"value": 0.04}
    ],
    "format": "percent:2",
    "dataType": "PERCENT_DATA"
  }
]
```

**Rules:**
- Must be a JSON **array**
- Each object requires `label`, `inputFormula`, and `tiers`
- `inputFormula` — math expression (same as calculated field formula); evaluated per row to get the input value
- `tiers` — array of objects. Each object has:
  - `min` (optional) — threshold; first tier where `input >= min` wins (tiers sorted by `min` descending)
  - `value` — the value to use when this tier matches
- The last tier typically has no `min` — it's the **default** used when no threshold matches
- `nullWhenZero` (optional, default false) — if true, return null when input is 0 or null (e.g., when denominator is 0 in a ratio)
- Optional `format`, `decimals`, `dataType` control display

**Tier Logic:**
1. Evaluate `inputFormula` for the row
2. Sort tiers by `min` descending (highest first)
3. Find the first tier where `input >= min`; use that tier's `value`
4. If none match, use the default tier (the one with no `min`)

**Examples:**

*Commission rate by conversion:*
```json
[
  {
    "label": "Rate",
    "inputFormula": "Funded / Approved",
    "nullWhenZero": true,
    "tiers": [
      {"min": 0.335, "value": 0.13},
      {"min": 0.265, "value": 0.10},
      {"min": 0.225, "value": 0.08},
      {"min": 0.20, "value": 0.07},
      {"min": 0.17, "value": 0.06},
      {"value": 0.04}
    ],
    "format": "percent:2",
    "dataType": "PERCENT_DATA"
  }
]
```

*Using tier column in a calculated field (commission example):*

Set **Tier Lookups (JSON)**:
```json
[
  {
    "label": "Rate",
    "inputFormula": "Funded / Approved",
    "nullWhenZero": true,
    "tiers": [
      {"min": 0.335, "value": 0.13},
      {"min": 0.265, "value": 0.10},
      {"min": 0.20, "value": 0.07},
      {"value": 0.04}
    ],
    "format": "percent:2",
    "dataType": "PERCENT_DATA"
  }
]
```

Set **Calculated Fields (JSON)**:
```json
[
  {"label": "Commission", "formula": "Rate * Funded Amount"}
]
```

The "Rate" tier column is added first, so the formula can reference it. For each row, `Funded / Approved` is evaluated, the matching tier value is selected, and "Commission" multiplies that Rate by Funded Amount.

**Common Mistakes:**
```json
// ❌ WRONG - Missing label or inputFormula
[{"inputFormula": "A/B", "tiers": [{"value": 0.1}]}]

// ❌ WRONG - Empty tiers array
[{"label": "Rate", "inputFormula": "A/B", "tiers": []}]

// ✅ CORRECT - At least one tier with value, default last
[{"label": "Rate", "inputFormula": "Funded/Approved", "nullWhenZero": true, "tiers": [{"min": 0.3, "value": 0.1}, {"value": 0.04}]}]
```

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

For issues or feature requests, please open an issue in the repository.

---

**Version:** 1.5.0  
**Last Updated:** February 2026
