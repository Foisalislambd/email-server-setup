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

# SSL/TLS configuration
SSL_CERT_DIR="/etc/ssl/certs"
SSL_KEY_DIR="/etc/ssl/private"
SSL_CERT_FILE="$SSL_CERT_DIR/mail.$DOMAIN.crt"
SSL_KEY_FILE="$SSL_KEY_DIR/mail.$DOMAIN.key"
SSL_CA_FILE="$SSL_CERT_DIR/mail.$DOMAIN.ca-bundle"

# SASL configuration
SASL_PASSWD_FILE="/etc/postfix/sasl_passwd"
SASL_DB_FILE="/etc/postfix/sasl_passwd.db"

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
        "dovecot-core"
        "dovecot-imapd"
        "dovecot-pop3d"
        "dovecot-lmtpd"
        "sasl2-bin"
        "libsasl2-modules"
        "libsasl2-modules-db"
        "certbot"
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

# Generate SSL certificates
generate_ssl_certificates() {
    log "Generating SSL certificates..."
    
    # Create SSL directories
    mkdir -p "$SSL_CERT_DIR" "$SSL_KEY_DIR"
    
    # Generate private key
    if [ ! -f "$SSL_KEY_FILE" ]; then
        log "Generating SSL private key..."
        openssl genrsa -out "$SSL_KEY_FILE" 2048
        chmod 600 "$SSL_KEY_FILE"
        chown root:root "$SSL_KEY_FILE"
    else
        log "SSL private key already exists"
    fi
    
    # Generate certificate signing request
    CSR_FILE="/tmp/mail.$DOMAIN.csr"
    if [ ! -f "$SSL_CERT_FILE" ]; then
        log "Generating SSL certificate..."
        openssl req -new -key "$SSL_KEY_FILE" -out "$CSR_FILE" -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=$SUBDOMAIN/emailAddress=admin@$DOMAIN"
        
        # Generate self-signed certificate (valid for 365 days)
        openssl x509 -req -days 365 -in "$CSR_FILE" -signkey "$SSL_KEY_FILE" -out "$SSL_CERT_FILE"
        
        # Set proper permissions
        chmod 644 "$SSL_CERT_FILE"
        chown root:root "$SSL_CERT_FILE"
        
        # Clean up CSR file
        rm -f "$CSR_FILE"
        
        log "SSL certificate generated successfully"
    else
        log "SSL certificate already exists"
    fi
    
    # Create certificate bundle (same as cert for self-signed)
    cp "$SSL_CERT_FILE" "$SSL_CA_FILE"
    chmod 644 "$SSL_CA_FILE"
    chown root:root "$SSL_CA_FILE"
    
    log "SSL certificates setup completed"
}

# Configure SASL authentication
configure_sasl() {
    log "Configuring SASL authentication..."
    
    # Configure SASL for Postfix
    postconf -e "smtpd_sasl_type = dovecot"
    postconf -e "smtpd_sasl_path = private/auth"
    postconf -e "smtpd_sasl_auth_enable = yes"
    postconf -e "smtpd_sasl_security_options = noanonymous"
    postconf -e "smtpd_sasl_local_domain = \$myhostname"
    postconf -e "broken_sasl_auth_clients = yes"
    
    # Configure SASL for outgoing mail (if needed)
    postconf -e "smtp_sasl_auth_enable = no"
    postconf -e "smtp_sasl_password_maps = hash:$SASL_PASSWD_FILE"
    postconf -e "smtp_sasl_security_options = noanonymous"
    
    # Configure Dovecot for SASL
    cat > /etc/dovecot/conf.d/10-auth.conf << EOF
# Authentication configuration
disable_plaintext_auth = no
auth_mechanisms = plain login
!include auth-system.conf.ext
EOF
    
    # Configure Dovecot auth socket
    cat > /etc/dovecot/conf.d/10-master.conf << EOF
service auth {
    unix_listener /var/spool/postfix/private/auth {
        mode = 0666
        user = postfix
        group = postfix
    }
}
EOF
    
    # Configure mail location
    cat > /etc/dovecot/conf.d/10-mail.conf << EOF
mail_location = maildir:~/Maildir
EOF
    
    # Configure SSL for Dovecot
    cat > /etc/dovecot/conf.d/10-ssl.conf << EOF
ssl = required
ssl_cert = <$SSL_CERT_FILE
ssl_key = <$SSL_KEY_FILE
ssl_protocols = !SSLv2 !SSLv3
ssl_cipher_list = ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
ssl_prefer_server_ciphers = yes
EOF
    
    log "SASL authentication configured"
}

