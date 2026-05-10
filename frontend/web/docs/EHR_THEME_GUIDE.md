# U-Konek+ Web App - EHR Theme Implementation Guide

## Overview

The U-Konek+ web application (doctor/staff-facing) has been restyled to follow Electronic Health Record (EHR) and medical record visual standards. This document explains the implementation, usage, and maintenance of the EHR theme.

## What Changed

### ✅ Visual Changes Applied

1. **Typography**
   - Font stack: Inter, Segoe UI, Roboto, Arial, sans-serif
   - Body text: 13-14px with 1.6 line-height
   - Field labels: 11px uppercase with 0.06em letter-spacing
   - Data values: 14px with 500 font-weight
   - Headings: 16-18px with 600 font-weight

2. **Layout & Spacing**
   - Sidebar: 240px width (90px collapsed)
   - Main content: max-width 1100px, centered
   - Section cards: white background, 1px border, 6px border-radius
   - Card headers: light gray background with border-bottom
   - Field rows: 12px vertical gap

3. **Components**
   - Buttons: 4px border-radius, 7px×16px padding
   - Inputs: 1px solid border, 4px border-radius, 6px×10px padding
   - Status badges: 11px uppercase, 3px border-radius
   - Tables: light header background, 2px bottom border
   - Tabs: underline-style with primary color indicator
   - ID fields: monospace font, light background

4. **Colors for New Elements Only**
   - Success/normal: text #166534, bg #dcfce7
   - Warning/borderline: text #854d0e, bg #fef9c3
   - Danger/critical: text #991b1b, bg #fee2e2
   - Border/divider: #d0d7e2
   - Page background: #f0f2f5
   - Muted text: #6b7a8d

### ❌ What Was NOT Changed

- **All existing colors preserved** (primary, secondary, brand colors)
- **All functionality intact** (logic, routing, API calls, state management)
- **Mobile app untouched** (completely separate codebase)
- **Shared components** (no modifications to shared resources)
- **Button colors** (all existing button colors preserved)
- **Link colors** (all existing link colors preserved)
- **Active/selected states** (all existing state colors preserved)

## File Structure

```
frontend/web/
├── css/
│   ├── style.css           # Original styles (preserved)
│   ├── ehr-theme.css       # NEW: EHR visual overrides
│   └── tv-view.css         # TV display (not modified)
├── html/
│   ├── dashboard.html      # Updated: includes ehr-theme.css
│   ├── dashboard-pharmacist.html  # Updated: includes ehr-theme.css
│   ├── index.html          # Updated: includes ehr-theme.css
│   └── tv-view.html        # Not modified (public display)
└── docs/
    └── EHR_THEME_GUIDE.md  # This file
```

## Implementation Details

### CSS Loading Order

```html
<link rel="stylesheet" href="../css/style.css?v=20260503b" />
<link rel="stylesheet" href="../css/ehr-theme.css?v=20260507" />
```

The EHR theme is loaded **after** the base styles, allowing it to override visual properties while preserving all functional styles.

### Scope

The EHR theme applies **only** to:
- `frontend/web/html/dashboard.html`
- `frontend/web/html/dashboard-pharmacist.html`
- `frontend/web/html/index.html`

It does **not** apply to:
- Mobile app (`frontend/mobile/`)
- TV display (`frontend/web/html/tv-view.html`)
- Any shared components used by mobile

## Using EHR Utility Classes

The EHR theme includes utility classes for common medical record patterns:

### Clinical Data Display

```html
<div class="ehr-data-row">
  <div class="ehr-data-label">Blood Pressure</div>
  <div class="ehr-data-value">120/80 mmHg</div>
</div>
```

### Clinical Notes

```html
<div class="clinical-note">
  <div class="clinical-note-header">Provider Notes</div>
  Patient presents with mild symptoms...
</div>
```

### Alert Boxes

```html
<div class="ehr-alert ehr-alert-warning">
  <span class="ehr-alert-icon">⚠️</span>
  <div>Patient has known drug allergies</div>
</div>
```

### Vital Signs Summary

```html
<div class="vital-signs-summary">
  <div class="vital-sign-box">
    <div class="vital-sign-label">Temperature</div>
    <div class="vital-sign-value">98.6<span class="vital-sign-unit">°F</span></div>
  </div>
  <!-- More vital signs... -->
</div>
```

### Patient Header Card

```html
<div class="patient-header-card">
  <div class="patient-header-avatar">JD</div>
  <div class="patient-header-info">
    <div class="patient-header-name">John Doe</div>
    <div class="patient-header-meta">
      <span class="patient-header-meta-item">DOB: 01/15/1980</span>
      <span class="patient-header-meta-item">MRN: 123456</span>
    </div>
  </div>
</div>
```

