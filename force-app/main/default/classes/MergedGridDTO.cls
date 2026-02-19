/**
 * @description Data Transfer Object for merged report grid results
 */
public class MergedGridDTO {
    
    /**
     * @description Column definitions for the grid
     */
    @AuraEnabled public List<ColumnDefinition> columns { get; set; }
    
    /**
     * @description Data rows for the grid
     */
    @AuraEnabled public List<GridRow> rows { get; set; }
    
    /**
     * @description Grand total row (if enabled)
     */
    @AuraEnabled public GridRow totalsRow { get; set; }
    
    /**
     * @description Non-fatal warnings to display
     */
    @AuraEnabled public List<String> warnings { get; set; }
    
    /**
     * @description Errors encountered during processing
     */
    @AuraEnabled public List<ReportError> errors { get; set; }
    
    /**
     * @description Total number of rows before limit was applied
     */
    @AuraEnabled public Integer totalRowCount { get; set; }
    
    /**
     * @description Whether the results were truncated due to maxRows
     */
    @AuraEnabled public Boolean isTruncated { get; set; }
    
    /**
     * @description Key overlap percentage (for mismatch warning)
     */
    @AuraEnabled public Decimal keyOverlapPercentage { get; set; }
    
    /**
     * @description Whether duplicates were detected and rolled up
     */
    @AuraEnabled public Boolean hadDuplicates { get; set; }
    
    /**
     * @description Map of report IDs to report names (for UI display)
     */
    @AuraEnabled public Map<String, String> reportNames { get; set; }
    
    /**
     * @description Processing time in milliseconds
     */
    @AuraEnabled public Long processingTimeMs { get; set; }
    
    /**
     * @description Whether the grid has a second dimension (UNION mode)
     */
    @AuraEnabled public Boolean hasSecondDimension { get; set; }
    
    /**
     * @description Label for the second dimension column
     */
    @AuraEnabled public String secondDimensionLabel { get; set; }
    
    public MergedGridDTO() {
        this.columns = new List<ColumnDefinition>();
        this.rows = new List<GridRow>();
        this.warnings = new List<String>();
        this.errors = new List<ReportError>();
        this.totalRowCount = 0;
        this.isTruncated = false;
        this.keyOverlapPercentage = 100;
        this.hadDuplicates = false;
        this.hasSecondDimension = false;
        this.reportNames = new Map<String, String>();
    }
    
    /**
     * @description Column definition for the grid
     */
    public class ColumnDefinition {
        @AuraEnabled public String key { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String dataType { get; set; }
        @AuraEnabled public String reportId { get; set; }
        @AuraEnabled public String reportName { get; set; }
        @AuraEnabled public String aggregateLabel { get; set; }
        @AuraEnabled public String aggregateKey { get; set; }
        @AuraEnabled public Boolean isKeyColumn { get; set; }
        @AuraEnabled public Boolean isSecondKeyColumn { get; set; }
        @AuraEnabled public Boolean isMergedColumn { get; set; }
        @AuraEnabled public String currencyCode { get; set; }
        @AuraEnabled public Integer reportIndex { get; set; }
        @AuraEnabled public List<Integer> sourceReportIndices { get; set; }
        // Custom format override from column aliases
        @AuraEnabled public String customFormat { get; set; }
        @AuraEnabled public Integer customDecimals { get; set; }
        @AuraEnabled public String customCurrencyCode { get; set; }
        // Original label before alias (for format lookup)
        public String originalLabel { get; set; }
        
        public ColumnDefinition() {
            this.isKeyColumn = false;
            this.isSecondKeyColumn = false;
            this.isMergedColumn = false;
            this.sourceReportIndices = new List<Integer>();
            this.customDecimals = 2;
        }
        
        public ColumnDefinition(String key, String label, String dataType) {
            this.key = key;
            this.label = label;
            this.dataType = dataType;
            this.isKeyColumn = false;
            this.isSecondKeyColumn = false;
            this.isMergedColumn = false;
            this.sourceReportIndices = new List<Integer>();
            this.customDecimals = 2;
        }
    }
    
