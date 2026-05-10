# EHR Theme Quick Reference

## Typography

| Element | Size | Weight | Transform | Letter Spacing |
|---------|------|--------|-----------|----------------|
| Body text | 13-14px | 400 | none | normal |
| Labels | 11px | 500 | uppercase | 0.06em |
| Data values | 14px | 500 | none | normal |
| Headings | 16-18px | 600 | none | -0.01em |
| Badges | 11px | 600 | uppercase | 0.05em |

## Spacing

| Element | Value |
|---------|-------|
| Card padding | 16px 20px |
| Field gap | 12px |
| Section margin | 16-20px |
| Border radius | 4-6px |

## Colors (New Elements Only)

| Purpose | Text | Background |
|---------|------|------------|
| Success/Normal | #166534 | #dcfce7 |
| Warning/Borderline | #854d0e | #fef9c3 |
| Danger/Critical | #991b1b | #fee2e2 |
| Border/Divider | - | #d0d7e2 |
| Page Background | - | #f0f2f5 |
| Muted Text | #6b7a8d | - |

## Common Patterns

### Data Row
```html
<div class="ehr-data-row">
  <div class="ehr-data-label">Label</div>
  <div class="ehr-data-value">Value</div>
</div>
```

### Alert
```html
<div class="ehr-alert ehr-alert-warning">
  <span class="ehr-alert-icon">⚠️</span>
  <div>Message</div>
</div>
```

### Badge
```html
<span class="badge-normal">Normal</span>
<span class="badge-warning">Warning</span>
<span class="badge-danger">Critical</span>
```

### Form Grid
```html
<div class="ehr-form-grid-2">
  <div class="field">...</div>
  <div class="field">...</div>
</div>
```

### ID/Code Field
```html
<span class="ticket-code">TKT-12345</span>
```

## Component Sizes

| Component | Padding | Border Radius | Font Size |
|-----------|---------|---------------|-----------|
| Button | 7px 16px | 4px | 13px |
| Input | 6px 10px | 4px | 13px |
| Badge | 2px 8px | 3px | 11px |
| Card | 16px 20px | 6px | 13px |

## Responsive Breakpoints

| Breakpoint | Behavior |
|------------|----------|
| >900px | Full sidebar, centered content |
| 769-900px | Collapsible sidebar |
| <768px | Slide-in sidebar, full-width |

## Focus States

All interactive elements:
```css
outline: 2px solid var(--primary);
outline-offset: 2px;
```

## Print Behavior

- Hides: sidebar, topbar, buttons
- Shows: content only
- Preserves: borders, backgrounds
- Layout: full-width, no margins

## File Locations

- Theme CSS: `frontend/web/css/ehr-theme.css`
- Base CSS: `frontend/web/css/style.css`
- Documentation: `frontend/web/docs/EHR_THEME_GUIDE.md`

## Quick Checks

✅ **Before committing:**
- [ ] Tested on all 3 HTML pages
- [ ] Mobile app unaffected
- [ ] All buttons work
- [ ] Forms submit correctly
- [ ] Print layout looks good
- [ ] Focus indicators visible

❌ **Never modify:**
- Existing color variables
- Mobile app files
- Shared components
- JavaScript logic
- API calls

## Common Mistakes

1. ❌ Changing `--primary` color → ✅ Use existing primary color
2. ❌ Editing `style.css` → ✅ Add to `ehr-theme.css`
3. ❌ Removing functional classes → ✅ Only override visual properties
4. ❌ Breaking mobile app → ✅ Test mobile is unaffected

## Need Help?

1. Check `EHR_THEME_GUIDE.md`
2. Review `ehr-theme.css` comments
3. Test with theme disabled
4. Verify issue is visual-only
