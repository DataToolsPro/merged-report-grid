# Change Set Deployment Inventory

**Component:** Merged Report Grid Lightning Web Component  
**Version:** 1.4.0  
**Date:** February 2026

---

## Prerequisites

Before creating a change set, you must deploy the source code directly to your sandbox first. This ensures all components are available as unpackaged metadata.

### Step 0: Deploy Source Code to Sandbox

1. **Deploy source code directly to sandbox:**
   ```bash
   # Authenticate to sandbox (if not already)
   sf org login web -a sandbox --instance-url https://test.salesforce.com
   
   # Deploy source code directly
   sf project deploy start -o sandbox
   ```

2. **Verify components are deployed:**
   - Go to **Setup → Apex Classes** in your sandbox
   - Verify `MergedReportController`, `MergedReportControllerTest`, `MergeOptions`, and `MergedGridDTO` are present
   - Go to **Setup → Lightning Components** and verify `mergedReportGrid` is present

---

## Complete Component List

### Apex Classes (4 classes - ALL required)

When adding to your change set, search for these in the **Apex Classes** component type:

1. **MergedReportController**
   - **Purpose:** Main controller that fetches and merges reports
   - **Required:** ✅ Yes
   - **Test Class:** No (this is the main class)

2. **MergedReportControllerTest**
   - **Purpose:** Unit tests (90%+ code coverage)
   - **Required:** ✅ Yes (required for production deployment)
   - **Test Class:** Yes

3. **MergeOptions**
   - **Purpose:** Configuration data transfer object
   - **Required:** ✅ Yes
   - **Test Class:** No

4. **MergedGridDTO**
   - **Purpose:** Response data transfer object with nested classes
   - **Required:** ✅ Yes
   - **Test Class:** No

---

### Lightning Components (1 component - ALL files included)

When adding to your change set, search for this in the **Lightning Components** component type:

1. **mergedReportGrid**
   - **Component Type:** Lightning Component Bundle
   - **Required:** ✅ Yes
   - **Includes automatically:**
     - `mergedReportGrid.js` (controller)
     - `mergedReportGrid.html` (template)
     - `mergedReportGrid.css` (styles)
     - `mergedReportGrid.js-meta.xml` (metadata/config)

> **Note:** When you add a Lightning Component to a change set, Salesforce automatically includes all files in the bundle (JS, HTML, CSS, and metadata). You only need to add the component name once.

---

## Change Set Creation Steps

### Step 1: Create Outbound Change Set (in Sandbox)

1. Navigate to **Setup → Outbound Change Sets**
2. Click **New**
3. Name: `Merged Report Grid v1.4.0` (or your preferred name)
4. Description: `Merged Report Grid LWC - Merges 2-5 Salesforce reports into unified grid`

### Step 2: Add Components

#### Add Apex Classes (4 total)

1. Click **Add** in the change set
2. Select component type: **Apex Classes**
3. Add each of these (one at a time or select multiple):
   - ✅ `MergedReportController`
   - ✅ `MergedReportControllerTest`
   - ✅ `MergeOptions`
   - ✅ `MergedGridDTO`

#### Add Lightning Component (1 total)

1. Click **Add** in the change set
2. Select component type: **Lightning Components**
3. Add:
   - ✅ `mergedReportGrid`

> **Important:** When you add `mergedReportGrid`, Salesforce automatically includes:
> - mergedReportGrid.js
> - mergedReportGrid.html
> - mergedReportGrid.css
> - mergedReportGrid.js-meta.xml

### Step 3: Upload Change Set

1. Click **Upload** button
2. Select your **Production** org as the target
3. Click **Upload**
4. Wait for upload to complete

### Step 4: Deploy to Production

1. In your **Production** org, navigate to **Setup → Inbound Change Sets**
2. Find your change set: `Merged Report Grid v1.4.0`
3. Click **Deploy**
4. Review the components list
5. Click **Deploy**
6. Monitor deployment status

> ⚠️ **Important:** Change sets require all Apex tests to pass. The `MergedReportControllerTest` class will run automatically during deployment. If tests fail, deployment will be rejected.

---

## Component Summary Table

| Component Type | Component Name | Required | Notes |
|----------------|----------------|----------|-------|
| Apex Class | MergedReportController | ✅ Yes | Main controller |
| Apex Class | MergedReportControllerTest | ✅ Yes | Unit tests (required for production) |
| Apex Class | MergeOptions | ✅ Yes | Configuration DTO |
| Apex Class | MergedGridDTO | ✅ Yes | Response DTO |
| Lightning Component | mergedReportGrid | ✅ Yes | Includes JS, HTML, CSS, metadata |

**Total Components:** 5 (4 Apex Classes + 1 Lightning Component)

---

## Exact Component Names (Copy-Paste Ready)

### Apex Classes
```
MergedReportController
MergedReportControllerTest
MergeOptions
MergedGridDTO
```

### Lightning Components
```
mergedReportGrid
```

---

## Dependencies

### No External Dependencies
- ✅ No managed packages required
- ✅ No custom objects required
- ✅ No custom fields required
- ✅ No permission sets required
- ✅ No profiles required
- ✅ No static resources required

### Platform Requirements
- ✅ Salesforce API Version: 59.0
- ✅ Lightning Experience required
- ✅ Reports API access (standard Salesforce feature)

---

## Verification Checklist

Before deploying the change set, verify:

- [ ] All 4 Apex classes are added to change set
- [ ] Lightning component `mergedReportGrid` is added
- [ ] Change set is uploaded to production
- [ ] Ready to deploy in production org

After deployment, verify:

- [ ] All components deployed successfully
- [ ] Apex tests passed (check deployment details)
- [ ] Component appears in Lightning App Builder
- [ ] Can add component to a Lightning page
- [ ] Component functions correctly with test reports

---

## Troubleshooting

### "Component not found" when adding to change set

**Cause:** Component doesn't exist in the sandbox yet, or components are still packaged.

**Solution:** 
1. Deploy source code directly to sandbox using CLI:
   ```bash
   sf project deploy start -o sandbox
   ```
2. Verify components are unpackaged (check Setup → Apex Classes - should not show "Installed Package")
3. Then create the change set

### "Component is part of a package" error

**Cause:** Components are still installed as part of a package and cannot be added to change sets.

**Solution:**
1. Deploy source code directly to sandbox (see Step 0 above)
2. If components still show as packaged, you may need to:
   - Remove the component from any Lightning pages
   - Uninstall any existing package: `sf package uninstall -p <package-version-id> -o sandbox`
   - Then redeploy source code: `sf project deploy start -o sandbox`

### "Test class required" error

**Cause:** Production deployments require test classes.

**Solution:** 
- ✅ `MergedReportControllerTest` is already included
- Ensure it's added to the change set
- Tests must pass for deployment to succeed

### "Missing dependencies" error

**Cause:** Some components depend on others.

**Solution:** 
- All components are included in the inventory above
- Add all 4 Apex classes and the Lightning component
- No external dependencies needed

---

## Alternative: Direct CLI Deployment

If you prefer to skip change sets, you can deploy directly to production via CLI:

```bash
# Deploy to production with tests
sf project deploy start -o prod --test-level RunSpecifiedTests --tests MergedReportControllerTest

# Verify deployment
sf project deploy report -o prod
```

This is faster than change sets but requires CLI access to production org.

---

**Last Updated:** February 2026  
**Component Version:** 1.4.0
