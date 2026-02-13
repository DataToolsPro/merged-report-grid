# Security Review - Merged Report Grid

**Date:** February 2026  
**Component:** Merged Report Grid Lightning Web Component  
**Reviewer:** Security Analysis

---

## Executive Summary

This security review identified **3 HIGH** severity issues, **2 MEDIUM** severity issues, and **3 LOW** severity issues. The most critical vulnerabilities are related to formula injection, insufficient input validation, and potential information disclosure.

---

## Critical Vulnerabilities (HIGH)

### 1. Formula Injection in Calculated Fields ⚠️ HIGH

**Location:** `MergedReportController.cls` - `evaluateFormula()` method (lines 1412-1467)

**Issue:** The formula evaluation uses string replacement and simple parsing, which could allow injection of malicious formulas if column names contain special characters or if the formula resolution logic is bypassed.

**Risk:**
- An attacker could potentially craft formulas that access unintended data
- Formula token resolution uses simple string replacement which could be exploited
- No validation that resolved tokens match expected patterns

**Current Code:**
```apex
private static String resolveFormulaLabels(String formula, Map<String, String> labelToKey, MergedGridDTO result) {
    String resolved = formula;
    // ...
    resolved = resolved.replace(token, labelToKey.get(token)); // Simple replacement
}
```

**Recommendation:**
1. Validate that all tokens in the formula resolve to known column keys
2. Use a whitelist approach - only allow tokens that exist in `labelToKey`
3. Add regex validation to ensure formulas only contain allowed characters: `[a-zA-Z0-9_() +\-*/]`
4. Escape special characters in column names before using them in formulas
5. Consider using a proper expression parser library instead of string manipulation

**Fix Example:**
```apex
// Validate formula contains only safe characters
if (!Pattern.matches('^[a-zA-Z0-9_() +\\-*/\\s]+$', formula)) {
    result.warnings.add('Formula contains invalid characters');
    return null;
}

// Validate all tokens resolve
for (String token : tokens) {
    if (!labelToKey.containsKey(token) && !token.isNumeric()) {
        // Reject unknown tokens
        return null;
    }
}
```

---

### 2. Insufficient Input Validation on JSON Properties ⚠️ HIGH

**Location:** `mergedReportGrid.js` - JSON parsing (lines 187-201, 234-248)

**Issue:** JSON parsing from user input (`columnAliasesJson`, `calculatedFieldsJson`, `dimensionConstantsJson`) is done with try-catch that silently fails. Malformed or malicious JSON could cause issues.

**Risk:**
- Malformed JSON could cause runtime errors
- Large JSON payloads could cause memory issues
- No size limits on JSON inputs
- Silent failures make debugging difficult

**Current Code:**
```javascript
try { columnAliases = JSON.parse(this.columnAliasesJson); } 
catch (e) { /* ignore */ }
```

**Recommendation:**
1. Add explicit size limits (e.g., max 10KB per JSON property)
2. Validate JSON structure before parsing
3. Log parsing errors for debugging (in debug mode)
4. Return user-friendly error messages instead of silent failures
5. Sanitize JSON content before parsing

**Fix Example:**
```javascript
_buildOptionsJson() {
    let columnAliases = {};
    if (this.columnAliasesJson) {
        // Validate size
        if (this.columnAliasesJson.length > 10000) {
            this.showToast('Error', 'Column Aliases JSON is too large (max 10KB)', 'error');
            return;
        }
        try { 
            columnAliases = JSON.parse(this.columnAliasesJson);
            // Validate structure
            if (typeof columnAliases !== 'object' || Array.isArray(columnAliases)) {
                throw new Error('Invalid structure');
            }
        } catch (e) {
            this.showToast('Error', 'Invalid Column Aliases JSON: ' + e.message, 'error');
            columnAliases = {};
        }
    }
    // ...
}
```

---

### 3. Information Disclosure in Error Messages ⚠️ HIGH

**Location:** `MergedReportController.cls` - Error handling (lines 114-120, 393-404)

**Issue:** Error messages include stack traces and detailed error information that could leak sensitive information about the system.

**Risk:**
- Stack traces reveal internal class/method names
- Error messages might reveal report structure or data
- Could aid attackers in understanding system architecture

**Current Code:**
```apex
catch (Exception e) {
    result.errors.add(new MergedGridDTO.ReportError(
        null,
        'Error processing reports: ' + e.getMessage() + ' - ' + e.getStackTraceString(),
        true
    ));
}
```

**Recommendation:**
1. Remove stack traces from production error messages
2. Log detailed errors server-side only
3. Return generic user-friendly messages to clients
4. Sanitize error messages before returning to client

**Fix Example:**
```apex
catch (Exception e) {
    // Log full error server-side
    System.debug(LoggingLevel.ERROR, 'Error processing reports: ' + e.getMessage() + '\n' + e.getStackTraceString());
    
    // Return generic message to client
    String userMessage = 'An error occurred while processing reports.';
    if (e instanceof System.NoAccessException) {
        userMessage = 'You don\'t have access to one or more reports.';
    } else if (e.getMessage() != null && e.getMessage().contains('insufficient access')) {
        userMessage = 'You don\'t have access to run one or more reports.';
    }
    
    result.errors.add(new MergedGridDTO.ReportError(null, userMessage, true));
}
```

---

## Medium Severity Issues

