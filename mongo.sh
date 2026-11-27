require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 5000;
const MONGO_URI = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/smart_health_wellness';
const JWT_SECRET = process.env.JWT_SECRET || 'un_sdg3_smart_wellness_secret_2026';

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname)));


const WorkoutSchema = new mongoose.Schema({
  id: String,
  type: String,
  duration: Number,
  intensity: String,
  time: String,
});

const ReminderSchema = new mongoose.Schema({
  id: String,
  title: String,
  time: String,
  active: { type: Boolean, default: true },
});

const DayHistorySchema = new mongoose.Schema({
  day: String,
  water: Number,
  sleep: Number,
  exercise: Number,
});

const UserSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    role: { type: String, default: 'Student Profile' },
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    passwordHash: { type: String, required: true },
    data: {
      goals: {
        water: { type: Number, default: 8 },
        sleep: { type: Number, default: 8 },
        exercise: { type: Number, default: 45 },
      },
      profile: {
        heightCm: { type: Number, default: 174 },
        weightKg: { type: Number, default: 68 },
      },
      nutrition: {
        proteinGoal: { type: String, default: 'active' },
        creatinePhase: { type: String, default: 'none' },
        creatineGrams: { type: Number, default: 0 }, // Exact daily creatine intake in grams
      },
      mood: {
        label: { type: String, default: 'Calm & Focused' },
        emoji: { type: String, default: '😌' },
      },
      today: {
        water: { type: Number, default: 2 },
        sleepHours: { type: Number, default: 7.0 },
        sleepQuality: { type: String, default: 'Good' },
        workouts: [WorkoutSchema],
      },
      pastSixDays: [DayHistorySchema],
      reminders: [ReminderSchema],
    },
  },
  { timestamps: true }
);

const User = mongoose.model('User', UserSchema);

function buildDefaultUserData(isDemo = false) {
  return {
    goals: { water: 8, sleep: 8, exercise: 45 },
    profile: { heightCm: 174, weightKg: 68 },
    nutrition: {
      proteinGoal: isDemo ? 'strength' : 'active',
      creatinePhase: isDemo ? 'maintenance' : 'none',
      creatineGrams: isDemo ? 5 : 0,
    },
    mood: { label: 'Calm & Focused', emoji: '😌' },
    today: {
      water: isDemo ? 6 : 2,
      sleepHours: isDemo ? 7.5 : 7.0,
      sleepQuality: 'Good',
      workouts: isDemo
        ? [
            { id: 'w-1', type: 'Brisk Walking', duration: 25, intensity: 'Moderate', time: '08:00 AM' },
            { id: 'w-2', type: 'Gym / Strength Training', duration: 20, intensity: 'Vigorous', time: '05:15 PM' },
          ]
        : [],
    },
    pastSixDays: [
      { day: 'Mon', water: isDemo ? 7 : 5, sleep: 7.0, exercise: isDemo ? 30 : 20 },
      { day: 'Tue', water: isDemo ? 8 : 6, sleep: 7.5, exercise: isDemo ? 45 : 30 },
      { day: 'Wed', water: isDemo ? 6 : 5, sleep: 6.5, exercise: isDemo ? 25 : 15 },
      { day: 'Thu', water: isDemo ? 8 : 7, sleep: 8.0, exercise: isDemo ? 50 : 35 },
      { day: 'Fri', water: isDemo ? 7 : 6, sleep: 7.5, exercise: isDemo ? 40 : 25 },
      { day: 'Sat', water: isDemo ? 9 : 7, sleep: 8.5, exercise: isDemo ? 55 : 40 },
    ],
    reminders: [
      { id: 'r-1', title: 'Drink 250ml Water', time: '10:30 AM', active: true },
      { id: 'r-2', title: 'Midday Stretch Break', time: '01:45 PM', active: true },
      { id: 'r-3', title: 'Evening Workout & Creatine', time: '05:30 PM', active: true },
      { id: 'r-4', title: 'Wind Down for Sleep', time: '10:30 PM', active: true },
    ],
  };
}

