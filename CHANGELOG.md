# Changelog

All notable changes to the Merged Report Grid project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [1.5.3] - 2026-02-24

### Fixed

- **Totals row alignment** – Totals row is a separate table below the datatable; column count and widths now match. Added missing second key column when `hasSecondDimension` is true (UNION with 2 dimensions). Set row-number to 2.5rem, key to 180px, second key to 140px to align with lightning-datatable.
- **Integration test** – `testIntegrationTierLookupsWithRealReports` used `r1_RowCount / r2_RowCount` and REPORT_LEADS_BY_OWNER + REPORT_LEADS_BY_STATUS; in JOIN mode both reports merge "Record Count" so those keys don't exist. Test now uses REPORT_LEADS_BY_OWNER + REPORT_LEADS_BY_OWNER_B and `inputFormula: "Record Count"`, formula `Rate * Record Count`.

### Changed

- **LWC** – `mergedReportGrid.html` totals row includes optional second key cell; `mergedReportGrid.css` totals column widths aligned to datatable; `mergedReportGrid.js` adds `hasSecondDimension` getter.

---

## [1.5.0] - 2026-02-24

### Added

#### Tier Lookups (JSON) Property

- **Tier Lookups** – New component property for tier-based rate lookups instead of nested IF formulas.
  - Define rate tiers (e.g., commission at 13% above 33.5%, 10% above 26.5%, 4% default)
  - Input formula is evaluated per row; first tier where `input >= min` wins (tiers sorted by `min` descending)
  - Supports `nullWhenZero` to return blank when the input denominator is 0
  - Tier columns are added **before** calculated fields so formulas can reference them (e.g., `Rate * Funded Amount`)
  - Optional `format`, `decimals`, and `dataType` for display

- **MergeOptions** – Added `TierLookup` and `TierEntry` classes; `tierLookups` property with validation.

- **Tests** – Unit tests for `evaluateTierLookup`; integration test for tier lookups with calculated fields.

### Fixed

- **Column Aliases** – Aliases were not applied because Apex `JSON.deserialize` does not populate `Map<String, Object>` in class properties. Now manually extracts `columnAliases` via `JSON.deserializeUntyped`. Also added trimmed-label fallback in `getColumnConfig` for robustness.

### Changed

- **Formula Resolution** – Extracted `buildLabelToKeyForFormulas()` for reuse by tier lookups and calculated fields.
- **Documentation** – ADMIN_GUIDE updated with Tier Lookups section, UNION vs JOIN column handling, and full commission example.
- **BUGS.md** – Clarified that “prefer larger total” fix applies to JOIN mode only (UNION merges same-name columns).

### Technical Details

| File | Changes |
|------|---------|
| `MergeOptions.cls` | Added `tierLookups`, `TierLookup`, `TierEntry`; `getColumnConfig()` trim fallback |
| `MergedReportController.cls` | Added `addTierLookups()`, `evaluateTierLookup()`, `buildLabelToKeyForFormulas()`, `extractColumnAliasesFromJson()` |
| `mergedReportGrid.js` | Added `tierLookupsJson` property, parsing, validation |
| `mergedReportGrid.js-meta.xml` | Added Tier Lookups (JSON) property |
| `MergedReportControllerTest.cls` | Added tier lookup unit and integration tests |

---

## [1.4.0] - 2026-02-24

### Fixed

- Percent formatting displays 100× too small (PERCENT_DATA)
- Totals row for calculated percent shows wrong value when reports have overlapping column names (prefer column with larger total for base label in JOIN mode)

### Changed

- Column aliases, calculated fields, dimension constants, formatting improvements

---

[1.5.3]: https://github.com/DataToolsPro/merged-report-grid/releases/tag/v1.5.3
[1.5.0]: https://github.com/DataToolsPro/merged-report-grid/releases/tag/v1.5.0
[1.4.0]: https://github.com/DataToolsPro/merged-report-grid/releases/tag/v1.4.0
