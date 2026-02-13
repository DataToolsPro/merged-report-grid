import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMergedReportData from '@salesforce/apex/MergedReportController.getMergedReportData';

const MERGE_MODE_OUTER_JOIN = 'OUTER_JOIN';
const SORT_DIRECTION_ASC = 'ASC';

export default class MergedReportGrid extends LightningElement {
    // ===== @api Properties - Simple declarations, no setters =====
    // Report IDs
    @api report1Id;
    @api report2Id;
    @api report3Id;
    @api report4Id;
    @api report5Id;
    
    // Merge Mode
    @api mergeMode = MERGE_MODE_OUTER_JOIN;
    
    // Data Visibility
    @api visibilityScope = 'ALL';
    
    // UNION Mode Options
    @api dimensionConstantsJson;
    @api showSubtotals = false;
    @api subtotalLabel = 'SUBTOTAL';
    @api fillMissingCategories = false;
    @api sortGroupsBy;
    
    // Column Configuration
    @api columnAliasesJson;
    @api calculatedFieldsJson;
    
    // Display Options
    @api missingValueAsZero = false;
    @api sortBy = 'KEY';
    @api sortDirection = SORT_DIRECTION_ASC;
    @api maxRows = 200;
    @api showGrandTotalRow;
    @api componentTitle;
    
    // Debug Mode
    @api debugMode = false;
    
    // Cache buster (required by managed package, not functionally used)
    @api refreshKey;
    
    // ===== Internal State =====
    @track gridData = null;
    @track isLoading = true;
    @track error = null;
    @track currentSortBy = null;
    @track currentSortDirection = null;
    @track showReportPopover = false;
    
    // Track fetch state
    _fetchTimer = null;
    _hasFetched = false;
    _lastOptionsJson = null;
    _lastStableOptionsJson = null; // Options without cache buster for comparison
    _isDesignMode = null; // Cached design mode check
    
    // ===== Design Mode Detection =====
    // Detects if we're in Lightning App Builder edit mode
    // In design mode: we add a cache-buster to prevent stale data
    // In runtime mode: we let Salesforce cache responses for performance
    get isInDesignMode() {
        if (this._isDesignMode === null) {
            try {
                const url = window.location.href;
                this._isDesignMode = url.includes('/flexipage/') || 
                                     url.includes('flexipageEditor') ||
                                     url.includes('/lightning/setup/');
            } catch (e) {
                this._isDesignMode = false;
            }
        }
        return this._isDesignMode;
    }
    
    // ===== Lifecycle =====
    connectedCallback() {
        this.currentSortBy = this.sortBy;
        this.currentSortDirection = this.sortDirection;
        
        // Simple approach: wait a moment for all properties to be set, then fetch
        // This handles both new components and saved configurations
        this._scheduleFetch();
    }
    
    disconnectedCallback() {
        if (this._fetchTimer) {
            clearTimeout(this._fetchTimer);
        }
    }
    
    // LWC calls renderedCallback after every render
    // We use this to detect property changes and re-fetch if needed
    renderedCallback() {
        // Use stable options (without cache buster) for comparison
        // to avoid infinite loops from the timestamp changing
        const currentOptions = this._buildStableOptionsJson();
        if (this._hasFetched && currentOptions !== this._lastStableOptionsJson) {
            // Properties changed - re-fetch
            this._scheduleFetch();
        }
    }
    
    // ===== Data Fetching =====
    _scheduleFetch() {
        // Clear any pending fetch
        if (this._fetchTimer) {
            clearTimeout(this._fetchTimer);
        }
        
        this.isLoading = true;
        
        // In design mode (App Builder), wait longer for properties to load
        // In runtime mode, use a shorter delay for better responsiveness
        const delay = this.isInDesignMode ? 500 : 100;
        
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._fetchTimer = setTimeout(() => {
            this._fetchData();
        }, delay);
    }
    
