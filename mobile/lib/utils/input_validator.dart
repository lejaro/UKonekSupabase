/// ═══════════════════════════════════════════════════════════════════════════
/// INPUT VALIDATION UTILITY - MOBILE APPLICATION
/// ═══════════════════════════════════════════════════════════════════════════
/// Purpose: Comprehensive client-side input validation for Flutter
/// Features:
///   - Trim and sanitize all text inputs
///   - Reject whitespace-only submissions
///   - Normalize multiple consecutive spaces
///   - Validate email, phone, and other formats
///   - Return user-friendly error messages
/// ═══════════════════════════════════════════════════════════════════════════
library;

class InputValidator {
  /// Sanitize text input by trimming and normalizing spaces
  /// Returns null if input is empty or whitespace-only
  static String? sanitizeText(String? input) {
    if (input == null) return null;

    // Trim leading and trailing whitespace
    String sanitized = input.trim();

    // Return null if empty after trimming
    if (sanitized.isEmpty) return null;

    // Normalize multiple consecutive spaces to single space
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ');

    return sanitized;
  }

  /// Validate required text field
  /// Returns error message if invalid, null if valid
  static String? validateRequired(String? input, {String fieldName = 'This field'}) {
    final sanitized = sanitizeText(input);

    if (sanitized == null) {
      return '$fieldName cannot be empty or contain only spaces';
    }

    return null;
  }

  /// Validate email format
  /// Returns error message if invalid, null if valid
  static String? validateEmail(String? email) {
    final sanitized = sanitizeText(email);

    if (sanitized == null) {
      return 'Email cannot be empty';
    }

    // Convert to lowercase
    final lowerEmail = sanitized.toLowerCase();

    // Email regex pattern
    final emailPattern = RegExp(
      r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
    );

    if (!emailPattern.hasMatch(lowerEmail)) {
      return 'Please enter a valid email address';
    }

    return null;
  }

  /// Validate Philippine phone number (10 digits after +63)
  /// Returns error message if invalid, null if valid
  static String? validatePhoneNumber(String? phone) {
    final sanitized = sanitizeText(phone);

    if (sanitized == null) {
      return 'Phone number cannot be empty';
    }

    // Remove all non-digit characters
    final digitsOnly = sanitized.replaceAll(RegExp(r'[^0-9]'), '');

    // Validate 10 digits
    if (digitsOnly.length != 10) {
      return 'Phone number must be 10 digits (e.g., 9XX XXX XXXX)';
    }

    // Check if starts with 9
    if (!digitsOnly.startsWith('9')) {
      return 'Phone number must start with 9';
    }

    return null;
  }

  /// Validate minimum length
  /// Returns error message if invalid, null if valid
  static String? validateMinLength(
    String? input,
    int minLength, {
    String fieldName = 'This field',
  }) {
    final sanitized = sanitizeText(input);

    if (sanitized == null) {
      return '$fieldName cannot be empty';
    }

    if (sanitized.length < minLength) {
      return '$fieldName must be at least $minLength characters';
    }

    return null;
  }

  /// Validate maximum length
  /// Returns error message if invalid, null if valid
  static String? validateMaxLength(
    String? input,
    int maxLength, {
    String fieldName = 'This field',
  }) {
    final sanitized = sanitizeText(input);

    if (sanitized == null) {
      return '$fieldName cannot be empty';
    }

    if (sanitized.length > maxLength) {
      return '$fieldName must not exceed $maxLength characters';
    }

    return null;
  }

  /// Validate length range
  /// Returns error message if invalid, null if valid
  static String? validateLengthRange(
    String? input,
    int minLength,
    int maxLength, {
    String fieldName = 'This field',
  }) {
    final sanitized = sanitizeText(input);

    if (sanitized == null) {
      return '$fieldName cannot be empty';
    }

    if (sanitized.length < minLength || sanitized.length > maxLength) {
      return '$fieldName must be between $minLength and $maxLength characters';
    }

    return null;
  }

