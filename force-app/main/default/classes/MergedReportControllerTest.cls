/**
 * @description Comprehensive unit tests for MergedReportController
 *              Tests all data shapes: JOIN/UNION modes, 1/2 dimensions, 
 *              column merging, subtotals, fill missing, sorting, etc.
 */
@IsTest
private class MergedReportControllerTest {
    
    // ========================================================================
    // MERGE OPTIONS TESTS
    // ========================================================================
    
    @IsTest
    static void testMergeOptionsDefaults() {
        MergeOptions options = new MergeOptions();
        
        System.assertEquals('OUTER_JOIN', options.mergeMode, 'Default mode should be OUTER_JOIN');
        System.assertEquals(false, options.missingValueAsZero, 'Default missingValueAsZero');
        System.assertEquals('KEY', options.sortBy, 'Default sortBy');
        System.assertEquals('ASC', options.sortDirection, 'Default sortDirection');
        System.assertEquals(200, options.maxRows, 'Default maxRows');
        System.assertEquals(true, options.showGrandTotalRow, 'Default showGrandTotalRow');
        System.assertEquals(false, options.showSubtotals, 'Default showSubtotals');
        System.assertEquals('SUBTOTAL', options.subtotalLabel, 'Default subtotalLabel');
        System.assertEquals(false, options.fillMissingCategories, 'Default fillMissingCategories');
        System.assertNotEquals(null, options.dimensionConstants, 'dimensionConstants not null');
        System.assertNotEquals(null, options.columnAliases, 'columnAliases not null');
        System.assertNotEquals(null, options.calculatedFields, 'calculatedFields not null');
    }
    
    @IsTest
    static void testMergeOptionsValidation() {
        MergeOptions options = new MergeOptions();
        options.mergeMode = 'UNION';
        options.sortDirection = 'DESC';
        options.maxRows = 500;
        options.showSubtotals = true;
        options.subtotalLabel = 'SUB';
        
        List<String> warnings = options.validate();
        
        System.assertEquals(0, warnings.size(), 'Valid options should produce no warnings');
        System.assertEquals('UNION', options.mergeMode);
        System.assertEquals('DESC', options.sortDirection);
        System.assertEquals(500, options.maxRows);
        System.assertEquals(true, options.showSubtotals);
        System.assertEquals('SUB', options.subtotalLabel);
    }
    
    @IsTest
    static void testMergeOptionsInvalidValues() {
        MergeOptions options = new MergeOptions();
        options.mergeMode = 'WRONG';
        options.sortDirection = 'BAD';
        options.maxRows = 5000;
        options.subtotalLabel = '';
        options.dimensionConstants = null;
        options.columnAliases = null;
        options.calculatedFields = null;
        
        List<String> warnings = options.validate();
        
        System.assert(warnings.size() > 0, 'Invalid options should produce warnings');
        System.assertEquals('OUTER_JOIN', options.mergeMode, 'Invalid mode defaults to OUTER_JOIN');
        System.assertEquals('ASC', options.sortDirection, 'Invalid direction defaults to ASC');
        System.assertEquals(2000, options.maxRows, 'Max rows capped at 2000');
        System.assertEquals('SUBTOTAL', options.subtotalLabel, 'Empty label defaults to SUBTOTAL');
        System.assertNotEquals(null, options.dimensionConstants);
        System.assertNotEquals(null, options.columnAliases);
        System.assertNotEquals(null, options.calculatedFields);
    }
    
    @IsTest
    static void testMergeOptionsIsUnionMode() {
        MergeOptions options = new MergeOptions();
        System.assertEquals(false, options.isUnionMode(), 'Default is not UNION');
        System.assertEquals(false, options.isInnerJoin(), 'Default is not INNER_JOIN');
        System.assertEquals(true, options.isJoinMode(), 'Default is a JOIN mode');
        
        options.mergeMode = 'UNION';
        System.assertEquals(true, options.isUnionMode(), 'Should be UNION');
        System.assertEquals(false, options.isJoinMode(), 'Should not be JOIN');
        
        options.mergeMode = 'INNER_JOIN';
        System.assertEquals(false, options.isUnionMode(), 'Should not be UNION');
        System.assertEquals(true, options.isInnerJoin(), 'Should be INNER_JOIN');
        System.assertEquals(true, options.isJoinMode(), 'Should be JOIN mode');
    }
    