    async _fetchData() {
        // Build report IDs list from @api properties
        const reportIds = this._getReportIds();
        
        // Need at least 2 reports
        if (reportIds.length < 2) {
            this.isLoading = false;
            this.error = null;
            this.gridData = null;
            return;
        }
        
        // Build options JSON (with cache buster for API call)
        const optionsJson = this._buildOptionsJson();
        this._lastOptionsJson = optionsJson;
        
        // Store stable options (without cache buster) for comparison in renderedCallback
        this._lastStableOptionsJson = this._buildStableOptionsJson();
        
        this.isLoading = true;
        this.error = null;
        
        try {
            const data = await getMergedReportData({ reportIds, optionsJson });
            
            this._hasFetched = true;
            this.gridData = data;
            this.error = null;
            
            if (this.hasFatalErrors) {
                this.error = this.fatalErrorMessages.join('; ');
            }
            
            if (data.warnings && data.warnings.length > 0) {
                data.warnings.forEach(warning => {
                    this.showToast('Warning', warning, 'warning');
                });
            }
        } catch (err) {
            this.error = this.reduceError(err);
            this.gridData = null;
        } finally {
            this.isLoading = false;
        }
    }
    
    _getReportIds() {
        const ids = [];
        if (this.report1Id) ids.push(this.report1Id);
        if (this.report2Id) ids.push(this.report2Id);
        if (this.report3Id) ids.push(this.report3Id);
        if (this.report4Id) ids.push(this.report4Id);
        if (this.report5Id) ids.push(this.report5Id);
        return ids;
    }
    
    _buildOptionsJson() {
        // JSON size warning thresholds (10KB is very generous - realistic max is ~5KB)
        // These are warnings for debugging, not hard limits
        const JSON_SIZE_WARNING = 10000; // 10KB - warn if larger
        const JSON_SIZE_CRITICAL = 50000; // 50KB - critical warning
        
        let columnAliases = {};
        if (this.columnAliasesJson) {
            const size = this.columnAliasesJson.length;
            if (size > JSON_SIZE_CRITICAL) {
                this.showToast('Warning', `Column Aliases JSON is very large (${Math.round(size/1024)}KB). This may cause performance issues.`, 'warning');
            } else if (size > JSON_SIZE_WARNING) {
                this.showToast('Info', `Column Aliases JSON is large (${Math.round(size/1024)}KB). If you experience issues, consider reducing aliases.`, 'info');
            }
            try { 
                const parsed = JSON.parse(this.columnAliasesJson);
                // Validate structure - must be an object, not array
                if (typeof parsed === 'object' && !Array.isArray(parsed) && parsed !== null) {
                    columnAliases = parsed;
                } else {
                    this.showToast('Warning', 'Column Aliases should be a JSON object (e.g., {"Column": "Alias"}). Using empty object.', 'warning');
                }
            } catch (e) {
                this.showToast('Warning', 'Invalid Column Aliases JSON: ' + (e.message || 'Parse error') + '. Using empty object.', 'warning');
            }
        }
        
        let calculatedFields = [];
        if (this.calculatedFieldsJson) {
            const size = this.calculatedFieldsJson.length;
            if (size > JSON_SIZE_CRITICAL) {
                this.showToast('Warning', `Calculated Fields JSON is very large (${Math.round(size/1024)}KB). This may cause performance issues.`, 'warning');
            } else if (size > JSON_SIZE_WARNING) {
                this.showToast('Info', `Calculated Fields JSON is large (${Math.round(size/1024)}KB). If you experience issues, consider reducing calculated fields.`, 'info');
            }
            try { 
                const parsed = JSON.parse(this.calculatedFieldsJson);
                // Validate structure - must be an array
                if (Array.isArray(parsed)) {
                    calculatedFields = parsed;
                } else {
                    this.showToast('Warning', 'Calculated Fields should be a JSON array (e.g., [{"label": "...", "formula": "..."}]). Using empty array.', 'warning');
                }
            } catch (e) {
                this.showToast('Warning', 'Invalid Calculated Fields JSON: ' + (e.message || 'Parse error') + '. Using empty array.', 'warning');
            }
        }
        
        let dimensionConstants = {};
        if (this.dimensionConstantsJson) {
            const size = this.dimensionConstantsJson.length;
            if (size > JSON_SIZE_CRITICAL) {
                this.showToast('Warning', `Dimension Constants JSON is very large (${Math.round(size/1024)}KB). This may cause performance issues.`, 'warning');
            } else if (size > JSON_SIZE_WARNING) {
                this.showToast('Info', `Dimension Constants JSON is large (${Math.round(size/1024)}KB).`, 'info');
            }
            try { 
                const parsed = JSON.parse(this.dimensionConstantsJson);
                // Validate structure - must be an object
                if (typeof parsed === 'object' && !Array.isArray(parsed) && parsed !== null) {
                    dimensionConstants = parsed;
                } else {
                    this.showToast('Warning', 'Dimension Constants should be a JSON object (e.g., {"1": "Total"}). Using empty object.', 'warning');
                }
            } catch (e) {
                this.showToast('Warning', 'Invalid Dimension Constants JSON: ' + (e.message || 'Parse error') + '. Using empty object.', 'warning');
            }
        }
        
        const options = {
            mergeMode: this.mergeMode || MERGE_MODE_OUTER_JOIN,
            dataVisibility: this.visibilityScope || 'ALL',
            missingValueAsZero: this.missingValueAsZero || false,
            sortBy: this.currentSortBy || this.sortBy || 'KEY',
            sortDirection: this.currentSortDirection || this.sortDirection || SORT_DIRECTION_ASC,
            sortGroupsBy: this.sortGroupsBy || null,
            maxRows: this.maxRows || 200,
            showGrandTotalRow: this.showGrandTotalRow !== false,
            showSubtotals: this.showSubtotals || false,
            subtotalLabel: this.subtotalLabel || 'SUBTOTAL',
            fillMissingCategories: this.fillMissingCategories || false,
            dimensionConstants: dimensionConstants,
            columnAliases: columnAliases,
            calculatedFields: calculatedFields
        };
        
        // In App Builder design mode, add a cache buster to ensure fresh data on every call
        // In runtime mode, we let Salesforce cache responses for better performance
        if (this.isInDesignMode) {
            options._designModeCacheBuster = Date.now();
        }
        
        return JSON.stringify(options);
    }
    
