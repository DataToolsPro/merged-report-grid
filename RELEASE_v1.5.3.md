# Release Notes - v1.5.3

**Release Date:** February 24, 2026

## Fixes

### Totals row alignment

The totals row is rendered in a separate table below the lightning-datatable. Column count and widths now match the datatable so totals line up with the data columns.

- **Second dimension** – When the grid has two dimensions (e.g. UNION with a bucket column), the totals row was missing the second key column, shifting all value columns left. The totals row now includes an optional second key cell when `hasSecondDimension` is true.
- **Column widths** – Totals table column widths aligned to the datatable: row number 2.5rem, key 180px, second key 140px; `table-layout: fixed` so value columns share the remaining space.

### Integration test

`testIntegrationTierLookupsWithRealReports` failed because it used `inputFormula: "r1_RowCount / r2_RowCount"` with two reports that both have "Record Count"; in JOIN mode that column is merged, so `r1_RowCount` and `r2_RowCount` don’t exist. The test now uses two reports with the same grouping (REPORT_LEADS_BY_OWNER + REPORT_LEADS_BY_OWNER_B) and formulas that reference the merged column: `inputFormula: "Record Count"`, calculated field `Rate * Record Count`.

---

**Full Changelog:** https://github.com/DataToolsPro/merged-report-grid/compare/v1.5.0...v1.5.3
