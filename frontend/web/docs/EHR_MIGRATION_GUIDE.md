# EHR Theme Migration Guide

## Overview

This guide helps developers understand how to work with the EHR theme when adding new features or modifying existing ones.

## Quick Start

### For New Features

1. **Use existing EHR utility classes** (see `EHR_QUICK_REFERENCE.md`)
2. **Follow EHR typography standards** (labels uppercase, consistent sizing)
3. **Use EHR spacing standards** (12px gaps, 16-20px padding)
4. **Preserve all existing colors** (never override theme colors)

### For Bug Fixes

1. **Check if issue is visual or functional**
2. **Visual issues**: Modify `ehr-theme.css` only
3. **Functional issues**: Modify JavaScript/logic files
4. **Never mix visual and functional changes** in the same commit

## Common Scenarios

### Scenario 1: Adding a New Form

**Goal**: Add a patient intake form with EHR styling

**Steps**:

1. Use EHR form grid:
```html
<div class="ehr-form-grid-2">
  <div class="field">
    <label>Patient Name</label>
    <input type="text" name="name" />
  </div>
  <div class="field">
    <label>Date of Birth</label>
    <input type="date" name="dob" />
  </div>
</div>
```

2. Labels will automatically be:
   - 11px
   - Uppercase
   - 0.06em letter-spacing
   - #6b7a8d color

3. Inputs will automatically be:
   - 1px solid #d0d7e2 border
   - 4px border-radius
   - 6px×10px padding
   - 13px font-size

**✅ Do:**
- Use `.ehr-form-grid-2` or `.ehr-form-grid-3`
- Use standard `.field` class
- Let EHR theme handle styling

**❌ Don't:**
- Add inline styles
- Override label colors
- Change input border styles
- Add custom spacing

### Scenario 2: Adding a New Table

**Goal**: Display lab results in a table

**Steps**:

1. Use EHR table structure:
```html
<table class="lab-results-table">
  <thead>
    <tr>
      <th>Test Name</th>
      <th>Result</th>
      <th>Reference Range</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Glucose</td>
      <td>95 mg/dL</td>
      <td class="ref-range">70-100 mg/dL</td>
    </tr>
  </tbody>
</table>
```

2. Styling is automatic:
   - Header: #f0f2f5 background
   - Header text: 11px uppercase
   - Cell padding: 10px 12px
   - Row borders: 1px #e5e7eb

**✅ Do:**
- Use `.lab-results-table` class
- Use `.ref-range` for reference values
- Use `.abnormal-flag` for indicators

**❌ Don't:**
- Use `.accounts-table` (different purpose)
- Override header styles
- Add custom borders

### Scenario 3: Adding Status Indicators

**Goal**: Show patient vital sign status

**Steps**:

1. Use semantic badge classes:
```html
<span class="badge-normal">Normal</span>
<span class="badge-warning">Borderline</span>
<span class="badge-danger">Critical</span>
```

2. Or use EHR alert boxes:
```html
<div class="ehr-alert ehr-alert-warning">
  <span class="ehr-alert-icon">⚠️</span>
  <div>Blood pressure is elevated</div>
</div>
```

**✅ Do:**
- Use semantic classes (normal, warning, danger)
- Use EHR alert boxes for important messages
- Include icons for visual clarity

**❌ Don't:**
- Create custom badge styles
- Use color alone to convey meaning
- Override semantic colors

### Scenario 4: Adding a Patient Header

**Goal**: Display patient information at top of page

**Steps**:

1. Use patient header card:
```html
<div class="patient-header-card">
  <div class="patient-header-avatar">JD</div>
  <div class="patient-header-info">
    <div class="patient-header-name">John Doe</div>
    <div class="patient-header-meta">
      <span class="patient-header-meta-item">
        <strong>DOB:</strong> 01/15/1980
      </span>
      <span class="patient-header-meta-item">
        <strong>MRN:</strong> <span class="ticket-code">123456</span>
      </span>
    </div>
  </div>
</div>
```

**✅ Do:**
- Use `.patient-header-card` structure
- Use `.ticket-code` for IDs (monospace)
- Include relevant metadata

**❌ Don't:**
- Create custom patient header styles
- Use different avatar sizes
- Override spacing

### Scenario 5: Adding a Timeline

**Goal**: Show patient medical history

**Steps**:

1. Use EHR timeline:
```html
<div class="ehr-timeline">
  <div class="ehr-timeline-item">
    <div class="ehr-timeline-date">May 7, 2026</div>
    <div class="ehr-timeline-content">
      Annual physical examination completed
    </div>
  </div>
  <div class="ehr-timeline-item">
    <div class="ehr-timeline-date">Jan 15, 2026</div>
    <div class="ehr-timeline-content">
      Flu vaccination administered
    </div>
  </div>
</div>
```