    // Build options JSON WITHOUT cache buster - used for comparing if options changed
    // This prevents infinite loops in renderedCallback where Date.now() would always differ
    _buildStableOptionsJson() {
        let columnAliases = {};
        if (this.columnAliasesJson) {
            try { 
                const parsed = JSON.parse(this.columnAliasesJson);
                if (typeof parsed === 'object' && !Array.isArray(parsed) && parsed !== null) {
                    columnAliases = parsed;
                }
            } catch (e) { /* ignore - will be caught in _buildOptionsJson */ }
        }
        
        let calculatedFields = [];
        if (this.calculatedFieldsJson) {
            try { 
                const parsed = JSON.parse(this.calculatedFieldsJson);
                if (Array.isArray(parsed)) {
                    calculatedFields = parsed;
                }
            } catch (e) { /* ignore - will be caught in _buildOptionsJson */ }
        }
        
        let dimensionConstants = {};
        if (this.dimensionConstantsJson) {
            try { 
                const parsed = JSON.parse(this.dimensionConstantsJson);
                if (typeof parsed === 'object' && !Array.isArray(parsed) && parsed !== null) {
                    dimensionConstants = parsed;
                }
            } catch (e) { /* ignore - will be caught in _buildOptionsJson */ }
        }
        
        // Same as _buildOptionsJson but WITHOUT the cache buster
        const options = {
            mergeMode: this.mergeMode || MERGE_MODE_OUTER_JOIN,
            dataVisibility: this.visibilityScope || 'ALL',
            missingValueAsZero: this.missingValueAsZero || false,
            sortBy: this.currentSortBy || this.sortBy || 'KEY',
            sortDirection: this.currentSortDirection || this.sortDirection || SORT_DIRECTION_ASC,
            sortGroupsBy: this.sortGroupsBy || null,
            maxRows: this.maxRows || 200,
            showGrandTotalRow: this.showGrandTotalRow !== false,
            showSubtotals: this.showSubtotals || false,
            subtotalLabel: this.subtotalLabel || 'SUBTOTAL',
            fillMissingCategories: this.fillMissingCategories || false,
            dimensionConstants: dimensionConstants,
            columnAliases: columnAliases,
            calculatedFields: calculatedFields
        };
        
        return JSON.stringify(options);
    }
    