// Seed default demo user in MongoDB if not present
async function seedDemoAccount() {
  try {
    const demoEmail = 'aarav.student@campus.edu';
    const existing = await User.findOne({ email: demoEmail });
    if (!existing) {
      const passwordHash = await bcrypt.hash('wellness123', 10);
      await User.create({
        name: 'Aarav Sharma',
        role: 'B.Tech Student • Campus Wellness',
        email: demoEmail,
        passwordHash,
        data: buildDefaultUserData(true),
      });
      console.log('Seeded Demo Account in MongoDB:', demoEmail);
    }
  } catch (err) {
    console.error('Demo seed error:', err.message);
  }
}

function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'Authentication token required' });

  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err) return res.status(403).json({ error: 'Invalid or expired token' });
    req.userId = decoded.userId;
    next();
  });
}


// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', database: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected' });
});

// POST /api/auth/signup - Register new user with isolated MongoDB document
app.post('/api/auth/signup', async (req, res) => {
  try {
    const { name, role, email, password } = req.body;
    if (!name || !email || !password) {
      return res.status(400).json({ error: 'Name, email, and password are required.' });
    }

    const normalizedEmail = email.trim().toLowerCase();
    const existing = await User.findOne({ email: normalizedEmail });
    if (existing) {
      return res.status(409).json({ error: 'An account with this email already exists.' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const newUser = await User.create({
      name: name.trim(),
      role: role?.trim() || 'Student Profile',
      email: normalizedEmail,
      passwordHash,
      data: buildDefaultUserData(false),
    });

    const token = jwt.sign({ userId: newUser._id, email: newUser.email }, JWT_SECRET, { expiresIn: '7d' });
    res.status(201).json({
      token,
      user: { name: newUser.name, role: newUser.role, email: newUser.email, data: newUser.data },
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error creating account: ' + err.message });
  }
});

// POST /api/auth/signin - Sign in user and load their isolated dashboard data
app.post('/api/auth/signin', async (req, res) => {
  try {
    const { email, password } = req.body;
    const normalizedEmail = (email || '').trim().toLowerCase();
    const user = await User.findOne({ email: normalizedEmail });

    if (!user) {
      return res.status(401).json({ error: 'Invalid email or password.' });
    }

    const isMatch = await bcrypt.compare(password || '', user.passwordHash);
    if (!isMatch) {
      return res.status(401).json({ error: 'Invalid email or password.' });
    }

    const token = jwt.sign({ userId: user._id, email: user.email }, JWT_SECRET, { expiresIn: '7d' });
    res.json({
      token,
      user: { name: user.name, role: user.role, email: user.email, data: user.data },
    });
  } catch (err) {
    res.status(500).json({ error: 'Sign in failed: ' + err.message });
  }
});

// GET /api/user/me - Fetch authenticated user's profile & wellness state
app.get('/api/user/me', authenticateToken, async (req, res) => {
  try {
    const user = await User.findById(req.userId).select('-passwordHash');
    if (!user) return res.status(404).json({ error: 'User not found' });
    res.json({ user: { name: user.name, role: user.role, email: user.email, data: user.data } });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/user/data - Persist updated habits, creatine grams, BMI, goals & reminders to MongoDB
app.put('/api/user/data', authenticateToken, async (req, res) => {
  try {
    const { data } = req.body;
    if (!data) return res.status(400).json({ error: 'Wellness data payload required' });

    const updatedUser = await User.findByIdAndUpdate(
      req.userId,
      { $set: { data } },
      { new: true }
    ).select('-passwordHash');

    if (!updatedUser) return res.status(404).json({ error: 'User not found' });
    res.json({ message: 'Saved to MongoDB', data: updatedUser.data });
  } catch (err) {
    res.status(500).json({ error: 'Failed to save data: ' + err.message });
  }
});

// Serve frontend for root path
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

mongoose
  .connect(MONGO_URI)
  .then(async () => {
    console.log('Connected to MongoDB:', MONGO_URI);
    await seedDemoAccount();
    app.listen(PORT, () => {
      console.log(`Smart Health & Wellness Server running on http://localhost:${PORT}`);
    });
  })
  .catch((err) => {
    console.error('MongoDB connection error:', err.message);
    process.exit(1);
  });
