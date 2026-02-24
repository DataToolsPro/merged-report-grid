/**
 * @description Controller for the Merged Report Grid LWC component.
 *              Handles fetching, validating, and merging data from multiple Salesforce reports.
 *              Supports JOIN (horizontal merge) and UNION (vertical stack) strategies.
 */
public with sharing class MergedReportController {
    
    // Report type constants
    private static final String REPORT_TYPE_SUMMARY = 'SUMMARY';
    private static final String REPORT_TYPE_TABULAR = 'TABULAR';
    private static final String REPORT_TYPE_MATRIX = 'MATRIX';
    private static final String REPORT_TYPE_JOINED = 'JOINED';
    
    // Blank key token
    private static final String BLANK_KEY_TOKEN = '(Blank)';
    private static final String KEY_SEPARATOR = '||';
    
    // Debug flag: Set to true to include stack traces in error messages (for debugging only)
    // SECURITY: Keep this false in production to prevent information disclosure
    private static final Boolean INCLUDE_STACK_TRACES_IN_ERRORS = false;
    
    /**
     * @description Main entry point - fetches and merges data from multiple reports
     * @param reportIds List of report IDs to merge (2-5 reports)
     * @param optionsJson JSON string of MergeOptions
     * @return MergedGridDTO containing the merged grid data
     */
    @AuraEnabled(cacheable=true)
    public static MergedGridDTO getMergedReportData(List<Id> reportIds, String optionsJson) {
        Long startTime = System.currentTimeMillis();
        MergedGridDTO result = new MergedGridDTO();
        
        try {
            // Parse and validate options
            MergeOptions options = parseOptions(optionsJson);
            result.warnings.addAll(options.validate());
            
            // Validate report IDs
            List<String> validationErrors = validateReportIds(reportIds);
            if (!validationErrors.isEmpty()) {
                for (String err : validationErrors) {
                    result.errors.add(new MergedGridDTO.ReportError(null, err, true));
                }
                return result;
            }
            
            // Fetch and parse each report
            List<MergedGridDTO.ParsedReportData> parsedReports = new List<MergedGridDTO.ParsedReportData>();
            
            for (Integer i = 0; i < reportIds.size(); i++) {
                Id reportId = reportIds[i];
                MergedGridDTO.ParsedReportData parsed = fetchAndParseReport(reportId, i, options);
                
                // Store report name for UI display (even if report has errors)
                if (String.isNotBlank(parsed.reportName)) {
                    result.reportNames.put(String.valueOf(reportId), parsed.reportName);
                }
                
                if (!parsed.isValid) {
                    MergedGridDTO.ReportError error = new MergedGridDTO.ReportError(
                        reportId,
                        parsed.errorMessage,
                        i < 2 // First two reports are required
                    );
                    error.reportName = parsed.reportName;
                    result.errors.add(error);
                    
                    if (i < 2) {
                        result.processingTimeMs = System.currentTimeMillis() - startTime;
                        return result;
                    }
                } else {
                    parsedReports.add(parsed);
                }
            }
            
            // Must have at least 2 valid reports
            if (parsedReports.size() < 2) {
                result.errors.add(new MergedGridDTO.ReportError(
                    null,
                    'At least 2 valid reports are required for merging',
                    true
                ));
                result.processingTimeMs = System.currentTimeMillis() - startTime;
                return result;
            }
            
            // Validate dimensions based on strategy
            String dimensionError = validateDimensions(parsedReports, options);
            if (dimensionError != null) {
                result.errors.add(new MergedGridDTO.ReportError(null, dimensionError, true));
                result.processingTimeMs = System.currentTimeMillis() - startTime;
                return result;
            }
            
            // Route to appropriate merge method
            if (options.isUnionMode()) {
                mergeUnion(parsedReports, options, result);
            } else {
                mergeJoin(parsedReports, options, result);
            }
            
            // Add tier lookups (before calculated fields so formulas can reference them)
            if (options.tierLookups != null && !options.tierLookups.isEmpty()) {
                addTierLookups(options, result);
            }
            
            // Add calculated fields (works in both JOIN and UNION modes)
            if (options.calculatedFields != null && !options.calculatedFields.isEmpty()) {
                addCalculatedFields(options, result);
            }
            
            // Calculate key overlap percentage
            result.keyOverlapPercentage = calculateKeyOverlap(parsedReports);
            if (result.keyOverlapPercentage < 70) {
                result.warnings.add(
                    'Key overlap is only ' + result.keyOverlapPercentage.setScale(0) + 
                    '%. Reports may not be grouping by the same field.'
                );
            }
            
        } catch (Exception e) {
            // Always log full error details server-side for debugging
            System.debug(LoggingLevel.ERROR, 'Error processing reports: ' + e.getMessage() + '\n' + e.getStackTraceString());
            
            // Return user-friendly error message (with optional stack trace for debugging)
            String errorMessage = formatErrorMessage(e);
            result.errors.add(new MergedGridDTO.ReportError(
                null,
                errorMessage,
                true
            ));
        }
        
        result.processingTimeMs = System.currentTimeMillis() - startTime;
        return result;
    }
    
    /**
     * @description Parses the options JSON string.
     * Manually extracts columnAliases because Apex JSON.deserialize does not reliably
     * populate Map<String, Object> in class properties.
     */
    private static MergeOptions parseOptions(String optionsJson) {
        if (String.isBlank(optionsJson)) {
            return new MergeOptions();
        }
        try {
            MergeOptions options = (MergeOptions) JSON.deserialize(optionsJson, MergeOptions.class);
            // Manually extract columnAliases - JSON.deserialize often fails to populate Map<String, Object>
            extractColumnAliasesFromJson(optionsJson, options);
            return options;
        } catch (Exception e) {
            return new MergeOptions();
        }
    }
    
    /**
     * @description Extracts columnAliases from raw JSON and sets on options.
     * Required because Apex JSON.deserialize does not properly populate Map<String, Object> properties.
     */
    private static void extractColumnAliasesFromJson(String optionsJson, MergeOptions options) {
        try {
            Object root = JSON.deserializeUntyped(optionsJson);
            if (!(root instanceof Map<String, Object>)) return;
            Map<String, Object> rootMap = (Map<String, Object>) root;
            Object colObj = rootMap.get('columnAliases');
            if (colObj == null) return;
            if (colObj instanceof Map<String, Object>) {
                options.columnAliases = (Map<String, Object>) colObj;
            }
        } catch (Exception e) {
            // Ignore - use whatever columnAliases the class deserializer produced (possibly null/empty)
        }
    }
    
    /**
     * @description Validates the list of report IDs
     */
    private static List<String> validateReportIds(List<Id> reportIds) {
        List<String> errors = new List<String>();
        
        if (reportIds == null || reportIds.isEmpty()) {
            errors.add('No report IDs provided');
            return errors;
        }
        
        if (reportIds.size() < 2) {
            errors.add('At least 2 report IDs are required');
            return errors;
        }
        
        if (reportIds.size() > 5) {
            errors.add('Maximum of 5 reports allowed');
            return errors;
        }
        
        Set<Id> seen = new Set<Id>();
        for (Integer i = 0; i < reportIds.size(); i++) {
            Id reportId = reportIds[i];
            if (reportId == null) {
                errors.add('Report ID at position ' + (i + 1) + ' is null');
            } else if (seen.contains(reportId)) {
                errors.add('Duplicate report ID: ' + reportId);
            } else {
                seen.add(reportId);
            }
        }
        
        return errors;
    }
    
    /**
     * @description Validates dimensions across reports based on merge strategy
     */
    private static String validateDimensions(List<MergedGridDTO.ParsedReportData> parsedReports, MergeOptions options) {
        Integer maxDims = 0;
        Integer minDims = 999;
        
        for (MergedGridDTO.ParsedReportData parsed : parsedReports) {
            if (parsed.dimensionCount > 2) {
                return 'Report "' + parsed.reportName + '" has ' + parsed.dimensionCount + 
                       ' dimensions. Maximum 2 dimensions supported.';
            }
            maxDims = Math.max(maxDims, parsed.dimensionCount);
            minDims = Math.min(minDims, parsed.dimensionCount);
        }
        
        // Check for dimension constants when there's a mismatch (works for both JOIN and UNION modes)
        if (maxDims == 2 && minDims == 1) {
            for (MergedGridDTO.ParsedReportData parsed : parsedReports) {
                if (parsed.dimensionCount == 1) {
                    String constant = options.getDimensionConstant(parsed.reportIndex + 1);
                    if (String.isBlank(constant)) {
                        String modeHint = options.isUnionMode() ? '' : ' Or change Merge Mode to UNION.';
                        return 'Report ' + (parsed.reportIndex + 1) + ' ("' + parsed.reportName + 
                               '") has 1 dimension but other reports have 2. Set a dimension constant using: {"' + 
                               (parsed.reportIndex + 1) + '": "Total"}.' + modeHint;
                    }
                }
            }
        }
        
        if (!options.isUnionMode()) {
            // JOIN mode: Dimensions must match (unless dimension constants handle the gap)
            if (maxDims != minDims) {
                // If we get here, dimension constants weren't configured - already handled above
                // This shouldn't be reached, but keep as safety check
                List<String> oneDimReports = new List<String>();
                List<String> twoDimReports = new List<String>();
                
                for (MergedGridDTO.ParsedReportData parsed : parsedReports) {
                    String reportRef = 'Report ' + (parsed.reportIndex + 1) + ' ("' + parsed.reportName + '")';
                    if (parsed.dimensionCount == 1) {
                        oneDimReports.add(reportRef);
                    } else {
                        twoDimReports.add(reportRef);
                    }
                }
                
                String errorMsg = 'JOIN mode requires all reports to have the same number of dimensions.\n\n';
                errorMsg += '1 dimension: ' + String.join(oneDimReports, ', ') + '\n';
                errorMsg += '2 dimensions: ' + String.join(twoDimReports, ', ') + '\n\n';
                errorMsg += 'Options:\n';
                errorMsg += '• Set Dimension Constants for reports with fewer dimensions\n';
                errorMsg += '• Change Merge Mode to UNION (allows different dimensions)\n';
                errorMsg += '• Modify reports so they all have the same number of group-by fields';
                
                return errorMsg;
            }
            
            // Check dimension field names match (skip for reports using constants)
            String firstDim1 = parsedReports[0].groupingField;
            String firstDim2 = parsedReports[0].secondGroupingField;
            
            for (Integer i = 1; i < parsedReports.size(); i++) {
                MergedGridDTO.ParsedReportData parsed = parsedReports[i];
                if (parsed.groupingField != firstDim1) {
                    return 'JOIN mode requires identical dimensions. Report 1 groups by "' + 
                           firstDim1 + '" but Report ' + (i + 1) + ' groups by "' + parsed.groupingField + '".';
                }
                // Only check second dimension match if both reports natively have 2 dimensions
                if (parsed.dimensionCount == 2 && parsedReports[0].dimensionCount == 2 && 
                    parsed.secondGroupingField != firstDim2) {
                    return 'JOIN mode requires identical dimensions. Report 1 has second grouping "' + 
                           firstDim2 + '" but Report ' + (i + 1) + ' has "' + parsed.secondGroupingField + '".';
                }
            }
        }
        
        return null;
    }
    
    /**
     * @description Fetches and parses a single report - supports up to 2 dimensions
     */
    private static MergedGridDTO.ParsedReportData fetchAndParseReport(Id reportId, Integer index, MergeOptions options) {
        MergedGridDTO.ParsedReportData parsed = new MergedGridDTO.ParsedReportData();
        parsed.reportId = reportId;
        parsed.reportIndex = index;
        
        try {
            // Get report metadata
            Reports.ReportDescribeResult describe = Reports.ReportManager.describeReport(reportId);
            Reports.ReportMetadata metadata = describe.getReportMetadata();
            
            parsed.reportName = metadata.getName();
            
            // Validate report type
            String reportFormat = metadata.getReportFormat().name();
            
            if (reportFormat == REPORT_TYPE_JOINED) {
                parsed.isValid = false;
                parsed.errorMessage = 'Joined reports are not supported. Report: ' + parsed.reportName;
                return parsed;
            }
            
            if (reportFormat == REPORT_TYPE_MATRIX) {
                parsed.isValid = false;
                parsed.errorMessage = 'Matrix reports are not supported. Report: ' + parsed.reportName;
                return parsed;
            }
            
            if (reportFormat == REPORT_TYPE_TABULAR) {
                parsed.isValid = false;
                parsed.errorMessage = 'Tabular reports are not supported. Report: ' + parsed.reportName;
                return parsed;
            }
            
            // Get groupings
            List<Reports.GroupingInfo> groupingsDown = metadata.getGroupingsDown();
            if (groupingsDown == null || groupingsDown.isEmpty()) {
                parsed.isValid = false;
                parsed.errorMessage = 'Report must have at least one grouping. Report: ' + parsed.reportName;
                return parsed;
            }
            
            // Check for groupings across (would make it matrix-like)
            List<Reports.GroupingInfo> groupingsAcross = metadata.getGroupingsAcross();
            if (groupingsAcross != null && !groupingsAcross.isEmpty()) {
                parsed.isValid = false;
                parsed.errorMessage = 'Report has column groupings which is not supported. Report: ' + parsed.reportName;
                return parsed;
            }
            
            // Set dimension info
            parsed.dimensionCount = groupingsDown.size();
            parsed.groupingField = groupingsDown[0].getName();
            parsed.groupingLabel = parsed.groupingField;
            
            if (parsed.dimensionCount >= 2) {
                parsed.secondGroupingField = groupingsDown[1].getName();
                parsed.secondGroupingLabel = parsed.secondGroupingField;
            }
            
            if (parsed.dimensionCount > 2) {
                parsed.isValid = false;
                parsed.errorMessage = 'Report has ' + parsed.dimensionCount + ' dimensions. Maximum 2 supported. Report: ' + parsed.reportName;
                return parsed;
            }
            
            // Apply data visibility scope override if configured
            if (options.shouldOverrideScope()) {
                String scope = options.getReportScope();
                if (scope != null) {
                    metadata.setScope(scope);
                }
            }
            
            // Run the report (with modified metadata if scope was overridden)
            Reports.ReportResults results;
            if (options.shouldOverrideScope()) {
                results = Reports.ReportManager.runReport(reportId, metadata, true);
            } else {
                results = Reports.ReportManager.runReport(reportId, true);
            }
            
            // Get aggregate column info
            Map<String, Reports.AggregateColumn> aggColumns = results.getReportExtendedMetadata().getAggregateColumnInfo();
            
            if (aggColumns == null || aggColumns.isEmpty()) {
                parsed.isValid = false;
                parsed.errorMessage = 'Report has no aggregates. At least one numeric aggregate is required. Report: ' + parsed.reportName;
                return parsed;
            }
            
            // Get aggregate keys in correct order
            List<String> orderedAggKeys = metadata.getAggregates();
            if (orderedAggKeys == null || orderedAggKeys.isEmpty()) {
                orderedAggKeys = new List<String>(aggColumns.keySet());
            }
            
            // Build list of aggregates
            for (Integer aggIndex = 0; aggIndex < orderedAggKeys.size(); aggIndex++) {
                String aggKey = orderedAggKeys[aggIndex];
                Reports.AggregateColumn agg = aggColumns.get(aggKey);
                if (agg == null) continue;
                
                Reports.ColumnDataType dataType = agg.getDataType();
                
                if (dataType == Reports.ColumnDataType.CURRENCY_DATA ||
                    dataType == Reports.ColumnDataType.INT_DATA ||
                    dataType == Reports.ColumnDataType.DOUBLE_DATA ||
                    dataType == Reports.ColumnDataType.PERCENT_DATA ||
                    aggKey == 'RowCount') {
                    
                    parsed.aggregates.add(new MergedGridDTO.AggregateInfo(
                        aggKey,
                        agg.getLabel(),
                        String.valueOf(dataType),
                        aggIndex
                    ));
                }
            }
            
            if (parsed.aggregates.isEmpty()) {
                parsed.isValid = false;
                parsed.errorMessage = 'No valid numeric aggregates found. Report: ' + parsed.reportName;
                return parsed;
            }
            
            // Extract data based on dimension count
            if (parsed.dimensionCount == 1) {
                extractSingleDimensionData(results, parsed, options);
            } else {
                extractTwoDimensionData(results, parsed, options);
            }
            
        } catch (System.NoAccessException e) {
            parsed.isValid = false;
            parsed.errorMessage = 'You don\'t have access to this report';
        } catch (Exception e) {
            parsed.isValid = false;
            String msg = e.getMessage();
            if (msg != null && msg.contains('insufficient access')) {
                parsed.errorMessage = 'You don\'t have access to run this report: ' + parsed.reportName;
            } else {
                parsed.errorMessage = 'Error processing report: ' + msg;
            }
        }
        
        return parsed;
    }
    
    /**
     * @description Extracts data from a single-dimension report
     */
    private static void extractSingleDimensionData(
        Reports.ReportResults results,
        MergedGridDTO.ParsedReportData parsed,
        MergeOptions options
    ) {
        Map<String, Reports.ReportFact> factMap = results.getFactMap();
        Reports.Dimension downDimension = results.getGroupingsDown();
        List<Reports.GroupingValue> groupings = downDimension.getGroupings();
        
        // Get constant for this report if in UNION mode with missing dimension
        String dimConstant = options.getDimensionConstant(parsed.reportIndex + 1);
        
        for (Reports.GroupingValue grouping : groupings) {
            String primaryKey = normalizeKey(grouping.getValue());
            String primaryLabel = grouping.getLabel();
            String factKey = grouping.getKey() + '!T';
            
            parsed.primaryKeys.add(primaryKey);
            
            // Build composite key (for single dim, use constant or empty)
            String compositeKey = primaryKey;
            String secondaryLabel = dimConstant;
            if (String.isNotBlank(dimConstant)) {
                compositeKey = primaryKey + KEY_SEPARATOR + dimConstant;
                parsed.secondaryKeys.add(dimConstant);
            }
            
            parsed.labelsByKey.put(compositeKey, primaryLabel);
            if (String.isNotBlank(dimConstant)) {
                parsed.secondLabelsByKey.put(compositeKey, dimConstant);
            }
            
            if (!parsed.valuesByKeyByAggregate.containsKey(compositeKey)) {
                parsed.valuesByKeyByAggregate.put(compositeKey, new Map<String, Decimal>());
            }
            
            if (factMap.containsKey(factKey)) {
                Reports.ReportFact fact = factMap.get(factKey);
                List<Reports.SummaryValue> summaryValues = fact.getAggregates();
                
                for (MergedGridDTO.AggregateInfo aggInfo : parsed.aggregates) {
                    Decimal value = null;
                    if (summaryValues != null && aggInfo.index < summaryValues.size()) {
                        Object rawValue = summaryValues[aggInfo.index].getValue();
                        value = convertToDecimal(rawValue);
                    }
                    parsed.valuesByKeyByAggregate.get(compositeKey).put(aggInfo.key, value);
                }
            }
        }
        
        // Grand totals
        if (factMap.containsKey('T!T')) {
            Reports.ReportFact totalFact = factMap.get('T!T');
            List<Reports.SummaryValue> totalValues = totalFact.getAggregates();
            
            for (MergedGridDTO.AggregateInfo aggInfo : parsed.aggregates) {
                Decimal total = null;
                if (totalValues != null && aggInfo.index < totalValues.size()) {
                    Object rawValue = totalValues[aggInfo.index].getValue();
                    total = convertToDecimal(rawValue);
                }
                parsed.grandTotals.put(aggInfo.key, total);
            }
        }
    }
    
    /**
     * @description Extracts data from a two-dimension report
     */
    private static void extractTwoDimensionData(
        Reports.ReportResults results,
        MergedGridDTO.ParsedReportData parsed,
        MergeOptions options
    ) {
        Map<String, Reports.ReportFact> factMap = results.getFactMap();
        Reports.Dimension downDimension = results.getGroupingsDown();
        List<Reports.GroupingValue> topGroupings = downDimension.getGroupings();
        
        for (Reports.GroupingValue topGrouping : topGroupings) {
            String primaryKey = normalizeKey(topGrouping.getValue());
            String primaryLabel = topGrouping.getLabel();
            
            parsed.primaryKeys.add(primaryKey);
            
            // Get child groupings (second dimension)
            List<Reports.GroupingValue> childGroupings = topGrouping.getGroupings();
            if (childGroupings != null) {
                for (Reports.GroupingValue childGrouping : childGroupings) {
                    String secondaryKey = normalizeKey(childGrouping.getValue());
                    String secondaryLabel = childGrouping.getLabel();
                    String factKey = childGrouping.getKey() + '!T';
                    
                    parsed.secondaryKeys.add(secondaryKey);
                    
                    String compositeKey = primaryKey + KEY_SEPARATOR + secondaryKey;
                    
                    parsed.labelsByKey.put(compositeKey, primaryLabel);
                    parsed.secondLabelsByKey.put(compositeKey, secondaryLabel);
                    
                    if (!parsed.valuesByKeyByAggregate.containsKey(compositeKey)) {
                        parsed.valuesByKeyByAggregate.put(compositeKey, new Map<String, Decimal>());
                    }
                    
                    if (factMap.containsKey(factKey)) {
                        Reports.ReportFact fact = factMap.get(factKey);
                        List<Reports.SummaryValue> summaryValues = fact.getAggregates();
                        
                        for (MergedGridDTO.AggregateInfo aggInfo : parsed.aggregates) {
                            Decimal value = null;
                            if (summaryValues != null && aggInfo.index < summaryValues.size()) {
                                Object rawValue = summaryValues[aggInfo.index].getValue();
                                value = convertToDecimal(rawValue);
                            }
                            parsed.valuesByKeyByAggregate.get(compositeKey).put(aggInfo.key, value);
                        }
                    }
                }
            }
        }
        
        // Grand totals
        if (factMap.containsKey('T!T')) {
            Reports.ReportFact totalFact = factMap.get('T!T');
            List<Reports.SummaryValue> totalValues = totalFact.getAggregates();
            
            for (MergedGridDTO.AggregateInfo aggInfo : parsed.aggregates) {
                Decimal total = null;
                if (totalValues != null && aggInfo.index < totalValues.size()) {
                    Object rawValue = totalValues[aggInfo.index].getValue();
                    total = convertToDecimal(rawValue);
                }
                parsed.grandTotals.put(aggInfo.key, total);
            }
        }
    }
    
    /**
     * @description Merges reports using UNION strategy (vertical stack)
     */
    private static void mergeUnion(
        List<MergedGridDTO.ParsedReportData> parsedReports,
        MergeOptions options,
        MergedGridDTO result
    ) {
        // Determine if we have 2 dimensions (native or via constants)
        Integer maxDims = 1;
        for (MergedGridDTO.ParsedReportData parsed : parsedReports) {
            Integer effectiveDims = parsed.dimensionCount;
            // Check if this report has a dimension constant (making it effectively 2-dim)
            if (parsed.dimensionCount == 1 && String.isNotBlank(options.getDimensionConstant(parsed.reportIndex + 1))) {
                effectiveDims = 2;
            }
            maxDims = Math.max(maxDims, effectiveDims);
        }
        result.hasSecondDimension = (maxDims == 2);
        
        // Build columns - merge by name
        result.columns = buildUnionColumns(parsedReports, options, result);
        
        // Collect all primary and secondary keys
        Set<String> allPrimaryKeys = new Set<String>();
        Set<String> allSecondaryKeys = new Set<String>();
        
        for (MergedGridDTO.ParsedReportData parsed : parsedReports) {
            allPrimaryKeys.addAll(parsed.primaryKeys);
            allSecondaryKeys.addAll(parsed.secondaryKeys);
        }
        
        // Build rows - each report contributes its own rows
        List<MergedGridDTO.GridRow> allRows = new List<MergedGridDTO.GridRow>();
        Map<String, List<MergedGridDTO.GridRow>> rowsByPrimaryKey = new Map<String, List<MergedGridDTO.GridRow>>();
        
        for (MergedGridDTO.ParsedReportData parsed : parsedReports) {
            for (String compositeKey : parsed.valuesByKeyByAggregate.keySet()) {
                String primaryKey;
                String secondaryKey = '';
                
                if (compositeKey.contains(KEY_SEPARATOR)) {
                    List<String> parts = compositeKey.split('\\|\\|');
                    primaryKey = parts[0];
                    secondaryKey = parts.size() > 1 ? parts[1] : '';
                } else {
                    primaryKey = compositeKey;
                }
                
                MergedGridDTO.GridRow row = new MergedGridDTO.GridRow();
                row.keyValue = primaryKey;
                row.keyLabel = parsed.labelsByKey.get(compositeKey);
                row.secondKeyValue = secondaryKey;
                row.secondKeyLabel = parsed.secondLabelsByKey.get(compositeKey);
                row.sourceReportIndex = parsed.reportIndex;
                
                // Add values for merged columns
                Map<String, Decimal> aggValues = parsed.valuesByKeyByAggregate.get(compositeKey);
                for (MergedGridDTO.ColumnDefinition col : result.columns) {
                    if (col.isKeyColumn || col.isSecondKeyColumn) continue;
                    
                    // Check if this column comes from this report
                    if (col.isMergedColumn) {
                        // Merged column - find matching aggregate by label
                        for (MergedGridDTO.AggregateInfo aggInfo : parsed.aggregates) {
                            if (aggInfo.label == col.aggregateLabel) {
                                Decimal value = aggValues.get(aggInfo.key);
                                if (value != null) {
                                    row.values.put(col.key, value);
                                    row.formattedValues.put(col.key, formatValue(value, col.dataType, col.customFormat, col.customDecimals, col.customCurrencyCode));
                                }
                                break;
                            }
                        }
                    } else if (col.reportIndex == parsed.reportIndex) {
                        // Non-merged column from this report
                        Decimal value = aggValues.get(col.aggregateKey);
                        if (value != null) {
                            row.values.put(col.key, value);
                            row.formattedValues.put(col.key, formatValue(value, col.dataType, col.customFormat, col.customDecimals, col.customCurrencyCode));
                        }
                    }
                }
                
                // Fill missing values
                for (MergedGridDTO.ColumnDefinition col : result.columns) {
                    if (col.isKeyColumn || col.isSecondKeyColumn) continue;
                    if (!row.formattedValues.containsKey(col.key)) {
                        if (options.missingValueAsZero) {
                            row.values.put(col.key, 0);
                            row.formattedValues.put(col.key, '0');
                        } else {
                            row.formattedValues.put(col.key, '—');
                        }
                    }
                }
                
                // Group by primary key
                if (!rowsByPrimaryKey.containsKey(primaryKey)) {
                    rowsByPrimaryKey.put(primaryKey, new List<MergedGridDTO.GridRow>());
                }
                rowsByPrimaryKey.get(primaryKey).add(row);
            }
        }
        
        // Fill missing categories if enabled
        if (options.fillMissingCategories && result.hasSecondDimension) {
            fillMissingCategories(rowsByPrimaryKey, allPrimaryKeys, allSecondaryKeys, parsedReports, result, options);
        }
        
        // Sort and flatten rows
        List<String> sortedPrimaryKeys = new List<String>(rowsByPrimaryKey.keySet());
        
        // Sort groups by aggregate if specified
        if (String.isNotBlank(options.sortGroupsBy)) {
            sortedPrimaryKeys = sortGroupsByAggregate(rowsByPrimaryKey, options);
        } else {
            sortedPrimaryKeys.sort();
            if (options.sortDirection == MergeOptions.SORT_DIRECTION_DESC) {
                List<String> reversed = new List<String>();
                for (Integer i = sortedPrimaryKeys.size() - 1; i >= 0; i--) {
                    reversed.add(sortedPrimaryKeys[i]);
                }
                sortedPrimaryKeys = reversed;
            }
        }
        
        // Build final row list with subtotals
        Map<String, Decimal> grandTotals = new Map<String, Decimal>();
        
        for (String primaryKey : sortedPrimaryKeys) {
            List<MergedGridDTO.GridRow> groupRows = rowsByPrimaryKey.get(primaryKey);
            
            // Sort rows within group by secondary key
            groupRows.sort(new SecondKeyComparator(options.sortDirection == MergeOptions.SORT_DIRECTION_ASC));
            
            // Add rows
            allRows.addAll(groupRows);
            
            // Calculate and add subtotal if enabled
            if (options.showSubtotals && result.hasSecondDimension) {
                MergedGridDTO.GridRow subtotalRow = new MergedGridDTO.GridRow();
                subtotalRow.keyValue = primaryKey;
                subtotalRow.keyLabel = groupRows[0].keyLabel;
                subtotalRow.secondKeyValue = options.subtotalLabel;
                subtotalRow.secondKeyLabel = options.subtotalLabel;
                subtotalRow.isSubtotalRow = true;
                
                // Sum values for all numeric columns (not just merged columns)
                for (MergedGridDTO.ColumnDefinition col : result.columns) {
                    if (col.isKeyColumn || col.isSecondKeyColumn) continue;
                    
                    Decimal sum = 0;
                    for (MergedGridDTO.GridRow row : groupRows) {
                        Decimal val = row.values.get(col.key);
                        if (val != null) sum += val;
                    }
                    subtotalRow.values.put(col.key, sum);
                    subtotalRow.formattedValues.put(col.key, formatValue(sum, col.dataType, col.customFormat, col.customDecimals, col.customCurrencyCode));
                    
                    // Accumulate grand total
                    if (!grandTotals.containsKey(col.key)) {
                        grandTotals.put(col.key, 0);
                    }
                    grandTotals.put(col.key, grandTotals.get(col.key) + sum);
                }
                
                allRows.add(subtotalRow);
            } else {
                // Accumulate grand totals without subtotals
                for (MergedGridDTO.GridRow row : groupRows) {
                    for (MergedGridDTO.ColumnDefinition col : result.columns) {
                        if (col.isKeyColumn || col.isSecondKeyColumn) continue;
                        Decimal val = row.values.get(col.key);
                        if (val != null) {
                            if (!grandTotals.containsKey(col.key)) {
                                grandTotals.put(col.key, 0);
                            }
                            grandTotals.put(col.key, grandTotals.get(col.key) + val);
                        }
                    }
                }
            }
        }
        
        result.totalRowCount = allRows.size();
        
        // Apply row limit
        if (allRows.size() > options.maxRows) {
            result.isTruncated = true;
            List<MergedGridDTO.GridRow> limitedRows = new List<MergedGridDTO.GridRow>();
            for (Integer i = 0; i < options.maxRows && i < allRows.size(); i++) {
                limitedRows.add(allRows[i]);
            }
            allRows = limitedRows;
        }
        
        result.rows = allRows;
        
        // Grand total row
        if (options.showGrandTotalRow) {
            MergedGridDTO.GridRow totalsRow = new MergedGridDTO.GridRow();
            totalsRow.keyValue = 'TOTAL';
            totalsRow.keyLabel = 'Total';
            totalsRow.isTotalRow = true;
            
            for (String colKey : grandTotals.keySet()) {
                Decimal total = grandTotals.get(colKey);
                totalsRow.values.put(colKey, total);
                
                // Find column definition for data type and custom format
                String dataType = 'DOUBLE_DATA';
                String customFormat = null;
                Integer customDecimals = null;
                String customCurrencyCode = null;
                for (MergedGridDTO.ColumnDefinition col : result.columns) {
                    if (col.key == colKey) {
                        dataType = col.dataType;
                        customFormat = col.customFormat;
                        customDecimals = col.customDecimals;
                        customCurrencyCode = col.customCurrencyCode;
                        break;
                    }
                }
                totalsRow.formattedValues.put(colKey, formatValue(total, dataType, customFormat, customDecimals, customCurrencyCode));
            }
            
            result.totalsRow = totalsRow;
        }
    }
    
    /**
     * @description Builds columns for UNION mode - merging by name match
     */
    private static List<MergedGridDTO.ColumnDefinition> buildUnionColumns(
        List<MergedGridDTO.ParsedReportData> parsedReports,
        MergeOptions options,
        MergedGridDTO result
    ) {
        List<MergedGridDTO.ColumnDefinition> columns = new List<MergedGridDTO.ColumnDefinition>();
        
        // Key column (Dim 1) - apply alias if configured
        MergedGridDTO.ColumnDefinition keyCol = new MergedGridDTO.ColumnDefinition();
        keyCol.key = 'keyLabel';
        String originalKeyLabel = parsedReports[0].groupingLabel;
        keyCol.label = options.getColumnAlias(originalKeyLabel);
        keyCol.dataType = 'STRING';
        keyCol.isKeyColumn = true;
        columns.add(keyCol);
        
        // Second key column (Dim 2) if applicable
        if (result.hasSecondDimension) {
            MergedGridDTO.ColumnDefinition secondKeyCol = new MergedGridDTO.ColumnDefinition();
            secondKeyCol.key = 'secondKeyLabel';
            
            // Find label from first report with 2 dimensions
            String originalSecondLabel = null;
            for (MergedGridDTO.ParsedReportData parsed : parsedReports) {
                if (parsed.dimensionCount == 2) {
                    originalSecondLabel = parsed.secondGroupingLabel;
                    break;
                }
            }
            if (originalSecondLabel == null) {
                originalSecondLabel = 'Category';
            }
            
            // Apply alias to second dimension column
            secondKeyCol.label = options.getColumnAlias(originalSecondLabel);
            result.secondDimensionLabel = secondKeyCol.label;
            
            secondKeyCol.dataType = 'STRING';
            secondKeyCol.isSecondKeyColumn = true;
            columns.add(secondKeyCol);
        }
        
        // Track aggregate labels to identify matches
        Map<String, List<MergedGridDTO.AggregateInfo>> aggsByLabel = new Map<String, List<MergedGridDTO.AggregateInfo>>();
        Map<String, List<Integer>> reportIndicesByLabel = new Map<String, List<Integer>>();
        
        for (MergedGridDTO.ParsedReportData parsed : parsedReports) {
            for (MergedGridDTO.AggregateInfo aggInfo : parsed.aggregates) {
                String label = aggInfo.label;
                if (!aggsByLabel.containsKey(label)) {
                    aggsByLabel.put(label, new List<MergedGridDTO.AggregateInfo>());
                    reportIndicesByLabel.put(label, new List<Integer>());
                }
                aggsByLabel.get(label).add(aggInfo);
                reportIndicesByLabel.get(label).add(parsed.reportIndex);
            }
        }
        
        // Create columns - merged if label appears in multiple reports
        Set<String> processedLabels = new Set<String>();
        
        for (MergedGridDTO.ParsedReportData parsed : parsedReports) {
            for (MergedGridDTO.AggregateInfo aggInfo : parsed.aggregates) {
                String label = aggInfo.label;
                
                if (processedLabels.contains(label)) continue;
                processedLabels.add(label);
                
                MergedGridDTO.ColumnDefinition col = new MergedGridDTO.ColumnDefinition();
                
                List<Integer> sourceIndices = reportIndicesByLabel.get(label);
                Boolean isMerged = sourceIndices.size() > 1;
                
                if (isMerged) {
                    col.key = 'merged_' + sanitizeKey(label);
                    col.isMergedColumn = true;
                    col.sourceReportIndices = sourceIndices;
                } else {
                    col.key = 'r' + (parsed.reportIndex + 1) + '_' + sanitizeKey(aggInfo.key);
                    col.reportIndex = parsed.reportIndex;
                }
                
                col.aggregateKey = aggInfo.key;
                col.aggregateLabel = label;
                col.dataType = aggInfo.dataType;
                col.reportName = parsed.reportName;
                
                // Store original label and apply alias + custom format
                col.originalLabel = label;
                col.label = options.getColumnAlias(label);
                col.customFormat = options.getColumnFormat(label);
                col.customDecimals = options.getColumnDecimals(label);
                col.customCurrencyCode = options.getColumnCurrencyCode(label);
                
                columns.add(col);
            }
        }
        
        return columns;
    }
    
    /**
     * @description Fills in missing category combinations
     */
    private static void fillMissingCategories(
        Map<String, List<MergedGridDTO.GridRow>> rowsByPrimaryKey,
        Set<String> allPrimaryKeys,
        Set<String> allSecondaryKeys,
        List<MergedGridDTO.ParsedReportData> parsedReports,
        MergedGridDTO result,
        MergeOptions options
    ) {
        for (String primaryKey : allPrimaryKeys) {
            if (!rowsByPrimaryKey.containsKey(primaryKey)) {
                rowsByPrimaryKey.put(primaryKey, new List<MergedGridDTO.GridRow>());
            }
            
            List<MergedGridDTO.GridRow> existingRows = rowsByPrimaryKey.get(primaryKey);
            Set<String> existingSecondKeys = new Set<String>();
            String primaryLabel = primaryKey;
            
            for (MergedGridDTO.GridRow row : existingRows) {
                existingSecondKeys.add(row.secondKeyValue);
                primaryLabel = row.keyLabel;
            }
            
            // Add missing secondary keys
            for (String secondaryKey : allSecondaryKeys) {
                if (!existingSecondKeys.contains(secondaryKey)) {
                    MergedGridDTO.GridRow row = new MergedGridDTO.GridRow();
                    row.keyValue = primaryKey;
                    row.keyLabel = primaryLabel;
                    row.secondKeyValue = secondaryKey;
                    row.secondKeyLabel = secondaryKey;
                    
                    // Fill with zeros or blanks
                    for (MergedGridDTO.ColumnDefinition col : result.columns) {
                        if (col.isKeyColumn || col.isSecondKeyColumn) continue;
                        if (options.missingValueAsZero) {
                            row.values.put(col.key, 0);
                            row.formattedValues.put(col.key, '0');
                        } else {
                            row.formattedValues.put(col.key, '—');
                        }
                    }
                    
                    existingRows.add(row);
                }
            }
        }
    }
    
    /**
     * @description Sorts primary key groups by aggregate sum
     */
    private static List<String> sortGroupsByAggregate(
        Map<String, List<MergedGridDTO.GridRow>> rowsByPrimaryKey,
        MergeOptions options
    ) {
        // Calculate sum for each group
        Map<String, Decimal> groupSums = new Map<String, Decimal>();
        
        for (String primaryKey : rowsByPrimaryKey.keySet()) {
            Decimal sum = 0;
            for (MergedGridDTO.GridRow row : rowsByPrimaryKey.get(primaryKey)) {
                Decimal val = row.values.get(options.sortGroupsBy);
                if (val != null) sum += val;
            }
            groupSums.put(primaryKey, sum);
        }
        
        // Sort by sum
        List<GroupSortWrapper> wrappers = new List<GroupSortWrapper>();
        for (String key : groupSums.keySet()) {
            wrappers.add(new GroupSortWrapper(key, groupSums.get(key)));
        }
        wrappers.sort();
        
        List<String> sortedKeys = new List<String>();
        if (options.sortDirection == MergeOptions.SORT_DIRECTION_DESC) {
            for (Integer i = wrappers.size() - 1; i >= 0; i--) {
                sortedKeys.add(wrappers[i].key);
            }
        } else {
            for (GroupSortWrapper w : wrappers) {
                sortedKeys.add(w.key);
            }
        }
        
        return sortedKeys;
    }
    
    /**
     * @description Wrapper class for sorting groups by value
     */
    public class GroupSortWrapper implements Comparable {
        public String key;
        public Decimal value;
        
        public GroupSortWrapper(String key, Decimal value) {
            this.key = key;
            this.value = value != null ? value : 0;
        }
        
        public Integer compareTo(Object other) {
            GroupSortWrapper otherWrapper = (GroupSortWrapper) other;
            if (this.value < otherWrapper.value) return -1;
            if (this.value > otherWrapper.value) return 1;
            return 0;
        }
    }
    
    /**
     * @description Comparator for sorting rows by second key
     */
    public class SecondKeyComparator implements Comparator<MergedGridDTO.GridRow> {
        private Boolean ascending;
        
        public SecondKeyComparator(Boolean ascending) {
            this.ascending = ascending;
        }
        
        public Integer compare(MergedGridDTO.GridRow a, MergedGridDTO.GridRow b) {
            String keyA = a.secondKeyLabel != null ? a.secondKeyLabel : '';
            String keyB = b.secondKeyLabel != null ? b.secondKeyLabel : '';
            Integer result = keyA.compareTo(keyB);
            return ascending ? result : -result;
        }
    }
    
    /**
     * @description Merges reports using JOIN strategy (horizontal merge) - original behavior
     */
    private static void mergeJoin(
        List<MergedGridDTO.ParsedReportData> parsedReports,
        MergeOptions options,
        MergedGridDTO result
    ) {
        // Determine if we have 2 dimensions (native or via constants)
        Integer maxDims = 1;
        for (MergedGridDTO.ParsedReportData parsed : parsedReports) {
            Integer effectiveDims = parsed.dimensionCount;
            // Check if this report has a dimension constant (making it effectively 2-dim)
            if (parsed.dimensionCount == 1 && String.isNotBlank(options.getDimensionConstant(parsed.reportIndex + 1))) {
                effectiveDims = 2;
            }
            maxDims = Math.max(maxDims, effectiveDims);
        }
        result.hasSecondDimension = (maxDims == 2);
        
        // Build column definitions
        result.columns = buildJoinColumns(parsedReports, options);
        
        // Collect all keys based on merge mode
        Set<String> allKeys = new Set<String>();
        
        if (options.isInnerJoin()) {
            allKeys.addAll(parsedReports[0].valuesByKeyByAggregate.keySet());
            for (Integer i = 1; i < parsedReports.size(); i++) {
                allKeys.retainAll(parsedReports[i].valuesByKeyByAggregate.keySet());
            }
        } else {
            for (MergedGridDTO.ParsedReportData parsed : parsedReports) {
                allKeys.addAll(parsed.valuesByKeyByAggregate.keySet());
            }
        }
        
        result.totalRowCount = allKeys.size();
        
        // Build rows
        List<MergedGridDTO.GridRow> rows = new List<MergedGridDTO.GridRow>();
        Map<String, Decimal> columnTotals = new Map<String, Decimal>();
        
        for (MergedGridDTO.ColumnDefinition col : result.columns) {
            if (!col.isKeyColumn) {
                columnTotals.put(col.key, 0);
            }
        }
        
        for (String compositeKey : allKeys) {
            MergedGridDTO.GridRow row = new MergedGridDTO.GridRow();
            
            // Parse composite key to get primary and secondary values
            String primaryKey = compositeKey;
            String secondaryKey = '';
            if (compositeKey.contains(KEY_SEPARATOR)) {
                List<String> parts = compositeKey.split('\\|\\|');
                primaryKey = parts[0];
                secondaryKey = parts.size() > 1 ? parts[1] : '';
            }
            
            row.keyValue = primaryKey;
            row.secondKeyValue = secondaryKey;
            
            // Get display labels
            row.keyLabel = primaryKey;
            row.secondKeyLabel = secondaryKey;
            for (MergedGridDTO.ParsedReportData parsed : parsedReports) {
                if (parsed.labelsByKey.containsKey(compositeKey)) {
                    row.keyLabel = parsed.labelsByKey.get(compositeKey);
                }
                if (parsed.secondLabelsByKey.containsKey(compositeKey)) {
                    row.secondKeyLabel = parsed.secondLabelsByKey.get(compositeKey);
                }
                if (String.isNotBlank(row.keyLabel) && row.keyLabel != primaryKey) {
                    break;
                }
            }
            
            // Get values for each column
            for (Integer rptIdx = 0; rptIdx < parsedReports.size(); rptIdx++) {
                MergedGridDTO.ParsedReportData parsed = parsedReports[rptIdx];
                
                for (MergedGridDTO.AggregateInfo aggInfo : parsed.aggregates) {
                    String colKey = 'r' + (rptIdx + 1) + '_' + sanitizeKey(aggInfo.key);
                    
                    // Find column definition for custom format
                    MergedGridDTO.ColumnDefinition matchingCol = null;
                    for (MergedGridDTO.ColumnDefinition col : result.columns) {
                        if (col.key == colKey) {
                            matchingCol = col;
                            break;
                        }
                    }
                    
                    Decimal value = null;
                    if (parsed.valuesByKeyByAggregate.containsKey(compositeKey)) {
                        Map<String, Decimal> aggValues = parsed.valuesByKeyByAggregate.get(compositeKey);
                        if (aggValues != null && aggValues.containsKey(aggInfo.key)) {
                            value = aggValues.get(aggInfo.key);
                        }
                    }
                    
                    if (value != null) {
                        row.values.put(colKey, value);
                        if (matchingCol != null) {
                            row.formattedValues.put(colKey, formatValue(value, aggInfo.dataType, matchingCol.customFormat, matchingCol.customDecimals, matchingCol.customCurrencyCode));
                        } else {
                            row.formattedValues.put(colKey, formatValue(value, aggInfo.dataType));
                        }
                        
                        Decimal currentTotal = columnTotals.get(colKey);
                        if (currentTotal != null) {
                            columnTotals.put(colKey, currentTotal + value);
                        }
                    } else {
                        if (options.missingValueAsZero) {
                            row.values.put(colKey, 0);
                            row.formattedValues.put(colKey, '0');
                        } else {
                            row.values.put(colKey, null);
                            row.formattedValues.put(colKey, '—');
                        }
                    }
                }
            }
            
            rows.add(row);
        }
        
        // Sort rows
        sortRows(rows, options, result.columns);
        
        // Apply row limit
        if (rows.size() > options.maxRows) {
            result.isTruncated = true;
            List<MergedGridDTO.GridRow> limitedRows = new List<MergedGridDTO.GridRow>();
            for (Integer i = 0; i < options.maxRows && i < rows.size(); i++) {
                limitedRows.add(rows[i]);
            }
            rows = limitedRows;
        }
        
        result.rows = rows;
        
        // Totals row
        if (options.showGrandTotalRow) {
            MergedGridDTO.GridRow totalsRow = new MergedGridDTO.GridRow();
            totalsRow.keyValue = 'TOTAL';
            totalsRow.keyLabel = 'Total';
            totalsRow.secondKeyValue = '';
            totalsRow.secondKeyLabel = '';
            totalsRow.isTotalRow = true;
            
            for (MergedGridDTO.ColumnDefinition col : result.columns) {
                if (!col.isKeyColumn && !col.isSecondKeyColumn) {
                    Decimal total = columnTotals.get(col.key);
                    totalsRow.values.put(col.key, total);
                    totalsRow.formattedValues.put(col.key, formatValue(total, col.dataType, col.customFormat, col.customDecimals, col.customCurrencyCode));
                }
            }
            
            result.totalsRow = totalsRow;
        }
    }
    
    /**
     * @description Builds columns for JOIN mode
     */
    private static List<MergedGridDTO.ColumnDefinition> buildJoinColumns(
        List<MergedGridDTO.ParsedReportData> parsedReports,
        MergeOptions options
    ) {
        List<MergedGridDTO.ColumnDefinition> columns = new List<MergedGridDTO.ColumnDefinition>();
        
        // Determine if we have 2 dimensions (native or via constants)
        Integer maxDims = 1;
        for (MergedGridDTO.ParsedReportData parsed : parsedReports) {
            Integer effectiveDims = parsed.dimensionCount;
            if (parsed.dimensionCount == 1 && String.isNotBlank(options.getDimensionConstant(parsed.reportIndex + 1))) {
                effectiveDims = 2;
            }
            maxDims = Math.max(maxDims, effectiveDims);
        }
        Boolean hasSecondDimension = (maxDims == 2);
        
        // Key column - apply alias if configured
        MergedGridDTO.ColumnDefinition keyCol = new MergedGridDTO.ColumnDefinition();
        keyCol.key = 'keyLabel';
        String originalKeyLabel = parsedReports[0].groupingLabel != null ? 
            parsedReports[0].groupingLabel : parsedReports[0].groupingField;
        keyCol.label = options.getColumnAlias(originalKeyLabel);
        keyCol.dataType = 'STRING';
        keyCol.isKeyColumn = true;
        columns.add(keyCol);
        
        // Second key column if we have 2 dimensions
        if (hasSecondDimension) {
            MergedGridDTO.ColumnDefinition secondKeyCol = new MergedGridDTO.ColumnDefinition();
            secondKeyCol.key = 'secondKeyLabel';
            // Find the second grouping label from a report that has 2 native dimensions
            String secondKeyLabel = 'Category';
            for (MergedGridDTO.ParsedReportData parsed : parsedReports) {
                if (parsed.dimensionCount == 2 && parsed.secondGroupingLabel != null) {
                    secondKeyLabel = parsed.secondGroupingLabel;
                    break;
                }
            }
            secondKeyCol.label = options.getColumnAlias(secondKeyLabel);
            secondKeyCol.dataType = 'STRING';
            secondKeyCol.isSecondKeyColumn = true;
            columns.add(secondKeyCol);
        }
        
        // Track label occurrences for duplicate handling
        Map<String, Integer> labelOccurrences = new Map<String, Integer>();
        
        for (Integer rptIdx = 0; rptIdx < parsedReports.size(); rptIdx++) {
            MergedGridDTO.ParsedReportData parsed = parsedReports[rptIdx];
            
            for (MergedGridDTO.AggregateInfo aggInfo : parsed.aggregates) {
                MergedGridDTO.ColumnDefinition col = new MergedGridDTO.ColumnDefinition();
                
                col.key = 'r' + (rptIdx + 1) + '_' + sanitizeKey(aggInfo.key);
                col.reportId = parsed.reportId;
                col.reportName = parsed.reportName;
                col.aggregateKey = aggInfo.key;
                col.aggregateLabel = aggInfo.label;
                col.dataType = aggInfo.dataType;
                col.reportIndex = rptIdx;
                
                String originalLabel = aggInfo.label;
                
                String fullLabel;
                if (labelOccurrences.containsKey(originalLabel)) {
                    Integer occurrence = labelOccurrences.get(originalLabel) + 1;
                    labelOccurrences.put(originalLabel, occurrence);
                    fullLabel = originalLabel + ' (' + occurrence + ')';
                } else {
                    labelOccurrences.put(originalLabel, 1);
                    fullLabel = originalLabel;
                }
                
                String displayLabel = options.getColumnAlias(fullLabel);
                if (displayLabel.equals(fullLabel)) {
                    String baseAlias = options.getColumnAlias(originalLabel);
                    if (!baseAlias.equals(originalLabel)) {
                        if (fullLabel.contains(' (')) {
                            String suffix = fullLabel.substring(fullLabel.lastIndexOf(' ('));
                            displayLabel = baseAlias + suffix;
                        } else {
                            displayLabel = baseAlias;
                        }
                    }
                }
                
                col.label = displayLabel;
                
                // Store original label and apply custom format (try fullLabel first, then originalLabel)
                col.originalLabel = fullLabel;
                col.customFormat = options.getColumnFormat(fullLabel);
                if (col.customFormat == null) {
                    col.customFormat = options.getColumnFormat(originalLabel);
                }
                col.customDecimals = options.getColumnDecimals(fullLabel);
                if (col.customDecimals == 2 && options.getColumnConfig(originalLabel) != null) {
                    col.customDecimals = options.getColumnDecimals(originalLabel);
                }
                col.customCurrencyCode = options.getColumnCurrencyCode(fullLabel);
                if (col.customCurrencyCode == null) {
                    col.customCurrencyCode = options.getColumnCurrencyCode(originalLabel);
                }
                
                columns.add(col);
            }
        }
        
        return columns;
    }
    
    /**
     * @description Adds tier lookup columns and values (rate lookups based on input thresholds)
     * Tier columns are added before calculated fields so formulas can reference them (e.g. Rate * Funded Amount)
     */
    private static void addTierLookups(MergeOptions options, MergedGridDTO result) {
        Map<String, String> labelToKey = buildLabelToKeyForFormulas(result);
        
        for (MergeOptions.TierLookup tl : options.tierLookups) {
            if (String.isBlank(tl.label) || String.isBlank(tl.inputFormula)) {
                result.warnings.add('Tier lookup skipped: label and inputFormula are required.');
                continue;
            }
            
            String resolvedInput = resolveFormulaLabels(tl.inputFormula, labelToKey, result);
            if (resolvedInput == null) {
                continue;
            }
            
            MergedGridDTO.ColumnDefinition col = new MergedGridDTO.ColumnDefinition();
            col.key = 'tier_' + sanitizeKey(tl.label);
            col.label = tl.label;
            col.dataType = (tl.dataType != null) ? tl.dataType : 'DOUBLE_DATA';
            col.isKeyColumn = false;
            parseAndApplyTierLookupFormat(tl, col);
            result.columns.add(col);
            
            List<MergeOptions.TierEntry> sortedTiers = sortTiersForLookup(tl.tiers);
            
            for (MergedGridDTO.GridRow row : result.rows) {
                if (row.isSubtotalRow) continue;
                Decimal inputVal = evaluateFormula(resolvedInput, row.values);
                Decimal tierVal = evaluateTierLookup(inputVal, sortedTiers, tl.nullWhenZero);
                row.values.put(col.key, tierVal);
                row.formattedValues.put(col.key, formatValue(tierVal, col.dataType, col.customFormat, col.customDecimals, col.customCurrencyCode));
            }
            
            for (MergedGridDTO.GridRow row : result.rows) {
                if (row.isSubtotalRow) {
                    Decimal inputVal = evaluateFormula(resolvedInput, row.values);
                    Decimal tierVal = evaluateTierLookup(inputVal, sortedTiers, tl.nullWhenZero);
                    row.values.put(col.key, tierVal);
                    row.formattedValues.put(col.key, formatValue(tierVal, col.dataType, col.customFormat, col.customDecimals, col.customCurrencyCode));
                }
            }
            
            if (result.totalsRow != null) {
                Decimal inputVal = evaluateFormula(resolvedInput, result.totalsRow.values);
                Decimal tierVal = evaluateTierLookup(inputVal, sortedTiers, tl.nullWhenZero);
                result.totalsRow.values.put(col.key, tierVal);
                result.totalsRow.formattedValues.put(col.key, formatValue(tierVal, col.dataType, col.customFormat, col.customDecimals, col.customCurrencyCode));
            }
            
            labelToKey.put(col.label, col.key);
            labelToKey.put(col.key, col.key);
        }
    }
    
    /**
     * @description Sorts tiers by min descending; default tier (no min) last
     */
    private static List<MergeOptions.TierEntry> sortTiersForLookup(List<MergeOptions.TierEntry> tiers) {
        if (tiers == null || tiers.isEmpty()) return new List<MergeOptions.TierEntry>();
        List<MergeOptions.TierEntry> withMin = new List<MergeOptions.TierEntry>();
        List<MergeOptions.TierEntry> defaults = new List<MergeOptions.TierEntry>();
        for (MergeOptions.TierEntry t : tiers) {
            if (t == null) continue;
            if (t.min != null) {
                withMin.add(t);
            } else {
                defaults.add(t);
            }
        }
        withMin.sort(new TierMinDescComparator());
        List<MergeOptions.TierEntry> result = new List<MergeOptions.TierEntry>();
        result.addAll(withMin);
        result.addAll(defaults);
        return result;
    }
    
    private class TierMinDescComparator implements Comparator<MergeOptions.TierEntry> {
        public Integer compare(MergeOptions.TierEntry a, MergeOptions.TierEntry b) {
            Decimal am = a != null ? a.min : null;
            Decimal bm = b != null ? b.min : null;
            if (am == null && bm == null) return 0;
            if (am == null) return 1;
            if (bm == null) return -1;
            return am < bm ? 1 : (am > bm ? -1 : 0);
        }
    }
    
    /**
     * @description Evaluates tier lookup: first tier where input >= min wins; fallback to default (no min)
     * @TestVisible for unit testing
     */
    @TestVisible
    private static Decimal evaluateTierLookup(Decimal inputVal, List<MergeOptions.TierEntry> sortedTiers, Boolean nullWhenZero) {
        if (nullWhenZero == true && (inputVal == null || inputVal == 0)) {
            return null;
        }
        if (inputVal == null) inputVal = 0;
        for (MergeOptions.TierEntry t : sortedTiers) {
            if (t == null || t.value == null) continue;
            if (t.min == null) {
                return t.value;
            }
            if (inputVal >= t.min) {
                return t.value;
            }
        }
        return null;
    }
    
    /**
     * @description Applies format/decimals from TierLookup to column definition
     */
    private static void parseAndApplyTierLookupFormat(MergeOptions.TierLookup tl, MergedGridDTO.ColumnDefinition col) {
        if (String.isBlank(tl.format)) return;
        String formatStr = tl.format.trim().toLowerCase();
        col.customFormat = formatStr;
        col.customDecimals = (tl.decimals != null) ? tl.decimals : 2;
        col.customCurrencyCode = null;
        if (formatStr.contains(':')) {
            List<String> parts = formatStr.split(':');
            col.customFormat = parts[0].toLowerCase();
            if (col.customFormat == 'currency' && parts.size() > 1) {
                col.customCurrencyCode = parts[1].toUpperCase();
            } else if ((col.customFormat == 'percent' || col.customFormat == 'number') && parts.size() > 1) {
                try {
                    col.customDecimals = Integer.valueOf(parts[1]);
                } catch (Exception e) {
                    col.customDecimals = 2;
                }
            }
        }
    }
    
    /**
     * @description Builds label-to-key map for formula resolution (used by tier lookups and calculated fields)
     */
    private static Map<String, String> buildLabelToKeyForFormulas(MergedGridDTO result) {
        Map<String, Decimal> totalByKey = (result.totalsRow != null && result.totalsRow.values != null)
            ? result.totalsRow.values : new Map<String, Decimal>();
        Map<String, String> baseLabelToBestKey = new Map<String, String>();
        for (MergedGridDTO.ColumnDefinition existingCol : result.columns) {
            if (existingCol.isKeyColumn || existingCol.isSecondKeyColumn || String.isBlank(existingCol.label)) continue;
            String baseLabel = getBaseLabelForDuplicateCheck(existingCol.label);
            Decimal total = totalByKey.get(existingCol.key);
            Decimal totalAbs = (total != null) ? total.abs() : Decimal.valueOf(0);
            String bestKey = baseLabelToBestKey.get(baseLabel);
            Decimal bestTotal = (bestKey != null && totalByKey.containsKey(bestKey)) ? totalByKey.get(bestKey).abs() : Decimal.valueOf(0);
            if (bestKey == null || totalAbs > bestTotal) {
                baseLabelToBestKey.put(baseLabel, existingCol.key);
            }
        }
        Map<String, String> labelToKey = new Map<String, String>();
        for (MergedGridDTO.ColumnDefinition existingCol : result.columns) {
            if (!existingCol.isKeyColumn && !existingCol.isSecondKeyColumn) {
                if (String.isNotBlank(existingCol.label)) {
                    labelToKey.put(existingCol.label, existingCol.key);
                    String baseLabel = getBaseLabelForDuplicateCheck(existingCol.label);
                    labelToKey.put(baseLabel, baseLabelToBestKey.get(baseLabel));
                }
                labelToKey.put(existingCol.key, existingCol.key);
            }
        }
        return labelToKey;
    }
    
    /**
     * @description Adds calculated field columns and values
     * Supports both internal keys (r1_Sum_of_Amount) and display labels (Sum of Amount)
     */
    private static void addCalculatedFields(MergeOptions options, MergedGridDTO result) {
        Map<String, String> labelToKey = buildLabelToKeyForFormulas(result);
        
        for (MergeOptions.CalculatedField calcField : options.calculatedFields) {
            if (String.isBlank(calcField.label) || String.isBlank(calcField.formula)) {
                result.warnings.add('Calculated field skipped: label and formula are required.');
                continue;
            }
            
            // Convert display labels to internal keys in the formula
            String resolvedFormula = resolveFormulaLabels(calcField.formula, labelToKey, result);
            if (resolvedFormula == null) {
                // Warning already added in resolveFormulaLabels
                continue;
            }
            
            MergedGridDTO.ColumnDefinition col = new MergedGridDTO.ColumnDefinition();
            col.key = 'calc_' + sanitizeKey(calcField.label);
            col.label = calcField.label;
            col.dataType = calcField.dataType != null ? calcField.dataType : 'DOUBLE_DATA';
            col.isKeyColumn = false;
            // Apply format, decimals, currency from calculated field
            parseAndApplyCalculatedFieldFormat(calcField, col);
            result.columns.add(col);
            
            Decimal totalCalcValue = 0;
            Integer validCount = 0;
            for (MergedGridDTO.GridRow row : result.rows) {
                if (row.isSubtotalRow) continue; // Skip subtotals, we'll calculate separately
                
                Decimal calcValue = evaluateFormula(resolvedFormula, row.values);
                row.values.put(col.key, calcValue);
                row.formattedValues.put(col.key, formatValue(calcValue, col.dataType, col.customFormat, col.customDecimals, col.customCurrencyCode));
                if (calcValue != null) {
                    totalCalcValue += calcValue;
                    validCount++;
                }
            }
            
            // For subtotal rows, recalculate based on their values
            for (MergedGridDTO.GridRow row : result.rows) {
                if (row.isSubtotalRow) {
                    Decimal calcValue = evaluateFormula(resolvedFormula, row.values);
                    row.values.put(col.key, calcValue);
                    row.formattedValues.put(col.key, formatValue(calcValue, col.dataType, col.customFormat, col.customDecimals, col.customCurrencyCode));
                }
            }
            
            if (result.totalsRow != null) {
                // For totals, evaluate formula on totals row values (not sum of calculated values)
                Decimal totalsCalcValue = evaluateFormula(resolvedFormula, result.totalsRow.values);
                result.totalsRow.values.put(col.key, totalsCalcValue);
                result.totalsRow.formattedValues.put(col.key, formatValue(totalsCalcValue, col.dataType, col.customFormat, col.customDecimals, col.customCurrencyCode));
            }
        }
    }
    
    /**
     * @description Returns base label for duplicate-check (strips " (2)", " (3)" suffix)
     * @TestVisible for unit testing
     */
    @TestVisible
    private static String getBaseLabelForDuplicateCheck(String label) {
        if (String.isBlank(label)) return label;
        Integer parenIdx = label.lastIndexOf(' (');
        if (parenIdx > 0 && label.endsWith(')') && label.length() > parenIdx + 3) {
            String suffix = label.substring(parenIdx);
            if (Pattern.matches(' \\(\\d+\\)', suffix)) {
                return label.substring(0, parenIdx).trim();
            }
        }
        return label.trim();
    }
    
    /**
     * @description Parses format/decimals/currencyCode from CalculatedField and applies to column
     * Supports shorthand: percent:1, currency:EUR
     */
    private static void parseAndApplyCalculatedFieldFormat(MergeOptions.CalculatedField calcField, MergedGridDTO.ColumnDefinition col) {
        if (String.isBlank(calcField.format)) return;
        String formatStr = calcField.format.trim().toLowerCase();
        col.customFormat = formatStr;
        col.customDecimals = calcField.decimals != null ? calcField.decimals : 2;
        col.customCurrencyCode = String.isNotBlank(calcField.currencyCode) ? calcField.currencyCode : null;
        if (formatStr.contains(':')) {
            List<String> parts = formatStr.split(':');
            col.customFormat = parts[0].toLowerCase();
            if (col.customFormat == 'currency' && parts.size() > 1) {
                col.customCurrencyCode = parts[1].toUpperCase();
            } else if ((col.customFormat == 'percent' || col.customFormat == 'number') && parts.size() > 1) {
                try {
                    col.customDecimals = Integer.valueOf(parts[1]);
                } catch (Exception e) {
                    col.customDecimals = 2;
                }
            }
        }
    }
    
    /**
     * @description Resolves display labels in formula to internal column keys
     * Uses word boundaries to prevent partial matches and validates formula safety
     */
    private static String resolveFormulaLabels(String formula, Map<String, String> labelToKey, MergedGridDTO result) {
        // Validate formula contains only safe characters (alphanumeric, spaces, operators, parentheses)
        if (!Pattern.matches('^[a-zA-Z0-9_() +\\-*/\\s]+$', formula)) {
            result.warnings.add('Calculated field formula contains invalid characters. Only letters, numbers, spaces, and operators (+, -, *, /) are allowed.');
            return null;
        }
        
        String resolved = formula;
        
        // Extract tokens from formula (split by operators)
        Set<String> tokens = new Set<String>();
        String tempFormula = formula.replace(' + ', '|').replace(' - ', '|')
                                    .replace(' * ', '|').replace(' / ', '|');
        for (String token : tempFormula.split('\\|')) {
            token = token.trim();
            if (String.isNotBlank(token) && !token.isNumeric()) {
                tokens.add(token);
            }
        }
        
        // Sort tokens by length (longest first) to avoid partial matches
        // Example: "Amount (2)" should match before "Amount"
        List<String> sortedTokens = new List<String>(tokens);
        sortedTokens.sort(new TokenLengthComparator());
        
        // Resolve each token using word boundaries to prevent partial matches
        List<String> unresolvedTokens = new List<String>();
        for (String token : sortedTokens) {
            if (labelToKey.containsKey(token)) {
                // Use word boundary regex to ensure exact token match
                // Escape special regex characters in token
                String escapedToken = Pattern.quote(token);
                // Replace with word boundaries to avoid partial matches
                resolved = resolved.replaceAll('\\b' + escapedToken + '\\b', labelToKey.get(token));
            } else {
                unresolvedTokens.add(token);
            }
        }
        
        if (!unresolvedTokens.isEmpty()) {
            // Build helpful error with available columns
            List<String> availableLabels = new List<String>();
            for (MergedGridDTO.ColumnDefinition col : result.columns) {
                if (!col.isKeyColumn && !col.isSecondKeyColumn) {
                    availableLabels.add('"' + col.label + '"');
                }
            }
            result.warnings.add(
                'Calculated field formula references unknown column(s): ' + String.join(unresolvedTokens, ', ') + 
                '. Available columns: ' + String.join(availableLabels, ', ')
            );
            return null;
        }
        
        return resolved;
    }
    
    /**
     * @description Comparator to sort tokens by length (longest first)
     * This prevents partial matches when replacing tokens in formulas
     */
    private class TokenLengthComparator implements Comparator<String> {
        public Integer compare(String a, String b) {
            if (a.length() > b.length()) return -1;
            if (a.length() < b.length()) return 1;
            return a.compareTo(b);
        }
    }
    
    /**
     * @description Evaluates a formula with support for parentheses and order of operations.
     * Supports + - * / with proper precedence; parentheses override precedence.
     * @TestVisible for unit testing formula logic in isolation
     */
    @TestVisible
    private static Decimal evaluateFormula(String formula, Map<String, Decimal> values) {
        if (String.isBlank(formula) || values == null) return null;
        
        try {
            formula = formula.trim();
            
            // Safety: only allow valid formula characters
            if (!Pattern.matches('^[a-zA-Z0-9_() +\\-*/\\s]+$', formula)) {
                return null;
            }
            
            // Strip outer parentheses if the whole expression is wrapped
            formula = stripOuterParentheses(formula);
            
            // Find first operator at depth 0 (lowest precedence first for correct order of ops)
            OperatorMatch addSub = findFirstOperatorAtDepth(formula, new List<String>{' + ', ' - '});
            if (addSub != null) {
                String left = formula.substring(0, addSub.idx).trim();
                String right = formula.substring(addSub.idx + addSub.op.length()).trim();
                Decimal leftVal = getValueOrEvaluate(left, values);
                Decimal rightVal = getValueOrEvaluate(right, values);
                if (leftVal == null) leftVal = 0;
                if (rightVal == null) rightVal = 0;
                return addSub.op.contains('+') ? leftVal + rightVal : leftVal - rightVal;
            }
            
            OperatorMatch mulDiv = findFirstOperatorAtDepth(formula, new List<String>{' * ', ' / '});
            if (mulDiv != null) {
                String left = formula.substring(0, mulDiv.idx).trim();
                String right = formula.substring(mulDiv.idx + mulDiv.op.length()).trim();
                Decimal leftVal = getValueOrEvaluate(left, values);
                Decimal rightVal = getValueOrEvaluate(right, values);
                if (mulDiv.op.contains('*')) {
                    if (leftVal == null) leftVal = 0;
                    if (rightVal == null) rightVal = 0;
                    return leftVal * rightVal;
                } else {
                    if (leftVal == null) return 0;
                    if (rightVal == null || rightVal == 0) return 0; // Divide by zero
                    return leftVal.divide(rightVal, 4, RoundingMode.HALF_UP);
                }
            }
            
            return getValueForToken(formula, values);
            
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * @description Strips outer parentheses if the entire expression is wrapped in matching ( )
     */
    private static String stripOuterParentheses(String formula) {
        if (formula.length() < 2 || formula.substring(0, 1) != '(') return formula;
        Integer depth = 1;
        for (Integer i = 1; i < formula.length(); i++) {
            String c = formula.substring(i, i + 1);
            if (c == '(') depth++;
            else if (c == ')') {
                depth--;
                if (depth == 0) {
                    if (i == formula.length() - 1) {
                        return formula.substring(1, formula.length() - 1).trim();
                    }
                    return formula;
                }
            }
        }
        return formula;
    }
    
    /**
     * @description Finds the first occurrence of any operator at parenthesis depth 0
     */
    private static OperatorMatch findFirstOperatorAtDepth(String formula, List<String> operators) {
        Integer depth = 0;
        Integer len = formula.length();
        for (Integer i = 0; i < len; i++) {
            String c = formula.substring(i, i + 1);
            if (c == '(') depth++;
            else if (c == ')') depth--;
            if (depth == 0) {
                for (String op : operators) {
                    if (i + op.length() <= len && formula.substring(i, i + op.length()) == op) {
                        return new OperatorMatch(i, op);
                    }
                }
            }
        }
        return null;
    }
    
    /**
     * @description Tries token lookup first; if not a simple token, recurses with evaluateFormula
     */
    private static Decimal getValueOrEvaluate(String part, Map<String, Decimal> values) {
        Decimal val = getValueForToken(part, values);
        if (val != null) return val;
        return evaluateFormula(part, values);
    }
    
    /**
     * @description Holds operator position and literal for formula parsing
     */
    private class OperatorMatch {
        public Integer idx;
        public String op;
        public OperatorMatch(Integer idx, String op) {
            this.idx = idx;
            this.op = op;
        }
    }
    
    private static Decimal getValueForToken(String token, Map<String, Decimal> values) {
        token = token.trim();
        if (values.containsKey(token)) return values.get(token);
        try {
            return Decimal.valueOf(token);
        } catch (Exception e) {
            return null;
        }
    }
    
    private static void sortRows(
        List<MergedGridDTO.GridRow> rows,
        MergeOptions options,
        List<MergedGridDTO.ColumnDefinition> columns
    ) {
        Integer sortColIndex = options.getSortColumnIndex();
        Boolean isAscending = options.sortDirection == MergeOptions.SORT_DIRECTION_ASC;
        
        if (sortColIndex == 0) {
            rows.sort(new KeyLabelComparator(isAscending));
        } else if (sortColIndex <= columns.size() - 1) {
            String colKey = columns[sortColIndex].key;
            rows.sort(new ColumnValueComparator(colKey, isAscending));
        }
    }
    
    private static Decimal calculateKeyOverlap(List<MergedGridDTO.ParsedReportData> parsedReports) {
        if (parsedReports.size() < 2) return 100;
        
        Set<String> intersection = new Set<String>(parsedReports[0].primaryKeys);
        Set<String> union = new Set<String>(parsedReports[0].primaryKeys);
        
        for (Integer i = 1; i < parsedReports.size(); i++) {
            Set<String> reportKeys = parsedReports[i].primaryKeys;
            intersection.retainAll(reportKeys);
            union.addAll(reportKeys);
        }
        
        if (union.isEmpty()) return 0;
        return (Decimal.valueOf(intersection.size()) / Decimal.valueOf(union.size()) * 100).setScale(1);
    }
    
    private static String sanitizeKey(String key) {
        if (key == null) return 'null';
        return key.replace('!', '_').replace('.', '_').replace(' ', '_');
    }
    
    private static String normalizeKey(Object keyValue) {
        if (keyValue == null) return BLANK_KEY_TOKEN;
        String keyStr = String.valueOf(keyValue).trim();
        if (String.isBlank(keyStr)) return BLANK_KEY_TOKEN;
        return keyStr;
    }
    
    private static Decimal convertToDecimal(Object value) {
        if (value == null) return null;
        if (value instanceof Decimal) return (Decimal) value;
        if (value instanceof Integer) return Decimal.valueOf((Integer) value);
        if (value instanceof Long) return Decimal.valueOf((Long) value);
        if (value instanceof Double) return Decimal.valueOf((Double) value);
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * @description Formats error messages for client display
     * Returns user-friendly messages by default, with optional stack traces for debugging
     * @param e The exception to format
     * @return Formatted error message string
     */
    private static String formatErrorMessage(Exception e) {
        String userMessage = 'An error occurred while processing reports. Please try again or contact your administrator.';
        
        // Provide specific messages for common error types
        if (e instanceof System.NoAccessException) {
            userMessage = 'You don\'t have access to one or more reports.';
        } else if (e.getMessage() != null) {
            String msg = e.getMessage();
            if (msg.contains('insufficient access')) {
                userMessage = 'You don\'t have access to run one or more reports.';
            } else if (msg.contains('limit') || msg.contains('LIMIT')) {
                userMessage = 'A system limit was reached. Please try again later or reduce the number of reports.';
            } else if (msg.contains('timeout') || msg.contains('TIMEOUT')) {
                userMessage = 'The request timed out. Please try again or reduce the number of reports.';
            }
        }
        
        // Optionally append stack trace for debugging (controlled by INCLUDE_STACK_TRACES_IN_ERRORS flag)
        if (INCLUDE_STACK_TRACES_IN_ERRORS) {
            userMessage += ' - ' + e.getStackTraceString();
        }
        
        return userMessage;
    }
    
    private static String formatValue(Decimal value, String dataType) {
        return formatValue(value, dataType, null, null, null);
    }
    
    /**
     * @description Formats a value with optional custom format override
     * @param value The decimal value to format
     * @param dataType The Salesforce data type (CURRENCY_DATA, PERCENT_DATA, INT_DATA, etc.)
     * @param customFormat Custom format override (currency, percent, number, none)
     * @param customDecimals Custom decimal places
     * @param customCurrencyCode Custom currency code (e.g., EUR, GBP)
     * @TestVisible for unit testing percent/currency formatting
     */
    @TestVisible
    private static String formatValue(Decimal value, String dataType, String customFormat, Integer customDecimals, String customCurrencyCode) {
        if (value == null) return '—';
        
        // Use custom decimals or default to 2
        Integer decimals = (customDecimals != null) ? customDecimals : 2;
        
        // Determine effective format (custom overrides data type)
        String effectiveFormat = customFormat;
        if (String.isBlank(effectiveFormat)) {
            // Map data type to format
            if (dataType == 'CURRENCY_DATA') effectiveFormat = 'currency';
            else if (dataType == 'PERCENT_DATA') effectiveFormat = 'percent';
            else if (dataType == 'INT_DATA') effectiveFormat = 'number';
            else effectiveFormat = 'number';
        }
        
        // Handle "none" format - raw number without formatting
        if (effectiveFormat == 'none') {
            return String.valueOf(value.setScale(decimals, RoundingMode.HALF_UP));
        }
        
        // Currency formatting with symbol and thousand separators
        if (effectiveFormat == 'currency') {
            Boolean isNegative = value < 0;
            Decimal absValue = value.abs().setScale(decimals, RoundingMode.HALF_UP);
            String formatted = formatWithCommas(absValue, decimals);
            
            // Determine currency symbol
            String currencySymbol;
            String currCode = String.isNotBlank(customCurrencyCode) ? customCurrencyCode : UserInfo.getDefaultCurrency();
            if (currCode == 'USD') currencySymbol = '$';
            else if (currCode == 'EUR') currencySymbol = '€';
            else if (currCode == 'GBP') currencySymbol = '£';
            else if (currCode == 'JPY') currencySymbol = '¥';
            else if (currCode == 'CAD') currencySymbol = 'CA$';
            else if (currCode == 'AUD') currencySymbol = 'A$';
            else currencySymbol = currCode + ' ';
            
            return isNegative ? '-' + currencySymbol + formatted : currencySymbol + formatted;
        }
        
        // Percentage formatting with % symbol (value in 0-1 scale, display as 0-100)
        if (effectiveFormat == 'percent') {
            return formatWithCommas((value * 100).setScale(decimals, RoundingMode.HALF_UP), decimals) + '%';
        }
        
        // Number formatting with thousand separators
        if (effectiveFormat == 'number') {
            // For INT_DATA without custom decimals, use 0 decimal places
            if (dataType == 'INT_DATA' && customDecimals == null) {
                return formatWithCommas(value.setScale(0, RoundingMode.HALF_UP), 0);
            }
            // Check if it's a whole number
            if (customDecimals == null && value == value.setScale(0)) {
                return formatWithCommas(value.setScale(0), 0);
            }
            return formatWithCommas(value.setScale(decimals, RoundingMode.HALF_UP), decimals);
        }
        
        // Default: format with appropriate decimal places
        if (value == value.setScale(0)) {
            return formatWithCommas(value.setScale(0), 0);
        }
        return formatWithCommas(value.setScale(decimals, RoundingMode.HALF_UP), decimals);
    }
    
    /**
     * @description Formats a decimal with thousand separators (commas)
     */
    private static String formatWithCommas(Decimal value, Integer decimalPlaces) {
        if (value == null) return '—';
        
        Boolean isNegative = value < 0;
        Decimal absValue = value.abs();
        
        // Split into integer and decimal parts
        Long integerPart = absValue.longValue();
        String integerStr = String.valueOf(integerPart);
        
        // Add thousand separators
        String result = '';
        Integer count = 0;
        for (Integer i = integerStr.length() - 1; i >= 0; i--) {
            if (count > 0 && Math.mod(count, 3) == 0) {
                result = ',' + result;
            }
            result = integerStr.substring(i, i + 1) + result;
            count++;
        }
        
        // Add decimal places if needed
        if (decimalPlaces > 0) {
            Decimal decimalPart = absValue - integerPart;
            String decimalStr = decimalPart.setScale(decimalPlaces, RoundingMode.HALF_UP).toPlainString();
            // Get the part after the decimal point
            Integer dotIndex = decimalStr.indexOf('.');
            if (dotIndex >= 0) {
                result += decimalStr.substring(dotIndex);
            } else {
                result += '.' + '0'.repeat(decimalPlaces);
            }
        }
        
        return isNegative ? '-' + result : result;
    }
    
    public class KeyLabelComparator implements Comparator<MergedGridDTO.GridRow> {
        private Boolean ascending;
        public KeyLabelComparator(Boolean ascending) { this.ascending = ascending; }
        public Integer compare(MergedGridDTO.GridRow a, MergedGridDTO.GridRow b) {
            String labelA = a.keyLabel != null ? a.keyLabel : '';
            String labelB = b.keyLabel != null ? b.keyLabel : '';
            Integer result = labelA.compareTo(labelB);
            return ascending ? result : -result;
        }
    }
    
    public class ColumnValueComparator implements Comparator<MergedGridDTO.GridRow> {
        private String columnKey;
        private Boolean ascending;
        public ColumnValueComparator(String columnKey, Boolean ascending) {
            this.columnKey = columnKey;
            this.ascending = ascending;
        }
        public Integer compare(MergedGridDTO.GridRow a, MergedGridDTO.GridRow b) {
            Decimal valueA = a.values.get(columnKey);
            Decimal valueB = b.values.get(columnKey);
            if (valueA == null && valueB == null) return 0;
            if (valueA == null) return ascending ? -1 : 1;
            if (valueB == null) return ascending ? 1 : -1;
            Integer result;
            if (valueA < valueB) result = -1;
            else if (valueA > valueB) result = 1;
            else result = 0;
            return ascending ? result : -result;
        }
    }
}