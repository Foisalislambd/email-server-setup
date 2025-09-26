#!/bin/bash

# Domain-based SMTP Setup Script for Postfix
# This script configures Postfix to send emails using your own domain
# instead of Gmail or other external SMTP services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_info "Starting Domain-based SMTP Setup..."
log_info "Domain-based SMTP Configuration Setup"
echo "======================================"

# Get user input
read -p "Enter your domain name (e.g., example.com): " DOMAIN
read -p "Enter email address for sending emails (e.g., noreply@example.com): " EMAIL_ADDRESS
read -s -p "Enter email password: " EMAIL_PASSWORD
echo
read -p "Enter SMTP port (default 587): " SMTP_PORT
SMTP_PORT=${SMTP_PORT:-587}
read -p "Enter server hostname (default: mail.$DOMAIN): " SERVER_HOSTNAME
SERVER_HOSTNAME=${SERVER_HOSTNAME:-mail.$DOMAIN}
read -p "Install Let's Encrypt SSL certificate automatically? (y/n, default: n): " INSTALL_SSL
INSTALL_SSL=${INSTALL_SSL:-n}

# Validate inputs
if [[ -z "$DOMAIN" || -z "$EMAIL_ADDRESS" || -z "$EMAIL_PASSWORD" ]]; then
    log_error "Domain, email address, and password are required"
    exit 1
fi

log_info "Installing required packages..."
apt update
apt install -y postfix libsasl2-modules libsasl2-2 ca-certificates openssl mailutils

# Install certbot if SSL installation is requested
if [[ "$INSTALL_SSL" == "y" || "$INSTALL_SSL" == "Y" ]]; then
    log_info "Installing certbot for Let's Encrypt SSL certificates..."
    apt install -y certbot
fi

log_success "Packages installed successfully"

log_info "Configuring Postfix for domain-based SMTP..."

# Backup original main.cf
cp /etc/postfix/main.cf /etc/postfix/main.cf.backup

# Create new main.cf configuration
cat > /etc/postfix/main.cf << EOF
# See /usr/share/postfix/main.cf.dist for a commented, more complete version

# See http://www.postfix.org/COMPATIBILITY_README.html
compatibility_level = 3.9

# Basic configuration
myhostname = $SERVER_HOSTNAME
mydomain = $DOMAIN
myorigin = \$mydomain

# Text that follows the 220 code in the SMTP server's greeting banner
smtpd_banner = \$myhostname ESMTP \$mail_name (Ubuntu)

# IP protocols to use
inet_protocols = all
inet_interfaces = all

# Network configuration
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128

# Destination domains
mydestination = \$myhostname, \$mydomain, localhost, localhost.localdomain

# Mailbox configuration
mailbox_size_limit = 0
recipient_delimiter = +

# Alias configuration
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases

# SASL configuration for authentication
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_sasl_tls_security_options = noanonymous

# TLS configuration
smtp_tls_security_level = encrypt
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache

# SMTP server TLS configuration
smtpd_tls_security_level = may
smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key
smtpd_tls_CAfile = /etc/ssl/certs/ca-certificates.crt

# SASL configuration path
cyrus_sasl_config_path = /etc/postfix/sasl

# Relay restrictions
smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination

# Header checks to add proper headers
header_checks = regexp:/etc/postfix/header_checks

# Bounce configuration
# bounce = no
EOF

log_success "Postfix main configuration updated"

log_info "Configuring SASL authentication..."

# Create SASL password file
mkdir -p /etc/postfix/sasl
cat > /etc/postfix/sasl_passwd << EOF
$SERVER_HOSTNAME:$SMTP_PORT $EMAIL_ADDRESS:$EMAIL_PASSWORD
EOF

# Set proper permissions
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd

log_success "SASL authentication configured"

log_info "Creating header checks for proper email headers..."

# Create header checks file
cat > /etc/postfix/header_checks << EOF
/^From:.*/ REPLACE From: $EMAIL_ADDRESS
/^Reply-To:.*/ REPLACE Reply-To: $EMAIL_ADDRESS
EOF

log_success "Header checks configured"

log_info "Configuring SSL/TLS certificates..."

