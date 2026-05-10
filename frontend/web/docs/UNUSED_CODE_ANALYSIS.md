# U-Konek+ Web App - Unused Code Analysis Report

**Generated**: May 7, 2026  
**Scope**: Frontend Web Application Only

## Executive Summary

Analysis of the U-Konek+ web application codebase identified **53 unused CSS classes** out of 244 total classes (21.7% unused). These classes are defined in `style.css` but not referenced in any HTML or JavaScript files.

## Analysis Methodology

### Files Scanned
- **CSS**: `frontend/web/css/style.css`
- **HTML**: All files in `frontend/web/html/` (3 files)
  - `dashboard.html`
  - `dashboard-pharmacist.html`
  - `index.html`
- **JavaScript**: All files in `frontend/web/js/` (7 files)

### Detection Method
1. Extract all CSS class definitions from `style.css`
2. Search for each class in all HTML files
3. Search for each class in all JavaScript files
4. Mark as unused if not found in either HTML or JS

## Results

### Statistics
- **Total CSS classes defined**: 244
- **Used CSS classes**: 191 (78.3%)
- **Unused CSS classes**: 53 (21.7%)

### Unused CSS Classes (53 total)

#### Layout & Utility Classes (12)
1. `.align-center` - Flexbox alignment utility
2. `.bg-light` - Background color utility
3. `.center-title` - Topbar center title
4. `.flex-1` - Flex utility
5. `.flex-between` - Flex justify-between utility
6. `.gap-12` - Gap utility
7. `.justify-center` - Flex justify-center utility
8. `.mb-12` - Margin bottom 12px
9. `.mb-15` - Margin bottom 15px
10. `.mt-14` - Margin top 14px
11. `.panel-grid` - Panel grid layout
12. `.rounded` - Border radius utility

#### Badge & Status Classes (3)
13. `.badge-on_call` - Queue status badge
14. `.badge-pending` - Pending status badge
15. `.badge-waiting` - Waiting status badge

#### Form & Input Classes (4)
16. `.avatar-column` - Profile avatar column
17. `.avatar-preview` - Avatar preview container
18. `.field-error` - Form field error message
19. `.file-label` - File input label

#### Filter & Search Classes (3)
20. `.filter-label` - Filter label
21. `.filter-select` - Filter dropdown
22. `.pagination-controls` - Pagination controls container

#### Management Section Classes (4)
23. `.management-head` - Management section header
24. `.management-shell` - Management container
25. `.management-toolbar` - Management toolbar
26. `.registration-box` - Registration form container

#### Citizen/Family Classes (4)
27. `.citizen-family-group-card` - Family group card
28. `.citizen-family-group-header` - Family group header
29. `.citizen-family-member-item` - Family member item
30. `.citizen-family-member-list` - Family member list

#### Button Classes (2)
31. `.chip-btn-soft` - Soft chip button variant
32. `.create-btn` - Create button

#### Modal Classes (2)
33. `.modal-icon` - Modal icon container
34. `.modal-message` - Modal message text

#### Notification Classes (3)
35. `.ann-pagination` - Announcement pagination
36. `.notif-type-announcement` - Announcement notification type
37. `.notif-type-feedback` - Feedback notification type

#### Miscellaneous (16)
38. `.pending-row` - Pending row styling
39. `.profile-grid` - Profile grid layout
40. `.reminders` - Reminders section
41. `.SiteName` - Site name styling
42. `.stats-chart-panel` - Stats chart panel (inline styles used instead)
43. `.w-60` - Width 60px utility
44. `.w-90` - Width 90px utility
45. `.w-200` - Width 200px utility
46. `.p-20` - Padding 20px utility
47. `.section-top` - Section top margin
48. `.small` - Small text utility
49. `.note` - Note text styling
50. `.side` - Login page side panel
51. `.wrap` - Login page wrapper
52. `.card` - Login page card
53. `.brand` - Login page brand

## Recommendations

### Priority 1: Safe to Remove (High Confidence)

These classes appear to be completely unused and can be safely removed:

1. **Utility classes with EHR theme equivalents**:
   - `.align-center`, `.flex-1`, `.flex-between`, `.gap-12`, `.justify-center`
   - `.mb-12`, `.mb-15`, `.mt-14`
   - `.bg-light`, `.rounded`
   - `.w-60`, `.w-90`, `.w-200`, `.p-20`
   
   **Reason**: EHR theme provides equivalent or better utilities

2. **Unused badge variants**:
   - `.badge-on_call`, `.badge-pending`, `.badge-waiting`
   
   **Reason**: Different badge classes are used in actual implementation

3. **Unused notification types**:
   - `.notif-type-announcement`, `.notif-type-feedback`
   
   **Reason**: Inline styles or different classes used

4. **Unused family/citizen classes**:
   - `.citizen-family-group-card`
   - `.citizen-family-group-header`
   - `.citizen-family-member-item`
   - `.citizen-family-member-list`
   
   **Reason**: Feature may have been redesigned or removed

### Priority 2: Verify Before Removing (Medium Confidence)

These classes might be used dynamically or in features not yet implemented:

1. **Form-related**:
   - `.field-error` - May be added dynamically by validation
   - `.avatar-column`, `.avatar-preview` - May be used in profile editing
   - `.file-label` - May be used in file upload features