    @IsTest
    static void testMergeOptionsGetDimensionConstant() {
        MergeOptions options = new MergeOptions();
        options.dimensionConstants = new Map<String, String>{
            '1' => 'Total',
            '2' => 'Combined'
        };
        
        System.assertEquals('Total', options.getDimensionConstant(1));
        System.assertEquals('Combined', options.getDimensionConstant(2));
        System.assertEquals(null, options.getDimensionConstant(3));
    }
    
    @IsTest
    static void testMergeOptionsGetColumnAlias() {
        MergeOptions options = new MergeOptions();
        options.columnAliases = new Map<String, Object>{
            'Record Count' => 'Total',
            'Record Count (2)' => 'Other'
        };
        
        System.assertEquals('Total', options.getColumnAlias('Record Count'));
        System.assertEquals('Other', options.getColumnAlias('Record Count (2)'));
        System.assertEquals('Sum of Amount', options.getColumnAlias('Sum of Amount')); // No alias
    }
    
    @IsTest
    static void testMergeOptionsGetSortColumnIndex() {
        MergeOptions options = new MergeOptions();
        
        options.sortBy = 'KEY';
        System.assertEquals(0, options.getSortColumnIndex());
        
        options.sortBy = 'REPORT1_VALUE';
        System.assertEquals(1, options.getSortColumnIndex());
        
        options.sortBy = 'REPORT5_VALUE';
        System.assertEquals(5, options.getSortColumnIndex());
        
        options.sortBy = 'INVALID';
        System.assertEquals(0, options.getSortColumnIndex());
    }
    
    @IsTest
    static void testCalculatedFieldDefaults() {
        MergeOptions.CalculatedField calcField = new MergeOptions.CalculatedField();
        calcField.label = 'Difference';
        calcField.formula = 'r1_RowCount - r2_RowCount';
        
        System.assertEquals('Difference', calcField.label);
        System.assertEquals('r1_RowCount - r2_RowCount', calcField.formula);
        System.assertEquals('DOUBLE_DATA', calcField.dataType);
    }
    
    // ========================================================================
    // DTO TESTS
    // ========================================================================
    
    @IsTest
    static void testMergedGridDTODefaults() {
        MergedGridDTO dto = new MergedGridDTO();
        
        System.assertNotEquals(null, dto.columns);
        System.assertNotEquals(null, dto.rows);
        System.assertNotEquals(null, dto.warnings);
        System.assertNotEquals(null, dto.errors);
        System.assertEquals(0, dto.totalRowCount);
        System.assertEquals(false, dto.isTruncated);
        System.assertEquals(100, dto.keyOverlapPercentage);
        System.assertEquals(false, dto.hadDuplicates);
        System.assertEquals(false, dto.hasSecondDimension);
    }
    
    @IsTest
    static void testColumnDefinitionDefaults() {
        MergedGridDTO.ColumnDefinition col = new MergedGridDTO.ColumnDefinition();
        
        System.assertEquals(false, col.isKeyColumn);
        System.assertEquals(false, col.isSecondKeyColumn);
        System.assertEquals(false, col.isMergedColumn);
        System.assertNotEquals(null, col.sourceReportIndices);
    }
    
    @IsTest
    static void testColumnDefinitionConstructor() {
        MergedGridDTO.ColumnDefinition col = new MergedGridDTO.ColumnDefinition('key1', 'Label 1', 'STRING');
        
        System.assertEquals('key1', col.key);
        System.assertEquals('Label 1', col.label);
        System.assertEquals('STRING', col.dataType);
        System.assertEquals(false, col.isKeyColumn);
    }
    
    @IsTest
    static void testGridRowDefaults() {
        MergedGridDTO.GridRow row = new MergedGridDTO.GridRow();
        
        System.assertNotEquals(null, row.values);
        System.assertNotEquals(null, row.formattedValues);
        System.assertEquals(false, row.isTotalRow);
        System.assertEquals(false, row.isSubtotalRow);
    }
    
    @IsTest
    static void testGridRowConstructor() {
        MergedGridDTO.GridRow row = new MergedGridDTO.GridRow('key1', 'Label 1');
        
        System.assertEquals('key1', row.keyValue);
        System.assertEquals('Label 1', row.keyLabel);
        System.assertEquals(false, row.isTotalRow);
    }
    