    // ===== Computed Properties =====
    get isConfigured() {
        return this.report1Id && this.report2Id;
    }
    
    get configurationError() {
        if (!this.report1Id || !this.report2Id) {
            return 'At least two report IDs must be configured.';
        }
        return null;
    }
    
    get hasFatalErrors() {
        return this.gridData?.errors?.some(err => err.isFatal) || false;
    }
    
    get fatalErrorMessages() {
        if (!this.gridData?.errors) return [];
        return this.gridData.errors.filter(err => err.isFatal).map(err => err.message);
    }
    
    get showErrorState() {
        return this.error || this.hasFatalErrors;
    }
    
    get errorMessage() {
        if (this.error) return this.error;
        if (this.hasFatalErrors) return this.fatalErrorMessages.join('; ');
        return 'An unexpected error occurred.';
    }
    
    get hasData() {
        return this.gridData?.rows?.length > 0;
    }
    
    get columns() {
        return this.gridData?.columns || [];
    }
    
    get rows() {
        return this.gridData?.rows || [];
    }
    
    get totalsRow() {
        return this.gridData?.totalsRow;
    }
    
    get title() {
        return this.componentTitle || 'Merged Report Grid';
    }
    
    get subtitle() {
        const count = this._getReportIds().length;
        const mode = this.mergeMode || 'OUTER_JOIN';
        const displayMode = mode.replace('_', ' ');
        const visibility = this.visibilityScope || 'ALL';
        const visibilityLabel = visibility === 'MY_RECORDS' ? ' (My Records)' 
                              : visibility === 'MY_TEAM' ? ' (My Team)' 
                              : '';
        return `${displayMode} from ${count} reports${visibilityLabel}`;
    }
    
    // Build list of reports with names, IDs, and URLs for the popover
    get reportDetailsList() {
        const reports = [];
        const reportIds = [this.report1Id, this.report2Id, this.report3Id, this.report4Id, this.report5Id];
        
        // Parse dimension constants to show which reports have them
        let dimConstants = {};
        if (this.dimensionConstantsJson) {
            try { dimConstants = JSON.parse(this.dimensionConstantsJson); } 
            catch (e) { /* ignore */ }
        }
        
        // Get report names from gridData if available
        const reportNames = this.gridData?.reportNames || {};
        
        reportIds.forEach((id, index) => {
            if (id) {
                const reportNum = index + 1;
                const name = reportNames[id] || `Report ${reportNum}`;
                reports.push({
                    id: id,
                    name: name,
                    url: `/lightning/r/Report/${id}/view`,
                    dimensionConstant: dimConstants[String(reportNum)] || null
                });
            }
        });
        
        return reports;
    }
    
    handleShowReports() {
        this.showReportPopover = !this.showReportPopover;
    }
    
    handleClosePopover() {
        this.showReportPopover = false;
    }
    
    get showTruncationWarning() {
        return this.gridData?.isTruncated;
    }
    
    get truncationMessage() {
        return `Showing first ${this.maxRows} of ${this.gridData?.totalRowCount} rows.`;
    }
    
    get processingTime() {
        return this.gridData?.processingTimeMs || 0;
    }
    
    get keyColumn() {
        return this.columns.find(col => col.isKeyColumn);
    }
    
    get secondKeyColumn() {
        return this.columns.find(col => col.isSecondKeyColumn);
    }
    
    get valueColumns() {
        const cols = this.columns.filter(col => !col.isKeyColumn && !col.isSecondKeyColumn);
        if (this.totalsRow) {
            return cols.map(col => ({
                ...col,
                totalValue: this.totalsRow.formattedValues?.[col.key] || '—'
            }));
        }
        return cols;
    }
    
