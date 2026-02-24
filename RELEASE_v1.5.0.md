# Release Notes - v1.5.0

**Release Date:** February 24, 2026

## Tier Lookups (JSON) Property

Add tier-based rate lookups to the Merged Report Grid without complex nested IF formulas.

### What's New

- **Tier Lookups (JSON)** – New component property for configurable rate tiers
  - Define thresholds and values (e.g., 13% above 33.5%, 10% above 26.5%, 4% default)
  - Input formula evaluated per row; first tier where `input >= min` wins
  - `nullWhenZero` option for ratios when denominator is 0
  - Tier columns are added **before** calculated fields and can be referenced in formulas (e.g., `Rate * Funded Amount`)

### Bug Fix

- **Column Aliases** – Aliases were not applied because Apex `JSON.deserialize` does not populate `Map<String, Object>` in class properties. Now manually extracts `columnAliases` via `JSON.deserializeUntyped`. Added trimmed-label fallback for robustness. **Note:** After deployment, change an alias slightly and save the page to bust cache if aliases don’t appear immediately.

### Example

**Tier Lookups (JSON):**
```json
[
  {
    "label": "Rate",
    "inputFormula": "Sum of Funded / Sum of Approved",
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
[{"label": "Commission", "formula": "Rate * Sum of Funded"}]
```

### Documentation

- See ADMIN_GUIDE.md for full syntax, rules, and examples
- Clarified UNION vs JOIN column handling (UNION merges same-name columns; JOIN keeps them separate)
- DEPLOYMENT_POLICY.md – Never deploy to production via CLI; use change sets

### Files Changed

| Component | Changes |
|-----------|---------|
| MergeOptions.cls | `tierLookups`, `TierLookup`, `TierEntry`; `getColumnConfig()` trim fallback |
| MergedReportController.cls | `addTierLookups()`, `evaluateTierLookup()`, `buildLabelToKeyForFormulas()`, `extractColumnAliasesFromJson()` |
| mergedReportGrid (LWC) | `tierLookupsJson` property |
| MergedReportControllerTest.cls | Tier lookup unit and integration tests |

---

**Full Changelog:** https://github.com/DataToolsPro/merged-report-grid/compare/v1.4.0...v1.5.0