    @IsTest
    static void testGridRowWithSecondDimension() {
        MergedGridDTO.GridRow row = new MergedGridDTO.GridRow();
        row.keyValue = 'Owner1';
        row.keyLabel = 'Ryan Goodman';
        row.secondKeyValue = 'Type1';
        row.secondKeyLabel = 'New Business';
        row.isSubtotalRow = false;
        row.sourceReportIndex = 0;
        
        System.assertEquals('Owner1', row.keyValue);
        System.assertEquals('Ryan Goodman', row.keyLabel);
        System.assertEquals('Type1', row.secondKeyValue);
        System.assertEquals('New Business', row.secondKeyLabel);
    }
    
    @IsTest
    static void testReportError() {
        MergedGridDTO.ReportError err = new MergedGridDTO.ReportError('00O000000000001', 'Test error', true);
        
        System.assertEquals('00O000000000001', err.reportId);
        System.assertEquals('Test error', err.message);
        System.assertEquals(true, err.isFatal);
    }
    
    @IsTest
    static void testAggregateInfo() {
        MergedGridDTO.AggregateInfo agg = new MergedGridDTO.AggregateInfo('s!Amount', 'Sum of Amount', 'CURRENCY_DATA', 0);
        
        System.assertEquals('s!Amount', agg.key);
        System.assertEquals('Sum of Amount', agg.label);
        System.assertEquals('CURRENCY_DATA', agg.dataType);
        System.assertEquals(0, agg.index);
    }
    
    @IsTest
    static void testDimensionInfo() {
        MergedGridDTO.DimensionInfo dim = new MergedGridDTO.DimensionInfo('StageName', 'Stage', 0);
        
        System.assertEquals('StageName', dim.fieldName);
        System.assertEquals('Stage', dim.label);
        System.assertEquals(0, dim.index);
    }
    
    @IsTest
    static void testParsedReportDataDefaults() {
        MergedGridDTO.ParsedReportData parsed = new MergedGridDTO.ParsedReportData();
        
        System.assertEquals(1, parsed.dimensionCount);
        System.assertNotEquals(null, parsed.aggregates);
        System.assertNotEquals(null, parsed.valuesByKeyByAggregate);
        System.assertNotEquals(null, parsed.labelsByKey);
        System.assertNotEquals(null, parsed.secondLabelsByKey);
        System.assertNotEquals(null, parsed.grandTotals);
        System.assertNotEquals(null, parsed.primaryKeys);
        System.assertNotEquals(null, parsed.secondaryKeys);
        System.assertEquals(true, parsed.isValid);
    }
    
    @IsTest
    static void testParsedReportDataTwoDimensions() {
        MergedGridDTO.ParsedReportData parsed = new MergedGridDTO.ParsedReportData();
        parsed.reportId = '00O000000000001';
        parsed.reportName = 'Test Report';
        parsed.reportIndex = 0;
        parsed.groupingField = 'Owner';
        parsed.groupingLabel = 'Owner Name';
        parsed.secondGroupingField = 'Type';
        parsed.secondGroupingLabel = 'Deal Type';
        parsed.dimensionCount = 2;
        
        // Add aggregate
        parsed.aggregates.add(new MergedGridDTO.AggregateInfo('RowCount', 'Record Count', 'INT_DATA', 0));
        
        // Add data
        String compositeKey = 'Owner1||Type1';
        parsed.primaryKeys.add('Owner1');
        parsed.secondaryKeys.add('Type1');
        parsed.labelsByKey.put(compositeKey, 'Ryan Goodman');
        parsed.secondLabelsByKey.put(compositeKey, 'New Business');
        parsed.valuesByKeyByAggregate.put(compositeKey, new Map<String, Decimal>{'RowCount' => 10});
        parsed.grandTotals.put('RowCount', 100);
        
        System.assertEquals('00O000000000001', parsed.reportId);
        System.assertEquals(2, parsed.dimensionCount);
        System.assertEquals(1, parsed.aggregates.size());
        System.assertEquals(1, parsed.valuesByKeyByAggregate.size());
        System.assertEquals(10, parsed.valuesByKeyByAggregate.get(compositeKey).get('RowCount'));
    }
    
    // ========================================================================
    // CONTROLLER VALIDATION TESTS
    // ========================================================================
    
    @IsTest
    static void testControllerNullReportIds() {
        Test.startTest();
        MergedGridDTO result = MergedReportController.getMergedReportData(null, null);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assert(result.errors.size() > 0);
        System.assert(result.errors[0].isFatal);
        System.assertEquals('No report IDs provided', result.errors[0].message);
    }
    