    get tableColumns() {
        if (!this.columns || this.columns.length === 0) return [];
        
        return this.columns.map((col, index) => {
            const column = {
                label: col.label,
                fieldName: col.isKeyColumn ? 'keyLabel' : (col.isSecondKeyColumn ? 'secondKeyLabel' : col.key),
                sortable: !col.isSecondKeyColumn,
                hideDefaultActions: true,
                columnIndex: index
            };
            
            if (col.isKeyColumn || col.isSecondKeyColumn) {
                column.type = 'text';
                column.initialWidth = col.isKeyColumn ? 180 : 140;
            } else {
                column.type = 'text';
                column.cellAttributes = { alignment: 'right' };
            }
            
            return column;
        });
    }
    
    get tableData() {
        if (!this.rows || this.rows.length === 0) return [];
        
        return this.rows.map((row, index) => {
            const data = {
                id: `${row.keyValue}-${row.secondKeyValue || ''}-${index}`,
                keyValue: row.keyValue,
                keyLabel: row.keyLabel,
                secondKeyValue: row.secondKeyValue,
                secondKeyLabel: row.secondKeyLabel,
                isSubtotalRow: row.isSubtotalRow,
                rowClass: row.isSubtotalRow ? 'slds-text-title_bold subtotal-row' : ''
            };
            
            this.valueColumns.forEach(col => {
                data[col.key] = row.formattedValues?.[col.key] || '—';
            });
            
            return data;
        });
    }
    
    get totalsRowData() {
        if (!this.totalsRow) return null;
        
        const data = {
            id: 'totals-row',
            keyValue: 'TOTAL',
            keyLabel: 'Total',
            secondKeyLabel: ''
        };
        
        this.valueColumns.forEach(col => {
            data[col.key] = this.totalsRow.formattedValues?.[col.key] || '—';
        });
        
        return data;
    }
    
    get showTotalsRow() {
        return this.showGrandTotalRow !== false && this.totalsRow;
    }
    
    // ===== Debug Mode Properties =====
    get isDebugMode() {
        return this.debugMode === true;
    }
    
    get debugInfo() {
        const info = {
            configuration: this.debugConfiguration,
            reports: this.debugReports,
            response: this.debugResponse,
            recommendations: this.debugRecommendations
        };
        return JSON.stringify(info, null, 2);
    }
    
    get debugConfiguration() {
        return {
            reportIds: this._getReportIds(),
            mergeMode: this.mergeMode,
            dimensionConstantsJson: this.dimensionConstantsJson || '(not set)',
            showSubtotals: this.showSubtotals,
            subtotalLabel: this.subtotalLabel,
            fillMissingCategories: this.fillMissingCategories,
            sortGroupsBy: this.sortGroupsBy || '(not set)',
            columnAliases: this.columnAliasesJson || '(not set)',
            calculatedFields: this.calculatedFieldsJson || '(not set)',
            missingValueAsZero: this.missingValueAsZero,
            sortBy: this.sortBy,
            sortDirection: this.sortDirection,
            maxRows: this.maxRows,
            showGrandTotalRow: this.showGrandTotalRow,
            isInDesignMode: this.isInDesignMode,
            cachingMode: this.isInDesignMode ? 'DISABLED (cache buster active)' : 'ENABLED (responses cached)',
            optionsSentToApex: this._lastOptionsJson ? JSON.parse(this._lastOptionsJson) : '(no API call yet)'
        };
    }
    
    get debugReports() {
        if (!this.gridData) return { status: 'No data received yet' };
        
        const reports = [];
        if (this.gridData.columns) {
            this.gridData.columns.forEach(col => {
                if (!col.isKeyColumn && !col.isSecondKeyColumn) {
                    reports.push({
                        reportId: col.reportId || '(merged)',
                        columnKey: col.key,
                        columnLabel: col.label,
                        isMergedColumn: col.isMergedColumn
                    });
                }
            });
        }
        
        return {
            columnCount: this.gridData.columns?.length || 0,
            rowCount: this.gridData.rows?.length || 0,
            hasSecondDimension: this.gridData.hasSecondDimension,
            columns: reports
        };
    }
    
