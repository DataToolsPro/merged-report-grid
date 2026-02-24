# Release Notes - v1.5.0

**Release Date:** February 24, 2026

## Tier Lookups (JSON) Property

Add tier-based rate lookups to the Merged Report Grid without complex nested IF formulas.

### What's New

- **Tier Lookups (JSON)** – New component property for configurable rate tiers
  - Define thresholds and values (e.g., 13% above 33.5%, 10% above 26.5%, 4% default)
  - Input formula evaluated per row; first tier where `input >= min` wins
  - `nullWhenZero` option for ratios when denominator is 0
  - Tier columns are added before calculated fields and can be referenced in formulas

### Example

**Tier Lookups (JSON):**
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
    "format": "percent:2"
  }
]
```

**Calculated Fields (JSON):**
```json
[{"label": "Commission", "formula": "Rate * Funded Amount"}]
```

### Documentation

- See ADMIN_GUIDE.md for full syntax, rules, and examples
- Clarified UNION vs JOIN column handling (UNION merges same-name columns; JOIN keeps them separate; "prefer larger total" applies only in JOIN mode)

### Files Changed

| Component | Changes |
|-----------|---------|
| MergeOptions.cls | `tierLookups`, `TierLookup`, `TierEntry` |
| MergedReportController.cls | `addTierLookups()`, `evaluateTierLookup()`, `buildLabelToKeyForFormulas()` |
| mergedReportGrid (LWC) | `tierLookupsJson` property |
| Tests | Unit and integration tests for tier lookups |

---

**Full Changelog:** https://github.com/DataToolsPro/merged-report-grid/compare/v1.4.0...v1.5.0
