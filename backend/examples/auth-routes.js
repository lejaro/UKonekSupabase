const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const cookieParser = require('cookie-parser');
const { authenticateToken, requireRole } = require('./auth-middleware');

const router = express.Router();
router.use(cookieParser());

const JWT_SECRET = process.env.JWT_SECRET;
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '8h';
const NODE_ENV = process.env.NODE_ENV || 'development';

// Replace with a real DB lookup.
async function findUserByEmail(email) {
  return null;
}

function signAccessToken(user) {
  return jwt.sign(
    {
      sub: user.id,
      email: user.email,
      role: String(user.role || '').toLowerCase()
    },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRES_IN }
  );
}

function setAuthCookie(res, token) {
  // httpOnly cookie avoids exposing tokens to JavaScript in production.
  res.cookie('access_token', token, {
    httpOnly: true,
    secure: NODE_ENV === 'production',
    sameSite: 'lax',
    maxAge: 8 * 60 * 60 * 1000
  });
}

router.post('/auth/login', async (req, res) => {
  if (!JWT_SECRET) {
    return res.status(500).json({ message: 'Server auth is not configured (missing JWT_SECRET).' });
  }

  const email = String(req.body?.email || '').trim().toLowerCase();
  const password = String(req.body?.password || '');
  if (!email || !password) {
    return res.status(400).json({ message: 'Email and password are required.' });
  }

  const user = await findUserByEmail(email);
  if (!user || !user.passwordHash) {
    return res.status(401).json({ message: 'Invalid email or password.' });
  }

  const valid = await bcrypt.compare(password, user.passwordHash);
  if (!valid) {
    return res.status(401).json({ message: 'Invalid email or password.' });
  }

  const token = signAccessToken(user);
  setAuthCookie(res, token);

  // Dev fallback: include token in payload when FE cannot use cookies yet.
  return res.json({
    token,
    user: {
      id: user.id,
      email: user.email,
      role: String(user.role || '').toLowerCase()
    }
  });
});

router.post('/auth/logout', (req, res) => {
  res.clearCookie('access_token', {
    httpOnly: true,
    secure: NODE_ENV === 'production',
    sameSite: 'lax'
  });
  return res.status(204).send();
});

router.get('/auth/me', authenticateToken, (req, res) => {
  return res.json({ user: req.user });
});

router.get('/admin/reports', authenticateToken, requireRole('admin'), (req, res) => {
  return res.json({ message: 'Admin reports endpoint', requestedBy: req.user.id });
});

router.get('/doctor/consultations', authenticateToken, requireRole('doctor', 'admin'), (req, res) => {
  return res.json({ message: 'Doctor consultations endpoint', requestedBy: req.user.id });
});

router.get('/staff/tasks', authenticateToken, requireRole('nurse', 'staff', 'doctor', 'admin'), (req, res) => {
  return res.json({ message: 'Staff tasks endpoint', requestedBy: req.user.id });
});

module.exports = router;
