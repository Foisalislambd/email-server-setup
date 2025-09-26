#!/bin/bash

# =============================================================================
# Postfix Mail System Auto-Setup Script
# For subdomain: mail.100to1shot.com
# Purpose: Configure SMTP server for website email sending
# =============================================================================

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
DOMAIN="100to1shot.com"
SUBDOMAIN="mail.100to1shot.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/postfix_setup.log"

# Function to print colored output
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

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        print_error "Cannot detect OS version"
        exit 1
    fi
    
    print_status "Detected OS: $OS $VER"
}

# Function to update system packages
update_system() {
    print_status "Updating system packages..."
    log_message "Updating system packages"
    
    if command -v apt-get &> /dev/null; then
        apt-get update -y
        apt-get upgrade -y
    elif command -v yum &> /dev/null; then
        yum update -y
    elif command -v dnf &> /dev/null; then
        dnf update -y
    else
        print_error "Unsupported package manager"
        exit 1
    fi
    
    print_success "System packages updated"
}

# Function to install required packages
install_packages() {
    print_status "Installing required packages..."
    log_message "Installing Postfix and related packages"
    
    local packages=(
        "postfix"
        "mailutils"
        "libsasl2-modules"
        "libsasl2-dev"
        "ca-certificates"
        "openssl"
        "curl"
        "wget"
        "nano"
        "ufw"
    )
    
    if command -v apt-get &> /dev/null; then
        for package in "${packages[@]}"; do
            if ! dpkg -l | grep -q "^ii  $package "; then
                print_status "Installing $package..."
                apt-get install -y "$package"
            else
                print_status "$package is already installed"
            fi
        done
    elif command -v yum &> /dev/null; then
        for package in "${packages[@]}"; do
            if ! rpm -q "$package" &> /dev/null; then
                print_status "Installing $package..."
                yum install -y "$package"
            else
                print_status "$package is already installed"
            fi
        done
    elif command -v dnf &> /dev/null; then
        for package in "${packages[@]}"; do
            if ! rpm -q "$package" &> /dev/null; then
                print_status "Installing $package..."
                dnf install -y "$package"
            else
                print_status "$package is already installed"
            fi
        done
    fi
    
    print_success "All required packages installed"
}

# Function to configure firewall
configure_firewall() {
    print_status "Configuring firewall rules..."
    log_message "Configuring firewall for SMTP ports"
    
    if command -v ufw &> /dev/null; then
        ufw --force enable
        ufw allow 25/tcp comment "SMTP"
        ufw allow 587/tcp comment "SMTP Submission"
        ufw allow 465/tcp comment "SMTPS"
        ufw allow 993/tcp comment "IMAPS"
        ufw allow 995/tcp comment "POP3S"
        print_success "UFW firewall configured"
    elif command -v firewall-cmd &> /dev/null; then
        systemctl enable firewalld
        systemctl start firewalld
        firewall-cmd --permanent --add-service=smtp
        firewall-cmd --permanent --add-service=smtps
        firewall-cmd --permanent --add-service=imaps
        firewall-cmd --permanent --add-service=pop3s
        firewall-cmd --reload
        print_success "Firewalld configured"
    else
        print_warning "No firewall detected, please configure manually"
    fi
}

# Function to set system hostname
set_hostname() {
    print_status "Setting system hostname to $SUBDOMAIN..."
    log_message "Setting hostname to $SUBDOMAIN"
    
    hostnamectl set-hostname "$SUBDOMAIN"
    echo "127.0.0.1 $SUBDOMAIN localhost" > /etc/hosts
    echo "::1 $SUBDOMAIN localhost" >> /etc/hosts
    
    print_success "Hostname set to $SUBDOMAIN"
}

# Function to configure Postfix main settings
configure_postfix_main() {
    print_status "Configuring Postfix main settings..."
    log_message "Configuring Postfix main.cf"
    
    # Backup original configuration
    cp /etc/postfix/main.cf /etc/postfix/main.cf.backup.$(date +%Y%m%d_%H%M%S)
    
    # Configure basic Postfix settings
    postconf -e "myhostname = $SUBDOMAIN"
    postconf -e "mydomain = $DOMAIN"
    postconf -e "myorigin = \$mydomain"
    postconf -e "inet_interfaces = all"
    postconf -e "inet_protocols = ipv4"
    postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost"
    
    # Network settings
    postconf -e "mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128"
    postconf -e "relayhost ="
    
    # Security settings
    postconf -e "smtpd_banner = \$myhostname ESMTP"
    postconf -e "disable_vrfy_command = yes"
    postconf -e "smtpd_helo_required = yes"
    postconf -e "smtpd_helo_restrictions = permit_mynetworks, reject_invalid_helo_hostname, reject_non_fqdn_helo_hostname"
    
    # TLS settings
    postconf -e "smtpd_use_tls = yes"
    postconf -e "smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem"
    postconf -e "smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key"
    postconf -e "smtpd_tls_security_level = may"
    postconf -e "smtpd_tls_protocols = !SSLv2, !SSLv3"
    postconf -e "smtpd_tls_ciphers = high"
    postconf -e "smtpd_tls_exclude_ciphers = aNULL, MD5, DES"
    
    # SMTP client settings
    postconf -e "smtp_use_tls = yes"
    postconf -e "smtp_tls_security_level = may"
    postconf -e "smtp_tls_protocols = !SSLv2, !SSLv3"
    postconf -e "smtp_tls_ciphers = high"
    
    # Message size limits
    postconf -e "message_size_limit = 10485760"
    postconf -e "mailbox_size_limit = 0"
    
    # Logging
    postconf -e "maillog_file = /var/log/mail.log"
    
    print_success "Postfix main configuration completed"
}

