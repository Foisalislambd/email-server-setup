#!/bin/bash

# =============================================================================
# Postfix Mail Server Auto-Setup Script
# For subdomain: mail.100to1shot.com
# Purpose: SMTP-only mail server for website email sending
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
SUBDOMAIN="mail.$DOMAIN"
HOSTNAME=$(hostname -f)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/postfix_setup.log"

# Postfix configuration files
POSTFIX_MAIN_CF="/etc/postfix/main.cf"
POSTFIX_MASTER_CF="/etc/postfix/master.cf"

# DKIM configuration
DKIM_SELECTOR="default"
DKIM_KEY_DIR="/etc/opendkim/keys/$DOMAIN"
DKIM_KEY="$DKIM_KEY_DIR/$DKIM_SELECTOR.private"
DKIM_PUBLIC_KEY="$DKIM_KEY_DIR/$DKIM_SELECTOR.txt"

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
    fi
}

# Check system requirements
check_system() {
    log "Checking system requirements..."
    
    # Check if running on supported OS
    if ! command -v apt &> /dev/null; then
        error "This script is designed for Debian/Ubuntu systems with apt package manager"
    fi
    
    # Check available disk space (need at least 1GB)
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt 1048576 ]; then  # 1GB in KB
        warning "Low disk space detected. At least 1GB recommended."
    fi
    
    # Check if hostname is set
    if [ -z "$HOSTNAME" ] || [ "$HOSTNAME" = "localhost" ]; then
        warning "Hostname not properly set. Setting to $SUBDOMAIN"
        hostnamectl set-hostname "$SUBDOMAIN"
        echo "127.0.0.1 $SUBDOMAIN" >> /etc/hosts
    fi
    
    log "System requirements check completed"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    apt update -y
    apt upgrade -y
    log "System packages updated"
}

# Install required packages
install_packages() {
    log "Installing required packages..."
    
    # Essential packages for Postfix mail server
    PACKAGES=(
        "postfix"
        "mailutils"
        "opendkim"
        "opendkim-tools"
        "ufw"
        "fail2ban"
        "curl"
        "wget"
        "openssl"
        "ca-certificates"
    )
    
    for package in "${PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log "Installing $package..."
            apt install -y "$package"
        else
            log "$package is already installed"
        fi
    done
    
    log "All packages installed successfully"
}

# Configure Postfix main settings
configure_postfix() {
    log "Configuring Postfix..."
    
    # Backup original configuration
    cp "$POSTFIX_MAIN_CF" "$POSTFIX_MAIN_CF.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Set basic Postfix configuration
    postconf -e "myhostname = $SUBDOMAIN"
    postconf -e "mydomain = $DOMAIN"
    postconf -e "myorigin = \$mydomain"
    postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
    postconf -e "mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128"
    postconf -e "inet_interfaces = loopback-only"
    postconf -e "inet_protocols = ipv4"
    
    # SMTP configuration for sending emails
    postconf -e "smtp_use_tls = yes"
    postconf -e "smtp_tls_security_level = may"
    postconf -e "smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache"
    postconf -e "smtp_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem"
    postconf -e "smtp_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key"
    
    # Message size limits
    postconf -e "message_size_limit = 10485760"  # 10MB
    postconf -e "mailbox_size_limit = 0"  # No limit for send-only
    
    # Security settings
    postconf -e "smtpd_helo_required = yes"
    postconf -e "smtpd_helo_restrictions = permit_mynetworks, warn_if_reject reject_non_fqdn_helo_hostname, reject_invalid_helo_hostname, permit"
    postconf -e "smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination"
    postconf -e "smtpd_sender_restrictions = permit_mynetworks, warn_if_reject reject_non_fqdn_sender, reject_unknown_sender_domain, permit"
    
    # Logging
    postconf -e "maillog_file = /var/log/mail.log"
    
    log "Postfix configuration completed"
}

