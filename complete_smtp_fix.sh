#!/bin/bash

# =============================================================================
# Complete SMTP Authentication Fix
# Run this on your server to complete the setup
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

# Function to stop saslauthd and use sasldb directly
configure_sasl_direct() {
    print_status "Configuring SASL to use sasldb directly (no daemon needed)..."
    
    # Stop saslauthd service
    systemctl stop saslauthd 2>/dev/null || true
    systemctl disable saslauthd 2>/dev/null || true
    
    # Update SASL configuration to use sasldb directly
    cat > /etc/postfix/sasl/smtpd.conf << EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
EOF
    
    # Update SMTP configuration
    cat > /etc/postfix/sasl/smtp.conf << EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
EOF
    
    print_success "SASL configured to use sasldb directly"
}

# Function to verify SASL database
verify_sasl_database() {
    print_status "Verifying SASL database..."
    
    if [[ -f /etc/sasldb2 ]]; then
        print_success "SASL database exists"
        
        # List users in database
        print_status "Users in SASL database:"
        sasldblistusers2 -f /etc/sasldb2 2>/dev/null || print_warning "Could not list users"
    else
        print_error "SASL database not found"
        print_status "Creating SASL database..."
        saslpasswd2 -c -u 100to1shot.com noreply
    fi
    
    # Set proper permissions
    chown postfix:postfix /etc/sasldb2 2>/dev/null || true
    chmod 660 /etc/sasldb2 2>/dev/null || true
}

# Function to restart Postfix
restart_postfix() {
    print_status "Restarting Postfix service..."
    
    # Restart Postfix
    systemctl restart postfix
    
    # Check if Postfix is running
    if systemctl is-active --quiet postfix; then
        print_success "Postfix is running"
    else
        print_error "Postfix failed to start"
        systemctl status postfix
        exit 1
    fi
}

# Function to test Postfix configuration
test_postfix_config() {
    print_status "Testing Postfix configuration..."
    
    if postfix check; then
        print_success "Postfix configuration is valid"
    else
        print_error "Postfix configuration has errors"
        postfix check
        exit 1
    fi
}

# Function to test SMTP connection
test_smtp_connection() {
    print_status "Testing SMTP connection..."
    
    # Test port 587
    if nc -z -w5 localhost 587; then
        print_success "SMTP submission port 587 is accessible"
    else
        print_error "SMTP submission port 587 is not accessible"
    fi
    
    # Test port 25
    if nc -z -w5 localhost 25; then
        print_success "SMTP port 25 is accessible"
    else
        print_error "SMTP port 25 is not accessible"
    fi
}

# Function to create test email script
create_test_script() {
    print_status "Creating test email script..."
    
    cat > /root/send_test_email.sh << 'EOF'
#!/bin/bash

echo "Testing SMTP authentication..."

# Test email
echo "This is a test email from your fixed SMTP server." | \
    mail -s "SMTP Authentication Test" -a "From: noreply@100to1shot.com" ifoisal19@gmail.com

echo "Test email sent to ifoisal19@gmail.com"
echo "Check your inbox (and spam folder) for the test email"
EOF
    
    chmod +x /root/send_test_email.sh
    print_success "Test email script created at /root/send_test_email.sh"
}

# Function to show final configuration
show_final_config() {
    print_success "SMTP authentication fix completed!"
    echo
    print_status "Your website SMTP configuration:"
    echo
    echo "SMTP Server: mail.100to1shot.com"
    echo "Port: 587"
    echo "Username: noreply"
    echo "Password: [the password you set during setup]"
    echo "TLS/SSL: Yes"
    echo "Authentication: Yes"
    echo
    print_status "Test the setup:"
    echo "sudo /root/send_test_email.sh"
    echo
    print_status "For Node.js nodemailer:"
    echo "const transporter = nodemailer.createTransporter({"
    echo "  host: 'mail.100to1shot.com',"
    echo "  port: 587,"
    echo "  secure: false,"
    echo "  auth: {"
    echo "    user: 'noreply',"
    echo "    pass: 'your_password_here'"
    echo "  },"
    echo "  tls: { rejectUnauthorized: false }"
    echo "});"
    echo
    print_status "If you need to change the password:"
    echo "saslpasswd2 -u 100to1shot.com noreply"
    echo
    print_status "To add more users:"
    echo "saslpasswd2 -c -u 100to1shot.com username"
}

# Main function
main() {
    print_status "Completing SMTP authentication fix..."
    
    check_root
    configure_sasl_direct
    verify_sasl_database
    restart_postfix
    test_postfix_config
    test_smtp_connection
    create_test_script
    show_final_config
    
    print_success "SMTP authentication fix completed successfully!"
}

# Run main function
main "$@"