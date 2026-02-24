# Changelog

All notable changes to the Merged Report Grid project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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

### Changed

- **Formula Resolution** – Extracted `buildLabelToKeyForFormulas()` for reuse by tier lookups and calculated fields.
- **Documentation** – ADMIN_GUIDE updated with Tier Lookups section, UNION vs JOIN column handling, and full commission example.
- **BUGS.md** – Clarified that “prefer larger total” fix applies to JOIN mode only (UNION merges same-name columns).

### Technical Details

| File | Changes |
|------|---------|
| `MergeOptions.cls` | Added `tierLookups`, `TierLookup`, `TierEntry` |
| `MergedReportController.cls` | Added `addTierLookups()`, `evaluateTierLookup()`, `buildLabelToKeyForFormulas()` |
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

[1.5.0]: https://github.com/DataToolsPro/merged-report-grid/releases/tag/v1.5.0
[1.4.0]: https://github.com/DataToolsPro/merged-report-grid/releases/tag/v1.4.0
