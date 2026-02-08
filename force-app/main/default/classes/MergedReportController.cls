/**
 * @description Controller for the Merged Report Grid LWC component.
 *              Handles fetching, validating, and merging data from multiple Salesforce reports.
 *              Supports JOIN (horizontal merge) and UNION (vertical stack) strategies.
 * @author DataTools Pro
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
            result.errors.add(new MergedGridDTO.ReportError(
                null,
                'Error processing reports: ' + e.getMessage() + ' - ' + e.getStackTraceString(),
                true
            ));
        }
        
        result.processingTimeMs = System.currentTimeMillis() - startTime;
        return result;
    }
    
    /**
     * @description Parses the options JSON string
     */
    private static MergeOptions parseOptions(String optionsJson) {
        if (String.isBlank(optionsJson)) {
            return new MergeOptions();
        }
        try {
            MergeOptions options = (MergeOptions) JSON.deserialize(optionsJson, MergeOptions.class);
            return options;
        } catch (Exception e) {
            return new MergeOptions();
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
                                    row.formattedValues.put(col.key, formatValue(value, col.dataType));
                                }
                                break;
                            }
                        }
                    } else if (col.reportIndex == parsed.reportIndex) {
                        // Non-merged column from this report
                        Decimal value = aggValues.get(col.aggregateKey);
                        if (value != null) {
                            row.values.put(col.key, value);
                            row.formattedValues.put(col.key, formatValue(value, col.dataType));
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
                    subtotalRow.formattedValues.put(col.key, formatValue(sum, col.dataType));
                    
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
                
                // Find data type
                String dataType = 'DOUBLE_DATA';
                for (MergedGridDTO.ColumnDefinition col : result.columns) {
                    if (col.key == colKey) {
                        dataType = col.dataType;
                        break;
                    }
                }
                totalsRow.formattedValues.put(colKey, formatValue(total, dataType));
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
                
                // Apply alias
                col.label = options.getColumnAlias(label);
                
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
                    
                    Decimal value = null;
                    if (parsed.valuesByKeyByAggregate.containsKey(compositeKey)) {
                        Map<String, Decimal> aggValues = parsed.valuesByKeyByAggregate.get(compositeKey);
                        if (aggValues != null && aggValues.containsKey(aggInfo.key)) {
                            value = aggValues.get(aggInfo.key);
                        }
                    }
                    
                    if (value != null) {
                        row.values.put(colKey, value);
                        row.formattedValues.put(colKey, formatValue(value, aggInfo.dataType));
                        
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
                    totalsRow.formattedValues.put(col.key, formatValue(total, col.dataType));
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
                columns.add(col);
            }
        }
        
        return columns;
    }
    
    /**
     * @description Adds calculated field columns and values
     * Supports both internal keys (r1_Sum_of_Amount) and display labels (Sum of Amount)
     */
    private static void addCalculatedFields(MergeOptions options, MergedGridDTO result) {
        // Build map of display label -> internal key for formula resolution
        Map<String, String> labelToKey = new Map<String, String>();
        for (MergedGridDTO.ColumnDefinition existingCol : result.columns) {
            if (!existingCol.isKeyColumn && !existingCol.isSecondKeyColumn) {
                // Map by display label (for user-friendly formulas)
                if (String.isNotBlank(existingCol.label)) {
                    labelToKey.put(existingCol.label, existingCol.key);
                }
                // Also map by internal key (for technical formulas)
                labelToKey.put(existingCol.key, existingCol.key);
            }
        }
        
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
            result.columns.add(col);
            
            Decimal totalCalcValue = 0;
            Integer validCount = 0;
            for (MergedGridDTO.GridRow row : result.rows) {
                if (row.isSubtotalRow) continue; // Skip subtotals, we'll calculate separately
                
                Decimal calcValue = evaluateFormula(resolvedFormula, row.values);
                row.values.put(col.key, calcValue);
                row.formattedValues.put(col.key, formatValue(calcValue, col.dataType));
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
                    row.formattedValues.put(col.key, formatValue(calcValue, col.dataType));
                }
            }
            
            if (result.totalsRow != null) {
                // For totals, evaluate formula on totals row values (not sum of calculated values)
                Decimal totalsCalcValue = evaluateFormula(resolvedFormula, result.totalsRow.values);
                result.totalsRow.values.put(col.key, totalsCalcValue);
                result.totalsRow.formattedValues.put(col.key, formatValue(totalsCalcValue, col.dataType));
            }
        }
    }
    
    /**
     * @description Resolves display labels in formula to internal column keys
     */
    private static String resolveFormulaLabels(String formula, Map<String, String> labelToKey, MergedGridDTO result) {
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
        
        // Resolve each token
        List<String> unresolvedTokens = new List<String>();
        for (String token : tokens) {
            if (labelToKey.containsKey(token)) {
                // Replace display label with internal key
                resolved = resolved.replace(token, labelToKey.get(token));
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
     * @description Evaluates a simple formula
     */
    private static Decimal evaluateFormula(String formula, Map<String, Decimal> values) {
        if (String.isBlank(formula) || values == null) return null;
        
        try {
            formula = formula.trim();
            
            if (formula.contains(' + ')) {
                List<String> parts = formula.split(' \\+ ');
                Decimal result = 0;
                for (String part : parts) {
                    Decimal val = getValueForToken(part.trim(), values);
                    if (val != null) result += val; // Treat null as 0
                }
                return result;
            }
            
            if (formula.contains(' - ')) {
                List<String> parts = formula.split(' - ');
                Decimal result = getValueForToken(parts[0].trim(), values);
                if (result == null) result = 0; // Treat null as 0
                for (Integer i = 1; i < parts.size(); i++) {
                    Decimal val = getValueForToken(parts[i].trim(), values);
                    if (val != null) result -= val; // Treat null as 0
                }
                return result;
            }
            
            if (formula.contains(' * ')) {
                List<String> parts = formula.split(' \\* ');
                Decimal result = 1;
                for (String part : parts) {
                    Decimal val = getValueForToken(part.trim(), values);
                    if (val == null) val = 0; // Treat null as 0
                    result *= val;
                }
                return result;
            }
            
            if (formula.contains(' / ')) {
                List<String> parts = formula.split(' / ');
                Decimal result = getValueForToken(parts[0].trim(), values);
                if (result == null) return 0; // Treat null as 0
                for (Integer i = 1; i < parts.size(); i++) {
                    Decimal val = getValueForToken(parts[i].trim(), values);
                    if (val == null || val == 0) return 0; // Divide by zero = 0
                    result = result.divide(val, 4, RoundingMode.HALF_UP);
                }
                return result;
            }
            
            return getValueForToken(formula, values);
            
        } catch (Exception e) {
            return null;
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
    
    private static String formatValue(Decimal value, String dataType) {
        if (value == null) return '—';
        
        // Currency formatting with $ symbol and thousand separators
        if (dataType == 'CURRENCY_DATA') {
            Boolean isNegative = value < 0;
            Decimal absValue = value.abs().setScale(2, RoundingMode.HALF_UP);
            String formatted = formatWithCommas(absValue, 2);
            // Get currency symbol from org (defaults to $)
            String currencySymbol = UserInfo.getDefaultCurrency() == 'USD' ? '$' : UserInfo.getDefaultCurrency() + ' ';
            return isNegative ? '-' + currencySymbol + formatted : currencySymbol + formatted;
        }
        
        // Percentage formatting with % symbol
        if (dataType == 'PERCENT_DATA') {
            return formatWithCommas(value.setScale(2, RoundingMode.HALF_UP), 2) + '%';
        }
        
        // Integer formatting with thousand separators
        if (dataType == 'INT_DATA') {
            return formatWithCommas(value.setScale(0, RoundingMode.HALF_UP), 0);
        }
        
        // Default: format with appropriate decimal places
        if (value == value.setScale(0)) {
            return formatWithCommas(value.setScale(0), 0);
        }
        return formatWithCommas(value.setScale(2, RoundingMode.HALF_UP), 2);
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