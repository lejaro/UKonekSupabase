import {
    signInStaff,
    requestPasswordReset,
    requestRegistrationEmailOtp,
    verifyRegistrationEmailOtp
} from './services/authService.js';
import { createPendingStaff } from './services/staffService.js';

const DASHBOARD_PAGE_URL = './dashboard.html';

const tabLogin = document.getElementById('tab-login');
const tabRegister = document.getElementById('tab-register');
const loginPanel = document.getElementById('login-panel');
const registerPanel = document.getElementById('register-panel');
const forgotPasswordToggle = document.getElementById('forgot-password-toggle');
const resetForm = document.getElementById('reset-form');
const panelTitle = document.getElementById('panel-title');
const panelDesc = document.getElementById('panel-desc');

const loginSubmitBtn = document.getElementById('login-submit-btn');
const loginSubmitLabel = loginSubmitBtn ? loginSubmitBtn.querySelector('.btn-label') : null;
const registerSubmitBtn = document.getElementById('register-submit-btn');
const registerSubmitLabel = registerSubmitBtn ? registerSubmitBtn.querySelector('.btn-label') : null;
const resetSubmitBtn = document.getElementById('reset-submit-btn');
const resetSubmitLabel = resetSubmitBtn ? resetSubmitBtn.querySelector('.btn-label') : null;

const otpModal = document.getElementById('registration-otp-modal');
const otpEmailTarget = document.getElementById('otp-email-target');
const otpInput = document.getElementById('otp-code-input');
const otpMsg = document.getElementById('otp-modal-msg');
const otpVerifyBtn = document.getElementById('otp-verify-btn');
const otpResendBtn = document.getElementById('otp-resend-btn');
const otpCancelBtn = document.getElementById('otp-cancel-btn');
const otpVerifyLabel = otpVerifyBtn ? otpVerifyBtn.querySelector('.btn-label') : null;

