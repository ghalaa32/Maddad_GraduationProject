const express = require('express');
const router = express.Router();
const rateLimit = require('express-rate-limit');
const Account = require('../models/Account');

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  message: { success: false, message: 'Too many requests, please try again later.' }
});

// POST /api/accounts/register - Create new account
router.post('/register', authLimiter, async (req, res) => {
  try {
    const { username, email, password, fullName, phone } = req.body;

    if (!username || !email || !password || !fullName) {
      return res.status(400).json({ success: false, message: 'Please provide username, email, password, and fullName' });
    }

    const existing = await Account.findOne({ $or: [{ email }, { username }] });
    if (existing) {
      return res.status(400).json({ success: false, message: 'Account already exists with that email or username' });
    }

    const account = new Account({ username, email, password, fullName, phone });
    await account.save();

    res.status(201).json({
      success: true,
      message: 'Account created successfully',
      account: {
        id: account._id,
        username: account.username,
        email: account.email,
        fullName: account.fullName
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
});

// POST /api/accounts/login - Authenticate account
router.post('/login', authLimiter, async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({ success: false, message: 'Please provide email and password' });
    }

    const account = await Account.findOne({ email }).select('+password');
    if (!account) {
      return res.status(401).json({ success: false, message: 'Invalid credentials' });
    }

    const isMatch = await account.matchPassword(password);
    if (!isMatch) {
      return res.status(401).json({ success: false, message: 'Invalid credentials' });
    }

    res.status(200).json({
      success: true,
      message: 'Login successful',
      account: {
        id: account._id,
        username: account.username,
        email: account.email,
        fullName: account.fullName
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
});

// GET /api/accounts - Get all accounts
router.get('/', authLimiter, async (req, res) => {
  try {
    const accounts = await Account.find().select('-password');
    res.status(200).json({ success: true, accounts });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
});

// GET /api/accounts/:id - Get single account
router.get('/:id', authLimiter, async (req, res) => {
  try {
    const account = await Account.findById(req.params.id).select('-password');
    if (!account) {
      return res.status(404).json({ success: false, message: 'Account not found' });
    }
    res.status(200).json({ success: true, account });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
});

// PUT /api/accounts/:id - Update account
router.put('/:id', authLimiter, async (req, res) => {
  try {
    const { username, email, fullName, phone } = req.body;

    // Check for conflicts with other accounts
    if (username || email) {
      const conflict = await Account.findOne({
        _id: { $ne: req.params.id },
        $or: [
          ...(username ? [{ username }] : []),
          ...(email ? [{ email }] : [])
        ]
      });
      if (conflict) {
        return res.status(400).json({ success: false, message: 'Username or email already in use by another account' });
      }
    }

    const account = await Account.findByIdAndUpdate(
      req.params.id,
      { username, email, fullName, phone, updatedAt: Date.now() },
      { new: true, runValidators: true }
    ).select('-password');

    if (!account) {
      return res.status(404).json({ success: false, message: 'Account not found' });
    }

    res.status(200).json({ success: true, message: 'Account updated', account });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
});

// DELETE /api/accounts/:id - Delete account
router.delete('/:id', authLimiter, async (req, res) => {
  try {
    const account = await Account.findByIdAndDelete(req.params.id);
    if (!account) {
      return res.status(404).json({ success: false, message: 'Account not found' });
    }
    res.status(200).json({ success: true, message: 'Account deleted' });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
});

module.exports = router;
