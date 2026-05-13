# Input Validation System - Implementation Guide

## Overview

This system provides comprehensive input validation across the entire application stack:
- **Database Level**: PostgreSQL functions, triggers, and constraints
- **Web Frontend**: JavaScript validation utility
- **Mobile Frontend**: Dart/Flutter validation utility
- **Backend API**: Automatic sanitization via database triggers

## Features

✅ **Automatic whitespace trimming** - Leading and trailing spaces removed  
✅ **Whitespace-only rejection** - Empty or space-only inputs are rejected  
✅ **Space normalization** - Multiple consecutive spaces reduced to single space  
✅ **Format validation** - Email, phone, name, numeric formats validated  
✅ **Length constraints** - Min/max length validation  
✅ **User-friendly errors** - Clear, actionable error messages  
✅ **Real-time validation** - Immediate feedback on blur/submit  
✅ **Security hardened** - Database-level enforcement prevents bypass  

---

## Database Level Validation

### Available Functions

#### 1. `validate_text_input(TEXT)`
Sanitizes text by trimming and normalizing spaces. Returns NULL if empty.

```sql
SELECT validate_text_input('  Hello   World  ');
-- Returns: 'Hello World'

SELECT validate_text_input('   ');
-- Returns: NULL
```

#### 2. `validate_required_text(TEXT, TEXT)`
Validates required field. Throws error if empty or whitespace-only.

```sql
SELECT validate_required_text('John Doe', 'First Name');
-- Returns: 'John Doe'

SELECT validate_required_text('   ', 'First Name');
-- ERROR: First Name cannot be empty or contain only spaces
```

#### 3. `validate_email(TEXT)`
Validates and sanitizes email format.

```sql
SELECT validate_email('  USER@EXAMPLE.COM  ');
-- Returns: 'user@example.com'

SELECT validate_email('invalid-email');
-- ERROR: Invalid email format
```

#### 4. `validate_phone_number(TEXT)`
Validates Philippine phone format (10 digits after +63).

```sql
SELECT validate_phone_number('9171234567');
-- Returns: '+639171234567'

SELECT validate_phone_number('123456');
-- ERROR: Phone number must be 10 digits
```

### Automatic Triggers

All text columns in these tables are automatically sanitized on INSERT/UPDATE:
- `public.citizens`
- `public.staff`
- `public.queue_tickets`

### Check Constraints

Database-level constraints prevent invalid data:
- Citizens: `firstname`, `surname`, `email` cannot be empty
- Staff: `first_name`, `last_name`, `username`, `email` cannot be empty
- Queue tickets: `service_label`, `citizen_type` cannot be empty

---

## Web Application (JavaScript)

### Setup

Include the validation script in your HTML:

```html
<script src="/js/validation.js"></script>
```

### Basic Usage

#### Manual Validation

```javascript
// Validate required field
const result = InputValidator.validateRequired(userInput, 'Username');
if (!result.valid) {
    console.error(result.error);
} else {
    console.log('Sanitized value:', result.value);
}

// Validate email
const emailResult = InputValidator.validateEmail(emailInput);
if (!emailResult.valid) {
    showError(emailResult.error);
}

// Validate phone
const phoneResult = InputValidator.validatePhoneNumber(phoneInput);
if (phoneResult.valid) {
    submitForm(phoneResult.value); // Use sanitized value
}
```

#### Auto-Attach to Form

```javascript
const form = document.getElementById('registrationForm');

InputValidator.attachToForm(form, {
    firstName: {
        required: true,
        label: 'First Name',
        minLength: 2,
        maxLength: 50
    },
    email: {
        required: true,
        type: 'email',
        label: 'Email Address'
    },
    phone: {
        required: true,
        type: 'phone',
        label: 'Phone Number'
    },
    address: {
        required: false,
        maxLength: 255
    }
});
```

### Available Methods

| Method | Description |
|--------|-------------|
| `sanitizeText(input)` | Trim and normalize spaces |
| `validateRequired(input, fieldName)` | Validate required field |
| `validateEmail(email)` | Validate email format |
| `validatePhoneNumber(phone)` | Validate PH phone (10 digits) |
| `validateMinLength(input, min, fieldName)` | Check minimum length |
| `validateMaxLength(input, max, fieldName)` | Check maximum length |
| `attachToForm(form, rules)` | Auto-attach validation to form |

---

## Mobile Application (Flutter/Dart)

### Setup

Import the validator:

```dart
import 'package:ukonekmobile/utils/input_validator.dart';
```

### Basic Usage

#### TextFormField Validation

```dart
TextFormField(
  controller: firstNameController,
  decoration: InputDecoration(labelText: 'First Name'),
  validator: InputValidator.createValidator(
    required: true,
    fieldName: 'First Name',
    isName: true,
    minLength: 2,
    maxLength: 50,
  ),
)
```

#### Manual Validation

```dart
// Validate required field
String? error = InputValidator.validateRequired(
  userInput,
  fieldName: 'Username',
);
if (error != null) {
  showSnackBar(error);
  return;
}

// Validate email
String? emailError = InputValidator.validateEmail(emailInput);
if (emailError != null) {
  setState(() => emailErrorText = emailError);
}

// Sanitize text
String? sanitized = InputValidator.sanitizeText(userInput);
if (sanitized != null) {
  // Use sanitized value
  submitData(sanitized);
}
```

#### Combine Multiple Validators

```dart
validator: (value) => InputValidator.combineValidators(
  value,
  [
    (v) => InputValidator.validateRequired(v, fieldName: 'Password'),
    (v) => InputValidator.validateMinLength(v, 8, fieldName: 'Password'),
    (v) => v != null && !v.contains(RegExp(r'[A-Z]'))
        ? 'Password must contain uppercase letter'
        : null,
  ],
)
```