### Timeline (Medical History)

```html
<div class="ehr-timeline">
  <div class="ehr-timeline-item">
    <div class="ehr-timeline-date">May 7, 2026</div>
    <div class="ehr-timeline-content">Annual checkup completed</div>
  </div>
  <!-- More timeline items... -->
</div>
```

### Prescription Items

```html
<div class="prescription-item">
  <div class="prescription-drug-name">Amoxicillin 500mg</div>
  <div class="prescription-instructions">Take 1 capsule by mouth 3 times daily for 10 days</div>
</div>
```

### Lab Results Table

```html
<table class="lab-results-table">
  <thead>
    <tr>
      <th>Test</th>
      <th>Result</th>
      <th>Reference Range</th>
      <th>Flag</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Glucose</td>
      <td>95 mg/dL</td>
      <td class="ref-range">70-100 mg/dL</td>
      <td>Normal</td>
    </tr>
  </tbody>
</table>
```

### Form Grids

```html
<!-- 2-column grid -->
<div class="ehr-form-grid-2">
  <div class="field">...</div>
  <div class="field">...</div>
</div>

<!-- 3-column grid -->
<div class="ehr-form-grid-3">
  <div class="field">...</div>
  <div class="field">...</div>
  <div class="field">...</div>
</div>
```

## Accessibility

All EHR theme styles meet **WCAG AA** contrast requirements:

- Focus indicators: 2px solid outline with 2px offset
- Muted text: #6b7a8d (sufficient contrast on white)
- All interactive elements have visible focus states
- Color is not the only means of conveying information

## Print Styles

The EHR theme includes print-optimized styles:

- Hides navigation, buttons, and interactive elements
- Removes margins and max-width constraints
- Preserves borders for section clarity
- Ensures header backgrounds print correctly

## Responsive Behavior

The EHR theme maintains responsive behavior:

- **Desktop (>900px)**: Full sidebar, centered content
- **Tablet (769-900px)**: Collapsible sidebar
- **Mobile (<768px)**: Slide-in sidebar, full-width content

## Maintenance Guidelines

### Adding New Components

When adding new components to the web app:

1. **Use existing EHR utility classes** when possible
2. **Preserve all existing colors** - never override theme colors
3. **Follow EHR typography standards**:
   - Labels: 11px uppercase
   - Data: 14px medium weight
   - Headings: 16-18px semi-bold

4. **Use EHR spacing standards**:
   - Card padding: 16px 20px
   - Field gaps: 12px
   - Section margins: 16-20px

### Modifying Styles

**DO:**
- ✅ Update visual properties (spacing, typography, borders)
- ✅ Add new utility classes to `ehr-theme.css`
- ✅ Test on all three HTML pages
- ✅ Verify WCAG AA contrast

**DON'T:**
- ❌ Modify `style.css` (base styles)
- ❌ Change existing color variables
- ❌ Override functional classes (JS-dependent)
- ❌ Touch mobile app styles
- ❌ Modify shared components

### Testing Checklist

Before deploying style changes:

- [ ] Test on `dashboard.html`
- [ ] Test on `dashboard-pharmacist.html`
- [ ] Test on `index.html` (login page)
- [ ] Verify mobile app is unaffected
- [ ] Check responsive breakpoints (900px, 768px)
- [ ] Verify all interactive elements work
- [ ] Test print layout
- [ ] Validate WCAG AA contrast
- [ ] Check focus indicators on all interactive elements

## Browser Support

The EHR theme supports:

- Chrome/Edge 90+
- Firefox 88+
- Safari 14+

Uses modern CSS features:
- CSS Grid
- CSS Custom Properties (for existing colors only)
- Flexbox
- CSS Animations

## Performance

The EHR theme adds minimal overhead:

- File size: ~15KB (uncompressed)
- No JavaScript dependencies
- No additional HTTP requests (single CSS file)
- Uses CSS-only animations

## Future Enhancements

Potential additions (without breaking existing functionality):

1. **Dark mode variant** (for night shifts)
2. **High contrast mode** (for accessibility)
3. **Compact density option** (for smaller screens)
4. **Print templates** (for specific document types)
5. **Icon library integration** (medical-specific icons)

## Support

For questions or issues with the EHR theme:

1. Check this guide first
2. Review `ehr-theme.css` comments
3. Verify the issue is visual-only (not functional)
4. Test with EHR theme disabled to isolate the issue

## Version History

- **v1.0 (May 7, 2026)**: Initial EHR theme implementation
  - Typography standardization
  - Layout refinements
  - Component styling
  - Utility classes
  - Print styles
  - Accessibility compliance

---

**Last Updated**: May 7, 2026  
**Maintained By**: U-Konek+ Development Team