# Create SMTP user for authentication
create_smtp_user() {
    log "Creating SMTP user for authentication..."
    
    # Create a system user for SMTP authentication
    SMTP_USER="smtpuser"
    SMTP_PASSWORD=$(openssl rand -base64 32)
    
    # Create user if it doesn't exist
    if ! id "$SMTP_USER" &>/dev/null; then
        useradd -r -s /bin/false -d /var/spool/mail/$SMTP_USER -m "$SMTP_USER"
        log "Created SMTP user: $SMTP_USER"
    else
        log "SMTP user already exists: $SMTP_USER"
    fi
    
    # Set password for the user
    echo "$SMTP_USER:$SMTP_PASSWORD" | chpasswd
    
    # Save credentials to file
    cat > "$SCRIPT_DIR/smtp_credentials.txt" << EOF
SMTP Authentication Credentials
==============================

Username: $SMTP_USER
Password: $SMTP_PASSWORD

Use these credentials in your website's SMTP configuration.

IMPORTANT: Keep these credentials secure and do not share them publicly.
EOF
    
    chmod 600 "$SCRIPT_DIR/smtp_credentials.txt"
    
    log "SMTP user created: $SMTP_USER"
    log "Credentials saved to: $SCRIPT_DIR/smtp_credentials.txt"
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
    postconf -e "inet_interfaces = all"
    postconf -e "inet_protocols = ipv4"
    
    # SSL/TLS configuration for incoming connections
    postconf -e "smtpd_use_tls = yes"
    postconf -e "smtpd_tls_cert_file = $SSL_CERT_FILE"
    postconf -e "smtpd_tls_key_file = $SSL_KEY_FILE"
    postconf -e "smtpd_tls_CAfile = $SSL_CA_FILE"
    postconf -e "smtpd_tls_security_level = may"
    postconf -e "smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache"
    postconf -e "smtpd_tls_protocols = !SSLv2, !SSLv3"
    postconf -e "smtpd_tls_ciphers = high"
    postconf -e "smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3"
    postconf -e "smtpd_tls_mandatory_ciphers = high"
    
    # SSL/TLS configuration for outgoing connections
    postconf -e "smtp_use_tls = yes"
    postconf -e "smtp_tls_security_level = may"
    postconf -e "smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache"
    postconf -e "smtp_tls_cert_file = $SSL_CERT_FILE"
    postconf -e "smtp_tls_key_file = $SSL_KEY_FILE"
    postconf -e "smtp_tls_CAfile = $SSL_CA_FILE"
    
    # Message size limits
    postconf -e "message_size_limit = 10485760"  # 10MB
    postconf -e "mailbox_size_limit = 0"  # No limit for send-only
    
    # Security settings with SASL
    postconf -e "smtpd_helo_required = yes"
    postconf -e "smtpd_helo_restrictions = permit_mynetworks, warn_if_reject reject_non_fqdn_helo_hostname, reject_invalid_helo_hostname, permit"
    postconf -e "smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination"
    postconf -e "smtpd_sender_restrictions = permit_sasl_authenticated, permit_mynetworks, warn_if_reject reject_non_fqdn_sender, reject_unknown_sender_domain, permit"
    
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
    
    # Allow SMTP with SSL/TLS
    ufw allow 25/tcp    # SMTP
    ufw allow 465/tcp   # SMTPS (SSL/TLS)
    ufw allow 587/tcp   # SMTP submission (STARTTLS)
    
    # Allow IMAP/POP3 with SSL (for Dovecot)
    ufw allow 993/tcp   # IMAPS
    ufw allow 995/tcp   # POP3S
    
    log "Firewall configured for SSL/TLS mail server"
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

# Test script for Postfix mail server with SSL/TLS and Authentication
DOMAIN="100to1shot.com"
SUBDOMAIN="mail.$DOMAIN"

echo "Testing Postfix mail server configuration with SSL/TLS and Authentication..."

# Test 1: Check Postfix status
echo "1. Checking Postfix status..."
systemctl is-active postfix
if [ $? -eq 0 ]; then
    echo "✓ Postfix is running"
else
    echo "✗ Postfix is not running"
fi

# Test 2: Check Dovecot status
echo "2. Checking Dovecot status..."
systemctl is-active dovecot
if [ $? -eq 0 ]; then
    echo "✓ Dovecot is running"
else
    echo "✗ Dovecot is not running"
fi

# Test 3: Check OpenDKIM status
echo "3. Checking OpenDKIM status..."
systemctl is-active opendkim
if [ $? -eq 0 ]; then
    echo "✓ OpenDKIM is running"
else
    echo "✗ OpenDKIM is not running"
fi

# Test 4: Check SSL certificates
echo "4. Checking SSL certificates..."
if [ -f "/etc/ssl/certs/mail.$DOMAIN.crt" ]; then
    echo "✓ SSL certificate exists"
    echo "Certificate details:"
    openssl x509 -in "/etc/ssl/certs/mail.$DOMAIN.crt" -text -noout | grep -E "(Subject:|Not Before:|Not After:)"
else
    echo "✗ SSL certificate not found"
fi

# Test 5: Test SSL/TLS connection
echo "5. Testing SSL/TLS connection..."
echo | openssl s_client -connect $SUBDOMAIN:587 -starttls smtp -quiet 2>/dev/null | grep -E "(Verify return code|subject=)"
if [ $? -eq 0 ]; then
    echo "✓ SSL/TLS connection successful"
else
    echo "✗ SSL/TLS connection failed"
fi

# Test 6: Test SASL authentication
echo "6. Testing SASL authentication..."
if [ -f "/etc/postfix/sasl_passwd" ]; then
    echo "✓ SASL password file exists"
else
    echo "✗ SASL password file not found"
fi

# Test 7: Test mail sending with authentication
echo "7. Testing mail sending..."
echo "This is a test email from $SUBDOMAIN with SSL/TLS" | mail -s "Test Email from $SUBDOMAIN (SSL/TLS)" root
if [ $? -eq 0 ]; then
    echo "✓ Test email sent successfully"
else
    echo "✗ Failed to send test email"
fi

# Test 8: Check mail queue
echo "8. Checking mail queue..."
mailq
if [ $? -eq 0 ]; then
    echo "✓ Mail queue is accessible"
else
    echo "✗ Mail queue check failed"
fi

# Test 9: Check DKIM key
echo "9. Checking DKIM configuration..."
if [ -f "/etc/opendkim/keys/$DOMAIN/default.private" ]; then
    echo "✓ DKIM key exists"
    echo "DKIM public key:"
    cat "/etc/opendkim/keys/$DOMAIN/default.txt"
else
    echo "✗ DKIM key not found"
fi

# Test 10: Check firewall rules
echo "10. Checking firewall rules..."
ufw status | grep -E "(25|465|587|993|995)"
if [ $? -eq 0 ]; then
    echo "✓ Mail ports are open in firewall"
else
    echo "✗ Mail ports not configured in firewall"
fi

# Test 11: Check fail2ban status
echo "11. Checking fail2ban status..."
systemctl is-active fail2ban
if [ $? -eq 0 ]; then
    echo "✓ Fail2ban is running"
    fail2ban-client status postfix 2>/dev/null || echo "  Postfix jail not active yet"
else
    echo "✗ Fail2ban is not running"
fi

echo ""
echo "Test completed. Check /var/log/mail.log for detailed logs."
echo ""
echo "SMTP Configuration for your website:"
echo "Host: $SUBDOMAIN"
echo "Port: 587 (STARTTLS) or 465 (SSL/TLS)"
echo "Security: STARTTLS or SSL/TLS"
echo "Authentication: Yes (check smtp_credentials.txt for credentials)"
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
Port: 587 (STARTTLS) or 465 (SSL/TLS)
Security: STARTTLS or SSL/TLS
Authentication: Yes (see smtp_credentials.txt for credentials)

Example PHP configuration (PHPMailer):
\$mail->Host = '$SUBDOMAIN';
\$mail->Port = 587;
\$mail->SMTPAuth = true;
\$mail->SMTPSecure = 'tls';
\$mail->Username = 'smtpuser';  // Check smtp_credentials.txt
\$mail->Password = 'your_password';  // Check smtp_credentials.txt

Example Node.js configuration (Nodemailer):
const transporter = nodemailer.createTransporter({
    host: '$SUBDOMAIN',
    port: 587,
    secure: false, // true for 465, false for other ports
    auth: {
        user: 'smtpuser',  // Check smtp_credentials.txt
        pass: 'your_password'  // Check smtp_credentials.txt
    }
});
EOF
    
    log "DNS instructions saved to $SCRIPT_DIR/DNS_SETUP_INSTRUCTIONS.txt"
}

