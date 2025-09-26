#!/bin/bash

# SMTP Test Script
# This script tests the SMTP configuration

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

log_info "Testing SMTP Configuration..."

# Test 1: Check Postfix status
log_info "1. Checking Postfix service status..."
if systemctl is-active --quiet postfix; then
    log_success "Postfix service is running"
else
    log_warning "Postfix service is not running, attempting to start..."
    systemctl daemon-reload
    systemctl start postfix
    if systemctl is-active --quiet postfix; then
        log_success "Postfix service started successfully"
    else
        log_error "Failed to start Postfix service"
        exit 1
    fi
fi

# Test 2: Check configuration
log_info "2. Checking Postfix configuration..."
if postconf -n > /dev/null 2>&1; then
    log_success "Postfix configuration is valid"
else
    log_error "Postfix configuration has errors"
    exit 1
fi

# Test 3: Check SSL certificates
log_info "3. Checking SSL certificates..."
if [[ -f /etc/ssl/certs/ssl-cert-snakeoil.pem ]] || [[ -f /etc/letsencrypt/live/*/fullchain.pem ]]; then
    log_success "SSL certificates are present"
else
    log_warning "No SSL certificates found"
fi

# Test 4: Check SASL configuration
log_info "4. Checking SASL configuration..."
if [[ -f /etc/postfix/sasl_passwd ]]; then
    log_success "SASL password file exists"
else
    log_error "SASL password file is missing"
fi

# Test 5: Check mailname
log_info "5. Checking mailname configuration..."
if [[ -f /etc/mailname ]]; then
    MAILNAME=$(cat /etc/mailname)
    log_success "Mailname is set to: $MAILNAME"
else
    log_warning "Mailname file is missing"
fi

# Test 6: Test SMTP connection
log_info "6. Testing SMTP connection..."
if command -v telnet > /dev/null; then
    log_info "Testing SMTP port 587..."
    if timeout 5 bash -c "</dev/tcp/localhost/587" 2>/dev/null; then
        log_success "SMTP port 587 is accessible"
    else
        log_warning "SMTP port 587 is not accessible"
    fi
else
    log_warning "telnet not available, skipping connection test"
fi

# Test 7: Check logs for errors
log_info "7. Checking recent Postfix logs for errors..."
if [[ -f /var/log/mail.log ]]; then
    RECENT_ERRORS=$(tail -n 50 /var/log/mail.log | grep -i error | wc -l)
    if [[ $RECENT_ERRORS -eq 0 ]]; then
        log_success "No recent errors found in mail logs"
    else
        log_warning "Found $RECENT_ERRORS recent errors in mail logs"
        log_info "Recent errors:"
        tail -n 50 /var/log/mail.log | grep -i error | tail -n 3
    fi
else
    log_warning "Mail log file not found"
fi

echo
log_success "SMTP configuration test completed!"
echo
log_info "Configuration Summary:"
log_info "- Postfix Status: $(systemctl is-active postfix)"
log_info "- Mailname: $(cat /etc/mailname 2>/dev/null || echo 'Not set')"
log_info "- SSL Certificate: $(if [[ -f /etc/letsencrypt/live/*/fullchain.pem ]]; then echo 'Let\'s Encrypt'; elif [[ -f /etc/ssl/certs/ssl-cert-snakeoil.pem ]]; then echo 'Self-signed'; else echo 'None'; fi)"
echo
log_info "To test sending emails, use:"
log_info "echo 'Test message' | mail -s 'Test Subject' -a 'From: your-email@domain.com' recipient@example.com"