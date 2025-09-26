#!/bin/bash

# =============================================================================
# Debug SMTP Authentication Issues
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

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to check SASL database
check_sasl_database() {
    print_status "Checking SASL database..."
    
    if [[ -f /etc/sasldb2 ]]; then
        print_success "SASL database exists"
        
        echo "Users in SASL database:"
        sasldblistusers2 -f /etc/sasldb2
        
        # Check permissions
        echo
        print_status "SASL database permissions:"
        ls -la /etc/sasldb2
    else
        print_error "SASL database not found!"
        return 1
    fi
}

# Function to check SASL configuration
check_sasl_config() {
    print_status "Checking SASL configuration files..."
    
    echo "SMTPD configuration:"
    if [[ -f /etc/postfix/sasl/smtpd.conf ]]; then
        cat /etc/postfix/sasl/smtpd.conf
    else
        print_error "SMTPD configuration not found!"
    fi
    
    echo
    echo "SMTP configuration:"
    if [[ -f /etc/postfix/sasl/smtp.conf ]]; then
        cat /etc/postfix/sasl/smtp.conf
    else
        print_error "SMTP configuration not found!"
    fi
}

# Function to check Postfix SASL configuration
check_postfix_sasl() {
    print_status "Checking Postfix SASL configuration..."
    
    echo "SASL-related Postfix settings:"
    postconf | grep -i sasl
}

# Function to test authentication manually
test_manual_auth() {
    print_status "Testing authentication manually..."
    
    print_status "Creating test script for manual authentication..."
    
    cat > /tmp/test_auth.sh << 'EOF'
#!/bin/bash

echo "Testing SMTP authentication manually..."
echo "This will help identify the exact issue."

# Get credentials
read -p "Enter username (noreply): " USERNAME
read -s -p "Enter password: " PASSWORD
echo

# Encode credentials for AUTH PLAIN
USERNAME_B64=$(echo -n "$USERNAME" | base64)
PASSWORD_B64=$(echo -n "$PASSWORD" | base64)
AUTH_STRING=$(echo -n "$USERNAME@100to1shot.com:$PASSWORD" | base64)

echo "Base64 encoded username: $USERNAME_B64"
echo "Base64 encoded password: $PASSWORD_B64"
echo "Base64 encoded auth string: $AUTH_STRING"

echo
echo "Now testing with telnet..."
echo "Run these commands in telnet:"
echo "1. telnet localhost 587"
echo "2. EHLO test.com"
echo "3. STARTTLS"
echo "4. AUTH PLAIN $AUTH_STRING"
echo

# Test with testsaslauthd if available
if command -v testsaslauthd &> /dev/null; then
    echo "Testing with testsaslauthd..."
    if echo "$PASSWORD" | testsaslauthd -u "$USERNAME" -r 100to1shot.com -s smtp; then
        echo "✅ testsaslauthd authentication successful"
    else
        echo "❌ testsaslauthd authentication failed"
    fi
fi
EOF
    
    chmod +x /tmp/test_auth.sh
    print_status "Run this script to test authentication: /tmp/test_auth.sh"
}

# Function to check master.cf configuration
check_master_cf() {
    print_status "Checking master.cf submission configuration..."
    
    echo "Submission port configuration:"
    grep -A 15 "^submission" /etc/postfix/master.cf || echo "No submission configuration found"
}

# Function to check if SASL is working
check_sasl_working() {
    print_status "Checking if SASL is working..."
    
    # Check if saslauthd is running
    if systemctl is-active --quiet saslauthd; then
        print_success "saslauthd is running"
    else
        print_warning "saslauthd is not running (this might be normal for sasldb)"
    fi
    
    # Check SASL mechanisms
    print_status "Available SASL mechanisms:"
    if command -v saslauthd &> /dev/null; then
        saslauthd -v 2>/dev/null || echo "Could not get saslauthd version"
    fi
}

# Function to fix common issues
fix_common_issues() {
    print_status "Fixing common SASL authentication issues..."
    
    # Fix SASL database permissions
    chown postfix:postfix /etc/sasldb2 2>/dev/null || true
    chmod 660 /etc/sasldb2 2>/dev/null || true
    
    # Ensure SASL configuration is correct
    cat > /etc/postfix/sasl/smtpd.conf << EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
EOF
    
    # Update Postfix configuration
    postconf -e "smtpd_sasl_auth_enable = yes"
    postconf -e "smtpd_sasl_type = cyrus"
    postconf -e "smtpd_sasl_path = smtpd"
    postconf -e "smtpd_sasl_security_options = noanonymous"
    postconf -e "smtpd_sasl_local_domain = 100to1shot.com"
    postconf -e "broken_sasl_auth_clients = yes"
    
    # Restart Postfix
    systemctl restart postfix
    
    print_success "Common issues fixed and Postfix restarted"
}

# Function to create a simple test
create_simple_test() {
    print_status "Creating simple authentication test..."
    
    cat > /root/simple_smtp_test.js << 'EOF'
// Simple SMTP Test
const nodemailer = require('nodemailer');

console.log('Testing SMTP authentication...');

const transporter = nodemailer.createTransporter({
    host: 'localhost', // Use localhost instead of domain
    port: 587,
    secure: false,
    auth: {
        user: 'noreply',
        pass: 'YOUR_PASSWORD_HERE' // Replace with actual password
    },
    tls: {
        rejectUnauthorized: false
    },
    debug: true,
    logger: true
});

// Test connection
transporter.verify((error, success) => {
    if (error) {
        console.log('❌ Connection failed:', error);
        console.log('Error details:', error.response);
    } else {
        console.log('✅ Connection successful!');
    }
});
EOF
    
    print_success "Simple test created at /root/simple_smtp_test.js"
    print_status "Edit the password and run: node /root/simple_smtp_test.js"
}

# Function to show debugging steps
show_debugging_steps() {
    print_status "Debugging Steps:"
    echo
    echo "1. Check if the user exists in SASL database:"
    echo "   sasldblistusers2 -f /etc/sasldb2"
    echo
    echo "2. Test authentication manually:"
    echo "   /tmp/test_auth.sh"
    echo
    echo "3. Check Postfix logs in real-time:"
    echo "   tail -f /var/log/mail.log"
    echo
    echo "4. Test with localhost instead of domain:"
    echo "   node /root/simple_smtp_test.js"
    echo
    echo "5. Check if submission port is working:"
    echo "   telnet localhost 587"
    echo
    echo "6. Verify SASL configuration:"
    echo "   postconf | grep sasl"
    echo
    echo "7. Check master.cf submission configuration:"
    echo "   grep -A 15 '^submission' /etc/postfix/master.cf"
}

# Main function
main() {
    check_root
    
    print_status "Starting SMTP authentication debugging..."
    echo
    
    check_sasl_database
    echo
    check_sasl_config
    echo
    check_postfix_sasl
    echo
    check_master_cf
    echo
    check_sasl_working
    echo
    fix_common_issues
    echo
    test_manual_auth
    echo
    create_simple_test
    echo
    show_debugging_steps
    
    print_success "Debugging complete! Follow the steps above to identify the issue."
}

# Run main function
main "$@"