  /// Validate name (letters, spaces, hyphens only)
  /// Returns error message if invalid, null if valid
  static String? validateName(String? name, {String fieldName = 'Name'}) {
    final sanitized = sanitizeText(name);

    if (sanitized == null) {
      return '$fieldName cannot be empty';
    }

    // Allow letters, spaces, hyphens, and apostrophes
    final namePattern = RegExp(r"^[a-zA-Z\s\-']+$");

    if (!namePattern.hasMatch(sanitized)) {
      return '$fieldName can only contain letters, spaces, hyphens, and apostrophes';
    }

    return null;
  }

  /// Validate numeric input
  /// Returns error message if invalid, null if valid
  static String? validateNumeric(String? input, {String fieldName = 'This field'}) {
    final sanitized = sanitizeText(input);

    if (sanitized == null) {
      return '$fieldName cannot be empty';
    }

    if (int.tryParse(sanitized) == null) {
      return '$fieldName must be a valid number';
    }

    return null;
  }

  /// Validate age (must be between min and max)
  /// Returns error message if invalid, null if valid
  static String? validateAge(String? age, {int minAge = 0, int maxAge = 150}) {
    final sanitized = sanitizeText(age);

    if (sanitized == null) {
      return 'Age cannot be empty';
    }

    final ageValue = int.tryParse(sanitized);

    if (ageValue == null) {
      return 'Age must be a valid number';
    }

    if (ageValue < minAge || ageValue > maxAge) {
      return 'Age must be between $minAge and $maxAge';
    }

    return null;
  }

  /// Combine multiple validators
  /// Returns first error message found, or null if all pass
  static String? combineValidators(
    String? input,
    List<String? Function(String?)> validators,
  ) {
    for (final validator in validators) {
      final error = validator(input);
      if (error != null) return error;
    }
    return null;
  }

  /// Format phone number for display (add +63 prefix)
  static String formatPhoneNumber(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length == 10) {
      return '+63$digitsOnly';
    }
    return phone;
  }

  /// Format email to lowercase
  static String formatEmail(String email) {
    return sanitizeText(email)?.toLowerCase() ?? email;
  }

  /// Create a validator function for TextFormField
  /// Usage: validator: InputValidator.createValidator(...)
  static String? Function(String?) createValidator({
    bool required = false,
    String? fieldName,
    int? minLength,
    int? maxLength,
    bool isEmail = false,
    bool isPhone = false,
    bool isName = false,
    bool isNumeric = false,
    String? Function(String?)? customValidator,
  }) {
    return (String? value) {
      // Sanitize first
      final sanitized = sanitizeText(value);

      // Check required
      if (required && sanitized == null) {
        return '${fieldName ?? "This field"} cannot be empty or contain only spaces';
      }

      // If not required and empty, allow it
      if (!required && sanitized == null) {
        return null;
      }

      // Apply specific validators
      if (isEmail) {
        final error = validateEmail(sanitized);
        if (error != null) return error;
      }

      if (isPhone) {
        final error = validatePhoneNumber(sanitized);
        if (error != null) return error;
      }

      if (isName) {
        final error = validateName(sanitized, fieldName: fieldName ?? 'Name');
        if (error != null) return error;
      }

      if (isNumeric) {
        final error = validateNumeric(sanitized, fieldName: fieldName ?? 'This field');
        if (error != null) return error;
      }

      // Check length constraints
      if (minLength != null) {
        final error = validateMinLength(
          sanitized,
          minLength,
          fieldName: fieldName ?? 'This field',
        );
        if (error != null) return error;
      }

      if (maxLength != null) {
        final error = validateMaxLength(
          sanitized,
          maxLength,
          fieldName: fieldName ?? 'This field',
        );
        if (error != null) return error;
      }

      // Apply custom validator if provided
      if (customValidator != null) {
        final error = customValidator(sanitized);
        if (error != null) return error;
      }

      return null;
    };
  }
}