    /**
     * @description Single row in the merged grid
     */
    public class GridRow {
        @AuraEnabled public String keyValue { get; set; }
        @AuraEnabled public String keyLabel { get; set; }
        @AuraEnabled public String secondKeyValue { get; set; }
        @AuraEnabled public String secondKeyLabel { get; set; }
        @AuraEnabled public Map<String, Decimal> values { get; set; }
        @AuraEnabled public Map<String, String> formattedValues { get; set; }
        @AuraEnabled public Boolean isTotalRow { get; set; }
        @AuraEnabled public Boolean isSubtotalRow { get; set; }
        @AuraEnabled public Integer sourceReportIndex { get; set; }
        
        public GridRow() {
            this.values = new Map<String, Decimal>();
            this.formattedValues = new Map<String, String>();
            this.isTotalRow = false;
            this.isSubtotalRow = false;
        }
        
        public GridRow(String keyValue, String keyLabel) {
            this();
            this.keyValue = keyValue;
            this.keyLabel = keyLabel;
        }
    }
    
    /**
     * @description Error information for a specific report
     */
    public class ReportError {
        @AuraEnabled public String reportId { get; set; }
        @AuraEnabled public String reportName { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Boolean isFatal { get; set; }
        @AuraEnabled public String errorCode { get; set; }
        
        public ReportError() {
            this.isFatal = false;
        }
        
        public ReportError(String reportId, String message, Boolean isFatal) {
            this.reportId = reportId;
            this.message = message;
            this.isFatal = isFatal;
        }
    }
    
    /**
     * @description Aggregate info from a report
     */
    public class AggregateInfo {
        public String key { get; set; }
        public String label { get; set; }
        public String dataType { get; set; }
        public Integer index { get; set; }
        
        public AggregateInfo(String key, String label, String dataType, Integer index) {
            this.key = key;
            this.label = label;
            this.dataType = dataType;
            this.index = index;
        }
    }
    
    /**
     * @description Dimension info from a report
     */
    public class DimensionInfo {
        public String fieldName { get; set; }
        public String label { get; set; }
        public Integer index { get; set; }
        
        public DimensionInfo(String fieldName, String label, Integer index) {
            this.fieldName = fieldName;
            this.label = label;
            this.index = index;
        }
    }
    
    /**
     * @description Internal class to hold parsed report data before merge
     */
    public class ParsedReportData {
        public String reportId { get; set; }
        public String reportName { get; set; }
        public Integer reportIndex { get; set; }
        public String groupingField { get; set; }
        public String groupingLabel { get; set; }
        public String secondGroupingField { get; set; }
        public String secondGroupingLabel { get; set; }
        public Integer dimensionCount { get; set; }
        public List<AggregateInfo> aggregates { get; set; }
        public String currencyCode { get; set; }
        // Map of composite key (dim1|dim2) -> (aggregate key -> value)
        public Map<String, Map<String, Decimal>> valuesByKeyByAggregate { get; set; }
        // Map of composite key -> primary label
        public Map<String, String> labelsByKey { get; set; }
        // Map of composite key -> secondary label
        public Map<String, String> secondLabelsByKey { get; set; }
        // Map of aggregate key -> grand total
        public Map<String, Decimal> grandTotals { get; set; }
        // All primary dimension values
        public Set<String> primaryKeys { get; set; }
        // All secondary dimension values
        public Set<String> secondaryKeys { get; set; }
        public Boolean isValid { get; set; }
        public String errorMessage { get; set; }
        
        public ParsedReportData() {
            this.dimensionCount = 1;
            this.aggregates = new List<AggregateInfo>();
            this.valuesByKeyByAggregate = new Map<String, Map<String, Decimal>>();
            this.labelsByKey = new Map<String, String>();
            this.secondLabelsByKey = new Map<String, String>();
            this.grandTotals = new Map<String, Decimal>();
            this.primaryKeys = new Set<String>();
            this.secondaryKeys = new Set<String>();
            this.isValid = true;
        }
    }
}