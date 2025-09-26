#!/bin/bash

# =============================================================================
# Comprehensive SMTP Authentication Test
# =============================================================================

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to test SASL authentication
test_sasl_auth() {
    print_status "Testing SASL authentication..."
    
    # Test with testsaslauthd if available
    if command -v testsaslauthd &> /dev/null; then
        print_status "Testing authentication for noreply user..."
        read -s -p "Enter password for noreply user: " PASSWORD
        echo
        
        if echo "$PASSWORD" | testsaslauthd -u noreply -r 100to1shot.com -s smtp; then
            print_success "SASL authentication successful!"
        else
            print_error "SASL authentication failed"
            print_status "Let's check the SASL database..."
            sasldblistusers2 -f /etc/sasldb2
        fi
    else
        print_warning "testsaslauthd not available, skipping direct auth test"
    fi
}

# Function to test SMTP handshake with authentication
test_smtp_auth() {
    print_status "Testing SMTP authentication via telnet..."
    
    print_status "Connecting to SMTP server on port 587..."
    print_status "You'll need to manually test the authentication sequence"
    echo
    
    cat << 'EOF'
Manual SMTP Authentication Test:
1. Run: telnet mail.100to1shot.com 587
2. Type: EHLO test.com
3. Type: STARTTLS
4. Type: AUTH LOGIN
5. Type: [base64 encoded username - see below]
6. Type: [base64 encoded password - see below]

To encode your credentials:
echo -n "noreply" | base64
echo -n "your_password" | base64
EOF
    
    echo
    print_status "Or use this automated test:"
    echo "swaks --to ifoisal19@gmail.com --from noreply@100to1shot.com --server mail.100to1shot.com:587 --auth-user noreply --auth-password your_password --tls"
}

# Function to test email sending
test_email_sending() {
    print_status "Testing email sending..."
    
    # Send test email
    echo "This is a test email from your SMTP server after authentication fix." | \
        mail -s "SMTP Authentication Test - $(date)" -a "From: noreply@100to1shot.com" ifoisal19@gmail.com
    
    print_success "Test email sent to ifoisal19@gmail.com"
    print_status "Check your inbox (and spam folder) for the test email"
}

# Function to check Postfix logs
check_logs() {
    print_status "Checking recent Postfix logs..."
    
    echo "Recent mail log entries:"
    tail -20 /var/log/mail.log | grep -E "(smtp|auth|error|warning)" || echo "No recent SMTP activity found"
}

# Function to show current configuration
show_config() {
    print_status "Current Postfix SASL configuration:"
    echo
    
    echo "SASL Auth Enable: $(postconf -h smtpd_sasl_auth_enable)"
    echo "SASL Type: $(postconf -h smtpd_sasl_type)"
    echo "SASL Path: $(postconf -h smtpd_sasl_path)"
    echo "SASL Security Options: $(postconf -h smtpd_sasl_security_options)"
    echo "SASL Local Domain: $(postconf -h smtpd_sasl_local_domain)"
    
    echo
    print_status "SASL Database Users:"
    sasldblistusers2 -f /etc/sasldb2 2>/dev/null || echo "Could not list users"
    
    echo
    print_status "Submission Port Configuration:"
    grep -A 10 "^submission" /etc/postfix/master.cf || echo "Submission port not configured"
}

# Function to create website test script
create_website_test() {
    print_status "Creating website integration test script..."
    
    cat > /root/test_website_smtp.js << 'EOF'
// Website SMTP Test Script
// Run with: node test_website_smtp.js

const nodemailer = require('nodemailer');

console.log('Testing SMTP connection for website integration...');

// SMTP configuration
const transporter = nodemailer.createTransporter({
    host: 'mail.100to1shot.com',
    port: 587,
    secure: false,
    auth: {
        user: 'noreply',
        pass: 'YOUR_PASSWORD_HERE' // Replace with actual password
    },
    tls: {
        rejectUnauthorized: false
    },
    debug: true, // Enable debug output
    logger: true // Enable logging
});

// Test connection
transporter.verify((error, success) => {
    if (error) {
        console.log('❌ Connection failed:', error);
    } else {
        console.log('✅ Connection successful!');
        
        // Send test email
        const mailOptions = {
            from: 'noreply@100to1shot.com',
            to: 'ifoisal19@gmail.com',
            subject: 'Website SMTP Test',
            text: 'This is a test email from your website SMTP integration.',
            html: '<p>This is a test email from your website SMTP integration.</p>'
        };
        
        transporter.sendMail(mailOptions, (error, info) => {
            if (error) {
                console.log('❌ Email sending failed:', error);
            } else {
                console.log('✅ Email sent successfully!');
                console.log('Message ID:', info.messageId);
            }
        });
    }
});
EOF
    
    print_success "Website test script created at /root/test_website_smtp.js"
    print_status "Edit the password in the script and run: node /root/test_website_smtp.js"
}

# Function to show troubleshooting steps
show_troubleshooting() {
    print_status "Troubleshooting Steps:"
    echo
    echo "1. Verify SASL database:"
    echo "   sasldblistusers2 -f /etc/sasldb2"
    echo
    echo "2. Check Postfix configuration:"
    echo "   postconf -n | grep sasl"
    echo
    echo "3. Test authentication manually:"
    echo "   telnet mail.100to1shot.com 587"
    echo
    echo "4. Check mail logs:"
    echo "   tail -f /var/log/mail.log"
    echo
    echo "5. Verify submission port:"
    echo "   netstat -tlnp | grep 587"
    echo
    echo "6. Test with swaks (if installed):"
    echo "   swaks --to test@example.com --from noreply@100to1shot.com --server mail.100to1shot.com:587 --auth-user noreply --auth-password your_password --tls"
}

# Main menu
show_menu() {
    echo
    print_status "SMTP Authentication Test Menu"
    echo
    echo "1. Test SASL authentication"
    echo "2. Test SMTP authentication via telnet"
    echo "3. Send test email"
    echo "4. Check Postfix logs"
    echo "5. Show current configuration"
    echo "6. Create website test script"
    echo "7. Show troubleshooting steps"
    echo "8. Run all tests"
    echo "9. Exit"
    echo
}

# Function to run all tests
run_all_tests() {
    print_status "Running all SMTP authentication tests..."
    echo
    
    show_config
    echo
    test_email_sending
    echo
    check_logs
    echo
    create_website_test
    echo
    show_troubleshooting
}

# Main function
main() {
    while true; do
        show_menu
        read -p "Select an option (1-9): " choice
        
        case $choice in
            1)
                test_sasl_auth
                ;;
            2)
                test_smtp_auth
                ;;
            3)
                test_email_sending
                ;;
            4)
                check_logs
                ;;
            5)
                show_config
                ;;
            6)
                create_website_test
                ;;
            7)
                show_troubleshooting
                ;;
            8)
                run_all_tests
                ;;
            9)
                print_status "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Run main function
main "$@"