    @IsTest
    static void testControllerEmptyReportIds() {
        Test.startTest();
        MergedGridDTO result = MergedReportController.getMergedReportData(new List<Id>(), null);
        Test.stopTest();
        
        System.assert(result.errors.size() > 0);
        System.assertEquals('No report IDs provided', result.errors[0].message);
    }
    
    @IsTest
    static void testControllerSingleReportId() {
        List<Id> reportIds = new List<Id>{ '00O000000000001AAA' };
        
        Test.startTest();
        MergedGridDTO result = MergedReportController.getMergedReportData(reportIds, null);
        Test.stopTest();
        
        System.assert(result.errors.size() > 0);
        System.assertEquals('At least 2 report IDs are required', result.errors[0].message);
    }
    
    @IsTest
    static void testControllerTooManyReportIds() {
        List<Id> reportIds = new List<Id>{
            '00O000000000001AAA', '00O000000000002AAA', '00O000000000003AAA',
            '00O000000000004AAA', '00O000000000005AAA', '00O000000000006AAA'
        };
        
        Test.startTest();
        MergedGridDTO result = MergedReportController.getMergedReportData(reportIds, null);
        Test.stopTest();
        
        System.assert(result.errors.size() > 0);
        System.assertEquals('Maximum of 5 reports allowed', result.errors[0].message);
    }
    
    @IsTest
    static void testControllerDuplicateReportIds() {
        List<Id> reportIds = new List<Id>{ '00O000000000001AAA', '00O000000000001AAA' };
        
        Test.startTest();
        MergedGridDTO result = MergedReportController.getMergedReportData(reportIds, null);
        Test.stopTest();
        
        System.assert(result.errors.size() > 0);
        System.assert(result.errors[0].message.contains('Duplicate'));
    }
    
    @IsTest
    static void testControllerNullInReportIds() {
        List<Id> reportIds = new List<Id>{ '00O000000000001AAA', null };
        
        Test.startTest();
        MergedGridDTO result = MergedReportController.getMergedReportData(reportIds, null);
        Test.stopTest();
        
        System.assert(result.errors.size() > 0);
    }
    
    @IsTest
    static void testControllerInvalidOptionsJson() {
        List<Id> reportIds = new List<Id>{ '00O000000000001AAA', '00O000000000002AAA' };
        
        Test.startTest();
        MergedGridDTO result = MergedReportController.getMergedReportData(reportIds, 'not valid json');
        Test.stopTest();
        
        // Should not crash - just use defaults
        System.assertNotEquals(null, result);
    }
    
    @IsTest
    static void testControllerValidJoinOptions() {
        List<Id> reportIds = new List<Id>{ '00O000000000001AAA', '00O000000000002AAA' };
        
        String optionsJson = JSON.serialize(new Map<String, Object>{
            'mergeMode' => 'INNER_JOIN',
            'missingValueAsZero' => true,
            'sortBy' => 'REPORT1_VALUE',
            'sortDirection' => 'DESC',
            'maxRows' => 100,
            'showGrandTotalRow' => false,
            'columnAliases' => new Map<String, Object>{'Record Count' => 'Total'}
        });
        
        Test.startTest();
        MergedGridDTO result = MergedReportController.getMergedReportData(reportIds, optionsJson);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
    }
    
    @IsTest
    static void testControllerValidUnionOptions() {
        List<Id> reportIds = new List<Id>{ '00O000000000001AAA', '00O000000000002AAA' };
        
        String optionsJson = JSON.serialize(new Map<String, Object>{
            'mergeMode' => 'UNION',
            'showSubtotals' => true,
            'subtotalLabel' => 'SUB',
            'fillMissingCategories' => true,
            'sortGroupsBy' => 'merged_Record_Count',
            'dimensionConstants' => new Map<String, String>{'2' => 'Total'}
        });
        
        Test.startTest();
        MergedGridDTO result = MergedReportController.getMergedReportData(reportIds, optionsJson);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
    }
    
    // ========================================================================
    // COMPARATOR TESTS
    // ========================================================================
    
