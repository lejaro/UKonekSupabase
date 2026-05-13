# Input Validation - Code Examples

## Quick Start Examples

### Example 1: Web Login Form

**Before (No Validation):**
```html
<form id="loginForm" onsubmit="handleLogin(event)">
    <input type="email" name="email" placeholder="Email">
    <input type="password" name="password" placeholder="Password">
    <button type="submit">Login</button>
</form>

<script>
function handleLogin(e) {
    e.preventDefault();
    const email = e.target.email.value;
    const password = e.target.password.value;
    // Submit to API
}
</script>
```

**After (With Validation):**
```html
<link rel="stylesheet" href="/css/validation.css">

<form id="loginForm">
    <div class="form-group">
        <label class="required-field">Email</label>
        <input type="email" name="email" placeholder="Email" class="form-control">
    </div>
    <div class="form-group">
        <label class="required-field">Password</label>
        <input type="password" name="password" placeholder="Password" class="form-control">
    </div>
    <button type="submit">Login</button>
</form>

<script src="/js/validation.js"></script>
<script>
document.addEventListener('DOMContentLoaded', function() {
    const loginForm = document.getElementById('loginForm');
    
    // Attach validation
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
    
    // Handle submission
    loginForm.addEventListener('submit', function(e) {
        e.preventDefault();
        
        // Values are already sanitized by validator
        const email = loginForm.elements.email.value;
        const password = loginForm.elements.password.value;
        
        // Submit to API
        fetch('/api/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email, password })
        });
    });
});
</script>
```

---

### Example 2: Mobile Registration Form

**Before (No Validation):**
```dart
TextFormField(
  controller: firstNameController,
  decoration: InputDecoration(labelText: 'First Name'),
)
```

**After (With Validation):**
```dart
import 'package:ukonekmobile/utils/input_validator.dart';

TextFormField(
  controller: firstNameController,
  decoration: InputDecoration(
    labelText: 'First Name *',
    hintText: 'Enter your first name',
  ),
  validator: InputValidator.createValidator(
    required: true,
    fieldName: 'First Name',
    isName: true,
    minLength: 2,
    maxLength: 50,
  ),
  onChanged: (value) {
    // Auto-sanitize on change
    final sanitized = InputValidator.sanitizeText(value);
    if (sanitized != null && sanitized != value) {
      firstNameController.text = sanitized;
      firstNameController.selection = TextSelection.fromPosition(
        TextPosition(offset: sanitized.length),
      );
    }
  },
)
```

---

### Example 3: Queue Ticket Form (Web)

```html
<form id="queueTicketForm">
    <div class="form-group">
        <label class="required-field">Service Type</label>
        <select name="serviceType" class="form-control">
            <option value="">Select Service</option>
            <option value="consultation">Consultation</option>
            <option value="pharmacy">Pharmacy</option>
        </select>
    </div>
    
    <div class="form-group">
        <label class="required-field">Citizen Type</label>
        <select name="citizenType" class="form-control">
            <option value="">Select Type</option>
            <option value="regular">Regular</option>
            <option value="pwd">PWD</option>
            <option value="pregnant">Pregnant</option>
        </select>
    </div>
    
    <div class="form-group">
        <label class="required-field">Reason for Visit</label>
        <textarea name="reason" class="form-control" rows="3" 
                  placeholder="Describe your reason for visit"></textarea>
    </div>
    
    <div class="form-group">
        <label>Symptoms (Optional)</label>
        <textarea name="symptoms" class="form-control" rows="3" 
                  placeholder="List any symptoms"></textarea>
    </div>
    
    <button type="submit" class="btn btn-primary">Get Queue Ticket</button>
</form>

<script src="/js/validation.js"></script>
<script>
document.addEventListener('DOMContentLoaded', function() {
    const form = document.getElementById('queueTicketForm');
    
    InputValidator.attachToForm(form, {
        serviceType: {
            required: true,
            label: 'Service Type'
        },
        citizenType: {
            required: true,
            label: 'Citizen Type'
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
    
    form.addEventListener('submit', async function(e) {
        e.preventDefault();
        
        const formData = {
            serviceKey: form.elements.serviceType.value,
            serviceLabel: form.elements.serviceType.options[form.elements.serviceType.selectedIndex].text,
            citizenType: form.elements.citizenType.value,
            reason: form.elements.reason.value,
            symptoms: form.elements.symptoms.value || null
        };
        
        try {
            const response = await fetch('/api/queue-tickets', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(formData)
            });
            
            if (response.ok) {
                alert('Queue ticket created successfully!');
                form.reset();
            } else {
                const error = await response.json();
                alert('Error: ' + error.message);
            }
        } catch (error) {
            alert('Network error. Please try again.');
        }
    });
});
</script>
```

---

### Example 4: Queue Ticket Form (Mobile)

