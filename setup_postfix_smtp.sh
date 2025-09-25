#!/bin/bash

# Postfix SMTP Setup Script for Client Website Email Functionality
# This script configures Postfix to send verification codes and password reset emails

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
DOMAIN_NAME=""
EMAIL_USER=""
EMAIL_PASSWORD=""
SMTP_PORT="587"
HOSTNAME=""

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

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to get user input
get_config() {
    print_status "Postfix SMTP Configuration Setup"
    echo "======================================"
    
    read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
    read -p "Enter email address for sending emails (e.g., noreply@example.com): " EMAIL_USER
    read -s -p "Enter email password: " EMAIL_PASSWORD
    echo
    read -p "Enter SMTP port (default 587): " SMTP_PORT
    SMTP_PORT=${SMTP_PORT:-587}
    read -p "Enter server hostname (default: $(hostname)): " HOSTNAME
    HOSTNAME=${HOSTNAME:-$(hostname)}
}

# Function to install required packages
install_packages() {
    print_status "Installing required packages..."
    
    # Update package list
    apt-get update -y
    
    # Install Postfix and related packages
    apt-get install -y postfix mailutils libsasl2-modules libsasl2-2 ca-certificates
    
    print_success "Packages installed successfully"
}

# Function to configure Postfix
configure_postfix() {
    print_status "Configuring Postfix..."
    
    # Backup original configuration
    cp /etc/postfix/main.cf /etc/postfix/main.cf.backup
    
    # Configure main.cf
    cat > /etc/postfix/main.cf << EOF
# Basic configuration
myhostname = $HOSTNAME
mydomain = $DOMAIN_NAME
myorigin = \$mydomain
inet_interfaces = loopback-only
inet_protocols = ipv4
mydestination = \$myhostname, localhost.\$mydomain, localhost

# SMTP configuration for sending emails
relayhost = [smtp.gmail.com]:$SMTP_PORT
smtp_use_tls = yes
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt

# Security settings
smtpd_banner = \$myhostname ESMTP
disable_vrfy_command = yes
smtpd_helo_required = yes
smtpd_helo_restrictions = permit_mynetworks,reject_invalid_helo_hostname,permit
smtpd_recipient_restrictions = permit_mynetworks,reject_unauth_destination,permit

# Message size limit (10MB)
message_size_limit = 10485760

# Queue settings
maximal_queue_lifetime = 7d
bounce_queue_lifetime = 7d
EOF

    print_success "Postfix main configuration updated"
}

# Function to configure SASL authentication
configure_sasl() {
    print_status "Configuring SASL authentication..."
    
    # Create SASL password file
    cat > /etc/postfix/sasl_passwd << EOF
[smtp.gmail.com]:$SMTP_PORT $EMAIL_USER:$EMAIL_PASSWORD
EOF

    # Set proper permissions
    chmod 600 /etc/postfix/sasl_passwd
    
    # Create hash database
    postmap /etc/postfix/sasl_passwd
    
    print_success "SASL authentication configured"
}

# Function to configure for Gmail (most common use case)
configure_gmail() {
    print_status "Configuring for Gmail SMTP..."
    
    # Update main.cf for Gmail
    cat >> /etc/postfix/main.cf << EOF

# Gmail specific configuration
smtp_sasl_mechanism_filter = plain, login
smtp_tls_security_level = encrypt
smtp_tls_mandatory_protocols = !SSLv2, !SSLv3
smtp_tls_protocols = !SSLv2, !SSLv3
EOF

    print_success "Gmail configuration added"
}