    @IsTest
    static void testKeyLabelComparatorAscending() {
        MergedGridDTO.GridRow rowA = new MergedGridDTO.GridRow('a', 'Apple');
        MergedGridDTO.GridRow rowB = new MergedGridDTO.GridRow('b', 'Banana');
        MergedGridDTO.GridRow rowNull = new MergedGridDTO.GridRow('c', null);
        
        MergedReportController.KeyLabelComparator comp = new MergedReportController.KeyLabelComparator(true);
        
        System.assert(comp.compare(rowA, rowB) < 0, 'Apple < Banana ASC');
        System.assert(comp.compare(rowB, rowA) > 0, 'Banana > Apple ASC');
        System.assertEquals(0, comp.compare(rowA, rowA), 'Same equals 0');
        System.assert(comp.compare(rowNull, rowA) < 0, 'Null treated as empty');
    }
    
    @IsTest
    static void testKeyLabelComparatorDescending() {
        MergedGridDTO.GridRow rowA = new MergedGridDTO.GridRow('a', 'Apple');
        MergedGridDTO.GridRow rowB = new MergedGridDTO.GridRow('b', 'Banana');
        
        MergedReportController.KeyLabelComparator comp = new MergedReportController.KeyLabelComparator(false);
        
        System.assert(comp.compare(rowA, rowB) > 0, 'Apple > Banana DESC');
        System.assert(comp.compare(rowB, rowA) < 0, 'Banana < Apple DESC');
    }
    
    @IsTest
    static void testColumnValueComparatorAscending() {
        MergedGridDTO.GridRow row10 = new MergedGridDTO.GridRow('a', 'A');
        row10.values.put('col1', 10);
        
        MergedGridDTO.GridRow row20 = new MergedGridDTO.GridRow('b', 'B');
        row20.values.put('col1', 20);
        
        MergedGridDTO.GridRow rowNull = new MergedGridDTO.GridRow('c', 'C');
        rowNull.values.put('col1', null);
        
        MergedReportController.ColumnValueComparator comp = 
            new MergedReportController.ColumnValueComparator('col1', true);
        
        System.assert(comp.compare(row10, row20) < 0, '10 < 20 ASC');
        System.assert(comp.compare(row20, row10) > 0, '20 > 10 ASC');
        System.assertEquals(0, comp.compare(row10, row10), 'Same equals 0');
        System.assert(comp.compare(rowNull, row10) < 0, 'Null first in ASC');
        System.assertEquals(0, comp.compare(rowNull, rowNull), 'Two nulls equal');
    }
    
    @IsTest
    static void testColumnValueComparatorDescending() {
        MergedGridDTO.GridRow row10 = new MergedGridDTO.GridRow('a', 'A');
        row10.values.put('col1', 10);
        
        MergedGridDTO.GridRow row20 = new MergedGridDTO.GridRow('b', 'B');
        row20.values.put('col1', 20);
        
        MergedGridDTO.GridRow rowNull = new MergedGridDTO.GridRow('c', 'C');
        rowNull.values.put('col1', null);
        
        MergedReportController.ColumnValueComparator comp = 
            new MergedReportController.ColumnValueComparator('col1', false);
        
        System.assert(comp.compare(row10, row20) > 0, '10 > 20 DESC');
        System.assert(comp.compare(row20, row10) < 0, '20 < 10 DESC');
        System.assert(comp.compare(rowNull, row10) > 0, 'Null last in DESC');
    }
    
    @IsTest
    static void testSecondKeyComparatorAscending() {
        MergedGridDTO.GridRow rowA = new MergedGridDTO.GridRow();
        rowA.secondKeyLabel = 'Alpha';
        
        MergedGridDTO.GridRow rowB = new MergedGridDTO.GridRow();
        rowB.secondKeyLabel = 'Beta';
        
        MergedGridDTO.GridRow rowNull = new MergedGridDTO.GridRow();
        rowNull.secondKeyLabel = null;
        
        MergedReportController.SecondKeyComparator comp = 
            new MergedReportController.SecondKeyComparator(true);
        
        System.assert(comp.compare(rowA, rowB) < 0, 'Alpha < Beta ASC');
        System.assert(comp.compare(rowB, rowA) > 0, 'Beta > Alpha ASC');
        System.assert(comp.compare(rowNull, rowA) < 0, 'Null < Alpha ASC');
    }
    
    @IsTest
    static void testSecondKeyComparatorDescending() {
        MergedGridDTO.GridRow rowA = new MergedGridDTO.GridRow();
        rowA.secondKeyLabel = 'Alpha';
        
        MergedGridDTO.GridRow rowB = new MergedGridDTO.GridRow();
        rowB.secondKeyLabel = 'Beta';
        
        MergedReportController.SecondKeyComparator comp = 
            new MergedReportController.SecondKeyComparator(false);
        
        System.assert(comp.compare(rowA, rowB) > 0, 'Alpha > Beta DESC');
        System.assert(comp.compare(rowB, rowA) < 0, 'Beta < Alpha DESC');
    }
    
