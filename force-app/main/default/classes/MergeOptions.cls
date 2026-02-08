/**
 * @description Options for configuring the merged report grid behavior
 * @author DataTools Pro
 */
public class MergeOptions {
    
    /**
     * @description Merge mode - determines how reports are combined
     * OUTER_JOIN: Horizontal merge, all keys (default)
     * INNER_JOIN: Horizontal merge, only matching keys
     * UNION: Vertical stack, allows different 2nd dimensions
     */
    @AuraEnabled public String mergeMode { get; set; }
    
    /**
     * @description Data visibility scope - controls whose data is shown
     * ALL: Use report's configured scope (default)
     * MY_RECORDS: Override to show only current user's records
     * MY_TEAM: Override to show current user's team records (subordinates)
     */
    @AuraEnabled public String dataVisibility { get; set; }
    
    /**
     * @description If true, missing values are rendered as 0; otherwise blank
     */
    @AuraEnabled public Boolean missingValueAsZero { get; set; }
    
    /**
     * @description Column to sort by: KEY, or a column key like r1_RowCount
     */
    @AuraEnabled public String sortBy { get; set; }
    
    /**
     * @description Sort direction: ASC or DESC
     */
    @AuraEnabled public String sortDirection { get; set; }
    
    /**
     * @description For UNION mode with 2 dimensions - sort groups by aggregate of this column
     * Groups stay together, but group order is determined by sum of this column
     */
    @AuraEnabled public String sortGroupsBy { get; set; }
    
    /**
     * @description Maximum rows to return (hard cap 2000)
     */
    @AuraEnabled public Integer maxRows { get; set; }
    
    /**
     * @description Whether to include a grand total row
     */
    @AuraEnabled public Boolean showGrandTotalRow { get; set; }
    
    /**
     * @description Whether to show subtotal rows per primary group (UNION mode with 2 dims)
     */
    @AuraEnabled public Boolean showSubtotals { get; set; }
    
    /**
     * @description Label for subtotal rows (default: "SUBTOTAL")
     */
    @AuraEnabled public String subtotalLabel { get; set; }
    
    /**
     * @description Fill missing category combinations with zeros (UNION mode)
     */
    @AuraEnabled public Boolean fillMissingCategories { get; set; }
    
    /**
     * @description Constants for reports missing 2nd dimension in UNION mode
     * Format: { "1": "Total", "2": "Combined" } - report index (1-based) to constant value
     */
    @AuraEnabled public Map<String, String> dimensionConstants { get; set; }
    
    /**
     * @description Column aliases - maps original aggregate label to display alias
     * Format: { "Record Count": "Metric_Value", "Sum of Amount": "Revenue" }
     * Matches by EXACT column name (including suffix like "(2)")
     */
    @AuraEnabled public Map<String, String> columnAliases { get; set; }
    
    /**
     * @description Calculated fields configuration
     * Format: [{ "label": "Difference", "formula": "r1_RowCount - r2_RowCount" }]
     */
    @AuraEnabled public List<CalculatedField> calculatedFields { get; set; }
    
    // Constants
    public static final String MERGE_MODE_OUTER_JOIN = 'OUTER_JOIN';
    public static final String MERGE_MODE_INNER_JOIN = 'INNER_JOIN';
    public static final String MERGE_MODE_UNION = 'UNION';
    public static final String DATA_VISIBILITY_ALL = 'ALL';
    public static final String DATA_VISIBILITY_MY_RECORDS = 'MY_RECORDS';
    public static final String DATA_VISIBILITY_MY_TEAM = 'MY_TEAM';
    public static final String SORT_BY_KEY = 'KEY';
    public static final String SORT_DIRECTION_ASC = 'ASC';
    public static final String SORT_DIRECTION_DESC = 'DESC';
    public static final Integer MAX_ROWS_LIMIT = 2000;
    public static final Integer DEFAULT_MAX_ROWS = 200;
    public static final String DEFAULT_SUBTOTAL_LABEL = 'SUBTOTAL';
    
    /**
     * @description Calculated field definition
     */
    public class CalculatedField {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String formula { get; set; }
        @AuraEnabled public String dataType { get; set; }
        
        public CalculatedField() {
            this.dataType = 'DOUBLE_DATA';
        }
    }
    
    /**
     * @description Default constructor with sensible defaults
     */
    public MergeOptions() {
        this.mergeMode = MERGE_MODE_OUTER_JOIN;
        this.dataVisibility = DATA_VISIBILITY_ALL;
        this.missingValueAsZero = false;
        this.sortBy = SORT_BY_KEY;
        this.sortDirection = SORT_DIRECTION_ASC;
        this.sortGroupsBy = null;
        this.maxRows = DEFAULT_MAX_ROWS;
        this.showGrandTotalRow = true;
        this.showSubtotals = false;
        this.subtotalLabel = DEFAULT_SUBTOTAL_LABEL;
        this.fillMissingCategories = false;
        this.dimensionConstants = new Map<String, String>();
        this.columnAliases = new Map<String, String>();
        this.calculatedFields = new List<CalculatedField>();
    }
    
