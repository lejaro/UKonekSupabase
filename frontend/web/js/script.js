const tabLogin = document.getElementById('tab-login');

// Handle port mismatch during development (Live Server on 5500, Backend on 5000)
const API_BASE = window.location.port === '5500'
    ? `${window.location.protocol}//${window.location.hostname}:5000`
    : '';
const LOGIN_PAGE_URL = API_BASE ? `${API_BASE}/html/index.html` : '/html/index.html';
const DASHBOARD_PAGE_URL = API_BASE ? `${API_BASE}/html/dashboard.html` : '/html/dashboard.html';

const loginPanel = document.getElementById('login-panel');
const forgotPasswordToggle = document.getElementById('forgot-password-toggle');
const resetForm = document.getElementById('reset-form');
let passwordResetOtpRequested = false;

const panelTitle = document.getElementById('panel-title');
const panelDesc = document.getElementById('panel-desc');

function clearAuthSensitiveInputs() {
    const sensitiveFieldIds = [
        'username',
        'password',
        'reset-email',
        'reset-otp',
        'reset-new-password',
        'reset-confirm-password'
    ];


    sensitiveFieldIds.forEach((fieldId) => {
        const field = document.getElementById(fieldId);
        if (!field) return;
        field.value = '';
    });

    const roleField = document.getElementById('role');
    if (roleField) roleField.value = '';

    const loginError = document.getElementById('login-error');
    if (loginError) loginError.style.display = 'none';

    setResetOtpStepEnabled(false);

}

function setResetOtpStepEnabled(enabled) {
    passwordResetOtpRequested = enabled;

    const resetOtpStep = document.getElementById('reset-otp-step');
    if (resetOtpStep) {
        resetOtpStep.style.display = enabled ? 'block' : 'none';
    }

    const otpField = document.getElementById('reset-otp');
    const newPasswordField = document.getElementById('reset-new-password');
    const confirmPasswordField = document.getElementById('reset-confirm-password');

    if (otpField) otpField.required = enabled;
    if (newPasswordField) newPasswordField.required = enabled;
    if (confirmPasswordField) confirmPasswordField.required = enabled;

    const inlineResetSubmitLabel = document.querySelector('#reset-submit-btn .btn-label');
    if (inlineResetSubmitLabel) {
        inlineResetSubmitLabel.textContent = enabled ? 'Reset password' : 'Send OTP';
    }
}

function hideAllPanels() {
    loginPanel.style.display = 'none';

    tabLogin.classList.remove('active');

    tabLogin.setAttribute('aria-selected', 'false');
}

tabLogin.addEventListener('click', () => {
    hideAllPanels();
    tabLogin.classList.add('active');
    tabLogin.setAttribute('aria-selected', 'true');
    loginPanel.style.display = 'block';
    if (resetForm) {
        resetForm.style.display = 'none';
    }
    panelTitle.textContent = 'Welcome Back';
    panelDesc.textContent = 'Enter your credentials to access the portal';
});



if (forgotPasswordToggle && resetForm) {
    forgotPasswordToggle.addEventListener('click', () => {
        const isHidden = resetForm.style.display === 'none' || !resetForm.style.display;
        resetForm.style.display = isHidden ? 'block' : 'none';
    });
}

// Flush credentials when auth page loads.
clearAuthSensitiveInputs();

// Flush credentials when the page is restored from browser cache/history.
window.addEventListener('pageshow', (event) => {
    const navEntries = performance.getEntriesByType('navigation');
    const navType = navEntries && navEntries.length > 0 ? navEntries[0].type : '';
    if (event.persisted || navType === 'back_forward') {
        clearAuthSensitiveInputs();
    }
});

// Helper function to validate email format
function validateEmail(email) {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
}

const loginSubmitBtn = document.getElementById('login-submit-btn');
const loginSubmitLabel = loginSubmitBtn ? loginSubmitBtn.querySelector('.btn-label') : null;
const resetSubmitBtn = document.getElementById('reset-submit-btn');
const resetSubmitLabel = resetSubmitBtn ? resetSubmitBtn.querySelector('.btn-label') : null;


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
        if (input.dataset.toggleAttached === 'true') {
            return;
        }

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