### Available Methods

| Method | Description |
|--------|-------------|
| `sanitizeText(input)` | Trim and normalize spaces |
| `validateRequired(input, {fieldName})` | Validate required field |
| `validateEmail(email)` | Validate email format |
| `validatePhoneNumber(phone)` | Validate PH phone (10 digits) |
| `validateMinLength(input, min, {fieldName})` | Check minimum length |
| `validateMaxLength(input, max, {fieldName})` | Check maximum length |
| `validateName(name, {fieldName})` | Validate name (letters only) |
| `validateNumeric(input, {fieldName})` | Validate numeric input |
| `validateAge(age, {minAge, maxAge})` | Validate age range |
| `createValidator({...options})` | Create validator function |
| `combineValidators(input, validators)` | Combine multiple validators |

---

## Example Implementations

### Web: Login Form

```javascript
const loginForm = document.getElementById('loginForm');

InputValidator.attachToForm(loginForm, {
    email: {
        required: true,
        type: 'email',
        label: 'Email'
    },
    password: {
        required: true,
        label: 'Password',
        minLength: 8
    }
});
```

### Web: Queue Ticket Form

```javascript
const queueForm = document.getElementById('queueTicketForm');

InputValidator.attachToForm(queueForm, {
    serviceType: {
        required: true,
        label: 'Service Type'
    },
    reason: {
        required: true,
        label: 'Reason for Visit',
        minLength: 10,
        maxLength: 500
    },
    symptoms: {
        required: false,
        maxLength: 1000
    }
});
```

### Mobile: Registration Form

```dart
Form(
  key: _formKey,
  child: Column(
    children: [
      TextFormField(
        controller: firstNameController,
        decoration: InputDecoration(labelText: 'First Name'),
        validator: InputValidator.createValidator(
          required: true,
          fieldName: 'First Name',
          isName: true,
          minLength: 2,
          maxLength: 50,
        ),
      ),
      TextFormField(
        controller: emailController,
        decoration: InputDecoration(labelText: 'Email'),
        validator: InputValidator.createValidator(
          required: true,
          fieldName: 'Email',
          isEmail: true,
        ),
      ),
      TextFormField(
        controller: phoneController,
        decoration: InputDecoration(labelText: 'Phone Number'),
        keyboardType: TextInputType.phone,
        validator: InputValidator.createValidator(
          required: true,
          fieldName: 'Phone Number',
          isPhone: true,
        ),
      ),
    ],
  ),
)
```

### Mobile: Queue Ticket Form

```dart
TextFormField(
  controller: reasonController,
  decoration: InputDecoration(
    labelText: 'Reason for Visit',
    hintText: 'Describe your concern',
  ),
  maxLines: 3,
  validator: InputValidator.createValidator(
    required: true,
    fieldName: 'Reason',
    minLength: 10,
    maxLength: 500,
  ),
)
```

---

## Testing Validation

### Test Cases

1. **Empty input**: `""` → Should reject
2. **Whitespace only**: `"   "` → Should reject
3. **Leading/trailing spaces**: `"  John  "` → Should trim to `"John"`
4. **Multiple spaces**: `"Hello    World"` → Should normalize to `"Hello World"`
5. **Valid input**: `"John Doe"` → Should accept
6. **Invalid email**: `"notanemail"` → Should reject
7. **Valid email**: `"user@example.com"` → Should accept
8. **Invalid phone**: `"12345"` → Should reject
9. **Valid phone**: `"9171234567"` → Should format to `"+639171234567"`

### Database Testing

```sql
-- Test validation functions
SELECT validate_text_input('  test  '); -- Should return 'test'
SELECT validate_text_input('   '); -- Should return NULL
SELECT validate_required_text('   ', 'Name'); -- Should throw error
SELECT validate_email('USER@TEST.COM'); -- Should return 'user@test.com'
SELECT validate_phone_number('9171234567'); -- Should return '+639171234567'
```

---

## Migration Instructions

### Apply Database Validation

```bash
supabase db push
```

This will:
- Create validation functions
- Add triggers to auto-sanitize inputs
- Add check constraints to tables
- Update `create_queue_ticket` function

### Update Web Forms

1. Include `/js/validation.js` in your HTML pages
2. Add validation rules to forms using `InputValidator.attachToForm()`
3. Test all forms to ensure validation works

### Update Mobile Forms

1. Import `input_validator.dart` in form files
2. Add validators to `TextFormField` widgets
3. Use `InputValidator.createValidator()` for consistent validation
4. Test all forms on device/emulator

---

## Best Practices

1. **Always validate on both frontend and backend** - Frontend for UX, backend for security
2. **Use sanitized values** - Always use the sanitized value returned by validators
3. **Show clear error messages** - Tell users exactly what's wrong and how to fix it
4. **Validate on blur and submit** - Real-time feedback improves UX
5. **Test edge cases** - Empty, whitespace, special characters, very long inputs
6. **Keep validation consistent** - Use the same rules across web and mobile
7. **Document custom validators** - If you add custom validation, document it

---

## Troubleshooting

### "Field cannot be empty" error on valid input
- Check if input has invisible characters (tabs, newlines)
- Verify the field is not disabled or readonly
- Check browser console for JavaScript errors

### Database constraint violation
- Ensure frontend validation matches database constraints
- Check if data is being sanitized before submission
- Verify triggers are enabled on the table

### Validation not working on mobile
- Ensure `input_validator.dart` is imported
- Check if validator is attached to the field
- Verify form key is set and `validate()` is called

---

## Support

For issues or questions:
1. Check this documentation
2. Review example implementations above
3. Test validation functions in database
4. Check browser/app console for errors
5. Verify migration was applied successfully

---

**Last Updated**: May 11, 2026  
**Version**: 1.0.0
