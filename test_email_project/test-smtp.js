// =============================================================================
// SMTP Test Project - Comprehensive Email Testing
// =============================================================================

require('dotenv').config();
const nodemailer = require('nodemailer');

// Configuration from environment variables
const config = {
    // Try different host options
    hosts: [
        process.env.SMTP_HOST || 'localhost',
        'mail.100to1shot.com',
        '127.0.0.1'
    ],
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
};

// Test email configuration
const testEmail = {
    from: process.env.TEST_EMAIL_FROM || 'noreply@100to1shot.com',
    to: process.env.TEST_EMAIL_TO || 'ifoisal19@gmail.com',
    subject: 'SMTP Test - ' + new Date().toISOString(),
    text: 'This is a test email from your SMTP server.',
    html: `
        <h2>SMTP Test Email</h2>
        <p>This is a test email from your SMTP server.</p>
        <p><strong>Timestamp:</strong> ${new Date().toISOString()}</p>
        <p><strong>Server:</strong> mail.100to1shot.com</p>
        <p><strong>Port:</strong> 587</p>
        <p><strong>Authentication:</strong> SASL</p>
    `
};

// Function to test SMTP connection
async function testSMTPConnection(host) {
    console.log(`\n🔍 Testing SMTP connection to: ${host}`);
    console.log('=' .repeat(50));
    
    const transporter = nodemailer.createTransporter({
        ...config,
        host: host
    });
    
    try {
        // Test connection
        console.log('📡 Testing connection...');
        const connectionResult = await transporter.verify();
        console.log('✅ Connection successful!');
        
        // Send test email
        console.log('📧 Sending test email...');
        const info = await transporter.sendMail(testEmail);
        
        console.log('✅ Email sent successfully!');
        console.log('📋 Email Details:');
        console.log(`   Message ID: ${info.messageId}`);
        console.log(`   Response: ${info.response}`);
        console.log(`   Accepted: ${info.accepted}`);
        console.log(`   Rejected: ${info.rejected}`);
        
        return { success: true, host, info };
        
    } catch (error) {
        console.log('❌ Connection/Email failed!');
        console.log('📋 Error Details:');
        console.log(`   Code: ${error.code}`);
        console.log(`   Response: ${error.response}`);
        console.log(`   Command: ${error.command}`);
        console.log(`   Message: ${error.message}`);
        
        if (error.responseCode) {
            console.log(`   Response Code: ${error.responseCode}`);
        }
        
        return { success: false, host, error };
    }
}

// Function to test different authentication methods
async function testAuthMethods(host) {
    console.log(`\n🔐 Testing different authentication methods for: ${host}`);
    console.log('=' .repeat(50));
    
    const authMethods = [
        { user: 'noreply', description: 'Username only' },
        { user: 'noreply@100to1shot.com', description: 'Full email' },
        { user: 'noreply@100to1shot.com', description: 'With domain' }
    ];
    
    for (const auth of authMethods) {
        console.log(`\n🧪 Testing: ${auth.description}`);
        
        const transporter = nodemailer.createTransporter({
            ...config,
            host: host,
            auth: {
                user: auth.user,
                pass: config.auth.pass
            }
        });
        
        try {
            await transporter.verify();
            console.log(`✅ ${auth.description} - SUCCESS`);
        } catch (error) {
            console.log(`❌ ${auth.description} - FAILED: ${error.message}`);
        }
    }
}

// Function to show configuration
function showConfiguration() {
    console.log('⚙️  SMTP Configuration:');
    console.log('=' .repeat(50));
    console.log(`Hosts to test: ${config.hosts.join(', ')}`);
    console.log(`Port: ${config.port}`);
    console.log(`Secure: ${config.secure}`);
    console.log(`Username: ${config.auth.user}`);
    console.log(`Password: ${'*'.repeat(config.auth.pass.length)}`);
    console.log(`TLS Reject Unauthorized: ${config.tls.rejectUnauthorized}`);
    console.log(`Debug: ${config.debug}`);
    console.log(`Logger: ${config.logger}`);
}

// Function to show troubleshooting tips
function showTroubleshooting() {
    console.log('\n🔧 Troubleshooting Tips:');
    console.log('=' .repeat(50));
    console.log('1. Make sure you replaced "YOUR_PASSWORD_HERE" with your actual password');
    console.log('2. Check if the noreply user exists: sasldblistusers2 -f /etc/sasldb2');
    console.log('3. Verify Postfix is running: systemctl status postfix');
    console.log('4. Check mail logs: tail -f /var/log/mail.log');
    console.log('5. Test with telnet: telnet localhost 587');
    console.log('6. Verify master.cf configuration: grep -A 15 "^submission" /etc/postfix/master.cf');
    console.log('7. Check SASL configuration: postconf | grep sasl');
}

// Main function
async function main() {
    console.log('🚀 SMTP Test Project Starting...');
    console.log('=' .repeat(50));
    
    // Check if password is set
    if (config.auth.pass === 'YOUR_PASSWORD_HERE') {
        console.log('❌ ERROR: Please set your password in the config!');
        console.log('Edit the file and replace "YOUR_PASSWORD_HERE" with your actual password');
        showTroubleshooting();
        return;
    }
    
    showConfiguration();
    
    const results = [];
    
    // Test each host
    for (const host of config.hosts) {
        const result = await testSMTPConnection(host);
        results.push(result);
        
        if (result.success) {
            console.log(`\n🎉 SUCCESS with host: ${host}`);
            break; // Stop testing if one works
        }
    }
    
    // Test authentication methods if no host worked
    const successfulHost = results.find(r => r.success);
    if (!successfulHost) {
        console.log('\n🔍 No host worked, testing authentication methods...');
        await testAuthMethods('localhost');
    }
    
    // Show summary
    console.log('\n📊 Test Summary:');
    console.log('=' .repeat(50));
    results.forEach(result => {
        const status = result.success ? '✅ SUCCESS' : '❌ FAILED';
        console.log(`${status} - ${result.host}`);
    });
    
    if (results.some(r => r.success)) {
        console.log('\n🎉 At least one configuration worked!');
        console.log('You can use the successful configuration in your website.');
    } else {
        console.log('\n❌ All configurations failed.');
        showTroubleshooting();
    }
}

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
    console.log('\n💥 Uncaught Exception:', error.message);
    showTroubleshooting();
});

process.on('unhandledRejection', (reason, promise) => {
    console.log('\n💥 Unhandled Rejection at:', promise, 'reason:', reason);
    showTroubleshooting();
});

// Run the test
main().catch(console.error);