const LOGIN_LOCK_KEY = 'ukonek_login_lock_state';
const LOGIN_MAX_ATTEMPTS = 3;
const LOGIN_LOCK_DURATION_MS = 5 * 60 * 1000;
let loginLockTimer = null;

function readLoginLockState() {
    try {
        const raw = localStorage.getItem(LOGIN_LOCK_KEY);
        if (!raw) return { attempts: 0, lockUntil: 0 };
        const parsed = JSON.parse(raw);
        return {
            attempts: Number.isInteger(parsed.attempts) ? Math.max(0, parsed.attempts) : 0,
            lockUntil: Number.isFinite(parsed.lockUntil) ? Math.max(0, parsed.lockUntil) : 0
        };
    } catch (_) {
        return { attempts: 0, lockUntil: 0 };
    }
}

function writeLoginLockState(state) {
    localStorage.setItem(LOGIN_LOCK_KEY, JSON.stringify(state));
}

function clearLoginLockState() {
    localStorage.removeItem(LOGIN_LOCK_KEY);
}

function getLoginLockRemainingMs() {
    const state = readLoginLockState();
    return Math.max(0, state.lockUntil - Date.now());
}

function isLoginLocked() {
    return getLoginLockRemainingMs() > 0;
}

function formatRemainingTime(ms) {
    const totalSeconds = Math.max(0, Math.ceil(ms / 1000));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

function stopLoginLockTimer() {
    if (loginLockTimer) {
        clearInterval(loginLockTimer);
        loginLockTimer = null;
    }
}

function applyLoginLockStateUI() {
    if (!loginSubmitBtn) return;

    const err = document.getElementById('login-error');
    const remainingMs = getLoginLockRemainingMs();
    const locked = remainingMs > 0;

    if (locked) {
        loginSubmitBtn.disabled = true;
        loginSubmitBtn.classList.remove('is-loading');
        if (loginSubmitLabel) {
            loginSubmitLabel.textContent = `TRY AGAIN IN ${formatRemainingTime(remainingMs)}`;
        }
        if (err) {
            err.textContent = `Too many invalid login attempts. Please try again in ${formatRemainingTime(remainingMs)}.`;
            err.style.display = 'block';
        }

        if (!loginLockTimer) {
            loginLockTimer = setInterval(() => {
                const nextRemainingMs = getLoginLockRemainingMs();
                if (nextRemainingMs <= 0) {
                    clearLoginLockState();
                    stopLoginLockTimer();
                    applyLoginLockStateUI();
                    return;
                }
                applyLoginLockStateUI();
            }, 1000);
        }
        return;
    }

    stopLoginLockTimer();

    const state = readLoginLockState();
    if (state.lockUntil > 0 && state.lockUntil <= Date.now()) {
        // Lockout window has ended; start a fresh attempt window.
        writeLoginLockState({ attempts: 0, lockUntil: 0 });
    }

    if (!loginSubmitBtn.classList.contains('is-loading')) {
        loginSubmitBtn.disabled = false;
        if (loginSubmitLabel) {
            loginSubmitLabel.textContent = 'SIGN IN';
        }
    }
}

function recordInvalidLoginAttempt() {
    const state = readLoginLockState();

    if (state.lockUntil > Date.now()) {
        return state;
    }

    const attempts = state.attempts + 1;
    if (attempts >= LOGIN_MAX_ATTEMPTS) {
        const lockedState = { attempts: 0, lockUntil: Date.now() + LOGIN_LOCK_DURATION_MS };
        writeLoginLockState(lockedState);
        return lockedState;
    }

    const nextState = { attempts, lockUntil: 0 };
    writeLoginLockState(nextState);
    return nextState;
}

function resetInvalidLoginAttempts() {
    clearLoginLockState();
    applyLoginLockStateUI();
}

function isInvalidCredentialsFailure(response, data) {
    if (response.status === 401) return true;
    const message = (data && typeof data.message === 'string') ? data.message : '';
    return /invalid credentials/i.test(message);
}



function setLoginLoading(isLoading) {
    if (!loginSubmitBtn) return;
    if (isLoading) {
        loginSubmitBtn.disabled = true;
        loginSubmitBtn.classList.add('is-loading');
        if (loginSubmitLabel) {
            loginSubmitLabel.textContent = 'SIGNING IN...';
        }
        return;
    }

    loginSubmitBtn.classList.remove('is-loading');
    applyLoginLockStateUI();
}

function setResetLoading(isLoading) {
    if (!resetSubmitBtn) return;
    resetSubmitBtn.disabled = isLoading;
    resetSubmitBtn.classList.toggle('is-loading', isLoading);
    if (resetSubmitLabel) {
        if (isLoading) {
            resetSubmitLabel.textContent = passwordResetOtpRequested ? 'Resetting...' : 'Sending...';
        } else {
            resetSubmitLabel.textContent = passwordResetOtpRequested ? 'Reset password' : 'Send OTP';
        }
    }
}

// Preloader helper - shows the preloader overlay for `duration` ms then hides it and calls callback
function showPreloader(duration = 700, cb) {
    const pre = document.getElementById('preloader');
    if (!pre) {
        if (typeof cb === 'function') cb();
        return;
    }
    pre.classList.remove('hidden');
    // ensure animation restarts
    pre.querySelector('.preloader-logo')?.classList.remove('animated');
    void pre.offsetWidth;
    pre.querySelector('.preloader-logo')?.classList.add('animated');
    setTimeout(() => {
        pre.classList.add('hidden');
        if (typeof cb === 'function') cb();
    }, duration);
}

// Show preloader once on page load briefly
window.addEventListener('load', () => {
    // show short preloader only for a moment
    showPreloader(900);
});

// Registration Form Handler
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
    const success = document.getElementById('register-success');
    const emailError = document.getElementById('err-reg-email');

    err.style.display = 'none';
    success.style.display = 'none';
    emailError.classList.add('hidden');

    // Validate email
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
        const otpResponse = await fetch(`${API_BASE}/api/staff/register`, {
            method: 'POST',
            credentials: 'include',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                first_name,
                middle_name,
                last_name,
                birthday,
                gender,
                employee_id,
                email,
                role
            })
        });

        const otpData = await otpResponse.json();

        if (!otpResponse.ok) {
            err.textContent = otpData.message || 'Failed to send OTP.';
            err.style.display = 'block';
            return;
        }

        pendingRegistrationProfile = {
            first_name,
            middle_name,
            last_name,
            birthday,
            gender,
            employee_id,
            email,
            role
        };

        success.style.display = 'block';
        success.textContent = otpData.message || 'OTP sent. Complete registration in the popup.';

        const otpModalError = document.getElementById('otp-modal-error');
        const otpModalSuccess = document.getElementById('otp-modal-success');
        if (otpModalError) otpModalError.style.display = 'none';
        if (otpModalSuccess) {
            otpModalSuccess.style.display = 'none';
            otpModalSuccess.textContent = '';
        }
        openRegistrationOtpModal();
    } catch (error) {
        console.error('Error:', error);
        err.textContent = 'Server connection failed.';
        err.style.display = 'block';
    } finally {
        setRegisterLoading(false);
    }
});