# Function to configure SASL authentication for local users
configure_sasl() {
    print_status "Configuring SASL authentication for local users..."
    log_message "Setting up SASL authentication for standalone mail server"
    
    # Install SASL packages
    if command -v apt-get &> /dev/null; then
        apt-get install -y sasl2-bin libsasl2-modules
    fi
    
    # Configure SASL for local authentication
    cat > /etc/postfix/sasl/smtpd.conf << EOF
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
EOF
    
    # Configure Postfix for SASL (for local user authentication)
    postconf -e "smtpd_sasl_auth_enable = yes"
    postconf -e "smtpd_sasl_type = cyrus"
    postconf -e "smtpd_sasl_path = smtpd"
    postconf -e "smtpd_sasl_security_options = noanonymous"
    postconf -e "smtpd_sasl_local_domain = $DOMAIN"
    postconf -e "broken_sasl_auth_clients = yes"
    
    print_success "SASL authentication configured for local users"
}

# Function to configure master.cf for submission port
configure_master() {
    print_status "Configuring Postfix master.cf for submission port..."
    log_message "Configuring master.cf for port 587"
    
    # Backup original master.cf
    cp /etc/postfix/master.cf /etc/postfix/master.cf.backup.$(date +%Y%m%d_%H%M%S)
    
    # Add submission service configuration for standalone mail server
    if ! grep -q "^submission" /etc/postfix/master.cf; then
        cat >> /etc/postfix/master.cf << EOF

# Submission port (587) for standalone mail server
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,permit_mynetworks,reject
  -o milter_macro_daemon_name=ORIGINATING
  -o smtpd_sasl_type=cyrus
  -o smtpd_sasl_path=smtpd
  -o smtpd_sasl_security_options=noanonymous
  -o smtpd_sasl_local_domain=$DOMAIN
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination
  -o smtpd_relay_restrictions=permit_sasl_authenticated,permit_mynetworks,defer_unauth_destination
  -o smtpd_sasl_authenticated_header=yes
EOF
    fi
    
    print_success "Master.cf configured for submission port"
}

# Function to create SSL certificates
create_ssl_certificates() {
    print_status "Creating SSL certificates..."
    log_message "Generating SSL certificates for TLS"
    
    # Create directory for certificates
    mkdir -p /etc/ssl/postfix
    
    # Generate self-signed certificate
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/postfix/mail.key \
        -out /etc/ssl/postfix/mail.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$SUBDOMAIN"
    
    # Set permissions
    chmod 600 /etc/ssl/postfix/mail.key
    chmod 644 /etc/ssl/postfix/mail.crt
    chown root:root /etc/ssl/postfix/mail.*
    
    # Update Postfix to use new certificates
    postconf -e "smtpd_tls_cert_file = /etc/ssl/postfix/mail.crt"
    postconf -e "smtpd_tls_key_file = /etc/ssl/postfix/mail.key"
    
    print_success "SSL certificates created"
}

# Function to configure mail aliases
configure_aliases() {
    print_status "Configuring mail aliases..."
    log_message "Setting up mail aliases"
    
    # Create aliases file
    cat > /etc/postfix/aliases << EOF
# Mail aliases for $DOMAIN
postmaster: root
admin: root
webmaster: root
noreply: /dev/null
EOF
    
    # Update aliases database
    newaliases
    
    print_success "Mail aliases configured"
}

# Function to create virtual domains configuration
configure_virtual_domains() {
    print_status "Configuring virtual domains..."
    log_message "Setting up virtual domains configuration"
    
    # Create virtual domains file
    cat > /etc/postfix/virtual_domains << EOF
# Virtual domains for $DOMAIN
$DOMAIN OK
$SUBDOMAIN OK
EOF
    
    # Create virtual aliases file
    cat > /etc/postfix/virtual_aliases << EOF
# Virtual aliases for $DOMAIN
admin@$DOMAIN root
webmaster@$DOMAIN root
noreply@$DOMAIN /dev/null
EOF
    
    # Update Postfix configuration
    postconf -e "virtual_alias_domains = $DOMAIN"
    postconf -e "virtual_alias_maps = hash:/etc/postfix/virtual_aliases"
    
    # Create hash databases
    postmap /etc/postfix/virtual_domains
    postmap /etc/postfix/virtual_aliases
    
    print_success "Virtual domains configured"
}

