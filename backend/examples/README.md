# Auth + RBAC Example (Express)

This folder contains production-oriented examples for isolated authentication and role-based authorization.

## Why this avoids session conflicts

1. Each login produces a signed JWT with user-specific claims (`sub`, `email`, `role`).
2. The backend validates the token on every request (`authenticateToken` middleware).
3. No global shared `currentUser` variable is used.
4. Browser sessions are isolated by cookie/session per browser profile/device.

## Recommended production setup

- Store access tokens in `httpOnly` cookies (`secure: true` in production).
- Keep CORS and cookie settings strict.
- Rotate JWT secret and set a short token TTL.
- Use refresh token flow if you need long-lived sessions.

## Frontend integration notes

- If using cookie auth, send requests with `credentials: 'include'`.
- Avoid storing auth tokens in `localStorage`.
- For local development fallback, `sessionStorage` may be used only for non-cookie token transport.

## Files

- `auth-middleware.js`: JWT verification + `requireRole()` helper.
- `auth-routes.js`: sample login/logout/me and protected role-specific endpoints.