if (otpModalCloseBtn) {
    otpModalCloseBtn.addEventListener('click', () => {
        closeRegistrationOtpModal();
    });
}

if (registerOtpModal) {
    registerOtpModal.addEventListener('click', (event) => {
        if (event.target === registerOtpModal) {
            closeRegistrationOtpModal();
        }
    });
}

if (registerOtpForm) {
    registerOtpForm.addEventListener('submit', async (event) => {
        event.preventDefault();

        const otpModalError = document.getElementById('otp-modal-error');
        const otpModalSuccess = document.getElementById('otp-modal-success');
        const otp = document.getElementById('reg-otp') ? document.getElementById('reg-otp').value.trim() : '';
        const username = document.getElementById('reg-username') ? document.getElementById('reg-username').value.trim() : '';
        const password = document.getElementById('reg-password') ? document.getElementById('reg-password').value : '';
        const confirmPassword = document.getElementById('reg-confirm-password') ? document.getElementById('reg-confirm-password').value : '';
        const consentGiven = document.getElementById('reg-consent') ? document.getElementById('reg-consent').checked : false;

        if (otpModalError) otpModalError.style.display = 'none';
        if (otpModalSuccess) otpModalSuccess.style.display = 'none';

        if (!pendingRegistrationProfile || !pendingRegistrationProfile.email) {
            if (otpModalError) {
                otpModalError.textContent = 'No active registration request found. Please send OTP again.';
                otpModalError.style.display = 'block';
            }
            return;
        }

        if (!/^\d{6}$/.test(otp)) {
            if (otpModalError) {
                otpModalError.textContent = 'Please enter a valid 6-digit OTP.';
                otpModalError.style.display = 'block';
            }
            return;
        }

        if (!username || !password || !confirmPassword) {
            if (otpModalError) {
                otpModalError.textContent = 'Username, password, and confirm password are required.';
                otpModalError.style.display = 'block';
            }
            return;
        }

        if (password !== confirmPassword) {
            if (otpModalError) {
                otpModalError.textContent = 'Passwords do not match.';
                otpModalError.style.display = 'block';
            }
            return;
        }

        if (!consentGiven) {
            if (otpModalError) {
                otpModalError.textContent = 'Consent is required to continue.';
                otpModalError.style.display = 'block';
            }
            return;
        }

        setOtpModalLoading(true);

        try {
            const completeResponse = await fetch(`${API_BASE}/api/staff/complete-registration`, {
                method: 'POST',
                credentials: 'include',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    email: pendingRegistrationProfile.email,
                    otp,
                    username,
                    password,
                    confirmPassword,
                    consentGiven
                })
            });

            const completeData = await completeResponse.json();

            if (!completeResponse.ok) {
                if (otpModalError) {
                    otpModalError.textContent = completeData.message || 'Unable to complete registration.';
                    otpModalError.style.display = 'block';
                }
                return;
            }

            closeRegistrationOtpModal();
            document.getElementById('register-form').reset();
            if (registerOtpForm) registerOtpForm.reset();
            pendingRegistrationProfile = null;

            const successModal = document.getElementById('registration-success-modal');
            successModal.classList.remove('hidden');
        } catch (error) {
            console.error('Error:', error);
            if (otpModalError) {
                otpModalError.textContent = 'Server connection failed.';
                otpModalError.style.display = 'block';
            }
        } finally {
            setOtpModalLoading(false);
        }
    });
}

