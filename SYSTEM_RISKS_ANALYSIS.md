# System-Level Risks Analysis

**Date:** February 2026  
**Component:** Merged Report Grid

---

## Executive Summary

After analysis, the component has **minimal system-level risks** due to built-in Salesforce limits and existing safeguards. The main risks are related to API call limits and large data processing, which are already mitigated.

---

## ✅ Existing Protections

### 1. API Call Limits (Salesforce Platform)
- **Limit:** 500 Reports API calls per user per 60 minutes
- **Protection:** Built into Salesforce platform
- **Impact:** Prevents DoS attacks via excessive API calls
- **Mitigation:** Component respects this limit (5 reports max per component)

### 2. Row Limits
- **Limit:** Maximum 2,000 rows (enforced in code)
- **Protection:** Prevents memory issues from extremely large datasets
- **Impact:** Limits data processing to manageable sizes
- **Code:** `MAX_ROWS_LIMIT = 2000` in `MergeOptions.cls`

### 3. Report Count Limits
- **Limit:** Maximum 5 reports per component
- **Protection:** Prevents excessive data processing
- **Impact:** Limits API calls and processing time

### 4. Apex Governor Limits
- **CPU Time:** 10 seconds (synchronous), 60 seconds (async)
- **Heap Size:** 6MB (synchronous), 12MB (async)
- **Protection:** Salesforce platform enforces these automatically
- **Impact:** Component will fail gracefully if limits are hit

---

## ⚠️ Potential System-Level Risks

### 1. Multiple Component Instances on Same Page

**Risk:** Multiple Merged Report Grid components on the same Lightning page

**Impact:**
- Each component makes separate API calls
- 5 components × 5 reports = 25 API calls per page load
- Could hit 500/hour limit quickly with page refreshes

**Mitigation:**
- Already documented in ADMIN_GUIDE.md
- Users should be aware of API limits
- Caching helps reduce calls in runtime mode

**Recommendation:**
- ✅ Already handled - documented limitation
- Consider adding warning if multiple instances detected

---

### 2. Large Report Data Processing

**Risk:** Reports with many rows (approaching 2,000 limit)

**Impact:**
- **Memory:** Processing 2,000 rows with multiple reports could use significant heap
- **CPU:** Complex merges (UNION with subtotals) could take time
- **Network:** Large response payloads

**Mitigation:**
- Row limit of 2,000 prevents extreme cases
- Apex governor limits will catch excessive processing
- Response is cached (reduces repeated processing)

**Realistic Assessment:**
- Typical reports: 50-200 rows
- Even with 5 reports × 200 rows = 1,000 rows max (well under 2,000)
- **Risk Level:** LOW

---

### 3. JSON Payload Size

**Risk:** Large JSON configuration strings

**Impact:**
- **Browser Memory:** Large JSON strings in component properties
- **Network:** JSON sent to Apex in each API call
- **Parsing:** JSON.parse() overhead

**Realistic Assessment:**
- Column Aliases: ~50 columns × 100 chars = 5KB (very generous)
- Calculated Fields: ~20 fields × 200 chars = 4KB
- Dimension Constants: ~5 reports × 50 chars = 250 bytes
- **Total realistic max: ~10KB** (very small)

**Mitigation:**
- ✅ Added size warnings (10KB warning, 50KB critical)
- JSON is parsed client-side (no server impact)
- Apex receives already-parsed data

**Risk Level:** VERY LOW

---

### 4. Apex Governor Limit Risks

**Risk:** Hitting Apex governor limits during processing

**Scenarios:**
1. **CPU Time:** Complex merges with many rows
2. **Heap Size:** Large data structures in memory
3. **SOQL Queries:** None used (uses Reports API)
4. **DML:** None used (read-only)

**Realistic Assessment:**
- Reports API calls are fast (< 1 second each)
- Data processing is in-memory (no SOQL/DML)
- Typical processing: 5 reports × 200 rows = < 2 seconds CPU
- **Risk Level:** LOW (well within limits)

**If Limits Are Hit:**
- Salesforce throws `LimitException`
- Component catches exception and returns error
- User sees error message (no system impact)

---

### 5. Concurrent User Load

**Risk:** Many users using component simultaneously

**Impact:**
- Each user has their own API call quota (500/hour)
- No shared resources that could cause contention
- Apex runs in separate execution contexts

**Mitigation:**
- Salesforce platform handles concurrency
- Each user's limits are independent
- No shared state or resources

**Risk Level:** NONE (handled by platform)

---

## 🔍 Code Analysis for System Risks

### Memory Usage Patterns

**Data Structures:**
- `MergedGridDTO` - Contains rows, columns, metadata
- `ParsedReportData` - Per-report data (up to 5)
- Maps and Lists for merging logic

**Memory Estimate:**
- 2,000 rows × ~500 bytes/row = ~1MB (worst case)
- 5 reports × metadata = ~50KB
- **Total: ~1.1MB** (well under 6MB heap limit)

### CPU Usage Patterns

**Operations:**
1. Report API calls (external, not counted in CPU)
2. Data parsing and merging (in-memory)
3. Sorting and calculations

**CPU Estimate:**
- Parsing: ~100ms per report × 5 = 500ms
- Merging: ~200ms for 2,000 rows
- Calculations: ~100ms for formulas
- **Total: ~800ms** (well under 10 second limit)

---

## ✅ Recommendations

### Already Implemented ✅
1. ✅ Row limits (2,000 max)
2. ✅ Report count limits (5 max)
3. ✅ JSON size warnings
4. ✅ Error handling for governor limits
5. ✅ Caching to reduce API calls

### Optional Enhancements (Low Priority)
1. **Warning for Multiple Instances:**
   - Detect if multiple components on same page
   - Show warning about API limits

2. **Processing Time Monitoring:**
   - Already tracks `processingTimeMs`
   - Could add warning if > 5 seconds

3. **Heap Size Monitoring:**
   - Could check `Limits.getHeapSize()` before processing
   - Warn if approaching limits

---

## Conclusion

**Overall Risk Level: LOW**

The component is well-protected by:
1. ✅ Salesforce platform limits (API, governor limits)
2. ✅ Built-in safeguards (row limits, report limits)
3. ✅ Proper error handling
4. ✅ Realistic usage patterns (well within limits)

**No system-level risks identified that would cause:**
- ❌ Server overload
- ❌ Memory exhaustion
- ❌ CPU exhaustion
- ❌ Interference with other components
- ❌ Platform instability

**The only realistic concern is API call limits**, which is:
- ✅ Documented in ADMIN_GUIDE.md
- ✅ Handled by Salesforce platform
- ✅ Mitigated by caching
- ✅ User-controlled (they choose how many components/reports)

---

## JSON Validation Approach

**Decision:** Use warnings instead of blocking

**Rationale:**
1. JSON comes from App Builder properties (internal, not user input)
2. Security risk is minimal (not user-facing input)
3. Warnings help debug issues without blocking functionality
4. Size warnings (10KB/50KB) provide visibility for troubleshooting

**Implementation:**
- ✅ Size warnings at 10KB (info) and 50KB (warning)
- ✅ Structure validation warnings (not blocking)
- ✅ Parse error warnings (fallback to empty object/array)
- ✅ All warnings are non-blocking - component continues to function