**✅ Do:**
- Use `.ehr-timeline` structure
- Format dates consistently
- Keep content concise

**❌ Don't:**
- Create custom timeline styles
- Override timeline connector
- Change dot colors

### Scenario 6: Modifying Existing Component

**Goal**: Update the queue ticket card styling

**Steps**:

1. **Identify the component** in HTML
2. **Check if EHR theme already styles it**
3. **If yes**: Modify `ehr-theme.css`
4. **If no**: Add new styles to `ehr-theme.css`

**Example**:
```css
/* In ehr-theme.css */
.queue-ticket-card {
    border: 1px solid #d0d7e2;
    border-radius: 6px;
    padding: 12px 14px;
    background: #ffffff;
}

.queue-ticket-card:hover {
    border-color: #94a3b8;
    box-shadow: 0 2px 8px rgba(15, 23, 42, 0.06);
}
```

**✅ Do:**
- Add to `ehr-theme.css`
- Follow EHR standards
- Test on all pages

**❌ Don't:**
- Modify `style.css`
- Use `!important` unless necessary
- Break existing functionality

## Migration Patterns

### Pattern 1: Converting Existing Forms

**Before**:
```html
<div class="field">
  <label class="inputLabel">Patient Name</label>
  <input type="text" />
</div>
```

**After**:
```html
<div class="field">
  <label>Patient Name</label>
  <input type="text" />
</div>
```

**Changes**:
- Remove `.inputLabel` class (EHR theme handles it)
- Label automatically becomes uppercase
- Spacing automatically adjusted

### Pattern 2: Converting Tables

**Before**:
```html
<table class="accounts-table">
  <thead>
    <tr class="table-header-row">
      <th class="table-header-cell">Name</th>
    </tr>
  </thead>
</table>
```

**After**:
```html
<table class="accounts-table">
  <thead>
    <tr class="table-header-row">
      <th class="table-header-cell">Name</th>
    </tr>
  </thead>
</table>
```

**Changes**:
- Keep same classes
- EHR theme automatically resizes headers
- Headers become uppercase
- Spacing adjusted

### Pattern 3: Converting Badges

**Before**:
```html
<span class="badge-active">Active</span>
```

**After**:
```html
<span class="badge-active">Active</span>
```

**Changes**:
- Keep same class
- Text automatically becomes uppercase
- Spacing adjusted
- Colors preserved

## Troubleshooting

### Issue: Styles Not Applying

**Symptoms**: New component doesn't have EHR styling

**Solutions**:
1. Check if `ehr-theme.css` is loaded:
   ```html
   <link rel="stylesheet" href="../css/ehr-theme.css?v=20260507" />
   ```

2. Clear browser cache (Ctrl+Shift+R)

3. Check CSS specificity:
   ```css
   /* If needed, increase specificity */
   .mainview .my-component { }
   ```

4. Verify class names match exactly

### Issue: Colors Changed Unexpectedly

**Symptoms**: Button or link colors different

**Solutions**:
1. Check if you accidentally overrode theme colors
2. Remove any color overrides from `ehr-theme.css`
3. Use existing color variables:
   ```css
   /* Use existing colors */
   color: var(--primary);
   background: var(--accent);
   ```

### Issue: Spacing Looks Wrong

**Symptoms**: Elements too close or too far apart

**Solutions**:
1. Use EHR spacing standards:
   - Field gap: 12px
   - Card padding: 16px 20px
   - Section margin: 16-20px

2. Check for conflicting inline styles

3. Use EHR utility classes:
   ```html
   <div class="ehr-form-grid-2">...</div>
   ```

### Issue: Typography Inconsistent

**Symptoms**: Font sizes or weights vary

**Solutions**:
1. Remove custom font styles
2. Use semantic HTML:
   ```html
   <label>Field Label</label>  <!-- Auto: 11px uppercase -->
   <h3>Section Title</h3>      <!-- Auto: 16px semi-bold -->
   ```

3. Use EHR classes:
   ```html
   <div class="ehr-data-label">Label</div>
   <div class="ehr-data-value">Value</div>
   ```

### Issue: Mobile App Affected

**Symptoms**: Mobile app styling changed

**Solutions**:
1. **This should never happen** - mobile app is separate
2. Check that you didn't modify:
   - `frontend/mobile/**/*`
   - Shared components
   - Base `style.css` (should only modify `ehr-theme.css`)

3. If mobile is affected, revert changes immediately

## Best Practices

### DO ✅

1. **Use EHR utility classes**
   ```html
   <div class="ehr-data-row">
     <div class="ehr-data-label">Label</div>
     <div class="ehr-data-value">Value</div>
   </div>
   ```

