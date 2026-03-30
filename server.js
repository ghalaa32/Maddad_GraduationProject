const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
require('dotenv').config();

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// General rate limiter for static routes
const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 200,
  message: 'Too many requests, please try again later.'
});

// Serve static files from specific public directories only
app.use('/pages', generalLimiter, express.static('pages'));
app.use('/js', generalLimiter, express.static('js'));
app.use('/pictures', generalLimiter, express.static('pictures'));
app.use('/skills-icons', generalLimiter, express.static('skills-icons'));
app.get('/', generalLimiter, (req, res) => {
  res.sendFile('index.html', { root: '.' });
});

// MongoDB Connection
const connectDB = async () => {
  try {
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('MongoDB connected successfully');
  } catch (error) {
    console.error('MongoDB connection error:', error);
    process.exit(1);
  }
};

connectDB();

// Routes
app.use('/api/accounts', require('./routes/accounts'));

// Start server
const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
