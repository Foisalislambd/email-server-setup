// Test SMTP connection for your website
// Run this with: node test_smtp_connection.js

const nodemailer = require('nodemailer');

// SMTP configuration for your standalone mail server
const transporter = nodemailer.createTransporter({
    host: 'mail.100to1shot.com',
    port: 587,
    secure: false, // true for 465, false for other ports
    auth: {
        user: 'noreply', // Your mail username
        pass: 'your_password_here' // Replace with actual password
    },
    tls: {
        rejectUnauthorized: false // For self-signed certificates
    }
});

// Test email configuration
const mailOptions = {
    from: 'noreply@100to1shot.com',
    to: 'ifoisal19@gmail.com', // Replace with your test email
    subject: 'Test Email from Website',
    text: 'This is a test email from your website SMTP integration.',
    html: '<p>This is a test email from your website SMTP integration.</p>'
};

// Send test email
transporter.sendMail(mailOptions, (error, info) => {
    if (error) {
        console.log('❌ Error sending email:', error);
        console.log('\n🔧 Troubleshooting:');
        console.log('1. Make sure you replaced "your_password_here" with the actual password');
        console.log('2. Check if the noreply user exists: saslpasswd2 -u 100to1shot.com noreply');
        console.log('3. Verify Postfix is running: systemctl status postfix');
        console.log('4. Check mail logs: tail -f /var/log/mail.log');
    } else {
        console.log('✅ Email sent successfully!');
        console.log('Message ID:', info.messageId);
        console.log('Response:', info.response);
    }
});

// Test connection
transporter.verify((error, success) => {
    if (error) {
        console.log('❌ SMTP connection failed:', error);
    } else {
        console.log('✅ SMTP connection successful!');
    }
});