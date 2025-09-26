// =============================================================================
// Simple SMTP Test - Quick Authentication Test
// =============================================================================

require('dotenv').config();
const nodemailer = require('nodemailer');

console.log('🚀 Simple SMTP Test Starting...');
console.log('=' .repeat(40));

// Simple configuration from environment variables
const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'localhost',
    port: parseInt(process.env.SMTP_PORT) || 587,
    secure: process.env.SMTP_SECURE === 'true',
    auth: {
        user: process.env.SMTP_USER || 'noreply',
        pass: process.env.SMTP_PASS || 'YOUR_PASSWORD_HERE'
    },
    tls: {
        rejectUnauthorized: false
    },
    debug: process.env.DEBUG_MODE === 'true' || true,
    logger: true
});

// Test connection
console.log('📡 Testing SMTP connection...');
transporter.verify((error, success) => {
    if (error) {
        console.log('❌ Connection failed!');
        console.log('Error:', error.message);
        console.log('Code:', error.code);
        console.log('Response:', error.response);
        
        console.log('\n🔧 Quick fixes to try:');
        console.log('1. Make sure you set the correct password');
        console.log('2. Try changing host to "mail.100to1shot.com"');
        console.log('3. Check if Postfix is running: systemctl status postfix');
        console.log('4. Check mail logs: tail -f /var/log/mail.log');
    } else {
        console.log('✅ Connection successful!');
        
        // Send test email
        console.log('📧 Sending test email...');
        const mailOptions = {
            from: process.env.TEST_EMAIL_FROM || 'noreply@100to1shot.com',
            to: process.env.TEST_EMAIL_TO || 'ifoisal19@gmail.com',
            subject: 'Simple SMTP Test',
            text: 'This is a simple test email from your SMTP server.',
            html: '<p>This is a simple test email from your SMTP server.</p>'
        };
        
        transporter.sendMail(mailOptions, (error, info) => {
            if (error) {
                console.log('❌ Email sending failed!');
                console.log('Error:', error.message);
            } else {
                console.log('✅ Email sent successfully!');
                console.log('Message ID:', info.messageId);
                console.log('Response:', info.response);
            }
        });
    }
});