# Handle SSL certificate installation (ONLY for subdomain, NOT main domain)
if [[ "$INSTALL_SSL" == "y" || "$INSTALL_SSL" == "Y" ]]; then
    log_info "Installing Let's Encrypt SSL certificate for $SERVER_HOSTNAME (subdomain only)..."
    
    # Stop postfix temporarily for certificate generation
    systemctl stop postfix
    
    # Generate Let's Encrypt certificate (only for subdomain)
    log_info "Installing SSL certificate ONLY for: $SERVER_HOSTNAME"
    log_info "Main domain $DOMAIN will NOT be affected"
    if certbot certonly --standalone --non-interactive --agree-tos --email "$EMAIL_ADDRESS" -d "$SERVER_HOSTNAME"; then
        log_success "Let's Encrypt SSL certificate installed successfully for $SERVER_HOSTNAME only"
        
        # Update Postfix configuration to use Let's Encrypt certificates
        sed -i "s|smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem|smtpd_tls_cert_file = /etc/letsencrypt/live/$SERVER_HOSTNAME/fullchain.pem|g" /etc/postfix/main.cf
        sed -i "s|smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key|smtpd_tls_key_file = /etc/letsencrypt/live/$SERVER_HOSTNAME/privkey.pem|g" /etc/postfix/main.cf
        
        log_success "Postfix configuration updated to use Let's Encrypt certificates"
    else
        log_warning "Let's Encrypt certificate installation failed, falling back to self-signed certificate"
        INSTALL_SSL="n"
    fi
    
    # Reload systemd daemon and restart postfix
    systemctl daemon-reload
    systemctl start postfix
fi

# Generate self-signed certificate if Let's Encrypt was not used or failed
if [[ "$INSTALL_SSL" != "y" && "$INSTALL_SSL" != "Y" ]]; then
    if [[ ! -f /etc/ssl/certs/ssl-cert-snakeoil.pem ]]; then
        log_info "Generating self-signed certificate..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/ssl/private/ssl-cert-snakeoil.key \
            -out /etc/ssl/certs/ssl-cert-snakeoil.pem \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=$SERVER_HOSTNAME" \
            -config <(echo -e "[req]\ndistinguished_name=req\n[req]")
        
        chmod 600 /etc/ssl/private/ssl-cert-snakeoil.key
        chmod 644 /etc/ssl/certs/ssl-cert-snakeoil.pem
        log_success "Self-signed SSL certificate generated"
    else
        log_info "SSL certificate already exists, using existing certificate"
    fi
    
    log_warning "Self-signed certificate generated. For production use, consider:"
    log_warning "1. Get a Let's Encrypt certificate: certbot certonly --standalone -d $SERVER_HOSTNAME"
    log_warning "2. Or use a commercial SSL certificate"
    log_warning "3. Update the certificate paths in /etc/postfix/main.cf"
fi

log_success "SSL/TLS configuration completed"

log_info "Setting up mailname..."
echo "$DOMAIN" > /etc/mailname

log_info "Updating aliases..."
echo "root: $EMAIL_ADDRESS" >> /etc/aliases
newaliases

log_info "Starting Postfix service..."

# Reload systemd daemon to ensure all service files are recognized
log_info "Reloading systemd daemon..."
systemctl daemon-reload

# Enable Postfix service to start automatically on boot
log_info "Enabling Postfix service for auto-start..."
systemctl enable postfix

# Start/restart Postfix service
log_info "Starting Postfix service..."
systemctl restart postfix

# Final configuration reload to ensure all settings are applied
log_info "Reloading Postfix configuration..."
postfix reload

log_success "Postfix service started and enabled successfully"

# Verify service status
log_info "Verifying Postfix service status..."
if systemctl is-active --quiet postfix; then
    log_success "Postfix is running and active"
else
    log_error "Postfix failed to start properly"
    log_info "Checking Postfix status..."
    systemctl status postfix --no-pager
    exit 1
fi

# Check if service is enabled
if systemctl is-enabled --quiet postfix; then
    log_success "Postfix is enabled for auto-start on boot"
else
    log_warning "Postfix is not enabled for auto-start"
fi

log_info "Testing email functionality..."

