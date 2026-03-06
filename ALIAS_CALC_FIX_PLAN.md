# Alias + Calculated Fields Fix – Architecture

## Problem
Column aliases and calculated fields conflicted when used together. Aliases were applied in both Apex and LWC; formula resolution depended on labels that could be aliased; and `originalLabel` was not available to the LWC.

## Solution: Single Source of Truth

### 1. Apex: Only Original Labels
- **Before**: Apex applied `getColumnAlias()` to `col.label` (when it received `columnAliases`).
- **After**: Apex always sets `col.label` to the **original** report label.
- **Format**: Still uses `getColumnFormat()`, `getColumnDecimals()`, etc., from alias config.
- **Columns**: Key, second key, report, tier, calculated – all use original labels from Apex.

### 2. LWC: Single Place for Display Aliases
- **`_getDisplayLabel()`**: Applies aliases only for display.
- **Applies to**: Columns with `originalLabel` or `aggregateLabel` (report/key columns).
- **Skips**: Calculated and tier columns (user-defined labels).
- **Fallbacks**: Exact match, trimmed, case-insensitive, then index-based.

### 3. Formula Resolution: Original Labels Only
- **`buildLabelToKeyForFormulas`**: Maps only original labels to column keys.
- **Order**: `aggregateLabel` → `originalLabel` → `label`.
- **Formulas**: Use report names (e.g. `"Sum of Funded Amount"`), never display aliases.

### 4. `originalLabel` Exposed to LWC
- **MergedGridDTO**: `originalLabel` is `@AuraEnabled`.
- **LWC**: Uses `originalLabel` for alias matching, including JOIN mode `"Sum of Amount (2)"`-style labels.

## Column Types and Aliasing

| Column Type | `originalLabel` | `aggregateLabel` | Alias Applied? |
|-------------|-----------------|------------------|----------------|
| Key         | ✓               | –                | ✓ (LWC)        |
| Second Key  | ✓               | –                | ✓ (LWC)        |
| Report      | ✓               | ✓                | ✓ (LWC)        |
| Tier        | –               | –                | ✗              |
| Calculated  | –               | –                | ✗              |

## Result
- **Formulas**: Always work with report names.
- **Display**: LWC applies aliases for report and key columns only.
- **No double aliasing**: Apex never changes labels for display.
- **Stable resolution**: Formula resolution is independent of aliases.