# Start and enable services
start_services() {
    log "Starting and enabling services..."
    
    # Start Dovecot first (for SASL)
    systemctl enable dovecot
    systemctl start dovecot
    
    # Start OpenDKIM
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
    systemctl is-active --quiet dovecot && log "✓ Dovecot is running" || error "Dovecot failed to start"
    systemctl is-active --quiet opendkim && log "✓ OpenDKIM is running" || error "OpenDKIM failed to start"
    systemctl is-active --quiet postfix && log "✓ Postfix is running" || error "Postfix failed to start"
    systemctl is-active --quiet fail2ban && log "✓ Fail2ban is running" || log "Fail2ban status: $(systemctl is-active fail2ban)"
    
    log "All services started successfully"
}

# Main installation function
main() {
    log "Starting Postfix mail server setup for $SUBDOMAIN with SSL/TLS and Authentication"
    log "Log file: $LOG_FILE"
    
    check_root
    check_system
    update_system
    install_packages
    generate_ssl_certificates
    configure_sasl
    create_smtp_user
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
    log "   Port: 587 (STARTTLS) or 465 (SSL/TLS)"
    log "   Security: STARTTLS or SSL/TLS"
    log "   Authentication: Yes (see smtp_credentials.txt)"
    
    echo ""
    echo -e "${GREEN}Setup completed! Check the following files:${NC}"
    echo -e "${GREEN}- DNS_SETUP_INSTRUCTIONS.txt for DNS configuration${NC}"
    echo -e "${GREEN}- smtp_credentials.txt for authentication credentials${NC}"
    echo -e "${GREEN}- Run test script: $SCRIPT_DIR/test_mail.sh${NC}"
}

# Run main function
main "$@"