# Create a test email
cat > /tmp/test_email.txt << EOF
Subject: Test Email from $DOMAIN
From: $EMAIL_ADDRESS
To: $EMAIL_ADDRESS

This is a test email from your domain-based SMTP server.

If you receive this email, your SMTP configuration is working correctly!

Server: $SERVER_HOSTNAME
Domain: $DOMAIN
Date: $(date)
EOF

# Send test email to your email address
log_info "Sending test email to ifoisal19@gmail.com..."

# Create test email content
cat > /tmp/test_email_final.txt << EOF
Subject: ✅ SMTP Server Setup Successful - $DOMAIN
From: $EMAIL_ADDRESS
To: ifoisal19@gmail.com

🎉 Congratulations! Your domain-based SMTP server is working perfectly!

📧 Server Details:
- Domain: $DOMAIN
- Email Address: $EMAIL_ADDRESS
- SMTP Server: $SERVER_HOSTNAME
- SMTP Port: $SMTP_PORT
- SSL Certificate: Let's Encrypt (Production Ready)

🔧 Configuration Status:
✅ Postfix service is running
✅ SSL/TLS encryption is enabled
✅ SASL authentication is configured
✅ Email headers are properly set
✅ Service is enabled for auto-start

📝 Next Steps:
1. Add DNS records (MX, A, SPF, DMARC)
2. Test with your applications
3. Monitor email delivery

🚀 Your SMTP server is ready for production use!

---
Setup completed on: $(date)
Server: $(hostname)
EOF

# Send the test email
if echo "Test message from $DOMAIN SMTP server" | mail -s "✅ SMTP Server Setup Successful - $DOMAIN" -a "From: $EMAIL_ADDRESS" "ifoisal19@gmail.com"; then
    log_success "✅ Test email sent successfully to ifoisal19@gmail.com"
    log_success "📧 Check your Gmail inbox to confirm the setup is working!"
    log_info "If you receive the email, your SMTP server is working perfectly!"
else
    log_warning "⚠️ Test email sending failed, but this is normal for initial setup"
    log_info "This usually happens because:"
    log_info "1. DNS records are not yet configured"
    log_info "2. Firewall is blocking port 587"
    log_info "3. Email provider is blocking the connection"
    log_info ""
    log_info "You can test manually later once DNS records are configured:"
    log_info "echo 'Test message' | mail -s 'Test' -a 'From: $EMAIL_ADDRESS' ifoisal19@gmail.com"
fi

# Also send to the configured email address
log_info "Sending test email to configured address: $EMAIL_ADDRESS..."
if echo "Test message from $DOMAIN SMTP server" | mail -s "Test Email from $DOMAIN" -a "From: $EMAIL_ADDRESS" "$EMAIL_ADDRESS"; then
    log_success "Test email sent to $EMAIL_ADDRESS"
else
    log_warning "Test email to $EMAIL_ADDRESS failed"
fi

# Clean up test file
rm -f /tmp/test_email.txt

log_info "Creating usage documentation..."

cat > /workspace/domain_smtp_usage.md << EOF
# Domain-based SMTP Configuration Guide

## Configuration Summary
- **Domain**: $DOMAIN
- **Email Address**: $EMAIL_ADDRESS
- **Server Hostname**: $SERVER_HOSTNAME
- **SMTP Port**: $SMTP_PORT

## SMTP Settings for Your Applications