# Function to start and enable services
start_services() {
    print_status "Starting and enabling Postfix service..."
    log_message "Starting Postfix service"
    
    # Start and enable Postfix
    systemctl enable postfix
    systemctl restart postfix
    
    # Check service status
    if systemctl is-active --quiet postfix; then
        print_success "Postfix service is running"
    else
        print_error "Failed to start Postfix service"
        systemctl status postfix
        exit 1
    fi
}

# Function to test mail configuration
test_mail_configuration() {
    print_status "Testing mail configuration..."
    log_message "Testing mail configuration"
    
    # Test Postfix configuration
    if postfix check; then
        print_success "Postfix configuration is valid"
    else
        print_error "Postfix configuration has errors"
        postfix check
        exit 1
    fi
    
    # Test mail queue
    mailq
    
    # Test sending email
    print_status "Sending test email..."
    echo "This is a test email from $SUBDOMAIN mail server setup." | \
        mail -s "Test Email from $SUBDOMAIN" -a "From: noreply@$DOMAIN" root
    
    print_success "Test email sent to root"
}

# Function to create configuration summary
create_summary() {
    print_status "Creating configuration summary..."
    log_message "Creating setup summary"
    
    local summary_file="/root/postfix_setup_summary.txt"
    
    cat > "$summary_file" << EOF
=============================================================================
Postfix Mail System Setup Summary
Generated: $(date)
Domain: $DOMAIN
Subdomain: $SUBDOMAIN
=============================================================================

CONFIGURATION DETAILS:
- Hostname: $SUBDOMAIN
- Domain: $DOMAIN
- SMTP Port: 25
- Submission Port: 587
- SMTPS Port: 465

FILES CONFIGURED:
- /etc/postfix/main.cf (main configuration)
- /etc/postfix/master.cf (service configuration)
- /etc/postfix/sasl_passwd (SMTP relay credentials)
- /etc/postfix/aliases (mail aliases)
- /etc/postfix/virtual_domains (virtual domains)
- /etc/postfix/virtual_aliases (virtual aliases)
- /etc/ssl/postfix/mail.crt (SSL certificate)
- /etc/ssl/postfix/mail.key (SSL private key)

SERVICES:
- Postfix: $(systemctl is-active postfix)
- Firewall: $(systemctl is-active ufw 2>/dev/null || systemctl is-active firewalld 2>/dev/null || echo "Not configured")

NEXT STEPS:
1. Configure DNS records (A, PTR, SPF, DKIM, DMARC)
2. Create local user accounts for email authentication
3. Test email sending from your website
4. Monitor mail logs for delivery status

DNS RECORDS REQUIRED:
- A record: mail.100to1shot.com -> YOUR_SERVER_IP
- PTR record: YOUR_SERVER_IP -> mail.100to1shot.com
- SPF record: v=spf1 a mx include:mail.100to1shot.com ~all
- DKIM record: (configure with your SMTP provider)
- DMARC record: v=DMARC1; p=quarantine; rua=mailto:admin@100to1shot.com

WEBSITE INTEGRATION:
For your website to send emails, use these SMTP settings:
- SMTP Server: mail.100to1shot.com
- Port: 587 (with TLS) or 465 (with SSL)
- Authentication: Required (use local system user credentials)
- From Address: noreply@100to1shot.com
- Username: local system username
- Password: local system user password

LOGS:
- Mail logs: /var/log/mail.log
- Setup logs: $LOG_FILE

=============================================================================
EOF
    
    print_success "Configuration summary saved to $summary_file"
    cat "$summary_file"
}

# Function to display final instructions
display_final_instructions() {
    print_success "Postfix mail system setup completed!"
    echo
    print_status "IMPORTANT: Complete these steps to finish the setup:"
    echo
    echo "1. Create local user accounts for email authentication:"
    echo "   useradd -m -s /bin/bash mailuser"
    echo "   passwd mailuser"
    echo
    echo "2. Configure DNS records for $SUBDOMAIN:"
    echo "   - A record: mail.100to1shot.com -> YOUR_SERVER_IP"
    echo "   - PTR record: YOUR_SERVER_IP -> mail.100to1shot.com"
    echo "   - SPF, DKIM, DMARC records"
    echo
    echo "3. Test email sending from your website using local user credentials"
    echo
    print_status "Configuration summary saved to /root/postfix_setup_summary.txt"
    print_status "Setup logs saved to $LOG_FILE"
}

# Main execution function
main() {
    print_status "Starting Postfix mail system setup for $SUBDOMAIN"
    log_message "Starting Postfix setup script"
    
    check_root
    detect_os
    update_system
    install_packages
    configure_firewall
    set_hostname
    configure_postfix_main
    configure_sasl
    configure_master
    create_ssl_certificates
    configure_aliases
    configure_virtual_domains
    start_services
    test_mail_configuration
    create_summary
    display_final_instructions
    
    log_message "Postfix setup completed successfully"
    print_success "Setup completed! Check the summary file for next steps."
}

# Run main function
main "$@"