# Configure DKIM for email authentication
configure_dkim() {
    log "Configuring DKIM..."
    
    # Create DKIM directory
    mkdir -p "$DKIM_KEY_DIR"
    
    # Generate DKIM key pair
    if [ ! -f "$DKIM_KEY" ]; then
        log "Generating DKIM key pair..."
        opendkim-genkey -b 2048 -d "$DOMAIN" -s "$DKIM_SELECTOR" -D "$DKIM_KEY_DIR"
        chown -R opendkim:opendkim "$DKIM_KEY_DIR"
        chmod 600 "$DKIM_KEY"
        chmod 644 "$DKIM_PUBLIC_KEY"
    else
        log "DKIM key already exists"
    fi
    
    # Configure OpenDKIM
    cat > /etc/opendkim.conf << EOF
# OpenDKIM configuration for $DOMAIN
Domain $DOMAIN
KeyFile $DKIM_KEY
Selector $DKIM_SELECTOR
AutoRestart Yes
AutoRestartRate 10/1h
UMask 002
Mode sv
PidFile /var/run/opendkim/opendkim.pid
UserID opendkim:opendkim
Socket inet:12301@localhost
Canonicalization relaxed/simple
OversignHeaders From
TrustAnchorFile /usr/share/dns/root.key
KeyTable refile:/etc/opendkim/key.table
SigningTable refile:/etc/opendkim/signing.table
ExternalIgnoreList refile:/etc/opendkim/trusted.hosts
InternalHosts refile:/etc/opendkim/trusted.hosts
EOF
    
    # Create key table
    echo "default._domainkey.$DOMAIN $DOMAIN:$DKIM_SELECTOR:$DKIM_KEY" > /etc/opendkim/key.table
    
    # Create signing table
    echo "*@$DOMAIN default._domainkey.$DOMAIN" > /etc/opendkim/signing.table
    
    # Create trusted hosts
    cat > /etc/opendkim/trusted.hosts << EOF
127.0.0.1
localhost
$DOMAIN
$SUBDOMAIN
EOF
    
    # Configure OpenDKIM socket
    echo "SOCKET=\"inet:12301@localhost\"" >> /etc/default/opendkim
    
    # Configure Postfix to use DKIM
    postconf -e "milter_protocol = 2"
    postconf -e "milter_default_action = accept"
    postconf -e "smtpd_milters = inet:localhost:12301"
    postconf -e "non_smtpd_milters = inet:localhost:12301"
    
    log "DKIM configuration completed"
}

# Configure firewall
configure_firewall() {
    log "Configuring firewall..."
    
    # Enable UFW if not already enabled
    ufw --force enable
    
    # Allow SSH (important!)
    ufw allow ssh
    
    # Allow HTTP and HTTPS (for web server)
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Allow SMTP (port 25) - only if you need to receive emails
    # ufw allow 25/tcp
    
    # Allow submission port (587) for authenticated SMTP
    # ufw allow 587/tcp
    
    # Since this is send-only, we don't need to open SMTP ports
    log "Firewall configured for send-only mail server"
}

# Configure fail2ban for security
configure_fail2ban() {
    log "Configuring fail2ban..."
    
    # Create Postfix jail configuration
    cat > /etc/fail2ban/jail.d/postfix.conf << EOF
[postfix]
enabled = true
port = smtp,465,587
filter = postfix
logpath = /var/log/mail.log
maxretry = 3
bantime = 3600
findtime = 600
EOF
    
    # Create Postfix filter
    cat > /etc/fail2ban/filter.d/postfix.conf << EOF
[Definition]
failregex = ^%(__prefix_line)sNOQUEUE: reject: RCPT from \S+\[<HOST>\]: 554 5\.7\.1 .*$
            ^%(__prefix_line)sNOQUEUE: reject: RCPT from \S+\[<HOST>\]: 450 4\.7\.1 .*$
            ^%(__prefix_line)sNOQUEUE: reject: RCPT from \S+\[<HOST>\]: 550 5\.7\.1 .*$
ignoreregex =
EOF
    
    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log "Fail2ban configured for Postfix security"
}

# Create test script
create_test_script() {
    log "Creating test script..."
    
    cat > "$SCRIPT_DIR/test_mail.sh" << 'EOF'
#!/bin/bash

# Test script for Postfix mail server
DOMAIN="100to1shot.com"
SUBDOMAIN="mail.$DOMAIN"

echo "Testing Postfix mail server configuration..."

# Test 1: Check Postfix status
echo "1. Checking Postfix status..."
systemctl is-active postfix
if [ $? -eq 0 ]; then
    echo "✓ Postfix is running"
else
    echo "✗ Postfix is not running"
fi

# Test 2: Check OpenDKIM status
echo "2. Checking OpenDKIM status..."
systemctl is-active opendkim
if [ $? -eq 0 ]; then
    echo "✓ OpenDKIM is running"
else
    echo "✗ OpenDKIM is not running"
fi

# Test 3: Test mail sending
echo "3. Testing mail sending..."
echo "This is a test email from $SUBDOMAIN" | mail -s "Test Email from $SUBDOMAIN" root
if [ $? -eq 0 ]; then
    echo "✓ Test email sent successfully"
else
    echo "✗ Failed to send test email"
fi

# Test 4: Check mail queue
echo "4. Checking mail queue..."
mailq
if [ $? -eq 0 ]; then
    echo "✓ Mail queue is accessible"
else
    echo "✗ Mail queue check failed"
fi

# Test 5: Check DKIM key
echo "5. Checking DKIM configuration..."
if [ -f "/etc/opendkim/keys/$DOMAIN/default.private" ]; then
    echo "✓ DKIM key exists"
    echo "DKIM public key:"
    cat "/etc/opendkim/keys/$DOMAIN/default.txt"
else
    echo "✗ DKIM key not found"
fi

echo "Test completed. Check /var/log/mail.log for detailed logs."
EOF
    
    chmod +x "$SCRIPT_DIR/test_mail.sh"
    log "Test script created at $SCRIPT_DIR/test_mail.sh"
}