    @IsTest
    static void testGroupSortWrapper() {
        MergedReportController.GroupSortWrapper w1 = 
            new MergedReportController.GroupSortWrapper('key1', 100);
        MergedReportController.GroupSortWrapper w2 = 
            new MergedReportController.GroupSortWrapper('key2', 200);
        MergedReportController.GroupSortWrapper w3 = 
            new MergedReportController.GroupSortWrapper('key3', null);
        
        System.assertEquals('key1', w1.key);
        System.assertEquals(100, w1.value);
        System.assertEquals(0, w3.value, 'Null value becomes 0');
        
        System.assert(w1.compareTo(w2) < 0, '100 < 200');
        System.assert(w2.compareTo(w1) > 0, '200 > 100');
        System.assertEquals(0, w1.compareTo(w1), 'Same equals 0');
    }
    
    // ========================================================================
    // PROCESSING TIME TEST
    // ========================================================================
    
    @IsTest
    static void testProcessingTimeRecorded() {
        List<Id> reportIds = new List<Id>{ '00O000000000001AAA', '00O000000000002AAA' };
        
        Test.startTest();
        MergedGridDTO result = MergedReportController.getMergedReportData(reportIds, null);
        Test.stopTest();
        
        System.assertNotEquals(null, result.processingTimeMs);
        System.assert(result.processingTimeMs >= 0);
    }
    
    // ========================================================================
    // CONSTANTS TESTS
    // ========================================================================
    
    @IsTest
    static void testMergeOptionsConstants() {
        System.assertEquals('OUTER_JOIN', MergeOptions.MERGE_MODE_OUTER_JOIN);
        System.assertEquals('INNER_JOIN', MergeOptions.MERGE_MODE_INNER_JOIN);
        System.assertEquals('UNION', MergeOptions.MERGE_MODE_UNION);
        System.assertEquals('KEY', MergeOptions.SORT_BY_KEY);
        System.assertEquals('ASC', MergeOptions.SORT_DIRECTION_ASC);
        System.assertEquals('DESC', MergeOptions.SORT_DIRECTION_DESC);
        System.assertEquals(2000, MergeOptions.MAX_ROWS_LIMIT);
        System.assertEquals(200, MergeOptions.DEFAULT_MAX_ROWS);
        System.assertEquals('SUBTOTAL', MergeOptions.DEFAULT_SUBTOTAL_LABEL);
    }
    
    // ========================================================================
    // GRID ROW VALUE OPERATIONS
    // ========================================================================
    
    @IsTest
    static void testGridRowValueOperations() {
        MergedGridDTO.GridRow row = new MergedGridDTO.GridRow('key1', 'Label 1');
        
        row.values.put('r1_Amount', 100.50);
        row.values.put('r2_Amount', 200.75);
        row.values.put('merged_Count', 50);
        row.formattedValues.put('r1_Amount', '100.50');
        row.formattedValues.put('r2_Amount', '200.75');
        row.formattedValues.put('merged_Count', '50');
        
        System.assertEquals(100.50, row.values.get('r1_Amount'));
        System.assertEquals(200.75, row.values.get('r2_Amount'));
        System.assertEquals(50, row.values.get('merged_Count'));
        System.assertEquals('100.50', row.formattedValues.get('r1_Amount'));
    }
    
    // ========================================================================
    // COLUMN DEFINITION PROPERTIES
    // ========================================================================
    
    @IsTest
    static void testColumnDefinitionAllProperties() {
        MergedGridDTO.ColumnDefinition col = new MergedGridDTO.ColumnDefinition();
        
        col.key = 'merged_Amount';
        col.label = 'Total Amount';
        col.dataType = 'CURRENCY_DATA';
        col.reportId = '00O000000000001AAA';
        col.reportName = 'Sales Report';
        col.aggregateKey = 's!Amount';
        col.aggregateLabel = 'Sum of Amount';
        col.isKeyColumn = false;
        col.isSecondKeyColumn = false;
        col.isMergedColumn = true;
        col.currencyCode = 'USD';
        col.reportIndex = 0;
        col.sourceReportIndices = new List<Integer>{0, 1};
        
        System.assertEquals('merged_Amount', col.key);
        System.assertEquals('Total Amount', col.label);
        System.assertEquals(true, col.isMergedColumn);
        System.assertEquals(2, col.sourceReportIndices.size());
    }
    