    get debugResponse() {
        if (!this.gridData) return { status: 'No data received' };
        return {
            processingTimeMs: this.gridData.processingTimeMs,
            totalRowCount: this.gridData.totalRowCount,
            isTruncated: this.gridData.isTruncated,
            hasSecondDimension: this.gridData.hasSecondDimension,
            errors: this.gridData.errors,
            warnings: this.gridData.warnings,
            keyOverlapPercentage: this.gridData.keyOverlapPercentage
        };
    }
    
    get debugRecommendations() {
        const recs = [];
        
        if (this.gridData?.errors) {
            const dimError = this.gridData.errors.find(e => 
                e.message?.includes('dimension')
            );
            if (dimError) {
                recs.push({
                    type: 'ERROR',
                    issue: 'Dimension mismatch detected',
                    fix: 'Change Merge Mode to UNION, or set Dimension Constants for reports with fewer dimensions'
                });
            }
        }
        
        if (this.mergeMode === 'UNION' && !this.dimensionConstantsJson) {
            recs.push({
                type: 'WARNING',
                issue: 'UNION mode without Dimension Constants',
                fix: 'If reports have different dimension counts, set constants like {"2": "Total"}'
            });
        }
        
        if (this.calculatedFieldsJson) {
            try {
                const parsed = JSON.parse(this.calculatedFieldsJson);
                if (Array.isArray(parsed)) {
                    parsed.forEach((f, i) => {
                        if (!f.label) {
                            recs.push({
                                type: 'ERROR',
                                issue: `Calculated field ${i + 1} missing label`,
                                fix: 'Add "label" property to calculated field'
                            });
                        }
                        if (!f.formula) {
                            recs.push({
                                type: 'ERROR',
                                issue: `Calculated field ${i + 1} missing formula`,
                                fix: 'Add "formula" property'
                            });
                        }
                    });
                }
            } catch (e) {
                recs.push({
                    type: 'ERROR',
                    issue: 'Invalid Calculated Fields JSON',
                    fix: 'Check JSON syntax'
                });
            }
        }
        
        if (this.columnAliasesJson) {
            try {
                JSON.parse(this.columnAliasesJson);
            } catch (e) {
                recs.push({
                    type: 'ERROR',
                    issue: 'Invalid Column Aliases JSON',
                    fix: 'Check JSON syntax'
                });
            }
        }
        
        if (this.dimensionConstantsJson) {
            try {
                JSON.parse(this.dimensionConstantsJson);
            } catch (e) {
                recs.push({
                    type: 'ERROR',
                    issue: 'Invalid Dimension Constants JSON',
                    fix: 'Check JSON syntax'
                });
            }
        }
        
        if (this.gridData?.keyOverlapPercentage && this.gridData.keyOverlapPercentage < 70) {
            recs.push({
                type: 'WARNING',
                issue: `Low key overlap: ${this.gridData.keyOverlapPercentage.toFixed(0)}%`,
                fix: 'Consider INNER_JOIN to only show matching keys'
            });
        }
        
        if (recs.length === 0) {
            recs.push({
                type: 'SUCCESS',
                issue: 'No issues detected',
                fix: 'Configuration looks good!'
            });
        }
        
        return recs;
    }
    
    get debugConfigJson() {
        return JSON.stringify(this.debugConfiguration, null, 2);
    }
    
    get debugReportsJson() {
        return JSON.stringify(this.debugReports, null, 2);
    }
    
    get debugResponseJson() {
        return JSON.stringify(this.debugResponse, null, 2);
    }
    
    get debugRecommendationsList() {
        return this.debugRecommendations;
    }
    
    // ===== Event Handlers =====
    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.currentSortBy = fieldName;
        this.currentSortDirection = sortDirection;
        this._scheduleFetch();
    }
    
    handleRefresh() {
        this._scheduleFetch();
    }
    
    // ===== Utilities =====
    reduceError(error) {
        if (typeof error === 'string') return error;
        if (error.body?.message) return error.body.message;
        if (error.message) return error.message;
        if (Array.isArray(error.body)) {
            return error.body.map(e => e.message).join(', ');
        }
        return 'Unknown error';
    }
    
    showToast(title, message, variant = 'info') {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }
}