// --- Validation Helpers ---
const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const nameRegex = /^[A-Za-z]+(?:[ '-][A-Za-z]+)*$/;
const numericRegex = /^\d+$/;

function validateEmail(email) { return emailRegex.test(email); }
function validateName(name) { return nameRegex.test(name); }
function validateNumericString(v) { return numericRegex.test(v); }

// --- Input cleanup on load / back-forward ---
function clearAuthSensitiveInputs() {
    ['username', 'password', 'reset-email'].forEach((id) => {
        const el = document.getElementById(id);
        if (el) el.value = '';
    });
    const roleField = document.getElementById('role');
    if (roleField) roleField.value = '';
    const loginError = document.getElementById('login-error');
    if (loginError) loginError.style.display = 'none';
    const registerError = document.getElementById('register-error');
    if (registerError) registerError.style.display = 'none';
}

clearAuthSensitiveInputs();
window.addEventListener('pageshow', (event) => {
    const navEntries = performance.getEntriesByType('navigation');
    const navType = navEntries && navEntries.length > 0 ? navEntries[0].type : '';
    if (event.persisted || navType === 'back_forward') {
        clearAuthSensitiveInputs();
    }
});

// --- Tab Switching ---
function hideAllPanels() {
    loginPanel.style.display = 'none';
    registerPanel.style.display = 'none';
    tabLogin.classList.remove('active');
    tabRegister.classList.remove('active');
    tabLogin.setAttribute('aria-selected', 'false');
    tabRegister.setAttribute('aria-selected', 'false');
}

tabLogin.addEventListener('click', () => {
    hideAllPanels();
    tabLogin.classList.add('active');
    tabLogin.setAttribute('aria-selected', 'true');
    loginPanel.style.display = 'block';
    if (resetForm) resetForm.style.display = 'none';
    panelTitle.textContent = 'Welcome Back';
    panelDesc.textContent = 'Enter your credentials to access the portal';
});

tabRegister.addEventListener('click', () => {
    hideAllPanels();
    tabRegister.classList.add('active');
    tabRegister.setAttribute('aria-selected', 'true');
    registerPanel.style.display = 'block';
    panelTitle.textContent = 'Join U-Konek+';
    panelDesc.textContent = 'Register as medical personnel to get started';
});

if (forgotPasswordToggle && resetForm) {
    forgotPasswordToggle.addEventListener('click', () => {
        const isHidden = resetForm.style.display === 'none' || !resetForm.style.display;
        resetForm.style.display = isHidden ? 'block' : 'none';
    });
}

// --- Registration Success Modal ---
const modalLoginBtn = document.getElementById('modal-login-btn');
if (modalLoginBtn) {
    modalLoginBtn.addEventListener('click', () => {
        const successModal = document.getElementById('registration-success-modal');
        successModal.classList.add('hidden');
        tabLogin.click();
    });
}

// --- Password Visibility Toggle ---
const EYE_OPEN_ICON = `
<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
    <path fill="currentColor" d="M12 5c-5.5 0-9.3 4.1-10.7 6.1a1.5 1.5 0 0 0 0 1.8C2.7 14.9 6.5 19 12 19s9.3-4.1 10.7-6.1a1.5 1.5 0 0 0 0-1.8C21.3 9.1 17.5 5 12 5zm0 11a5 5 0 1 1 0-10 5 5 0 0 1 0 10zm0-2.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z"/>
</svg>`;

const EYE_CLOSED_ICON = `
<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
    <path fill="currentColor" d="M2.3 1.3a1 1 0 0 0-1.4 1.4l3 3A13.8 13.8 0 0 0 1.3 11a1.5 1.5 0 0 0 0 1.8C2.7 14.9 6.5 19 12 19a12 12 0 0 0 4.6-.9l3.1 3.1a1 1 0 1 0 1.4-1.4zm7.5 10.3a2.5 2.5 0 0 0 3.6 2.4l-3.5-3.5c0 .4-.1.7-.1 1.1zM12 7a5 5 0 0 1 5 5c0 .7-.1 1.3-.4 1.9l1.5 1.5a13.8 13.8 0 0 0 4.6-4.4 1.5 1.5 0 0 0 0-1.8C21.3 9.1 17.5 5 12 5c-1.4 0-2.7.3-3.8.8l1.5 1.5c.6-.2 1.5-.3 2.3-.3z"/>
</svg>`;

function setupPasswordVisibilityToggles(root = document) {
    const passwordInputs = root.querySelectorAll('input[type="password"]');
    passwordInputs.forEach((input) => {
        if (input.dataset.toggleAttached === 'true') return;
        const wrapper = document.createElement('div');
        wrapper.className = 'password-input-wrap';
        input.parentNode.insertBefore(wrapper, input);
        wrapper.appendChild(input);
        const toggleBtn = document.createElement('button');
        toggleBtn.type = 'button';
        toggleBtn.className = 'password-toggle';
        toggleBtn.setAttribute('aria-label', 'Show password');
        toggleBtn.setAttribute('aria-pressed', 'false');
        toggleBtn.innerHTML = EYE_OPEN_ICON;
        toggleBtn.addEventListener('click', () => {
            const showPassword = input.type === 'password';
            input.type = showPassword ? 'text' : 'password';
            toggleBtn.innerHTML = showPassword ? EYE_CLOSED_ICON : EYE_OPEN_ICON;
            toggleBtn.setAttribute('aria-label', showPassword ? 'Hide password' : 'Show password');
            toggleBtn.setAttribute('aria-pressed', showPassword ? 'true' : 'false');
        });
        wrapper.appendChild(toggleBtn);
        input.dataset.toggleAttached = 'true';
    });
}

// --- Login Lockout ---
const LOGIN_LOCK_KEY = 'ukonek_login_lock_state';
function clearLoginLockState() { localStorage.removeItem(LOGIN_LOCK_KEY); }

function applyLoginLockStateUI() {
    if (!loginSubmitBtn) return;
    clearLoginLockState();
    if (!loginSubmitBtn.classList.contains('is-loading')) {
        loginSubmitBtn.disabled = false;
        if (loginSubmitLabel) loginSubmitLabel.textContent = 'SIGN IN';
    }
}

function resetInvalidLoginAttempts() { clearLoginLockState(); applyLoginLockStateUI(); }

function setLoginLoading(isLoading) {
    if (!loginSubmitBtn) return;
    if (isLoading) {
        loginSubmitBtn.disabled = true;
        loginSubmitBtn.classList.add('is-loading');
        if (loginSubmitLabel) loginSubmitLabel.textContent = 'SIGNING IN...';
        return;
    }
    loginSubmitBtn.classList.remove('is-loading');
    applyLoginLockStateUI();
}

function setRegisterLoading(isLoading) {
    if (!registerSubmitBtn) return;
    registerSubmitBtn.disabled = isLoading;
    registerSubmitBtn.classList.toggle('is-loading', isLoading);
    if (registerSubmitLabel) registerSubmitLabel.textContent = isLoading ? 'SUBMITTING...' : 'REGISTER';
}

function setResetLoading(isLoading) {
    if (!resetSubmitBtn) return;
    resetSubmitBtn.disabled = isLoading;
    resetSubmitBtn.classList.toggle('is-loading', isLoading);
    if (resetSubmitLabel) resetSubmitLabel.textContent = isLoading ? 'Sending...' : 'Send reset link';
}

function setOtpMessage(text, color = '#dc2626') {
    if (!otpMsg) return;
    if (!text) {
        otpMsg.style.display = 'none';
        otpMsg.textContent = '';
        return;
    }
    otpMsg.style.display = 'block';
    otpMsg.style.color = color;
    otpMsg.textContent = text;
}

function setOtpVerifyLoading(isLoading) {
    if (!otpVerifyBtn) return;
    otpVerifyBtn.disabled = isLoading;
    otpVerifyBtn.classList.toggle('is-loading', isLoading);
    if (otpVerifyLabel) otpVerifyLabel.textContent = isLoading ? 'Verifying...' : 'Verify OTP';
    if (otpCancelBtn) otpCancelBtn.disabled = isLoading;
    if (otpResendBtn) otpResendBtn.disabled = isLoading;
}

function closeOtpModal() {
    if (!otpModal) return;
    otpModal.classList.add('hidden');
    otpModal.setAttribute('aria-hidden', 'true');
    if (otpInput) otpInput.value = '';
    setOtpMessage('');
    setOtpVerifyLoading(false);
}

function openOtpModal(email) {
    if (!otpModal || !otpInput || !otpVerifyBtn || !otpResendBtn || !otpCancelBtn) {
        return Promise.reject(new Error('OTP module is not available.'));
    }

    otpModal.classList.remove('hidden');
    otpModal.setAttribute('aria-hidden', 'false');
    otpInput.value = '';
    otpEmailTarget.textContent = email;
    setOtpMessage('');
    otpInput.focus();

    return new Promise((resolve, reject) => {
        const cleanup = () => {
            otpVerifyBtn.removeEventListener('click', onVerify);
            otpResendBtn.removeEventListener('click', onResend);
            otpCancelBtn.removeEventListener('click', onCancel);
            otpModal.removeEventListener('click', onOverlayClick);
            otpInput.removeEventListener('input', onOtpInput);
        };

        const onOtpInput = () => {
            otpInput.value = otpInput.value.replace(/\D+/g, '').slice(0, 8);
        };

        const onVerify = async () => {
            const otpCode = String(otpInput.value || '').trim();
            if (!/^\d{8}$/.test(otpCode)) {
                setOtpMessage('Please enter a valid 8-digit code.');
                return;
            }

            setOtpVerifyLoading(true);
            setOtpMessage('');
            try {
                const authUserId = await verifyRegistrationEmailOtp(email, otpCode);
                cleanup();
                closeOtpModal();
                resolve(authUserId);
            } catch (error) {
                setOtpMessage(String(error?.message || 'Invalid or expired verification code.'));
            } finally {
                setOtpVerifyLoading(false);
            }
        };

        const onResend = async () => {
            setOtpVerifyLoading(true);
            setOtpMessage('');
            try {
                await requestRegistrationEmailOtp(email);
                setOtpMessage('A new OTP was sent to your email.', '#15803d');
            } catch (error) {
                setOtpMessage(String(error?.message || 'Failed to resend OTP.'));
            } finally {
                setOtpVerifyLoading(false);
            }
        };

        const onCancel = () => {
            cleanup();
            closeOtpModal();
            reject(new Error('Email verification was cancelled.'));
        };

        const onOverlayClick = (event) => {
            if (event.target === otpModal) {
                onCancel();
            }
        };

        otpVerifyBtn.addEventListener('click', onVerify);
        otpResendBtn.addEventListener('click', onResend);
        otpCancelBtn.addEventListener('click', onCancel);
        otpModal.addEventListener('click', onOverlayClick);
        otpInput.addEventListener('input', onOtpInput);
    });
}

// --- Email real-time validation ---
const emailInput = document.getElementById('reg-email');
if (emailInput) {
    emailInput.addEventListener('blur', function () {
        const emailError = document.getElementById('err-reg-email');
        const email = this.value.trim();
        if (!email) { emailError.classList.add('hidden'); return; }
        if (!validateEmail(email)) {
            emailError.textContent = 'Please enter a valid email address';
            emailError.classList.remove('hidden');
        } else {
            emailError.classList.add('hidden');
        }
    });
    emailInput.addEventListener('input', function () {
        const emailError = document.getElementById('err-reg-email');
        if (emailError.classList.contains('hidden') || !this.value.trim()) return;
        if (validateEmail(this.value.trim())) emailError.classList.add('hidden');
    });
}

// Strip numbers from name fields
['reg-first-name', 'reg-middle-name', 'reg-last-name'].forEach((fieldId) => {
    const input = document.getElementById(fieldId);
    if (input) input.addEventListener('input', function () { this.value = this.value.replace(/\d+/g, ''); });
});

// Strip non-digits from employee ID
const employeeIdInput = document.getElementById('reg-employee-id');
if (employeeIdInput) {
    employeeIdInput.addEventListener('input', function () { this.value = this.value.replace(/\D+/g, ''); });
}

// =======================================================================
// Registration Form — directly inserts into pending_staff via Supabase
// =======================================================================
document.getElementById('register-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const first_name = document.getElementById('reg-first-name').value.trim();
    const middle_name = document.getElementById('reg-middle-name').value.trim();
    const last_name = document.getElementById('reg-last-name').value.trim();
    const birthday = document.getElementById('reg-birthday').value;
    const gender = document.getElementById('reg-gender').value;
    const employee_id = document.getElementById('reg-employee-id').value.trim();
    const email = document.getElementById('reg-email').value.trim();
    const role = document.getElementById('reg-role').value;

    const err = document.getElementById('register-error');
    const emailError = document.getElementById('err-reg-email');
    err.style.display = 'none';
    emailError.classList.add('hidden');

    if (!email) {
        emailError.textContent = 'Email is required';
        emailError.classList.remove('hidden');
        return;
    }
    if (!validateEmail(email)) {
        emailError.textContent = 'Please enter a valid email address';
        emailError.classList.remove('hidden');
        return;
    }
    if (!validateName(first_name) || !validateName(last_name) || (middle_name && !validateName(middle_name))) {
        err.textContent = 'First and last name must contain letters only. Middle name is optional but must contain letters if provided.';
        err.style.display = 'block';
        return;
    }
    if (!validateNumericString(employee_id)) {
        err.textContent = 'Employee ID must contain numbers only.';
        err.style.display = 'block';
        return;
    }
    if (!first_name || !last_name || !birthday || !gender || !employee_id || !role) {
        err.textContent = 'Please complete all required registration fields.';
        err.style.display = 'block';
        return;
    }

    setRegisterLoading(true);

    try {
        await requestRegistrationEmailOtp(email.toLowerCase());
        const authUserId = await openOtpModal(email.toLowerCase());

        await createPendingStaff({
            first_name,
            middle_name,
            last_name,
            birthday,
            gender,
            username: email.split('@')[0],
            employee_id,
            email: email.toLowerCase(),
            role,
            consent_given: true,
            status: 'Pending',
            auth_user_id: authUserId
        });

        document.getElementById('register-form').reset();
        const successModal = document.getElementById('registration-success-modal');
        successModal.classList.remove('hidden');
    } catch (error) {
        console.error('Registration error:', error);
        const errorText = String(error?.message || 'Unable to submit registration.');
        err.textContent = errorText.toLowerCase().includes('duplicate')
            ? 'Username, employee ID, or email already exists.'
            : errorText;
        err.style.display = 'block';
    } finally {
        setRegisterLoading(false);
    }
});

// =======================================================================
// Login Form — uses Supabase auth, then verifies staff role
// =======================================================================
document.getElementById('login-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const selectedRole = document.getElementById('role').value;
    const identifier = document.getElementById('username').value.trim();
    const password = document.getElementById('password').value;
    const err = document.getElementById('login-error');
    err.style.display = 'none';

    if (!selectedRole || !identifier || !password) {
        err.textContent = 'Please select a role and enter email and password.';
        err.style.display = 'block';
        return;
    }

    if (!validateEmail(identifier)) {
        err.textContent = 'Please enter a valid email address.';
        err.style.display = 'block';
        return;
    }

    setLoginLoading(true);

    try {
        await signInStaff({ identifier, password, selectedRole });

        resetInvalidLoginAttempts();
        clearAuthSensitiveInputs();
        window.location.href = DASHBOARD_PAGE_URL;
    } catch (error) {
        console.error('Login error:', error);
        const errorText = String(error?.message || 'Connection failed. Please try again.');
        err.textContent = errorText;
        err.style.display = 'block';
    } finally {
        setLoginLoading(false);
    }
});

// =======================================================================
// Reset Password — uses Supabase auth reset email flow
// =======================================================================
document.getElementById('reset-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const msg = document.getElementById('reset-msg');
    const resetEmail = document.getElementById('reset-email').value.trim();

    msg.style.display = 'none';

    if (!resetEmail) {
        msg.style.display = 'block';
        msg.style.color = '#dc2626';
        msg.textContent = 'Please enter your email address.';
        return;
    }

    if (!validateEmail(resetEmail)) {
        msg.style.display = 'block';
        msg.style.color = '#dc2626';
        msg.textContent = 'Please enter a valid email address.';
        return;
    }

    setResetLoading(true);

    try {
        await requestPasswordReset(resetEmail.toLowerCase());
        msg.style.display = 'block';
        msg.style.color = '#15803d';
        msg.textContent = 'If an account exists for that email, a reset link has been sent.';
    } catch (error) {
        console.error('Reset request error:', error);
        msg.style.display = 'block';
        msg.style.color = '#dc2626';
        msg.textContent = String(error?.message || 'Connection failed. Please try again.');
    } finally {
        setResetLoading(false);
    }
});

// --- Init ---
applyLoginLockStateUI();
setupPasswordVisibilityToggles();