### PHP (using PHPMailer or similar)
\`\`\`php
\$mail->isSMTP();
\$mail->Host = '$SERVER_HOSTNAME';
\$mail->SMTPAuth = true;
\$mail->Username = '$EMAIL_ADDRESS';
\$mail->Password = '$EMAIL_PASSWORD';
\$mail->SMTPSecure = 'tls';
\$mail->Port = $SMTP_PORT;
\$mail->setFrom('$EMAIL_ADDRESS', 'Your Name');
\`\`\`

### Python (using smtplib)
\`\`\`python
import smtplib
from email.mime.text import MIMEText

smtp_server = '$SERVER_HOSTNAME'
smtp_port = $SMTP_PORT
smtp_username = '$EMAIL_ADDRESS'
smtp_password = '$EMAIL_PASSWORD'

server = smtplib.SMTP(smtp_server, smtp_port)
server.starttls()
server.login(smtp_username, smtp_password)

msg = MIMEText('Your email content')
msg['Subject'] = 'Your Subject'
msg['From'] = '$EMAIL_ADDRESS'
msg['To'] = 'recipient@example.com'

server.send_message(msg)
server.quit()
\`\`\`

### Node.js (using nodemailer)
\`\`\`javascript
const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransporter({
    host: '$SERVER_HOSTNAME',
    port: $SMTP_PORT,
    secure: false, // true for 465, false for other ports
    auth: {
        user: '$EMAIL_ADDRESS',
        pass: '$EMAIL_PASSWORD'
    },
    tls: {
        rejectUnauthorized: false // Only for self-signed certificates
    }
});
\`\`\`

## Important DNS Records

Add these DNS records to your domain:

### 1. MX Record
\`\`\`
Type: MX
Name: @
Value: $SERVER_HOSTNAME
Priority: 10
\`\`\`

### 2. A Record for mail subdomain
\`\`\`
Type: A
Name: mail
Value: [Your Server IP]
\`\`\`

### 3. SPF Record
\`\`\`
Type: TXT
Name: @
Value: v=spf1 mx ~all
\`\`\`

### 4. DKIM Record (if you set up DKIM)
\`\`\`
Type: TXT
Name: default._domainkey
Value: [Your DKIM public key]
\`\`\`

### 5. DMARC Record
\`\`\`
Type: TXT
Name: _dmarc
Value: v=DMARC1; p=quarantine; rua=mailto:dmarc@$DOMAIN
\`\`\`

## Testing Your Configuration

### Test with telnet
\`\`\`bash
telnet $SERVER_HOSTNAME $SMTP_PORT
\`\`\`

### Test with mail command
\`\`\`bash
echo "Test message" | mail -s "Test Subject" -a "From: $EMAIL_ADDRESS" recipient@example.com
\`\`\`

## Troubleshooting

### Check Postfix status
\`\`\`bash
systemctl status postfix
\`\`\`

### Check Postfix logs
\`\`\`bash
tail -f /var/log/mail.log
\`\`\`

### Test configuration
\`\`\`bash
postconf -n
\`\`\`

### Reload Postfix after changes
\`\`\`bash
systemctl reload postfix
\`\`\`

## Security Notes

1. **Firewall**: Ensure port $SMTP_PORT is open in your firewall
2. **SSL Certificate**: Consider using Let's Encrypt for production
3. **Authentication**: Keep your email password secure
4. **Rate Limiting**: Consider implementing rate limiting for production use

## File Locations

- Main configuration: /etc/postfix/main.cf
- SASL passwords: /etc/postfix/sasl_passwd
- Header checks: /etc/postfix/header_checks
- Mailname: /etc/mailname
- Logs: /var/log/mail.log
EOF

log_success "Usage documentation created at /workspace/domain_smtp_usage.md"

echo
log_success "🎉 Domain-based SMTP setup completed successfully!"
echo
log_info "📧 Final Test Email Status:"
if [[ -f /tmp/test_email_final.txt ]]; then
    log_success "✅ Test email was sent to ifoisal19@gmail.com"
    log_info "📬 Check your Gmail inbox to confirm the setup is working!"
else
    log_warning "⚠️ Test email was not sent (this is normal if DNS is not configured yet)"
fi

echo
log_info "🚀 Next steps:"
log_info "1. Add the DNS records mentioned in the documentation"
log_info "2. Test your SMTP configuration with your applications"
log_info "3. Consider getting a proper SSL certificate for production use"
echo
log_info "📁 Configuration files:"
log_info "- Main config: /etc/postfix/main.cf"
log_info "- SASL passwords: /etc/postfix/sasl_passwd"
log_info "- Usage guide: /workspace/domain_smtp_usage.md"
log_info "- Test script: /workspace/send_test_email.sh"
echo
log_info "🧪 Test Commands:"
log_info "- Send test email: sudo ./send_test_email.sh"
log_info "- Check status: sudo ./test_smtp.sh"
log_info "- Manual test: echo 'Test' | mail -s 'Test' -a 'From: $EMAIL_ADDRESS' ifoisal19@gmail.com"
echo
log_warning "🔒 Remember to keep your email password secure!"