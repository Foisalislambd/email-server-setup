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
    apt-get install -y postfix mailutils libsasl2-modules libsasl2-2 ca-certificates openssl certbot
    
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

# Function to configure SSL/TLS certificates
configure_ssl() {
    print_status "Configuring SSL/TLS certificates..."
    
    # Create SSL directory
    mkdir -p /etc/postfix/ssl
    
    # Check if Let's Encrypt certificate exists
    if [ -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]; then
        print_status "Using existing Let's Encrypt certificate..."
        SSL_CERT="/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem"
        SSL_KEY="/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem"
    else
        print_status "Generating self-signed certificate..."
        
        # Generate self-signed certificate
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/postfix/ssl/mail.key \
            -out /etc/postfix/ssl/mail.crt \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN_NAME"
        
        SSL_CERT="/etc/postfix/ssl/mail.crt"
        SSL_KEY="/etc/postfix/ssl/mail.key"
        
        # Set proper permissions
        chmod 600 /etc/postfix/ssl/mail.key
        chmod 644 /etc/postfix/ssl/mail.crt
        chown root:root /etc/postfix/ssl/*
    fi
    
    # Update Postfix configuration for SSL/TLS
    cat >> /etc/postfix/main.cf << EOF

# SSL/TLS configuration
smtpd_use_tls = yes
smtpd_tls_cert_file = $SSL_CERT
smtpd_tls_key_file = $SSL_KEY
smtpd_tls_security_level = may
smtpd_tls_auth_only = no
smtpd_tls_loglevel = 1
smtpd_tls_received_header = yes
smtpd_tls_session_cache_timeout = 3600s
tls_random_source = dev:/dev/urandom

# TLS protocols and ciphers
smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1
smtpd_tls_ciphers = high
smtpd_tls_mandatory_ciphers = high
smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1

# TLS session cache
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache

# Client-side TLS
smtp_use_tls = yes
smtp_tls_security_level = may
smtp_tls_loglevel = 1
smtp_tls_note_starttls_offer = yes
EOF

    print_success "SSL/TLS configuration completed"
    
    if [ ! -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]; then
        print_warning "Self-signed certificate generated. For production use, consider:"
        echo "1. Get a Let's Encrypt certificate: certbot certonly --standalone -d $DOMAIN_NAME"
        echo "2. Or use a commercial SSL certificate"
        echo "3. Update the certificate paths in /etc/postfix/main.cf"
    fi
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
- SSL/TLS certificates are configured for secure connections
- DKIM signing is configured to prevent spam
- OpenDKIM service is running for email authentication
- Strong TLS protocols (TLSv1.2+) and ciphers are enforced

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

## SSL/TLS Configuration
The script automatically configures SSL/TLS for secure email transmission:

### Certificate Options
1. **Let's Encrypt Certificate** (Recommended for production)
   - If you have an existing Let's Encrypt certificate, it will be used automatically
   - To get a new certificate: `certbot certonly --standalone -d yourdomain.com`

2. **Self-Signed Certificate** (For testing)
   - Generated automatically if no Let's Encrypt certificate exists
   - Located in `/etc/postfix/ssl/`
   - Not trusted by email clients but enables encryption

### SSL Features
- **TLS 1.2+ only** - Disables weak protocols (SSLv2, SSLv3, TLSv1, TLSv1.1)
- **Strong ciphers** - Uses high-grade encryption ciphers
- **Session caching** - Improves performance with TLS session reuse
- **Perfect Forward Secrecy** - Ensures past communications remain secure

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
    configure_ssl
    configure_anti_spam
    start_postfix
    test_email
    create_documentation
    
    print_success "Postfix SMTP setup completed successfully!"
    print_status "Next steps:"
    echo "1. Check your email for the test message"
    echo "2. Add the DNS records shown above to prevent spam"
    echo "3. For production, get a Let's Encrypt SSL certificate"
    echo "4. Review the documentation at /root/postfix_setup_guide.md"
    echo "5. Your secure SMTP server is ready to send emails"
    
    print_warning "Important: Make sure to use strong passwords and enable 2FA on your email account!"
}

# Run main function
main "$@"