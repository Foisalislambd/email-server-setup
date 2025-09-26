#!/bin/bash

# =============================================================================
# Update master.cf for SMTP Authentication Fix
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
    print_status "Creating backup of master.cf..."
    cp /etc/postfix/master.cf /etc/postfix/master.cf.backup.$(date +%Y%m%d_%H%M%S)
    print_success "Backup created: /etc/postfix/master.cf.backup.$(date +%Y%m%d_%H%M%S)"
}

# Function to update master.cf
update_master_cf() {
    print_status "Updating master.cf with proper SASL authentication..."
    
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
EOF
    
    print_success "master.cf updated with proper submission configuration"
}

# Function to verify configuration
verify_config() {
    print_status "Verifying Postfix configuration..."
    
    if postfix check; then
        print_success "Postfix configuration is valid"
    else
        print_error "Postfix configuration has errors"
        postfix check
        exit 1
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
        exit 1
    fi
}

# Function to test submission port
test_submission() {
    print_status "Testing submission port..."
    
    if nc -z -w5 localhost 587; then
        print_success "Submission port 587 is working"
    else
        print_error "Submission port 587 is not accessible"
    fi
}

# Function to show final status
show_status() {
    print_success "master.cf update completed successfully!"
    echo
    print_status "Your website SMTP settings:"
    echo "Host: localhost (or mail.100to1shot.com)"
    echo "Port: 587"
    echo "Username: noreply"
    echo "Password: [your password]"
    echo "TLS: Yes"
    echo
    print_status "Test your website now - the authentication should work!"
}

# Main function
main() {
    print_status "Starting master.cf update for SMTP authentication fix..."
    
    check_root
    backup_master_cf
    update_master_cf
    verify_config
    restart_postfix
    test_submission
    show_status
    
    print_success "All done! Your SMTP authentication should now work."
}

# Run main function
main "$@"