const {onCall} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');

admin.initializeApp();

// ========================================
// Gmail SMTP Configuration
// ========================================
const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: 'munir.smart.glasses@gmail.com',
    pass: 'zqxyfynzxlkevzuq'
  }
});

// ========================================
// Cloud Function: Send Welcome Email (Callable)
// ========================================
exports.sendWelcomeEmail = onCall(async (request) => {
  const email = request.data.email;
  const displayName = request.data.displayName || 'User';

  console.log('📧 Sending welcome email to:', email);

  try {
    const link = await admin.auth().generateEmailVerificationLink(email);

    const mailOptions = {
      from: '"MUNIR - Smart Glasses 💜" <munir.smart.glasses@gmail.com>',
      to: email,
      subject: '✨ Welcome to MUNIR - Verify Your Email',
      html: getWelcomeEmailTemplate(displayName, link)
    };

    await transporter.sendMail(mailOptions);

    console.log('✅ Email sent successfully to:', email);
    return {success: true, message: 'Email sent successfully'};

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
});

// ========================================
// Cloud Function: Send Password Reset Email (Callable)
// ========================================
exports.sendCustomPasswordReset = onCall(async (request) => {
  const email = request.data.email;

  console.log('🔐 Sending password reset email to:', email);

  // Validate email
  if (!email) {
    throw new Error('Email is required');
  }

  try {
    // Generate password reset link
    const resetLink = await admin.auth().generatePasswordResetLink(email);

    const mailOptions = {
      from: '"MUNIR - Smart Glasses 💜" <munir.smart.glasses@gmail.com>',
      to: email,
      subject: '🔐 Password Reset Request - MUNIR',
      html: getPasswordResetEmailTemplate(resetLink)
    };

    await transporter.sendMail(mailOptions);

    console.log('✅ Password reset email sent successfully to:', email);
    return {success: true, message: 'Password reset email sent successfully'};

  } catch (error) {
    console.error('❌ Error sending password reset email:', error);
    
    if (error.code === 'auth/user-not-found') {
      throw new Error('No user found with this email');
    }
    
    throw new Error('Failed to send password reset email');
  }
});

// ========================================
// Welcome Email Template
// ========================================
function getWelcomeEmailTemplate(userName, verificationLink) {
  return `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f8f9fa;">
    
    <div style="max-width: 600px; margin: 0 auto; background: white;">
        
        <!-- Header -->
        <div style="background: linear-gradient(135deg, #B14ABA, #8E44AD); padding: 40px 20px; text-align: center;">
            <h1 style="color: white; margin: 0; font-size: 40px; font-weight: bold; letter-spacing: 3px;">✨ MUNIR</h1>
            <p style="color: rgba(255,255,255,0.9); margin: 8px 0 0 0; font-size: 15px;">Smart Glasses for the Visually Impaired</p>
        </div>
        
        <!-- Content -->
        <div style="padding: 40px 30px;">
            
            <h2 style="color: #2C3E50; margin: 0 0 20px 0; font-size: 26px;">Welcome, ${userName}! 👋</h2>
            
            <p style="color: #34495E; line-height: 1.6; font-size: 16px;">
                Thank you for joining <strong style="color: #B14ABA;">MUNIR</strong>! To get started, please verify your email address by clicking the button below:
            </p>
            
            <!-- Verify Button -->
            <div style="text-align: center; margin: 35px 0;">
                <a href="${verificationLink}" style="background: linear-gradient(135deg, #B14ABA, #8E44AD); color: white; padding: 16px 40px; text-decoration: none; border-radius: 12px; display: inline-block; font-weight: 600; font-size: 16px; box-shadow: 0 4px 12px rgba(177, 74, 186, 0.3);">
                    Verify My Email
                </a>
            </div>
            
            <!-- Backup Link -->
            <p style="color: #999; font-size: 13px; text-align: center; margin: 30px 0;">
                If the button doesn't work, copy this link:<br>
                <a href="${verificationLink}" style="color: #B14ABA; word-break: break-all; text-decoration: none;">${verificationLink}</a>
            </p>
            
            <!-- Security Note -->
            <div style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 30px 0; border-left: 4px solid #B14ABA;">
                <p style="color: #6c757d; margin: 0; font-size: 14px;">
                    <strong>⏰ Note:</strong> This link will expire in 1 hour. If you didn't request this, please ignore this email.
                </p>
            </div>
            
            <p style="color: #34495E; line-height: 1.6; margin-top: 30px; font-size: 15px;">
                Need help? Contact us at <a href="mailto:munir.smart.glasses@gmail.com" style="color: #B14ABA; text-decoration: none;">munir.smart.glasses@gmail.com</a>
            </p>
            
        </div>
        
        <!-- Footer -->
        <div style="padding: 30px 20px; text-align: center; background: #2C3E50; color: rgba(255,255,255,0.7); font-size: 12px;">
            <p style="margin: 0 0 5px 0; font-weight: 600; color: white; font-size: 16px;">MUNIR</p>
            <p style="margin: 0;">© 2024 MUNIR - AI Assistant App</p>
            <p style="margin: 10px 0 0 0; font-size: 11px;">This email was sent because you created an account.</p>
        </div>
        
    </div>
    
</body>
</html>
  `;
}

// ========================================
// Password Reset Email Template
// ========================================
function getPasswordResetEmailTemplate(resetLink) {
  return `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f8f9fa;">
    
    <div style="max-width: 600px; margin: 0 auto; background: white;">
        
        <!-- Header -->
        <div style="background: linear-gradient(135deg, #B14ABA, #8E44AD); padding: 40px 20px; text-align: center;">
            <div style="font-size: 50px; margin-bottom: 10px;">🔐</div>
            <h1 style="color: white; margin: 0; font-size: 32px; font-weight: bold;">Password Reset</h1>
            <p style="color: rgba(255,255,255,0.9); margin: 8px 0 0 0; font-size: 15px;">MUNIR - Smart Glasses</p>
        </div>
        
        <!-- Content -->
        <div style="padding: 40px 30px;">
            
            <h2 style="color: #2C3E50; margin: 0 0 20px 0; font-size: 24px;">Reset Your Password</h2>
            
            <p style="color: #34495E; line-height: 1.6; font-size: 16px;">
                We received a request to reset your password for your <strong style="color: #B14ABA;">MUNIR</strong> account.
            </p>
            
            <p style="color: #34495E; line-height: 1.6; font-size: 16px;">
                Click the button below to reset your password:
            </p>
            
            <!-- Reset Button -->
            <div style="text-align: center; margin: 35px 0;">
                <a href="${resetLink}" style="background: linear-gradient(135deg, #B14ABA, #8E44AD); color: white; padding: 16px 40px; text-decoration: none; border-radius: 12px; display: inline-block; font-weight: 600; font-size: 16px; box-shadow: 0 4px 12px rgba(177, 74, 186, 0.3);">
                    Reset Password
                </a>
            </div>
            
            <!-- Backup Link -->
            <p style="color: #999; font-size: 13px; text-align: center; margin: 30px 0;">
                Or copy and paste this link into your browser:<br>
                <a href="${resetLink}" style="color: #B14ABA; word-break: break-all; text-decoration: none; font-size: 12px;">${resetLink}</a>
            </p>
            
            <!-- Warning Box -->
            <div style="background: #fff5e6; padding: 20px; border-radius: 8px; margin: 30px 0; border-left: 4px solid #f59e0b;">
                <p style="color: #78350f; margin: 0 0 10px 0; font-size: 15px; font-weight: 600;">
                    ⚠️ Security Notice:
                </p>
                <ul style="margin: 0; padding-left: 20px; color: #78350f; font-size: 14px; line-height: 1.8;">
                    <li>This link is valid for <strong>1 hour only</strong></li>
                    <li>If you didn't request a password reset, please ignore this email</li>
                    <li>Never share this link with anyone</li>
                    <li>Your current password remains unchanged until you create a new one</li>
                </ul>
            </div>
            
            <!-- Help Section -->
            <div style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 30px 0;">
                <p style="color: #6c757d; margin: 0; font-size: 14px; line-height: 1.6;">
                    <strong>Having trouble?</strong><br>
                    If you continue to have problems, please contact our support team at 
                    <a href="mailto:munir.smart.glasses@gmail.com" style="color: #B14ABA; text-decoration: none;">munir.smart.glasses@gmail.com</a>
                </p>
            </div>
            
        </div>
        
        <!-- Footer -->
        <div style="padding: 30px 20px; text-align: center; background: #2C3E50; color: rgba(255,255,255,0.7); font-size: 12px;">
            <p style="margin: 0 0 5px 0; font-weight: 600; color: white; font-size: 16px;">MUNIR</p>
            <p style="margin: 0;">© 2024 MUNIR - AI Assistant App</p>
            <p style="margin: 10px 0 0 0; font-size: 11px;">This is an automated email, please do not reply.</p>
        </div>
        
    </div>
    
</body>
</html>
  `;
}