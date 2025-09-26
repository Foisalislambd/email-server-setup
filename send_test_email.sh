#!/bin/bash

# Test Email Sending Script
# This script sends a test email to verify SMTP configuration

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

log_info "📧 SMTP Test Email Sender"
echo "=========================="

# Get configuration from existing setup
if [[ -f /etc/mailname ]]; then
    DOMAIN=$(cat /etc/mailname)
    log_info "Detected domain: $DOMAIN"
else
    read -p "Enter your domain name: " DOMAIN
fi

if [[ -f /etc/postfix/sasl_passwd ]]; then
    EMAIL_ADDRESS=$(head -n1 /etc/postfix/sasl_passwd | cut -d' ' -f2 | cut -d':' -f1)
    log_info "Detected email address: $EMAIL_ADDRESS"
else
    read -p "Enter your email address: " EMAIL_ADDRESS
fi

# Get recipient email
read -p "Enter recipient email address (default: ifoisal19@gmail.com): " RECIPIENT_EMAIL
RECIPIENT_EMAIL=${RECIPIENT_EMAIL:-ifoisal19@gmail.com}

# Get email subject
read -p "Enter email subject (default: Test Email from $DOMAIN): " EMAIL_SUBJECT
EMAIL_SUBJECT=${EMAIL_SUBJECT:-"Test Email from $DOMAIN"}

# Get email message
read -p "Enter email message (default: Test message from SMTP server): " EMAIL_MESSAGE
EMAIL_MESSAGE=${EMAIL_MESSAGE:-"Test message from SMTP server"}

log_info "Sending test email..."
log_info "From: $EMAIL_ADDRESS"
log_info "To: $RECIPIENT_EMAIL"
log_info "Subject: $EMAIL_SUBJECT"

# Create email content
cat > /tmp/test_email_content.txt << EOF
Subject: $EMAIL_SUBJECT
From: $EMAIL_ADDRESS
To: $RECIPIENT_EMAIL

$EMAIL_MESSAGE

---
📧 SMTP Server Details:
- Domain: $DOMAIN
- Server: $(hostname)
- Date: $(date)
- Status: ✅ Working

🚀 This email confirms your SMTP server is working correctly!
EOF

# Send the email
if echo "$EMAIL_MESSAGE" | mail -s "$EMAIL_SUBJECT" -a "From: $EMAIL_ADDRESS" "$RECIPIENT_EMAIL"; then
    log_success "✅ Email sent successfully to $RECIPIENT_EMAIL"
    log_success "📧 Check the recipient's inbox to confirm delivery"
    log_info ""
    log_info "If the email is received, your SMTP server is working perfectly!"
    log_info "If not received, check:"
    log_info "1. DNS records (MX, A, SPF)"
    log_info "2. Firewall settings (port 587)"
    log_info "3. Email provider restrictions"
else
    log_error "❌ Failed to send email"
    log_info "Troubleshooting steps:"
    log_info "1. Check Postfix status: systemctl status postfix"
    log_info "2. Check mail logs: tail -f /var/log/mail.log"
    log_info "3. Test configuration: postconf -n"
    log_info "4. Check DNS records"
fi

# Clean up
rm -f /tmp/test_email_content.txt

echo
log_info "📋 Quick Commands:"
log_info "Check Postfix status: systemctl status postfix"
log_info "View mail logs: tail -f /var/log/mail.log"
log_info "Test configuration: postconf -n"
log_info "Send another test: sudo ./send_test_email.sh"