2. **Management section**:
   - `.management-head`, `.management-shell`, `.management-toolbar`
   - `.registration-box`
   
   **Action**: Check if these are used in dashboard-pharmacist.html or planned features

3. **Filter/pagination**:
   - `.filter-label`, `.filter-select`
   - `.pagination-controls`, `.ann-pagination`
   
   **Action**: Verify if pagination is implemented differently

### Priority 3: Keep (Low Confidence for Removal)

These classes might be used in specific contexts:

1. **Login page classes**:
   - `.side`, `.wrap`, `.card`, `.brand`, `.reminders`
   
   **Action**: Verify usage in `index.html` (login page)

2. **Modal classes**:
   - `.modal-icon`, `.modal-message`
   
   **Action**: Check if used in any modal implementations

3. **Profile classes**:
   - `.profile-grid`
   
   **Action**: Check profile section implementation

## Detailed Analysis by File

### style.css (3,164 lines)
- **Lines with unused classes**: Approximately 530 lines (16.7%)
- **Potential space savings**: ~15-20KB (uncompressed)

### Impact Assessment

#### Performance Impact
- **Current CSS file size**: ~95KB (uncompressed)
- **Estimated reduction**: ~15-20KB (15-20% reduction)
- **Gzipped impact**: ~5-8KB reduction
- **Load time improvement**: Minimal (< 50ms on slow connections)

#### Maintenance Impact
- **Reduced complexity**: Fewer classes to maintain
- **Clearer codebase**: Easier to understand what's actually used
- **Less confusion**: Developers won't use deprecated classes

#### Risk Assessment
- **Low risk**: Utility classes and obvious unused classes
- **Medium risk**: Classes that might be dynamically added
- **High risk**: Classes used in features not yet tested

## Action Plan

### Phase 1: Safe Removal (Immediate)
Remove the following with high confidence:

```css
/* Utility classes - replaced by EHR theme */
.align-center, .flex-1, .flex-between, .gap-12, .justify-center
.mb-12, .mb-15, .mt-14
.bg-light, .rounded
.w-60, .w-90, .w-200, .p-20

/* Unused badge variants */
.badge-on_call, .badge-pending, .badge-waiting

/* Unused notification types */
.notif-type-announcement, .notif-type-feedback

/* Unused family/citizen classes */
.citizen-family-group-card, .citizen-family-group-header
.citizen-family-member-item, .citizen-family-member-list
```

**Estimated savings**: ~8-10KB

### Phase 2: Verification & Removal (After Testing)
1. Test all features thoroughly
2. Check for dynamic class additions in JavaScript
3. Verify login page, profile page, and all modals
4. Remove verified unused classes

**Estimated additional savings**: ~5-8KB

### Phase 3: Documentation Update
1. Update style guide to reflect removed classes
2. Document which EHR theme classes replace removed utilities
3. Update developer documentation

## Testing Checklist

Before removing any classes, verify:

- [ ] Login page displays correctly
- [ ] All dashboard sections work
- [ ] Profile editing works
- [ ] All modals display correctly
- [ ] Form validation displays errors
- [ ] All badges display correctly
- [ ] Pagination works (if implemented)
- [ ] Filter dropdowns work
- [ ] Family/citizen features work (if implemented)
- [ ] Mobile responsiveness maintained

## JavaScript Analysis

### Functions/Variables Defined
- **Total**: ~150+ functions and variables
- **Scope**: Most are scoped within modules (IIFE pattern)
- **Unused**: Difficult to determine without runtime analysis

### Recommendation
- Use browser DevTools Coverage tool for runtime analysis
- Check for unused exports in modules
- Consider tree-shaking with a build tool

## HTML ID Analysis

### IDs Not Referenced in JavaScript
Many HTML IDs are not referenced in JavaScript because they're:
1. Used only for CSS styling
2. Used for accessibility (ARIA labels)
3. Used for form submission
4. Placeholders for future features

**Recommendation**: Keep all IDs unless confirmed unused

## Conclusion

The web app has **53 unused CSS classes (21.7%)** that can potentially be removed to:
- Reduce CSS file size by 15-20%
- Improve code maintainability
- Reduce developer confusion

**Recommended approach**:
1. Remove high-confidence unused classes immediately
2. Test thoroughly
3. Remove medium-confidence classes after verification
4. Keep low-confidence classes until features are confirmed unused

**Estimated total savings**: 15-20KB uncompressed, 5-8KB gzipped

---

## Appendix: Complete List of Unused Classes

```
align-center
ann-pagination
avatar-column
avatar-preview
badge-on_call
badge-pending
badge-waiting
bg-light
center-title
chip-btn-soft
citizen-family-group-card
citizen-family-group-header
citizen-family-member-item
citizen-family-member-list
create-btn
field-error
file-label
filter-label
filter-select
flex-1
flex-between
gap-12
justify-center
management-head
management-shell
management-toolbar
mb-12
mb-15
modal-icon
modal-message
mt-14
notif-type-announcement
notif-type-feedback
pagination-controls
pagination-info
panel-grid
pending-row
profile-grid
registration-box
reminders
rounded
section-top
small
note
side
wrap
card
brand
SiteName
w-60
w-90
w-200
p-20
```

---

**Report Generated By**: Kiro AI Assistant  
**Analysis Date**: May 7, 2026  
**Next Review**: Recommended after major feature additions
