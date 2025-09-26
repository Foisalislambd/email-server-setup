#!/bin/bash

# =============================================================================
# Fix Postfix master.cf for Proper SMTP Authentication
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

# Function to backup master.cf
backup_master_cf() {
    print_status "Backing up current master.cf..."
    
    cp /etc/postfix/master.cf /etc/postfix/master.cf.backup.$(date +%Y%m%d_%H%M%S)
    print_success "Backup created"
}

# Function to show current master.cf
show_current_master_cf() {
    print_status "Current master.cf submission configuration:"
    echo
    
    grep -A 20 "^submission" /etc/postfix/master.cf || echo "No submission configuration found"
}

# Function to fix master.cf
fix_master_cf() {
    print_status "Fixing master.cf for proper SMTP authentication..."
    
    # Remove existing submission configuration
    sed -i '/^submission /,/^$/d' /etc/postfix/master.cf
    
    # Add proper submission configuration
    cat >> /etc/postfix/master.cf << 'EOF'

# Submission port (587) with proper SASL authentication
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=cyrus
  -o smtpd_sasl_path=smtpd
  -o smtpd_sasl_security_options=noanonymous
  -o smtpd_sasl_local_domain=100to1shot.com
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,permit_mynetworks,reject
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination
  -o smtpd_relay_restrictions=permit_sasl_authenticated,permit_mynetworks,defer_unauth_destination
  -o milter_macro_daemon_name=ORIGINATING
  -o smtpd_sasl_authenticated_header=yes
  -o smtpd_tls_cert_file=/etc/ssl/postfix/mail.crt
  -o smtpd_tls_key_file=/etc/ssl/postfix/mail.key

# SMTPS port (465) with proper SASL authentication
smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=cyrus
  -o smtpd_sasl_path=smtpd
  -o smtpd_sasl_security_options=noanonymous
  -o smtpd_sasl_local_domain=100to1shot.com
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,permit_mynetworks,reject
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination
  -o smtpd_relay_restrictions=permit_sasl_authenticated,permit_mynetworks,defer_unauth_destination
  -o milter_macro_daemon_name=ORIGINATING
  -o smtpd_sasl_authenticated_header=yes
  -o smtpd_tls_cert_file=/etc/ssl/postfix/mail.crt
  -o smtpd_tls_key_file=/etc/ssl/postfix/mail.key
EOF
    
    print_success "master.cf updated with proper submission configuration"
}

# Function to verify master.cf
verify_master_cf() {
    print_status "Verifying master.cf configuration..."
    
    if postfix check; then
        print_success "master.cf configuration is valid"
    else
        print_error "master.cf configuration has errors"
        postfix check
        return 1
    fi
}

# Function to restart Postfix
restart_postfix() {
    print_status "Restarting Postfix service..."
    
    systemctl restart postfix
    
    if systemctl is-active --quiet postfix; then
        print_success "Postfix restarted successfully"
    else
        print_error "Postfix failed to restart"
        systemctl status postfix
        return 1
    fi
}

# Function to test submission port
test_submission_port() {
    print_status "Testing submission port configuration..."
    
    # Test port 587
    if nc -z -w5 localhost 587; then
        print_success "Submission port 587 is accessible"
    else
        print_error "Submission port 587 is not accessible"
    fi
    
    # Test port 465
    if nc -z -w5 localhost 465; then
        print_success "SMTPS port 465 is accessible"
    else
        print_warning "SMTPS port 465 is not accessible (optional)"
    fi
}

# Function to show final configuration
show_final_config() {
    print_status "Final master.cf submission configuration:"
    echo
    
    grep -A 25 "^submission" /etc/postfix/master.cf
    echo
    grep -A 25 "^smtps" /etc/postfix/master.cf
}

# Function to create test script
create_test_script() {
    print_status "Creating test script for website integration..."
    
    cat > /root/test_website_auth.js << 'EOF'
// Test SMTP Authentication After master.cf Fix
const nodemailer = require('nodemailer');

console.log('Testing SMTP authentication after master.cf fix...');

const transporter = nodemailer.createTransporter({
    host: 'localhost',  // Use localhost for testing
    port: 587,
    secure: false,
    auth: {
        user: 'noreply',
        pass: 'YOUR_PASSWORD_HERE'  // Replace with actual password
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
        
        // Send test email
        const mailOptions = {
            from: 'noreply@100to1shot.com',
            to: 'ifoisal19@gmail.com',
            subject: 'SMTP Authentication Test - Fixed',
            text: 'This is a test email after fixing master.cf configuration.',
            html: '<p>This is a test email after fixing master.cf configuration.</p>'
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
    
    chmod +x /root/test_website_auth.js
    print_success "Test script created at /root/test_website_auth.js"
}

# Function to show instructions
show_instructions() {
    print_success "master.cf fix completed!"
    echo
    print_status "Next steps:"
    echo
    echo "1. Test the configuration:"
    echo "   node /root/test_website_auth.js"
    echo
    echo "2. Update your website with these settings:"
    echo "   host: 'localhost' (or 'mail.100to1shot.com')"
    echo "   port: 587"
    echo "   auth: { user: 'noreply', pass: 'your_password' }"
    echo
    echo "3. Check mail logs:"
    echo "   tail -f /var/log/mail.log"
    echo
    echo "4. If still having issues, check SASL database:"
    echo "   sasldblistusers2 -f /etc/sasldb2"
    echo
    print_status "The master.cf file has been updated with proper SASL authentication settings."
}

# Main function
main() {
    print_status "Starting master.cf fix for SMTP authentication..."
    
    check_root
    backup_master_cf
    show_current_master_cf
    fix_master_cf
    verify_master_cf
    restart_postfix
    test_submission_port
    show_final_config
    create_test_script
    show_instructions
    
    print_success "master.cf fix completed successfully!"
}

# Run main function
main "$@"