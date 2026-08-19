const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET;

function getBearerToken(req) {
  const header = String(req.headers.authorization || '');
  if (!header.toLowerCase().startsWith('bearer ')) return null;
  return header.slice(7).trim() || null;
}

function getAccessToken(req) {
  // Production-first: prefer httpOnly cookie.
  if (req.cookies && req.cookies.access_token) {
    return String(req.cookies.access_token);
  }

  // Dev fallback: allow Authorization: Bearer <token>.
  return getBearerToken(req);
}

function authenticateToken(req, res, next) {
  if (!JWT_SECRET) {
    return res.status(500).json({ message: 'Server auth is not configured (missing JWT_SECRET).' });
  }

  const token = getAccessToken(req);
  if (!token) {
    return res.status(401).json({ message: 'Missing access token.' });
  }

  try {
    const payload = jwt.verify(token, JWT_SECRET);
    req.user = {
      id: payload.sub,
      email: payload.email,
      role: String(payload.role || '').toLowerCase()
    };
    return next();
  } catch (_) {
    return res.status(401).json({ message: 'Invalid or expired access token.' });
  }
}

function requireRole(...allowedRoles) {
  const normalized = allowedRoles.map((role) => String(role || '').toLowerCase());

  return (req, res, next) => {
    const role = String(req.user?.role || '').toLowerCase();
    if (!role) {
      return res.status(403).json({ message: 'Role is required.' });
    }

    if (!normalized.includes(role)) {
      return res.status(403).json({ message: 'Insufficient permissions for this route.' });
    }

    return next();
  };
}

module.exports = {
  authenticateToken,
  requireRole
};
