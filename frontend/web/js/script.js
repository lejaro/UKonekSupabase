const tabLogin = document.getElementById('tab-login');

// Handle port mismatch during development (Live Server on 5500, Backend on 5000)
const API_BASE = window.location.port === '5500'
    ? `${window.location.protocol}//${window.location.hostname}:5000`
    : '';

const loginPanel = document.getElementById('login-panel');

const panelTitle = document.getElementById('panel-title');
const panelDesc = document.getElementById('panel-desc');

function clearAuthSensitiveInputs() {
    const sensitiveFieldIds = [
        'username',
        'password'
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
    panelTitle.textContent = 'Welcome Back';
    panelDesc.textContent = 'Enter your credentials to access the portal';
});

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
let authServiceModulePromise = null;
let authSessionModulePromise = null;

function loadAuthServiceModule() {
    if (!authServiceModulePromise) {
        authServiceModulePromise = import('./services/authService.js').catch((error) => {
            authServiceModulePromise = null;
            throw error;
        });
    }
    return authServiceModulePromise;
}

function loadAuthSessionModule() {
    if (!authSessionModulePromise) {
        authSessionModulePromise = import('./services/sessionAuth.js').catch((error) => {
            authSessionModulePromise = null;
            throw error;
        });
    }
    return authSessionModulePromise;
}

function resolveDashboardPath(username = '', role = '') {
    // Unified dashboard shell for all roles.
    return './dashboard-admin.html';
}


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
        const raw = sessionStorage.getItem(LOGIN_LOCK_KEY);
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
    sessionStorage.setItem(LOGIN_LOCK_KEY, JSON.stringify(state));
}

function clearLoginLockState() {
    sessionStorage.removeItem(LOGIN_LOCK_KEY);
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

// Login Form Handler
const loginForm = document.getElementById('login-form');
if (loginForm) {
loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const username = document.getElementById('username') ? document.getElementById('username').value.trim() : '';
    const password = document.getElementById('password') ? document.getElementById('password').value : '';
    const err = document.getElementById('login-error');
    if (err) {
        err.style.display = 'none';
        err.textContent = '';
    }

    if (isLoginLocked()) {
        applyLoginLockStateUI();
        return;
    }

    if (!username || !password) {
        if (err) {
            err.textContent = 'Please enter email and password.';
            err.style.display = 'block';
        }
        return;
    }

    setLoginLoading(true);

    try {
        const authService = await loadAuthServiceModule();
        await authService.signInStaff({ identifier: username, password });
        const profile = await authService.getAuthenticatedStaffProfile();
        const role = profile?.role || profile?.staff_role || profile?.user_role || '';
        const authSession = await loadAuthSessionModule();

        sessionStorage.setItem('ukonek_role', String(role || '').trim().toLowerCase());
        authSession.setAuthSessionMeta({
            role: String(role || '').trim().toLowerCase(),
            userId: profile?.id || null,
            email: profile?.email || null
        });

        resetInvalidLoginAttempts();
        showPreloader(700, () => {
            window.location.href = resolveDashboardPath(username, role);
        });
    } catch (error) {
        const message = String(error?.message || 'Unable to sign in. Please try again.');
        const invalidCredentials = /invalid email or password|invalid credentials/i.test(message);

        if (invalidCredentials) {
            const state = recordInvalidLoginAttempt();
            if (state.lockUntil > Date.now()) {
                applyLoginLockStateUI();
                return;
            }
        }

        if (err) {
            err.textContent = message;
            err.style.display = 'block';
        }
    } finally {
        setLoginLoading(false);
    }
});
}

applyLoginLockStateUI();
setupPasswordVisibilityToggles();