### 4. Formula Token Resolution Vulnerability ⚠️ MEDIUM

**Location:** `MergedReportController.cls` - `resolveFormulaLabels()` (lines 1366-1407)

**Issue:** The token resolution uses simple string replacement which could be exploited if column names contain substrings that match other column names.

**Example Attack:**
- Column 1: "Amount"
- Column 2: "Amount (2)"
- Formula: "Amount - Amount (2)"
- Replacement could incorrectly match "Amount" in "Amount (2)"

**Recommendation:**
1. Use word boundaries or exact token matching
2. Sort tokens by length (longest first) before replacement
3. Use regex with word boundaries: `\b${token}\b`

**Fix Example:**
```apex
// Sort tokens by length (longest first) to avoid partial matches
List<String> sortedTokens = new List<String>(tokens);
sortedTokens.sort(new TokenLengthComparator());

for (String token : sortedTokens) {
    if (labelToKey.containsKey(token)) {
        // Use word boundary to avoid partial matches
        resolved = resolved.replaceAll('\\b' + Pattern.quote(token) + '\\b', labelToKey.get(token));
    }
}
```

---

### 5. Missing Authorization Checks ⚠️ MEDIUM

**Location:** `MergedReportController.cls` - `fetchAndParseReport()` (lines 261-407)

**Issue:** While the class uses `with sharing` and relies on Salesforce Reports API for authorization, there's no explicit verification that the user has access to each report before processing.

**Risk:**
- If Reports API has a bug or misconfiguration, unauthorized access could occur
- No explicit check that report IDs are valid Salesforce report IDs

**Recommendation:**
1. Add explicit report access validation before processing
2. Verify report IDs are valid Salesforce IDs (18 characters, correct prefix)
3. Consider adding a SOQL query to verify report existence and access

**Fix Example:**
```apex
private static Boolean hasReportAccess(Id reportId) {
    try {
        // Query to verify report exists and user has access
        List<Report> reports = [SELECT Id FROM Report WHERE Id = :reportId WITH SECURITY_ENFORCED LIMIT 1];
        return !reports.isEmpty();
    } catch (Exception e) {
        return false;
    }
}
```

---

## Low Severity Issues

### 6. XSS Prevention (Already Handled) ✅ LOW

**Status:** LWC automatically escapes template variables, so XSS is mitigated. However, verify all user inputs are properly escaped.

**Recommendation:**
- Continue using LWC template syntax `{variable}` which auto-escapes
- Avoid using `lwc:dom-manipulation` with user input
- Review HTML template for any unsafe HTML rendering

---

### 7. Input Size Limits ⚠️ LOW

**Location:** Various input properties

**Issue:** No explicit limits on:
- Report ID length
- Dimension constant values
- Column alias labels
- Calculated field labels/formulas

**Recommendation:**
1. Add reasonable size limits (e.g., 255 chars for labels, 1000 chars for formulas)
2. Validate in both LWC and Apex
3. Return clear error messages when limits are exceeded

---

### 8. Rate Limiting / DoS Protection ⚠️ LOW

**Location:** `MergedReportController.cls` - `getMergedReportData()`

**Issue:** No protection against:
- Rapid successive calls
- Large number of reports in a single request
- Maliciously crafted requests

**Recommendation:**
1. The 5-report limit helps, but consider adding:
   - Request rate limiting per user
   - Timeout on report processing
   - Maximum processing time limits
2. Monitor for unusual patterns

**Note:** Salesforce's built-in API limits (500 reports per hour) provide some protection.

---

## Positive Security Features ✅

1. **`with sharing` keyword** - Enforces sharing rules
2. **Salesforce Reports API** - Leverages platform security
3. **Input validation** - Report IDs are validated
4. **LWC auto-escaping** - Prevents XSS
5. **Exception handling** - Prevents information leakage in some cases
6. **Access control** - Uses Salesforce's built-in report access controls

---

## Recommendations Summary

### Immediate Actions (High Priority)
1. ✅ Fix formula injection vulnerability
2. ✅ Add proper JSON validation and size limits
3. ✅ Remove stack traces from error messages
4. ✅ Improve formula token resolution

### Short-term Actions (Medium Priority)
5. ✅ Add explicit report access validation
6. ✅ Add input size limits
7. ✅ Improve error handling and logging

### Long-term Actions (Low Priority)
8. ✅ Consider rate limiting
9. ✅ Add security monitoring
10. ✅ Regular security audits

---

## Testing Recommendations

1. **Penetration Testing:**
   - Test formula injection with malicious inputs
   - Test JSON parsing with malformed/large payloads
   - Test with unauthorized report access attempts

2. **Security Unit Tests:**
   - Test formula validation with special characters
   - Test JSON parsing with edge cases
   - Test error handling doesn't leak information

3. **Code Review:**
   - Review all user input handling
   - Review all JSON parsing
   - Review all error messages

---

## Compliance Notes

- **OWASP Top 10:** Addresses A03:2021 (Injection), A01:2021 (Broken Access Control)
- **Salesforce Security Best Practices:** Follows most practices, but needs improvement in input validation

---

**Review Status:** ⚠️ **REQUIRES FIXES BEFORE PRODUCTION**

**Next Steps:**
1. Address all HIGH severity issues
2. Address MEDIUM severity issues
3. Re-review after fixes
4. Conduct penetration testing
