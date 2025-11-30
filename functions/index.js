const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');

admin.initializeApp();
const db = admin.firestore();

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: 'munir.smart.glasses@gmail.com',
    pass: 'zqxyfynzxlkevzuq'
  }
});


exports.sendVerificationEmail = onCall(async (request) => {
  const email = request.data.email;
  const displayName = request.data.displayName || 'User';

  console.log('📧 Sending verification email to:', email);

  try {
    const link = await admin.auth().generateEmailVerificationLink(email);
    const dateOnly = new Date().toISOString().split('T')[0];

    const mailOptions = {
      from: '"MUNIR - Smart Glasses 💜" <munir.smart.glasses@gmail.com>',
      to: email,
      subject: `Welcome to MUNIR - Verify Your Emai (${dateOnly})`,
      html: getWelcomeEmailTemplate(displayName, link)
    };

    await transporter.sendMail(mailOptions);

    await db
      .collection('email_verifications')
      .doc(email)
      .set(
        {
          lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

    console.log('✅ Email sent successfully to:', email);
    return { success: true, message: 'Email sent successfully' };

  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
});

function getResendVerificationExpiredTemplate(userName, verificationLink) {
  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>New Verification Link – MUNIR</title>
</head>

<body style="margin:0; padding:0; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif; background:#f8f9fa;">
  <div style="max-width:600px; margin:0 auto; background:#ffffff;">

    <div style="padding:30px 20px; text-align:center; background:linear-gradient(135deg, #B14ABA, #8E44AD);">
      <h1 style="color:#ffffff; margin:0 0 10px 0; font-size:26px; font-weight:700;">
        New verification link
      </h1>
      <p style="color:rgba(255,255,255,0.95); margin:0; font-size:14px;">
        Hi ${userName}, your previous link may have expired, so here is a new one.
      </p>
    </div>

    <div style="padding:26px 22px; color:#2C3E50;">
      <p style="font-size:15px; margin:0 0 16px 0;">
        To activate your <strong>MUNIR</strong> account, please verify your email by clicking the button below:
      </p>

      <div style="text-align: center; margin: 28px 0;">
        <a href="${verificationLink}" style="background: linear-gradient(135deg, #B14ABA, #8E44AD); color: white; padding: 16px 40px; text-decoration: none; border-radius: 12px; display: inline-block; font-weight: 600; font-size: 16px; box-shadow: 0 4px 12px rgba(177, 74, 186, 0.3);">
          Verify my email
        </a>
      </div>

      <p style="color: #999; font-size: 13px; text-align: center; margin: 24px 0;">
        Or copy and paste this link into your browser:<br>
        <a href="${verificationLink}" style="color: #B14ABA; word-break: break-all; text-decoration: none; font-size: 12px;">${verificationLink}</a>
      </p>
    </div>

    <div style="padding:14px 20px; font-size:12px; color:#95a5a6; text-align:center; background:#f2f2f2;">
      MUNIR – Smart Glasses · Empowering visually impaired users 💜
    </div>

  </div>
</body>
</html>
  `;
}
exports.handleUnverifiedLogin = onCall(async (request) => {
  const email = request.data.email;
  const displayName = request.data.displayName || 'User';

  if (!email) {
    throw new HttpsError('invalid-argument', 'Email is required');
  }

  const metaRef = db.collection('email_verifications').doc(email);
  const metaSnap = await metaRef.get();

  let shouldResend = false;
  let lastSentAtIso = null;

  if (!metaSnap.exists) {
    // ما عندنا أي سجل → غالباً أول مرة أو من قبل ما نطبق التخزين
    shouldResend = true;
  } else {
    const data = metaSnap.data() || {};
    const lastSentAt = data.lastSentAt;

    if (!lastSentAt) {
      shouldResend = true;
    } else {
      const lastDate = lastSentAt.toDate
        ? lastSentAt.toDate()
        : new Date(lastSentAt);
      lastSentAtIso = lastDate.toISOString();

      const diffMs = Date.now() - lastDate.getTime();
      const diffHours = diffMs / (1000 * 60 * 60);

      // هنا شرط الـ 1 ساعة
      if (diffHours >= 1) {
        shouldResend = true;
      }
    }
  }

  if (!shouldResend) {
    // لا نرسل جديد → نقول للـ client إنه يستعمل الإيميل القديم
    return {
      resent: false,
      lastSentAt: lastSentAtIso,
      message: 'Verification email already sent recently',
    };
  }

  // نسوي generate لرابط جديد + نرسل تمبلت "expired/new link"
  try {
    const link = await admin.auth().generateEmailVerificationLink(email);
    const dateOnly = new Date().toISOString().split('T')[0];

    const mailOptions = {
      from: '"MUNIR - Smart Glasses 💜" <munir.smart.glasses@gmail.com>',
      to: email,
      subject: `New Email Verification Link – MUNIR (${dateOnly})`,
      html: getResendVerificationExpiredTemplate(displayName, link),
    };

    await transporter.sendMail(mailOptions);

    await metaRef.set(
      {
        lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    console.log('✅ Resent verification email (after login) to:', email);

    return {
      resent: true,
      message: 'New verification email sent',
    };
  } catch (error) {
    console.error('❌ Error in handleUnverifiedLogin:', error);
    throw new HttpsError(
      'internal',
      'Failed to send a new verification email',
    );
  }
});

exports.sendCustomPasswordReset = onCall(async (request) => {
  const email = request.data.email;

  console.log('🔐 Sending password reset email to:', email);

  if (!email) {
    throw new Error('Email is required');
  }

  try {
    const resetLink = await admin.auth().generatePasswordResetLink(email);
const dateOnly = new Date().toISOString().split('T')[0];

    const mailOptions = {
      from: '"MUNIR - Smart Glasses 💜" <munir.smart.glasses@gmail.com>',
      to: email,
    subject: `🔐 Password Reset Request – MUNIR (${dateOnly})`,
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

function getWelcomeEmailTemplate(userName, verificationLink) {
  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>Welcome to MUNIR</title>
</head>

<body style="margin:0; padding:0; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif; background:#f8f9fa;">
  <div style="max-width:600px; margin:0 auto; background:#ffffff;">

    <!-- Header -->
    <div style="padding:30px 20px; text-align:center; background:linear-gradient(135deg, #B14ABA, #8E44AD);">
      
      <!-- Logo -->
      <img 
        src="https://firebasestorage.googleapis.com/v0/b/munir-21f4a.firebasestorage.app/o/Munir_Logo%2Fmunir_logo.png?alt=media&token=c8315518-f368-4aac-ad80-30166b9f0680"
        alt="MUNIR Logo"
        style="width:150px; height:auto; display:block; margin:0 auto 18px auto;"
      />

      <!-- Welcome Title -->
      <h1 style="color:#ffffff; margin:0 0 10px 0; font-size:28px; font-weight:700;">
        Welcome to MUNIR
      </h1>

      <!-- Greeting -->
      <p style="color:rgba(255,255,255,0.95); margin:0; font-size:15px;">
We're happy to have you with us, ${userName}
      </p>
    </div>

    <!-- Body -->
    <div style="padding:26px 22px; color:#2C3E50;">
      <p style="font-size:16px; margin:0 0 16px 0;">
        Thank you for signing up to <strong>MUNIR</strong>.
      </p>

      <p style="font-size:15px; margin:0 0 18px 0;">
        To complete your registration, please verify your email by clicking the button below:
      </p>

            <div style="text-align: center; margin: 35px 0;">
                <a href="${verificationLink}" style="background: linear-gradient(135deg, #B14ABA, #8E44AD); color: white; padding: 16px 40px; text-decoration: none; border-radius: 12px; display: inline-block; font-weight: 600; font-size: 16px; box-shadow: 0 4px 12px rgba(177, 74, 186, 0.3);">
                    Verify my email
                </a>
            </div>

     <p style="color: #999; font-size: 13px; text-align: center; margin: 30px 0;">
      Or copy and paste this link into your browser:<br>
      <a href="${verificationLink}" style="color: #B14ABA; word-break: break-all; text-decoration: none; font-size: 12px;">${verificationLink}</a>
      </p>

      <p style="font-size:14px; margin:0 0 4px 0;">
        If you did not create this account, you can safely ignore this email.
      </p>
    </div>

    <!-- Footer -->
    <div style="padding:14px 20px; font-size:12px; color:#95a5a6; text-align:center; background:#f2f2f2;">
      MUNIR – Smart Glasses · Empowering visually impaired users 💜
    </div>

  </div>
</body>
</html>
  `;
}


function getPasswordResetEmailTemplate(resetLink) {
  return `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>

<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f8f9fa;">
    <!-- prevent-gmail-collapse: ${Date.now()} -->

    <div style="max-width: 600px; margin: 0 auto; background: white;">

        <!-- Gmail anti-expansion fix -->
        <div style="height:1px; opacity:0; line-height:1px; font-size:1px;">&zwnj;</div>

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
        </div>
            <div style="padding:14px 20px; font-size:12px; color:#95a5a6; text-align:center; background:#f2f2f2;">
      MUNIR – Smart Glasses · Empowering visually impaired users 💜
    </div>
    </div>
</body>
</html>
  `;
}


exports.sendLoginAlertEmail = onCall(async (request) => {
  const email = request.data.email;
  const loginMethod = request.data.loginMethod || 'Email/Password';

  console.log('🔔 Login alert requested for:', email, 'via', loginMethod);

  if (!email) {
    console.error('❌ No email provided for login alert');
    throw new Error('Email is required');
  }
const dateOnly = new Date().toISOString().split('T')[0];

  const mailOptions = {
    from: '"MUNIR - Smart Glasses 💜" <munir.smart.glasses@gmail.com>',
    to: email,
subject: `🔔 New Login to Your MUNIR Account (${dateOnly})`,
    html: `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
</head>

<body style="margin:0; padding:0; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif; background:#f0f0f0;">
  <!-- prevent-gmail-collapse: ${Date.now()} -->

  <div style="max-width:600px; margin:0 auto; padding:20px;">

    <!-- Gmail anti-expansion fix -->
    <div style="height:1px; opacity:0; line-height:1px; font-size:1px;">&zwnj;</div>

    <!-- Card -->
    <div style="background:#ffffff; border-radius:12px; overflow:hidden; box-shadow:0 4px 12px rgba(0,0,0,0.08);">

      <!-- Header -->
      <div style="background: linear-gradient(135deg, #B14ABA, #8E44AD); padding:30px 20px; text-align:center;">
        <h1 style="color:#ffffff; margin:0; font-size:28px; font-weight:bold;">MUNIR - Security Alert</h1>
        <p style="color:rgba(255,255,255,0.9); margin:8px 0 0; font-size:14px;">
          New login detected to your account
        </p>
      </div>

      <!-- Body content -->
      <div style="padding:30px;">
        <p style="color:#34495E; font-size:16px; line-height:1.6; margin:0 0 16px;">
          We noticed a new login to your <strong style="color:#B14ABA;">MUNIR</strong> account.
        </p>

        <p style="color:#34495E; font-size:15px; line-height:1.6; margin:0 0 22px;">
          <strong>Login method:</strong> ${loginMethod}<br/>
          <strong>Time:</strong> ${new Date().toISOString()}
        </p>

        <!-- Alert Box (card inside card) -->
        <div style="background:#f8f9fa; padding:16px; border-radius:8px; border-left:4px solid #B14ABA;">
          <p style="color:#6c757d; margin:0; font-size:14px; line-height:1.6;">
            If this was you, no action is needed.<br/>
            If you did <strong>not</strong> perform this login, we strongly recommend:
          </p>

          <ul style="color:#6c757d; font-size:14px; line-height:1.8; margin:10px 0 0 20px; padding:0;">
            <li>Changing your password immediately.</li>
            <li>Reviewing recent activity in your account.</li>
          </ul>
        </div>
      </div>

    </div>
        <div style="padding:14px 20px; font-size:12px; color:#95a5a6; text-align:center; background:#f2f2f2;">
      MUNIR – Smart Glasses · Empowering visually impaired users 💜
    </div>
  </div>

</body>
</html>
    `,
  };

  try {
    await transporter.sendMail(mailOptions);
    console.log('✅ Login alert email sent to:', email);
    return { success: true, message: 'Login alert email sent successfully' };
  } catch (error) {
    console.error('❌ Error sending login alert email:', error);
    throw new Error('Failed to send login alert email');
  }
});


exports.sendAccountDeletionEmail = onCall(async (request) => {
  const email = request.data.email;
  const displayName = request.data.displayName || 'User';

  console.log('🗑️ Account deletion email requested for:', email);

  if (!email) {
    throw new Error('Email is required');
  }

  try {
    const dateOnly = new Date().toISOString().split('T')[0];

    const mailOptions = {
      from: '"MUNIR - Smart Glasses 💜" <munir.smart.glasses@gmail.com>',
      to: email,
      subject: `Your MUNIR Account Has Been Deleted (${dateOnly})`,
      html: getAccountDeletionEmailTemplate(displayName),
    };

    await transporter.sendMail(mailOptions);

    console.log('✅ Account deletion email sent to:', email);
    return { success: true, message: 'Account deletion email sent successfully' };
  } catch (error) {
    console.error('❌ Error sending account deletion email:', error);
    throw new Error('Failed to send account deletion email');
  }
});


function getAccountDeletionEmailTemplate(userName) {
  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>MUNIR – Account Deleted</title>
</head>

<body style="margin:0; padding:0; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif; background:#f8f9fa;">
  <div style="max-width:600px; margin:0 auto; background:#ffffff;">

    <!-- Header -->
    <div style="padding:30px 20px; text-align:center; background:linear-gradient(135deg, #B14ABA, #8E44AD);">
      <h1 style="color:#ffffff; margin:0 0 8px 0; font-size:26px; font-weight:700;">
        Your MUNIR account has been deleted
      </h1>

      <p style="color:rgba(255,255,255,0.95); margin:0; font-size:14px;">
        Goodbye, ${userName}.
      </p>
    </div>

    <!-- Body -->
    <div style="padding:26px 22px; color:#2C3E50;">
      <p style="font-size:16px; margin:0 0 16px 0;">
        This email confirms that your <strong>MUNIR</strong> account has been permanently deleted.
      </p>

      <p style="font-size:15px; margin:0 0 16px 0; line-height:1.6;">
        Your account data and personal information associated with this account have been removed from our active systems, according to our retention and security policies.
      </p>

      <p style="font-size:14px; color:#B14ABA; margin:0 0 4px 0;">
        Thank you for using MUNIR. You are always welcome to come back and create a new account in the future.
      </p>
    </div>

    <!-- Footer -->
    <div style="padding:14px 20px; font-size:12px; color:#95a5a6; text-align:center; background:#f2f2f2;">
      MUNIR – Smart Glasses · Empowering visually impaired users 💜
    </div>

  </div>
</body>
</html>
  `;
}

exports.checkEmailStatus = onCall(async (request) => {
  const email = request.data.email;

  if (!email) {
    throw new HttpsError('invalid-argument', 'Email is required');
  }

  try {
    const userRecord = await admin.auth().getUserByEmail(email);

    const providers = userRecord.providerData.map((p) => p.providerId);

    return {
      exists: true,
      providers: providers,
    };
  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      return {
        exists: false,
        providers: [],
      };
    }

    console.error('Error checking email status:', error);
    throw new HttpsError('internal', 'Unable to check email status');
  }
});

