#!/bin/bash

# =============================================================================
# Fix SMTP Authentication for Website Integration
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

# Function to fix SASL configuration
fix_sasl_config() {
    print_status "Fixing SASL configuration for website authentication..."
    
    # Install required packages
    apt-get update -y
    apt-get install -y sasl2-bin libsasl2-modules
    
    # Create SASL configuration directory
    mkdir -p /etc/postfix/sasl
    
    # Configure SASL for authentication
    cat > /etc/postfix/sasl/smtpd.conf << EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
EOF
    
    # Configure SASL for SMTP client authentication
    cat > /etc/postfix/sasl/smtp.conf << EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
EOF
    
    print_success "SASL configuration files created"
}

# Function to create SASL database
create_sasl_database() {
    print_status "Creating SASL database for mail users..."
    
    # Create SASL database
    saslpasswd2 -c -u 100to1shot.com noreply
    
    # Set proper permissions
    chown postfix:postfix /etc/sasldb2
    chmod 660 /etc/sasldb2
    
    print_success "SASL database created for noreply user"
}

# Function to update Postfix configuration
update_postfix_config() {
    print_status "Updating Postfix configuration for proper authentication..."
    
    # Update main.cf for SASL authentication
    postconf -e "smtpd_sasl_auth_enable = yes"
    postconf -e "smtpd_sasl_type = cyrus"
    postconf -e "smtpd_sasl_path = smtpd"
    postconf -e "smtpd_sasl_security_options = noanonymous"
    postconf -e "smtpd_sasl_local_domain = 100to1shot.com"
    postconf -e "broken_sasl_auth_clients = yes"
    
    # Configure client restrictions
    postconf -e "smtpd_client_restrictions = permit_mynetworks, permit_sasl_authenticated, reject"
    postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"
    postconf -e "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination"
    
    # Configure submission port properly
    postconf -e "smtpd_tls_security_level = may"
    postconf -e "smtpd_tls_cert_file = /etc/ssl/postfix/mail.crt"
    postconf -e "smtpd_tls_key_file = /etc/ssl/postfix/mail.key"
    
    print_success "Postfix configuration updated"
}

# Function to update master.cf for submission
update_master_cf() {
    print_status "Updating master.cf for submission port..."
    
    # Backup original master.cf
    cp /etc/postfix/master.cf /etc/postfix/master.cf.backup.$(date +%Y%m%d_%H%M%S)
    
    # Remove existing submission configuration
    sed -i '/^submission /d' /etc/postfix/master.cf
    
    # Add proper submission configuration
    cat >> /etc/postfix/master.cf << EOF

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
EOF
    
    print_success "Master.cf updated for submission port"
}

# Function to start SASL daemon
start_sasl_daemon() {
    print_status "Starting SASL authentication daemon..."
    
    # Configure saslauthd
    cat > /etc/default/saslauthd << EOF
START=yes
DESC="SASL Authentication Daemon"
NAME="saslauthd"
MECHANISMS="sasldb"
THREADS=5
OPTIONS="-c -m /var/spool/postfix/var/run/saslauthd"
EOF
    
    # Create directory for saslauthd
    mkdir -p /var/spool/postfix/var/run/saslauthd
    chown postfix:postfix /var/spool/postfix/var/run/saslauthd
    
    # Start and enable saslauthd
    systemctl enable saslauthd
    systemctl start saslauthd
    
    print_success "SASL authentication daemon started"
}

# Function to restart services
restart_services() {
    print_status "Restarting services..."
    
    # Restart Postfix
    systemctl restart postfix
    
    # Check if services are running
    if systemctl is-active --quiet postfix; then
        print_success "Postfix is running"
    else
        print_error "Postfix failed to start"
        systemctl status postfix
        exit 1
    fi
    
    if systemctl is-active --quiet saslauthd; then
        print_success "SASL daemon is running"
    else
        print_warning "SASL daemon is not running, but this may be normal for sasldb"
    fi
}

# Function to test authentication
test_authentication() {
    print_status "Testing SASL authentication..."
    
    # Test SASL database
    if sasldblistusers2 -f /etc/sasldb2; then
        print_success "SASL database is working"
    else
        print_error "SASL database test failed"
    fi
    
    # Test Postfix configuration
    if postfix check; then
        print_success "Postfix configuration is valid"
    else
        print_error "Postfix configuration has errors"
        postfix check
    fi
}

# Function to create test script
create_test_script() {
    print_status "Creating test script for website integration..."
    
    cat > /root/test_website_smtp.sh << 'EOF'
#!/bin/bash

# Test script for website SMTP integration
echo "Testing SMTP connection for website integration..."

# Test with telnet
echo "Testing SMTP connection on port 587..."
echo "EHLO test.com" | nc -w5 mail.100to1shot.com 587

echo ""
echo "Testing SMTP connection on port 25..."
echo "EHLO test.com" | nc -w5 mail.100to1shot.com 25

echo ""
echo "For your website, use these settings:"
echo "SMTP Server: mail.100to1shot.com"
echo "Port: 587"
echo "Username: noreply"
echo "Password: [the password you set for noreply user]"
echo "TLS: Yes"
echo "Authentication: Yes"
EOF
    
    chmod +x /root/test_website_smtp.sh
    print_success "Test script created at /root/test_website_smtp.sh"
}

# Function to show final instructions
show_final_instructions() {
    print_success "SMTP authentication fix completed!"
    echo
    print_status "For your website integration, use these SMTP settings:"
    echo
    echo "SMTP Server: mail.100to1shot.com"
    echo "Port: 587"
    echo "Username: noreply"
    echo "Password: [the password you set for the noreply user]"
    echo "TLS/SSL: Yes"
    echo "Authentication: Yes"
    echo
    print_status "Test the connection:"
    echo "sudo /root/test_website_smtp.sh"
    echo
    print_status "If you need to change the noreply user password:"
    echo "saslpasswd2 -u 100to1shot.com noreply"
    echo
    print_status "To add more mail users:"
    echo "saslpasswd2 -c -u 100to1shot.com username"
}

# Main function
main() {
    print_status "Starting SMTP authentication fix..."
    
    check_root
    fix_sasl_config
    create_sasl_database
    update_postfix_config
    update_master_cf
    start_sasl_daemon
    restart_services
    test_authentication
    create_test_script
    show_final_instructions
    
    print_success "SMTP authentication fix completed successfully!"
}

# Run main function
main "$@"