```dart
import 'package:flutter/material.dart';
import 'package:ukonekmobile/utils/input_validator.dart';
import 'package:ukonekmobile/services/api_service.dart';

class QueueTicketForm extends StatefulWidget {
  @override
  _QueueTicketFormState createState() => _QueueTicketFormState();
}

class _QueueTicketFormState extends State<QueueTicketForm> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _symptomsController = TextEditingController();
  
  String? _selectedService;
  String? _selectedCitizenType;
  
  @override
  void dispose() {
    _reasonController.dispose();
    _symptomsController.dispose();
    super.dispose();
  }
  
  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fix the errors before submitting')),
      );
      return;
    }
    
    try {
      final result = await ApiService().createQueueTicket(
        serviceKey: _selectedService!,
        serviceLabel: _getServiceLabel(_selectedService!),
        citizenType: _selectedCitizenType!,
        reason: _reasonController.text,
        symptoms: _symptomsController.text.isEmpty ? null : _symptomsController.text,
      );
      
      if (result != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Queue ticket created successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }
  
  String _getServiceLabel(String key) {
    switch (key) {
      case 'consultation': return 'Consultation';
      case 'pharmacy': return 'Pharmacy';
      default: return key;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Get Queue Ticket')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            // Service Type Dropdown
            DropdownButtonFormField<String>(
              value: _selectedService,
              decoration: InputDecoration(
                labelText: 'Service Type *',
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 'consultation', child: Text('Consultation')),
                DropdownMenuItem(value: 'pharmacy', child: Text('Pharmacy')),
              ],
              onChanged: (value) => setState(() => _selectedService = value),
              validator: (value) => InputValidator.validateRequired(
                value,
                fieldName: 'Service Type',
              ),
            ),
            SizedBox(height: 16),
            
            // Citizen Type Dropdown
            DropdownButtonFormField<String>(
              value: _selectedCitizenType,
              decoration: InputDecoration(
                labelText: 'Citizen Type *',
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 'regular', child: Text('Regular')),
                DropdownMenuItem(value: 'pwd', child: Text('PWD')),
                DropdownMenuItem(value: 'pregnant', child: Text('Pregnant')),
              ],
              onChanged: (value) => setState(() => _selectedCitizenType = value),
              validator: (value) => InputValidator.validateRequired(
                value,
                fieldName: 'Citizen Type',
              ),
            ),
            SizedBox(height: 16),
            
            // Reason Field
            TextFormField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: 'Reason for Visit *',
                hintText: 'Describe your reason for visit',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 500,
              validator: InputValidator.createValidator(
                required: true,
                fieldName: 'Reason',
                minLength: 10,
                maxLength: 500,
              ),
            ),
            SizedBox(height: 16),
            
            // Symptoms Field (Optional)
            TextFormField(
              controller: _symptomsController,
              decoration: InputDecoration(
                labelText: 'Symptoms (Optional)',
                hintText: 'List any symptoms',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 1000,
              validator: InputValidator.createValidator(
                required: false,
                maxLength: 1000,
              ),
            ),
            SizedBox(height: 24),
            
            // Submit Button
            ElevatedButton(
              onPressed: _submitForm,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text('Get Queue Ticket', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

### Example 5: Profile Update Form (Web)

```javascript
// profile-update.js
document.addEventListener('DOMContentLoaded', function() {
    const profileForm = document.getElementById('profileForm');
    
    // Attach validation
    InputValidator.attachToForm(profileForm, {
        firstName: {
            required: true,
            label: 'First Name',
            minLength: 2,
            maxLength: 50
        },
        lastName: {
            required: true,
            label: 'Last Name',
            minLength: 2,
            maxLength: 50
        },
        email: {
            required: true,
            type: 'email',
            label: 'Email'
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
    
    // Handle form submission
    profileForm.addEventListener('submit', async function(e) {
        e.preventDefault();
        
        const formData = {
            firstName: profileForm.elements.firstName.value,
            lastName: profileForm.elements.lastName.value,
            email: profileForm.elements.email.value,
            phone: profileForm.elements.phone.value,
            address: profileForm.elements.address.value || null
        };
        
        try {
            const response = await fetch('/api/profile', {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(formData)
            });
            
            if (response.ok) {
                alert('Profile updated successfully!');
            } else {
                const error = await response.json();
                InputValidator.showFormError(profileForm, error.message);
            }
        } catch (error) {
            InputValidator.showFormError(profileForm, 'Network error. Please try again.');
        }
    });
});
```

---

### Example 6: Search Form with Validation

```javascript
// search-form.js
const searchForm = document.getElementById('searchForm');
const searchInput = searchForm.elements.query;

// Real-time validation
searchInput.addEventListener('input', function() {
    const sanitized = InputValidator.sanitizeText(this.value);
    
    if (sanitized === null) {
        InputValidator.showFieldError(this, 'Search query cannot be empty');
    } else if (sanitized.length < 3) {
        InputValidator.showFieldError(this, 'Search query must be at least 3 characters');
    } else {
        InputValidator.clearFieldError(this);
    }
});

// Form submission
searchForm.addEventListener('submit', function(e) {
    e.preventDefault();
    
    const result = InputValidator.validateMinLength(
        searchInput.value,
        3,
        'Search query'
    );
    
    if (!result.valid) {
        InputValidator.showFieldError(searchInput, result.error);
        return;
    }
    
    // Perform search with sanitized value
    performSearch(result.value);
});
```

---

### Example 7: Custom Validator (Mobile)

```dart
// Custom validator for password confirmation
TextFormField(
  controller: confirmPasswordController,
  decoration: InputDecoration(labelText: 'Confirm Password'),
  obscureText: true,
  validator: (value) {
    // First check if it's not empty
    final emptyError = InputValidator.validateRequired(
      value,
      fieldName: 'Confirm Password',
    );
    if (emptyError != null) return emptyError;
    
    // Then check if it matches
    if (value != passwordController.text) {
      return 'Passwords do not match';
    }
    
    return null;
  },
)
```

---

### Example 8: Batch Validation (Web)

```javascript
// Validate multiple fields at once
function validateRegistrationForm(formData) {
    const errors = {};
    
    // Validate first name
    const firstNameResult = InputValidator.validateRequired(
        formData.firstName,
        'First Name'
    );
    if (!firstNameResult.valid) {
        errors.firstName = firstNameResult.error;
    }
    
    // Validate email
    const emailResult = InputValidator.validateEmail(formData.email);
    if (!emailResult.valid) {
        errors.email = emailResult.error;
    }
    
    // Validate phone
    const phoneResult = InputValidator.validatePhoneNumber(formData.phone);
    if (!phoneResult.valid) {
        errors.phone = phoneResult.error;
    }
    
    // Return errors or null
    return Object.keys(errors).length > 0 ? errors : null;
}

// Usage
const formData = {
    firstName: document.getElementById('firstName').value,
    email: document.getElementById('email').value,
    phone: document.getElementById('phone').value
};

const errors = validateRegistrationForm(formData);
if (errors) {
    // Display errors
    Object.keys(errors).forEach(field => {
        const input = document.getElementById(field);
        InputValidator.showFieldError(input, errors[field]);
    });
} else {
    // Submit form
    submitRegistration(formData);
}
```

---

## Testing Examples

### Test Database Validation

```sql
-- Test 1: Empty input should return NULL
SELECT validate_text_input('   ');
-- Expected: NULL

-- Test 2: Whitespace should be trimmed
SELECT validate_text_input('  Hello World  ');
-- Expected: 'Hello World'

-- Test 3: Multiple spaces should be normalized
SELECT validate_text_input('Hello    World');
-- Expected: 'Hello World'

-- Test 4: Required field with empty input should error
SELECT validate_required_text('   ', 'Name');
-- Expected: ERROR: Name cannot be empty or contain only spaces

-- Test 5: Email should be lowercase
SELECT validate_email('USER@EXAMPLE.COM');
-- Expected: 'user@example.com'

-- Test 6: Invalid email should error
SELECT validate_email('not-an-email');
-- Expected: ERROR: Invalid email format

-- Test 7: Phone should be formatted
SELECT validate_phone_number('9171234567');
-- Expected: '+639171234567'

-- Test 8: Invalid phone should error
SELECT validate_phone_number('12345');
-- Expected: ERROR: Phone number must be 10 digits
```

---

## Common Patterns

### Pattern 1: Optional Field with Validation

```javascript
// Web
{
    middleName: {
        required: false,  // Optional field
        minLength: 2,     // But if provided, must be at least 2 chars
        maxLength: 50
    }
}
```

```dart
// Mobile
validator: (value) {
  // If empty, allow it
  if (value == null || value.trim().isEmpty) return null;
  
  // If provided, validate it
  return InputValidator.validateMinLength(value, 2, fieldName: 'Middle Name');
}
```

### Pattern 2: Conditional Validation

```javascript
// Validate emergency contact only if provided
if (emergencyContact.value.trim() !== '') {
    const result = InputValidator.validatePhoneNumber(emergencyContact.value);
    if (!result.valid) {
        InputValidator.showFieldError(emergencyContact, result.error);
    }
}
```

### Pattern 3: Cross-Field Validation

```dart
// Ensure emergency contact is different from primary contact
validator: (value) {
  final error = InputValidator.validatePhoneNumber(value);
  if (error != null) return error;
  
  if (value == contactController.text) {
    return 'Emergency contact must be different from your contact';
  }
  
  return null;
}
```

---

**For more examples, see [INPUT_VALIDATION_GUIDE.md](./INPUT_VALIDATION_GUIDE.md)**