if (registerResendOtpBtn) {
    registerResendOtpBtn.addEventListener('click', async (event) => {
        event.preventDefault();

        if (registerResendOtpBtn.getAttribute('aria-disabled') === 'true') {
            return;
        }

        const err = document.getElementById('register-error');
        const otpModalError = document.getElementById('otp-modal-error');
        const otpModalSuccess = document.getElementById('otp-modal-success');

        if (!pendingRegistrationProfile) {
            if (otpModalError) {
                otpModalError.textContent = 'No active registration request found. Please send OTP again.';
                otpModalError.style.display = 'block';
            }
            return;
        }

        err.style.display = 'none';
        if (otpModalError) otpModalError.style.display = 'none';
        if (otpModalSuccess) otpModalSuccess.style.display = 'none';

        registerResendOtpBtn.setAttribute('aria-disabled', 'true');
        registerResendOtpBtn.style.pointerEvents = 'none';
        registerResendOtpBtn.style.opacity = '0.65';
        registerResendOtpBtn.textContent = 'Sending...';

        try {
            const response = await fetch(`${API_BASE}/api/staff/register`, {
                method: 'POST',
                credentials: 'include',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(pendingRegistrationProfile)
            });
            const data = await response.json();

            if (!response.ok) {
                if (otpModalError) {
                    otpModalError.textContent = data.message || 'Failed to resend OTP.';
                    otpModalError.style.display = 'block';
                }
                return;
            }

            if (otpModalSuccess) {
                otpModalSuccess.style.display = 'block';
                otpModalSuccess.textContent = data.message || 'OTP resent. Please check your email.';
            }
        } catch (error) {
            console.error('Error:', error);
            if (otpModalError) {
                otpModalError.textContent = 'Server connection failed.';
                otpModalError.style.display = 'block';
            }
        } finally {
            registerResendOtpBtn.setAttribute('aria-disabled', 'false');
            registerResendOtpBtn.style.pointerEvents = '';
            registerResendOtpBtn.style.opacity = '';
            registerResendOtpBtn.textContent = 'Resend OTP';
        }
    });
}

