const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema({
    name: {
        type: String,
        required: [true, 'Please provide a name'],
        trim: true,
        maxlength: 100
    },
    email: {
        type: String,
        required: [true, 'Please provide an email'],
        unique: true,
        lowercase: true,
        match: [
            /^\w+([.-]?\w+)*@\w+([.-]?\w+)*(\.\w{2,3})+$/,
            'Please provide a valid email'
        ]
    },
    password: {
        type: String,
        required: [true, 'Please provide a password'],
        minlength: 6,
        select: false
    },
    subscription: {
        type: String,
        enum: ['free', 'basic', 'ai_enhanced'],
        default: 'free'
    },
    subscriptionExpiry: {
        type: Date,
        default: null
    },
    stripeCustomerId: {
        type: String,
        default: null
    },
    reportCount: {
        free: { type: Number, default: 0, max: 2 },
        basic: { type: Number, default: 0 },
        ai: { type: Number, default: 0 }
    },
    aiCredits: {
        type: Number,
        default: 0
    },
    isEmailVerified: {
        type: Boolean,
        default: false
    },
    emailVerificationToken: {
        type: String,
        select: false
    },
    resetPasswordToken: {
        type: String,
        select: false
    },
    resetPasswordExpire: {
        type: Date,
        select: false
    },
    lastLogin: {
        type: Date,
        default: Date.now
    },
    createdAt: {
        type: Date,
        default: Date.now
    }
});

// Hash password before saving
userSchema.pre('save', async function(next) {
    if (!this.isModified('password')) return next();
    
    this.password = await bcrypt.hash(this.password, 12);
    next();
});

// Compare password method
userSchema.methods.comparePassword = async function(enteredPassword) {
    return await bcrypt.compare(enteredPassword, this.password);
};

// Check if user can generate more reports
userSchema.methods.canGenerateReport = function(reportType = 'basic') {
    if (this.subscription === 'free') {
        return this.reportCount.free < 2;
    } else if (this.subscription === 'basic') {
        return true; // Unlimited basic reports
    } else if (this.subscription === 'ai_enhanced') {
        if (reportType === 'ai') {
            return this.aiCredits > 0;
        }
        return true; // Unlimited basic reports
    }
    return false;
};

// Increment report count
userSchema.methods.incrementReportCount = function(reportType = 'basic') {
    if (this.subscription === 'free') {
        this.reportCount.free += 1;
    } else if (reportType === 'ai' && this.subscription === 'ai_enhanced') {
        this.aiCredits -= 1;
    }
    return this.save();
};

module.exports = mongoose.model('User', userSchema);