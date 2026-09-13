/**
 * ═══════════════════════════════════════════════════════════════════════════
 * INPUT VALIDATION UTILITY - WEB APPLICATION
 * ═══════════════════════════════════════════════════════════════════════════
 * Purpose: Comprehensive client-side input validation
 * Features:
 *   - Trim and sanitize all text inputs
 *   - Reject whitespace-only submissions
 *   - Normalize multiple consecutive spaces
 *   - Validate email, phone, and other formats
 *   - Display user-friendly error messages
 * ═══════════════════════════════════════════════════════════════════════════
 */

const InputValidator = {
    /**
     * Validate and sanitize text input
     * @param {string} input - The input text to validate
     * @returns {string|null} - Sanitized text or null if invalid
     */
    sanitizeText(input) {
        if (input === null || input === undefined) {
            return null;
        }

        // Convert to string and trim
        let sanitized = String(input).trim();

        // Return null if empty after trimming
        if (sanitized === '') {
            return null;
        }

        // Normalize multiple consecutive spaces to single space
        sanitized = sanitized.replace(/\s+/g, ' ');

        return sanitized;
    },

    /**
     * Validate required text field
     * @param {string} input - The input text to validate
     * @param {string} fieldName - Name of the field for error message
     * @returns {Object} - {valid: boolean, value: string|null, error: string|null}
     */
    validateRequired(input, fieldName = 'This field') {
        const sanitized = this.sanitizeText(input);

        if (sanitized === null) {
            return {
                valid: false,
                value: null,
                error: `${fieldName} cannot be empty or contain only spaces`
            };
        }

        return {
            valid: true,
            value: sanitized,
            error: null
        };
    },

    /**
     * Validate email format
     * @param {string} email - The email to validate
     * @returns {Object} - {valid: boolean, value: string|null, error: string|null}
     */
    validateEmail(email) {
        const sanitized = this.sanitizeText(email);

        if (sanitized === null) {
            return {
                valid: false,
                value: null,
                error: 'Email cannot be empty'
            };
        }

        // Convert to lowercase
        const lowerEmail = sanitized.toLowerCase();

        // Email regex pattern
        const emailPattern = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;

        if (!emailPattern.test(lowerEmail)) {
            return {
                valid: false,
                value: null,
                error: 'Please enter a valid email address'
            };
        }

        return {
            valid: true,
            value: lowerEmail,
            error: null
        };
    },

    /**
     * Validate Philippine phone number
     * @param {string} phone - The phone number to validate
     * @returns {Object} - {valid: boolean, value: string|null, error: string|null}
     */
    validatePhoneNumber(phone) {
        const sanitized = this.sanitizeText(phone);

        if (sanitized === null) {
            return {
                valid: false,
                value: null,
                error: 'Phone number cannot be empty'
            };
        }

        // Remove all non-digit characters
        const digitsOnly = sanitized.replace(/[^0-9]/g, '');

        // Validate 10 digits (after +63)
        if (digitsOnly.length !== 10) {
            return {
                valid: false,
                value: null,
                error: 'Phone number must be 10 digits (e.g., 9XX XXX XXXX)'
            };
        }

        // Check if starts with 9
        if (!digitsOnly.startsWith('9')) {
            return {
                valid: false,
                value: null,
                error: 'Phone number must start with 9'
            };
        }

        return {
            valid: true,
            value: `+63${digitsOnly}`,
            error: null
        };
    },

    /**
     * Validate minimum length
     * @param {string} input - The input text to validate
     * @param {number} minLength - Minimum required length
     * @param {string} fieldName - Name of the field for error message
     * @returns {Object} - {valid: boolean, value: string|null, error: string|null}
     */
    validateMinLength(input, minLength, fieldName = 'This field') {
        const sanitized = this.sanitizeText(input);

        if (sanitized === null) {
            return {
                valid: false,
                value: null,
                error: `${fieldName} cannot be empty`
            };
        }

        if (sanitized.length < minLength) {
            return {
                valid: false,
                value: null,
                error: `${fieldName} must be at least ${minLength} characters`
            };
        }

        return {
            valid: true,
            value: sanitized,
            error: null
        };
    },

    /**
     * Validate maximum length
     * @param {string} input - The input text to validate
     * @param {number} maxLength - Maximum allowed length
     * @param {string} fieldName - Name of the field for error message
     * @returns {Object} - {valid: boolean, value: string|null, error: string|null}
     */
    validateMaxLength(input, maxLength, fieldName = 'This field') {
        const sanitized = this.sanitizeText(input);

        if (sanitized === null) {
            return {
                valid: false,
                value: null,
                error: `${fieldName} cannot be empty`
            };
        }

        if (sanitized.length > maxLength) {
            return {
                valid: false,
                value: null,
                error: `${fieldName} must not exceed ${maxLength} characters`
            };
        }

        return {
            valid: true,
            value: sanitized,
            error: null
        };
    },

    /**
     * Auto-attach validation to form inputs
     * @param {HTMLFormElement} form - The form element
     * @param {Object} rules - Validation rules for each field
     */
    attachToForm(form, rules = {}) {
        if (!form) return;

        // Prevent form submission if validation fails
        form.addEventListener('submit', (e) => {
            let isValid = true;
            const errors = [];

            // Validate each field with rules
            Object.keys(rules).forEach(fieldName => {
                const field = form.elements[fieldName];
                if (!field) return;

                const rule = rules[fieldName];
                let result;

                // Apply validation based on rule type
                if (rule.type === 'email') {
                    result = this.validateEmail(field.value);
                } else if (rule.type === 'phone') {
                    result = this.validatePhoneNumber(field.value);
                } else if (rule.required) {
                    result = this.validateRequired(field.value, rule.label || fieldName);
                } else {
                    result = { valid: true, value: this.sanitizeText(field.value), error: null };
                }

                // Apply min/max length if specified
                if (result.valid && rule.minLength) {
                    result = this.validateMinLength(result.value, rule.minLength, rule.label || fieldName);
                }
                if (result.valid && rule.maxLength) {
                    result = this.validateMaxLength(result.value, rule.maxLength, rule.label || fieldName);
                }

                // Show error if invalid
                if (!result.valid) {
                    isValid = false;
                    errors.push(result.error);
                    this.showFieldError(field, result.error);
                } else {
                    this.clearFieldError(field);
                    // Update field value with sanitized version
                    if (result.value !== null) {
                        field.value = result.value;
                    }
                }
            });

            // Prevent submission if validation failed
            if (!isValid) {
                e.preventDefault();
                e.stopPropagation();
                
                // Show summary error message
                this.showFormError(form, errors[0] || 'Please fix the errors before submitting');
                return false;
            }

            return true;
        });

        // Real-time validation on blur
        Object.keys(rules).forEach(fieldName => {
            const field = form.elements[fieldName];
            if (!field) return;

            field.addEventListener('blur', () => {
                const rule = rules[fieldName];
                let result;

                if (rule.type === 'email') {
                    result = this.validateEmail(field.value);
                } else if (rule.type === 'phone') {
                    result = this.validatePhoneNumber(field.value);
                } else if (rule.required) {
                    result = this.validateRequired(field.value, rule.label || fieldName);
                } else {
                    result = { valid: true, value: this.sanitizeText(field.value), error: null };
                }

                if (!result.valid) {
                    this.showFieldError(field, result.error);
                } else {
                    this.clearFieldError(field);
                    if (result.value !== null) {
                        field.value = result.value;
                    }
                }
            });

            // Clear error on input
            field.addEventListener('input', () => {
                this.clearFieldError(field);
            });
        });
    },

    /**
     * Show field-level error message
     * @param {HTMLElement} field - The input field
     * @param {string} message - Error message to display
     */
    showFieldError(field, message) {
        // Remove existing error
        this.clearFieldError(field);

        // Add error class to field
        field.classList.add('input-error');

        // Create error message element
        const errorDiv = document.createElement('div');
        errorDiv.className = 'field-error-message';
        errorDiv.textContent = message;
        errorDiv.style.color = '#dc3545';
        errorDiv.style.fontSize = '0.875rem';
        errorDiv.style.marginTop = '0.25rem';

        // Insert after field
        field.parentNode.insertBefore(errorDiv, field.nextSibling);
    },

    /**
     * Clear field-level error message
     * @param {HTMLElement} field - The input field
     */
    clearFieldError(field) {
        field.classList.remove('input-error');
        
        // Remove error message if exists
        const errorMsg = field.parentNode.querySelector('.field-error-message');
        if (errorMsg) {
            errorMsg.remove();
        }
    },

    /**
     * Show form-level error message
     * @param {HTMLFormElement} form - The form element
     * @param {string} message - Error message to display
     */
    showFormError(form, message) {
        // Remove existing form error
        const existingError = form.querySelector('.form-error-message');
        if (existingError) {
            existingError.remove();
        }

        // Create error alert
        const errorDiv = document.createElement('div');
        errorDiv.className = 'form-error-message alert alert-danger';
        errorDiv.textContent = message;
        errorDiv.style.marginBottom = '1rem';

        // Insert at top of form
        form.insertBefore(errorDiv, form.firstChild);

        // Auto-remove after 5 seconds
        setTimeout(() => {
            errorDiv.remove();
        }, 5000);
    }
};

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
    module.exports = InputValidator;
}