// Login Form Handler
document.getElementById('login-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    // Local (dev) sign-in override: do not call backend, simply validate and go to dashboard
    const username = document.getElementById('username') ? document.getElementById('username').value.trim() : '';
    const password = document.getElementById('password') ? document.getElementById('password').value : '';
    const err = document.getElementById('login-error');
    if (err) err.style.display = 'none';

    if (!username || !password) {
        if (err) {
            err.textContent = 'Please enter username and password.';
            err.style.display = 'block';
        }
        return;
    }

    // Show a short preloader then navigate locally to dashboard (no backend required)
    showPreloader(700, () => {
        // Use local relative path to dashboard
        window.location.href = './dashboard.html';
    });
});

applyLoginLockStateUI();
setupPasswordVisibilityToggles();

// Reset Form Handler
document.getElementById('reset-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const msg = document.getElementById('reset-msg');
    const resetEmail = document.getElementById('reset-email').value.trim();
    const resetOtp = document.getElementById('reset-otp') ? document.getElementById('reset-otp').value.trim() : '';
    const resetNewPassword = document.getElementById('reset-new-password') ? document.getElementById('reset-new-password').value : '';
    const resetConfirmPassword = document.getElementById('reset-confirm-password') ? document.getElementById('reset-confirm-password').value : '';

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

    if (passwordResetOtpRequested) {
        if (!/^\d{6}$/.test(resetOtp)) {
            msg.style.display = 'block';
            msg.style.color = '#dc2626';
            msg.textContent = 'Please enter a valid 6-digit OTP.';
            return;
        }

        if (!resetNewPassword || !resetConfirmPassword) {
            msg.style.display = 'block';
            msg.style.color = '#dc2626';
            msg.textContent = 'Please enter and confirm your new password.';
            return;
        }

        if (resetNewPassword.length < 6) {
            msg.style.display = 'block';
            msg.style.color = '#dc2626';
            msg.textContent = 'Password must be at least 6 characters.';
            return;
        }

        if (resetNewPassword !== resetConfirmPassword) {
            msg.style.display = 'block';
            msg.style.color = '#dc2626';
            msg.textContent = 'Passwords do not match.';
            return;
        }
    }

    setResetLoading(true);

    try {
        if (!passwordResetOtpRequested) {
            const response = await fetch(`${API_BASE}/api/staff/forgot-password`, {
                method: 'POST',
                credentials: 'include',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email: resetEmail })
            });

            const data = await response.json();

            msg.style.display = 'block';
            if (response.ok) {
                msg.style.color = '#15803d';
                msg.textContent = data.message || 'If the email exists, a reset OTP has been sent.';
                setResetOtpStepEnabled(true);
            } else {
                msg.style.color = '#dc2626';
                msg.textContent = data.message || 'Failed to request password reset OTP.';
            }
            return;
        }

        const response = await fetch(`${API_BASE}/api/staff/reset-password`, {
            method: 'POST',
            credentials: 'include',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                email: resetEmail,
                otp: resetOtp,
                password: resetNewPassword,
                confirmPassword: resetConfirmPassword
            })
        });

        const data = await response.json();

        msg.style.display = 'block';
        if (response.ok) {
            msg.style.color = '#15803d';
            msg.textContent = data.message || 'Password reset successful. You can now log in.';
            if (resetForm) resetForm.reset();
            setResetOtpStepEnabled(false);
        } else {
            msg.style.color = '#dc2626';
            msg.textContent = data.message || 'Failed to reset password.';
        }
    } catch (error) {
        console.error('Reset request error:', error);
        msg.style.display = 'block';
        msg.style.color = '#dc2626';
        msg.textContent = 'Server connection failed.';
    } finally {
        setResetLoading(false);
    }
});

setResetOtpStepEnabled(false);