    // ========================================================================
    // REPORT ERROR PROPERTIES
    // ========================================================================
    
    @IsTest
    static void testReportErrorAllProperties() {
        MergedGridDTO.ReportError err = new MergedGridDTO.ReportError();
        
        err.reportId = '00O000000000001AAA';
        err.reportName = 'Test Report';
        err.message = 'Dimension mismatch';
        err.isFatal = true;
        err.errorCode = 'DIMENSION_ERROR';
        
        System.assertEquals('00O000000000001AAA', err.reportId);
        System.assertEquals('Test Report', err.reportName);
        System.assertEquals('Dimension mismatch', err.message);
        System.assertEquals(true, err.isFatal);
        System.assertEquals('DIMENSION_ERROR', err.errorCode);
    }
    
    // ========================================================================
    // COMPLEX DTO SCENARIOS
    // ========================================================================
    
    @IsTest
    static void testMergedGridDTOCompleteJoinScenario() {
        MergedGridDTO dto = new MergedGridDTO();
        dto.hasSecondDimension = false;
        
        // Key column
        MergedGridDTO.ColumnDefinition keyCol = new MergedGridDTO.ColumnDefinition('keyLabel', 'Owner', 'STRING');
        keyCol.isKeyColumn = true;
        dto.columns.add(keyCol);
        
        // Report 1 columns
        dto.columns.add(new MergedGridDTO.ColumnDefinition('r1_Amount', 'Amount', 'CURRENCY_DATA'));
        dto.columns.add(new MergedGridDTO.ColumnDefinition('r1_Count', 'Count', 'INT_DATA'));
        
        // Report 2 columns  
        dto.columns.add(new MergedGridDTO.ColumnDefinition('r2_Amount', 'Amount (2)', 'CURRENCY_DATA'));
        
        // Data rows
        MergedGridDTO.GridRow row1 = new MergedGridDTO.GridRow('owner1', 'Ryan Goodman');
        row1.values.put('r1_Amount', 1000);
        row1.values.put('r1_Count', 10);
        row1.values.put('r2_Amount', 500);
        dto.rows.add(row1);
        
        MergedGridDTO.GridRow row2 = new MergedGridDTO.GridRow('owner2', 'Jane Smith');
        row2.values.put('r1_Amount', 2000);
        row2.values.put('r1_Count', 20);
        row2.values.put('r2_Amount', 1500);
        dto.rows.add(row2);
        
        // Totals
        MergedGridDTO.GridRow totals = new MergedGridDTO.GridRow('TOTAL', 'Total');
        totals.isTotalRow = true;
        totals.values.put('r1_Amount', 3000);
        totals.values.put('r1_Count', 30);
        totals.values.put('r2_Amount', 2000);
        dto.totalsRow = totals;
        
        dto.totalRowCount = 2;
        dto.keyOverlapPercentage = 100;
        
        System.assertEquals(4, dto.columns.size());
        System.assertEquals(2, dto.rows.size());
        System.assertNotEquals(null, dto.totalsRow);
        System.assertEquals(false, dto.hasSecondDimension);
    }
    