    /**
     * @description Validates and normalizes the options
     * @return List of validation warnings (empty if all valid)
     */
    public List<String> validate() {
        List<String> warnings = new List<String>();
        
        // Validate merge mode
        if (String.isBlank(this.mergeMode)) {
            this.mergeMode = MERGE_MODE_OUTER_JOIN;
        } else {
            this.mergeMode = this.mergeMode.toUpperCase();
            if (this.mergeMode != MERGE_MODE_OUTER_JOIN && 
                this.mergeMode != MERGE_MODE_INNER_JOIN && 
                this.mergeMode != MERGE_MODE_UNION) {
                warnings.add('Invalid mergeMode "' + this.mergeMode + '". Use OUTER_JOIN, INNER_JOIN, or UNION.');
                this.mergeMode = MERGE_MODE_OUTER_JOIN;
            }
        }
        
        // Validate data visibility
        if (String.isBlank(this.dataVisibility)) {
            this.dataVisibility = DATA_VISIBILITY_ALL;
        } else {
            this.dataVisibility = this.dataVisibility.toUpperCase();
            if (this.dataVisibility != DATA_VISIBILITY_ALL && 
                this.dataVisibility != DATA_VISIBILITY_MY_RECORDS && 
                this.dataVisibility != DATA_VISIBILITY_MY_TEAM) {
                warnings.add('Invalid dataVisibility "' + this.dataVisibility + '". Use ALL, MY_RECORDS, or MY_TEAM.');
                this.dataVisibility = DATA_VISIBILITY_ALL;
            }
        }
        
        // Normalize sort direction
        if (String.isBlank(this.sortDirection)) {
            this.sortDirection = SORT_DIRECTION_ASC;
        } else {
            this.sortDirection = this.sortDirection.toUpperCase();
            if (this.sortDirection != SORT_DIRECTION_ASC && this.sortDirection != SORT_DIRECTION_DESC) {
                warnings.add('Invalid sortDirection "' + this.sortDirection + '", defaulting to ASC');
                this.sortDirection = SORT_DIRECTION_ASC;
            }
        }
        
        // Normalize sort by
        if (String.isBlank(this.sortBy)) {
            this.sortBy = SORT_BY_KEY;
        } else {
            this.sortBy = this.sortBy.toUpperCase();
        }
        
        // Normalize max rows
        if (this.maxRows == null || this.maxRows <= 0) {
            this.maxRows = DEFAULT_MAX_ROWS;
        } else if (this.maxRows > MAX_ROWS_LIMIT) {
            warnings.add('maxRows ' + this.maxRows + ' exceeds limit, capping at ' + MAX_ROWS_LIMIT);
            this.maxRows = MAX_ROWS_LIMIT;
        }
        
        // Default booleans
        if (this.missingValueAsZero == null) {
            this.missingValueAsZero = false;
        }
        if (this.showGrandTotalRow == null) {
            this.showGrandTotalRow = true;
        }
        if (this.showSubtotals == null) {
            this.showSubtotals = false;
        }
        if (this.fillMissingCategories == null) {
            this.fillMissingCategories = false;
        }
        if (String.isBlank(this.subtotalLabel)) {
            this.subtotalLabel = DEFAULT_SUBTOTAL_LABEL;
        }
        if (this.dimensionConstants == null) {
            this.dimensionConstants = new Map<String, String>();
        }
        if (this.columnAliases == null) {
            this.columnAliases = new Map<String, String>();
        }
        if (this.calculatedFields == null) {
            this.calculatedFields = new List<CalculatedField>();
        }
        
        return warnings;
    }
    
    /**
     * @description Gets the sort column index (0 = key, 1+ = report values)
     * @return The column index to sort by
     */
    public Integer getSortColumnIndex() {
        if (this.sortBy == SORT_BY_KEY || String.isBlank(this.sortBy)) {
            return 0;
        }
        // Parse REPORT1_VALUE, REPORT2_VALUE, etc.
        if (this.sortBy.startsWith('REPORT') && this.sortBy.endsWith('_VALUE')) {
            String numStr = this.sortBy.removeStart('REPORT').removeEnd('_VALUE');
            try {
                return Integer.valueOf(numStr);
            } catch (Exception e) {
                return 0;
            }
        }
        return 0;
    }
    
    /**
     * @description Gets the alias for a column label, or returns the original if no match
     * Matches by EXACT original label - safe even if columns are reordered
     */
    public String getColumnAlias(String originalLabel) {
        if (this.columnAliases != null && this.columnAliases.containsKey(originalLabel)) {
            return this.columnAliases.get(originalLabel);
        }
        return originalLabel;
    }
    
    /**
     * @description Gets the dimension constant for a report (1-based index)
     */
    public String getDimensionConstant(Integer reportIndex) {
        String key = String.valueOf(reportIndex);
        if (this.dimensionConstants != null && this.dimensionConstants.containsKey(key)) {
            return this.dimensionConstants.get(key);
        }
        return null;
    }
    
    /**
     * @description Check if using UNION mode
     */
    public Boolean isUnionMode() {
        return this.mergeMode == MERGE_MODE_UNION;
    }
    
    /**
     * @description Check if using INNER JOIN mode
     */
    public Boolean isInnerJoin() {
        return this.mergeMode == MERGE_MODE_INNER_JOIN;
    }
    
    /**
     * @description Check if using any JOIN mode (INNER or OUTER)
     */
    public Boolean isJoinMode() {
        return this.mergeMode == MERGE_MODE_OUTER_JOIN || this.mergeMode == MERGE_MODE_INNER_JOIN;
    }
    
    /**
     * @description Get the report scope to use based on dataVisibility setting
     * Returns null if using report's default (ALL), otherwise returns the scope string
     */
    public String getReportScope() {
        if (this.dataVisibility == DATA_VISIBILITY_MY_RECORDS) {
            return 'user';
        } else if (this.dataVisibility == DATA_VISIBILITY_MY_TEAM) {
            return 'team';
        }
        return null; // Use report's configured scope
    }
    
    /**
     * @description Check if we need to override the report scope
     */
    public Boolean shouldOverrideScope() {
        return this.dataVisibility != null && this.dataVisibility != DATA_VISIBILITY_ALL;
    }
}