2. **Follow EHR typography**
   - Labels: 11px uppercase
   - Data: 14px medium
   - Headings: 16-18px semi-bold

3. **Use semantic HTML**
   ```html
   <label>Field Label</label>
   <h3>Section Title</h3>
   ```

4. **Test on all pages**
   - dashboard.html
   - dashboard-pharmacist.html
   - index.html

5. **Verify mobile unaffected**
   - Check mobile app still works
   - No visual changes

6. **Document new patterns**
   - Add to this guide
   - Update quick reference

### DON'T ❌

1. **Don't override theme colors**
   ```css
   /* ❌ BAD */
   .btn { background: #ff0000; }
   
   /* ✅ GOOD */
   .btn { background: var(--accent); }
   ```

2. **Don't modify base styles**
   ```css
   /* ❌ BAD - modifying style.css */
   
   /* ✅ GOOD - adding to ehr-theme.css */
   ```

3. **Don't use inline styles**
   ```html
   <!-- ❌ BAD -->
   <div style="padding: 10px;">
   
   <!-- ✅ GOOD -->
   <div class="ehr-data-row">
   ```

4. **Don't create duplicate classes**
   ```css
   /* ❌ BAD - creating new class */
   .my-custom-label { font-size: 11px; }
   
   /* ✅ GOOD - using existing class */
   .ehr-data-label { }
   ```

5. **Don't break functionality**
   - Never remove JS-dependent classes
   - Never change data attributes
   - Never modify event handlers

6. **Don't touch mobile app**
   - Never modify mobile files
   - Never modify shared components
   - Never modify base styles used by mobile

## Testing Checklist

Before committing changes:

- [ ] **Visual**: Styles look correct on all pages
- [ ] **Functional**: All features work identically
- [ ] **Responsive**: Works on desktop, tablet, mobile
- [ ] **Accessibility**: Focus states visible, contrast OK
- [ ] **Print**: Print layout looks good
- [ ] **Mobile app**: Completely unaffected
- [ ] **Browser**: Works in Chrome, Firefox, Safari
- [ ] **Documentation**: Updated if needed

## Code Review Checklist

When reviewing EHR theme changes:

- [ ] Changes only in `ehr-theme.css` (not `style.css`)
- [ ] No color overrides (theme colors preserved)
- [ ] Follows EHR typography standards
- [ ] Uses existing utility classes when possible
- [ ] No inline styles added
- [ ] Mobile app unaffected
- [ ] Functionality unchanged
- [ ] Documentation updated if needed

## Getting Help

1. **Check documentation**:
   - `EHR_THEME_GUIDE.md` - Complete guide
   - `EHR_QUICK_REFERENCE.md` - Quick patterns
   - `EHR_VISUAL_CHANGES.md` - Visual comparison

2. **Review examples**:
   - Look at existing components
   - Check `ehr-theme.css` comments
   - See utility class usage

3. **Test incrementally**:
   - Make small changes
   - Test immediately
   - Verify mobile unaffected

4. **Ask for review**:
   - Get code review
   - Verify with QA
   - Check with design team

## Version Control

### Commit Message Format

```
feat(ehr): Add patient timeline component

- Added .ehr-timeline utility classes
- Follows EHR visual standards
- Tested on all web pages
- Mobile app unaffected
```

### Branch Naming

```
feature/ehr-patient-timeline
fix/ehr-table-spacing
docs/ehr-migration-guide
```

## Rollback Procedure

If EHR theme causes issues:

1. **Identify the issue**:
   - Visual only? Fix in `ehr-theme.css`
   - Functional? Revert changes

2. **Quick disable**:
   ```html
   <!-- Comment out EHR theme -->
   <!-- <link rel="stylesheet" href="../css/ehr-theme.css?v=20260507" /> -->
   ```

3. **Permanent rollback**:
   ```bash
   git revert <commit-hash>
   ```

4. **Partial rollback**:
   - Comment out specific sections in `ehr-theme.css`
   - Test incrementally

## Future Considerations

### Planned Enhancements

1. **Dark mode** - For night shift staff
2. **High contrast** - Enhanced accessibility
3. **Compact mode** - Denser information display
4. **Print templates** - Specialized layouts

### Extensibility

The EHR theme is designed to be extended:

```css
/* Add new utility classes */
.ehr-custom-component {
    /* Follow EHR standards */
    font-size: 13px;
    padding: 12px;
    border: 1px solid #d0d7e2;
    border-radius: 4px;
}
```

---

**Document Version**: 1.0  
**Last Updated**: May 7, 2026  
**Maintained By**: U-Konek+ Development Team