# Generate DNS configuration instructions
generate_dns_instructions() {
    log "Generating DNS configuration instructions..."
    
    cat > "$SCRIPT_DIR/DNS_SETUP_INSTRUCTIONS.txt" << EOF
DNS Configuration Instructions for $DOMAIN
==========================================

To complete your mail server setup, you need to configure the following DNS records:

1. MX Record (if you want to receive emails):
   Type: MX
   Name: @
   Value: 10 $SUBDOMAIN
   TTL: 3600

2. A Record for mail subdomain:
   Type: A
   Name: mail
   Value: [YOUR_SERVER_IP]
   TTL: 3600

3. SPF Record (prevents email spoofing):
   Type: TXT
   Name: @
   Value: "v=spf1 mx -all"
   TTL: 3600

4. DKIM Record (email authentication):
   Type: TXT
   Name: default._domainkey
   Value: [See DKIM public key below]
   TTL: 3600

5. DMARC Record (email policy):
   Type: TXT
   Name: _dmarc
   Value: "v=DMARC1; p=quarantine; rua=mailto:admin@$DOMAIN"
   TTL: 3600

DKIM Public Key:
$(cat "$DKIM_PUBLIC_KEY" 2>/dev/null || echo "DKIM key not found. Run the setup script first.")

Important Notes:
- Replace [YOUR_SERVER_IP] with your actual server IP address
- DNS changes can take up to 48 hours to propagate
- Test your configuration using online tools like mxtoolbox.com
- For send-only mail server, MX record is optional

SMTP Configuration for your website:
====================================
Host: $SUBDOMAIN
Port: 25 (or 587 for authenticated SMTP)
Security: None (or STARTTLS if configured)
Authentication: None (for local applications)

Example PHP configuration:
\$mail->Host = '$SUBDOMAIN';
\$mail->Port = 25;
\$mail->SMTPAuth = false;
\$mail->SMTPSecure = false;
EOF
    
    log "DNS instructions saved to $SCRIPT_DIR/DNS_SETUP_INSTRUCTIONS.txt"
}

# Start and enable services
start_services() {
    log "Starting and enabling services..."
    
    # Start OpenDKIM first
    systemctl enable opendkim
    systemctl start opendkim
    
    # Start Postfix
    systemctl enable postfix
    systemctl restart postfix
    
    # Start fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
    
    # Check service status
    log "Checking service status..."
    systemctl is-active --quiet opendkim && log "✓ OpenDKIM is running" || error "OpenDKIM failed to start"
    systemctl is-active --quiet postfix && log "✓ Postfix is running" || error "Postfix failed to start"
    systemctl is-active --quiet fail2ban && log "✓ Fail2ban is running" || log "Fail2ban status: $(systemctl is-active fail2ban)"
    
    log "All services started successfully"
}

# Main installation function
main() {
    log "Starting Postfix mail server setup for $SUBDOMAIN"
    log "Log file: $LOG_FILE"
    
    check_root
    check_system
    update_system
    install_packages
    configure_postfix
    configure_dkim
    configure_firewall
    configure_fail2ban
    create_test_script
    generate_dns_instructions
    start_services
    
    log "Postfix mail server setup completed successfully!"
    log "Next steps:"
    log "1. Configure DNS records as described in DNS_SETUP_INSTRUCTIONS.txt"
    log "2. Run test script: $SCRIPT_DIR/test_mail.sh"
    log "3. Check logs: tail -f /var/log/mail.log"
    log "4. Configure your website to use SMTP settings:"
    log "   Host: $SUBDOMAIN"
    log "   Port: 25"
    log "   Security: None"
    log "   Authentication: None"
    
    echo ""
    echo -e "${GREEN}Setup completed! Check the DNS_SETUP_INSTRUCTIONS.txt file for DNS configuration.${NC}"
    echo -e "${GREEN}Run the test script to verify everything is working: $SCRIPT_DIR/test_mail.sh${NC}"
}

# Run main function
main "$@"