# Test Coverage Summary

## Overview

| Class | Coverage | Test Count |
|-------|----------|------------|
| MergeOptions | 100% | via MergeOptions tests |
| MergedGridDTO | 99% | via DTO and integration tests |
| MergedReportController | 80% | 103 total tests |

**Run tests:**
```bash
sf apex run test --class-names MergedReportControllerTest --result-format human --code-coverage --target-org sandbox --wait 10
```

---

## Formula Evaluator Tests (evaluateFormula)

The formula evaluator supports parentheses and order of operations. Coverage via `@TestVisible` direct unit tests:

| Test | Formula | Validates |
|------|---------|-----------|
| testFormulaSimpleDivision | `A / B` | Regression; simple division |
| testFormulaParenthesesAndMultiplication | `(A / B) * 100` | Parens + order of ops (main fix) |
| testFormulaOrderOfOperations | `A + B * C` | * before + (2+4*5=22) |
| testFormulaParenthesesWithSubtraction | `(A - B) / C` | Parens with subtraction |
| testFormulaNestedParentheses | `((A) / B)` | Redundant parens strip |
| testFormulaDivideByZero | `A / 0` | Returns 0 |
| testFormulaInvalidToken | `A / NotAKey` | Unknown token → 0 |
| testFormulaSimpleAddition | `A + B` | Addition |
| testFormulaSimpleSubtraction | `A - B` | Subtraction |
| testFormulaSimpleMultiplication | `A * B` | Multiplication |
| testFormulaPureToken | `Amount`, `100` | Column lookup, literal |
| testFormulaNullInputs | null formula, null values | Edge cases |
| testFormulaChainedSubtraction | `A - B - C` | Right-associative (90) |
| testFormulaInvalidChars | `A @ B` | Invalid chars → null |

**Integration tests** exercise the full flow with real reports:
- testIntegrationCalculatedFieldsWithRealReports
- testIntegrationTwoDimensionCalculatedFields
- testIntegrationJoinModeWithCalculatedFields

---

## Known Limitation

Chained subtraction `A - B - C` evaluates as `A - (B - C)` (right-associative) because we split on the first operator. Use parentheses for left-associative: `(A - B) - C`.