# Function to configure anti-spam measures
configure_anti_spam() {
    print_status "Configuring anti-spam measures..."
    
    # Install additional packages for DKIM
    apt-get install -y opendkim opendkim-tools
    
    # Configure OpenDKIM
    cat > /etc/opendkim.conf << EOF
# OpenDKIM configuration
Domain                  *
Selector                mail
KeyFile                 /etc/opendkim/keys/mail.private
Canonicalization        relaxed/simple
Mode                    sv
SubDomains              no
AutoRestart             yes
AutoRestartRate         10/1M
Background              yes
DNSTimeout              5
SignatureAlgorithm      rsa-sha256
EOF

    # Create DKIM directory and generate keys
    mkdir -p /etc/opendkim/keys
    cd /etc/opendkim/keys
    
    # Generate DKIM key
    opendkim-genkey -s mail -d $DOMAIN_NAME
    chown opendkim:opendkim mail.private
    chmod 600 mail.private
    
    # Update Postfix configuration for DKIM
    cat >> /etc/postfix/main.cf << EOF

# DKIM configuration
milter_protocol = 2
milter_default_action = accept
smtpd_milters = inet:localhost:8891
non_smtpd_milters = inet:localhost:8891
EOF

    # Configure OpenDKIM socket
    echo "Socket inet:8891@localhost" >> /etc/opendkim.conf
    
    # Start and enable OpenDKIM
    systemctl start opendkim
    systemctl enable opendkim
    
    # Get DKIM public key for DNS
    DKIM_PUBLIC_KEY=$(cat /etc/opendkim/keys/mail.txt | grep -o '"[^"]*"' | tr -d '"')
    
    print_success "Anti-spam measures configured"
    print_warning "IMPORTANT: Add these DNS records to prevent spam:"
    echo ""
    echo "1. SPF Record (TXT):"
    echo "   v=spf1 include:_spf.google.com ~all"
    echo ""
    echo "2. DKIM Record (TXT):"
    echo "   mail._domainkey.$DOMAIN_NAME"
    echo "   $DKIM_PUBLIC_KEY"
    echo ""
    echo "3. DMARC Record (TXT):"
    echo "   _dmarc.$DOMAIN_NAME"
    echo "   v=DMARC1; p=quarantine; rua=mailto:dmarc@$DOMAIN_NAME"
    echo ""
    echo "4. Reverse DNS (PTR):"
    echo "   Set up reverse DNS for your server IP to point to $HOSTNAME"
    echo ""
}


# Function to start and enable Postfix
start_postfix() {
    print_status "Starting Postfix service..."
    
    # Reload configuration
    postfix reload
    
    # Start and enable Postfix
    systemctl start postfix
    systemctl enable postfix
    
    print_success "Postfix service started and enabled"
}

# Function to test email functionality
test_email() {
    print_status "Testing email functionality..."
    
    # Create a test email
    echo "This is a test email from Postfix SMTP setup." | mail -s "Postfix SMTP Test" $EMAIL_USER
    
    print_success "Test email sent to $EMAIL_USER"
    print_warning "Check your email inbox to verify the setup is working"
}

# Function to create usage documentation
create_documentation() {
    print_status "Creating usage documentation..."
    
    cat > /root/postfix_setup_guide.md << EOF
# Postfix SMTP Email Setup

## Overview
This setup configures Postfix to send verification codes and password reset emails for your client website.

## Configuration Files
- Main config: /etc/postfix/main.cf
- SASL auth: /etc/postfix/sasl_passwd

## Usage Examples

### Test Basic Email
\`\`\`bash
echo "Test message" | mail -s "Test Subject" recipient@example.com
\`\`\`


## Security Notes
- Email passwords are stored in /etc/postfix/sasl_passwd (chmod 600)
- Postfix is configured to only listen on loopback interface
- SASL authentication is required for sending emails
- TLS encryption is enabled for secure transmission
- DKIM signing is configured to prevent spam
- OpenDKIM service is running for email authentication

## Anti-Spam Configuration
The script configures DKIM signing to prevent emails from going to spam. After running the script, you need to add these DNS records:

### 1. SPF Record (TXT)
\`\`\`
v=spf1 include:_spf.google.com ~all
\`\`\`

### 2. DKIM Record (TXT)
\`\`\`
mail._domainkey.yourdomain.com
[Generated DKIM public key will be shown after script completion]
\`\`\`

### 3. DMARC Record (TXT)
\`\`\`
_dmarc.yourdomain.com
v=DMARC1; p=quarantine; rua=mailto:dmarc@yourdomain.com
\`\`\`

### 4. Reverse DNS (PTR)
Set up reverse DNS for your server IP to point to your hostname.

## Troubleshooting
- Check Postfix logs: \`tail -f /var/log/mail.log\`
- Test configuration: \`postfix check\`
- Reload configuration: \`postfix reload\`
- Check service status: \`systemctl status postfix\`

## Important Security Considerations
1. Use strong, unique passwords for your email account
2. Enable 2FA on your email account if available
3. Regularly rotate email passwords
4. Monitor email logs for suspicious activity
5. Consider using a dedicated email service for production
EOF

    print_success "Documentation created at /root/postfix_setup_guide.md"
}

# Main execution
main() {
    print_status "Starting Postfix SMTP Setup..."
    
    check_root
    get_config
    install_packages
    configure_postfix
    configure_sasl
    configure_gmail
    configure_anti_spam
    start_postfix
    test_email
    create_documentation
    
    print_success "Postfix SMTP setup completed successfully!"
    print_status "Next steps:"
    echo "1. Check your email for the test message"
    echo "2. Add the DNS records shown above to prevent spam"
    echo "3. Review the documentation at /root/postfix_setup_guide.md"
    echo "4. Your SMTP server is ready to send emails"
    
    print_warning "Important: Make sure to use strong passwords and enable 2FA on your email account!"
}

# Run main function
main "$@"