    @IsTest
    static void testMergedGridDTOCompleteUnionScenario() {
        MergedGridDTO dto = new MergedGridDTO();
        dto.hasSecondDimension = true;
        dto.secondDimensionLabel = 'Deal Type';
        
        // Key columns
        MergedGridDTO.ColumnDefinition keyCol = new MergedGridDTO.ColumnDefinition('keyLabel', 'Owner', 'STRING');
        keyCol.isKeyColumn = true;
        dto.columns.add(keyCol);
        
        MergedGridDTO.ColumnDefinition secondKeyCol = new MergedGridDTO.ColumnDefinition('secondKeyLabel', 'Deal Type', 'STRING');
        secondKeyCol.isSecondKeyColumn = true;
        dto.columns.add(secondKeyCol);
        
        // Merged column (appears in both reports)
        MergedGridDTO.ColumnDefinition mergedCol = new MergedGridDTO.ColumnDefinition('merged_Count', 'Record Count', 'INT_DATA');
        mergedCol.isMergedColumn = true;
        mergedCol.sourceReportIndices = new List<Integer>{0, 1};
        dto.columns.add(mergedCol);
        
        // Non-merged column (only in report 1)
        MergedGridDTO.ColumnDefinition r1Col = new MergedGridDTO.ColumnDefinition('r1_Amount', 'Amount', 'CURRENCY_DATA');
        r1Col.reportIndex = 0;
        dto.columns.add(r1Col);
        
        // Data rows - Owner 1, New Business (from Report 1)
        MergedGridDTO.GridRow row1 = new MergedGridDTO.GridRow();
        row1.keyValue = 'owner1';
        row1.keyLabel = 'Ryan Goodman';
        row1.secondKeyValue = 'new';
        row1.secondKeyLabel = 'New Business';
        row1.sourceReportIndex = 0;
        row1.values.put('merged_Count', 10);
        row1.values.put('r1_Amount', 5000);
        dto.rows.add(row1);
        
        // Data rows - Owner 1, Renewal (from Report 1)
        MergedGridDTO.GridRow row2 = new MergedGridDTO.GridRow();
        row2.keyValue = 'owner1';
        row2.keyLabel = 'Ryan Goodman';
        row2.secondKeyValue = 'renewal';
        row2.secondKeyLabel = 'Renewal';
        row2.sourceReportIndex = 0;
        row2.values.put('merged_Count', 5);
        row2.values.put('r1_Amount', 2000);
        dto.rows.add(row2);
        
        // Data rows - Owner 1, TOTAL (from Report 2 with constant)
        MergedGridDTO.GridRow row3 = new MergedGridDTO.GridRow();
        row3.keyValue = 'owner1';
        row3.keyLabel = 'Ryan Goodman';
        row3.secondKeyValue = 'total';
        row3.secondKeyLabel = 'TOTAL';
        row3.sourceReportIndex = 1;
        row3.values.put('merged_Count', 15);
        dto.rows.add(row3);
        
        // Subtotal row
        MergedGridDTO.GridRow subtotal = new MergedGridDTO.GridRow();
        subtotal.keyValue = 'owner1';
        subtotal.keyLabel = 'Ryan Goodman';
        subtotal.secondKeyValue = 'SUBTOTAL';
        subtotal.secondKeyLabel = 'SUBTOTAL';
        subtotal.isSubtotalRow = true;
        subtotal.values.put('merged_Count', 30);
        dto.rows.add(subtotal);
        
        dto.totalRowCount = 4;
        
        System.assertEquals(4, dto.columns.size());
        System.assertEquals(4, dto.rows.size());
        System.assertEquals(true, dto.hasSecondDimension);
        System.assertEquals('Deal Type', dto.secondDimensionLabel);
        System.assertEquals(true, dto.rows[3].isSubtotalRow);
    }
    
    // ========================================================================
    // EDGE CASES
    // ========================================================================
    
    @IsTest
    static void testGridRowWithAllNullValues() {
        MergedGridDTO.GridRow row = new MergedGridDTO.GridRow();
        row.keyValue = null;
        row.keyLabel = null;
        row.secondKeyValue = null;
        row.secondKeyLabel = null;
        
        System.assertEquals(null, row.keyValue);
        System.assertEquals(null, row.keyLabel);
    }
    
    @IsTest
    static void testColumnDefinitionWithEmptySourceIndices() {
        MergedGridDTO.ColumnDefinition col = new MergedGridDTO.ColumnDefinition();
        col.sourceReportIndices = new List<Integer>();
        
        System.assertEquals(0, col.sourceReportIndices.size());
    }
    
    @IsTest
    static void testParsedReportDataWithEmptyCollections() {
        MergedGridDTO.ParsedReportData parsed = new MergedGridDTO.ParsedReportData();
        
        System.assertEquals(0, parsed.aggregates.size());
        System.assertEquals(0, parsed.valuesByKeyByAggregate.size());
        System.assertEquals(0, parsed.primaryKeys.size());
        System.assertEquals(0, parsed.secondaryKeys.size());
    }
    
    @IsTest
    static void testMergeOptionsWithEmptyAliasMap() {
        MergeOptions options = new MergeOptions();
        options.columnAliases = new Map<String, Object>();
        
        // Should return original when no alias exists
        System.assertEquals('Test Column', options.getColumnAlias('Test Column'));
    }
    
    @IsTest
    static void testMergeOptionsWithEmptyDimensionConstants() {
        MergeOptions options = new MergeOptions();
        options.dimensionConstants = new Map<String, String>();
        
        System.assertEquals(null, options.getDimensionConstant(1));
        System.assertEquals(null, options.getDimensionConstant(2));
    }
}