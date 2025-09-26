// =============================================================================
// Simple SMTP Test - Quick Authentication Test
// =============================================================================

const nodemailer = require('nodemailer');

console.log('🚀 Simple SMTP Test Starting...');
console.log('=' .repeat(40));

// Simple configuration
const transporter = nodemailer.createTransporter({
    host: 'localhost', // Try localhost first
    port: 587,
    secure: false,
    auth: {
        user: 'noreply',
        pass: 'YOUR_PASSWORD_HERE' // Replace with your actual password
    },
    tls: {
        rejectUnauthorized: false
    },
    debug: true,
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
            from: 'noreply@100to1shot.com',
            to: 'ifoisal19@gmail.com', // Replace with your email
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