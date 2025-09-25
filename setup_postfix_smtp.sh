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

# Function to create email templates directory
create_templates() {
    print_status "Creating email templates directory..."
    
    mkdir -p /opt/email-templates
    
    # Create verification email template
    cat > /opt/email-templates/verification.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Email Verification</title>
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background-color: #f4f4f4; padding: 20px; text-align: center; }
        .content { padding: 20px; }
        .verification-code { 
            background-color: #007bff; 
            color: white; 
            padding: 15px; 
            text-align: center; 
            font-size: 24px; 
            font-weight: bold; 
            margin: 20px 0; 
            border-radius: 5px; 
        }
        .footer { background-color: #f4f4f4; padding: 10px; text-align: center; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Email Verification</h1>
        </div>
        <div class="content">
            <p>Hello,</p>
            <p>Thank you for registering with us. Please use the following verification code to complete your registration:</p>
            <div class="verification-code">VERIFICATION_CODE</div>
            <p>This code will expire in 15 minutes.</p>
            <p>If you did not request this verification, please ignore this email.</p>
        </div>
        <div class="footer">
            <p>This is an automated message. Please do not reply to this email.</p>
        </div>
    </div>
</body>
</html>
EOF

    # Create password reset email template
    cat > /opt/email-templates/password-reset.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Password Reset</title>
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background-color: #f4f4f4; padding: 20px; text-align: center; }
        .content { padding: 20px; }
        .reset-code { 
            background-color: #dc3545; 
            color: white; 
            padding: 15px; 
            text-align: center; 
            font-size: 24px; 
            font-weight: bold; 
            margin: 20px 0; 
            border-radius: 5px; 
        }
        .footer { background-color: #f4f4f4; padding: 10px; text-align: center; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Password Reset Request</h1>
        </div>
        <div class="content">
            <p>Hello,</p>
            <p>We received a request to reset your password. Please use the following reset code:</p>
            <div class="reset-code">RESET_CODE</div>
            <p>This code will expire in 30 minutes.</p>
            <p>If you did not request a password reset, please ignore this email and your password will remain unchanged.</p>
        </div>
        <div class="footer">
            <p>This is an automated message. Please do not reply to this email.</p>
        </div>
    </div>
</body>
</html>
EOF

    # Create PHP script for sending emails
    cat > /opt/email-templates/send_email.php << 'EOF'
<?php
/**
 * Email sending function for verification codes and password resets
 * Usage: php send_email.php recipient@example.com verification 123456
 */

function sendEmail($to, $type, $code) {
    $templates = [
        'verification' => [
            'subject' => 'Email Verification Code',
            'template' => '/opt/email-templates/verification.html'
        ],
        'password-reset' => [
            'subject' => 'Password Reset Code',
            'template' => '/opt/email-templates/password-reset.html'
        ]
    ];
    
    if (!isset($templates[$type])) {
        throw new Exception("Invalid email type: $type");
    }
    
    $config = $templates[$type];
    $subject = $config['subject'];
    $template = file_get_contents($config['template']);
    
    // Replace placeholders
    $body = str_replace(['VERIFICATION_CODE', 'RESET_CODE'], $code, $template);
    
    // Email headers
    $headers = [
        'MIME-Version: 1.0',
        'Content-type: text/html; charset=UTF-8',
        'From: noreply@' . gethostname(),
        'Reply-To: noreply@' . gethostname(),
        'X-Mailer: PHP/' . phpversion()
    ];
    
    // Send email using mail() function
    $result = mail($to, $subject, $body, implode("\r\n", $headers));
    
    if ($result) {
        echo "Email sent successfully to $to\n";
        return true;
    } else {
        echo "Failed to send email to $to\n";
        return false;
    }
}

// Command line usage
if ($argc < 4) {
    echo "Usage: php send_email.php <recipient> <type> <code>\n";
    echo "Types: verification, password-reset\n";
    exit(1);
}

$recipient = $argv[1];
$type = $argv[2];
$code = $argv[3];

try {
    sendEmail($recipient, $type, $code);
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
    exit(1);
}
?>
EOF

    chmod +x /opt/email-templates/send_email.php
    chown -R www-data:www-data /opt/email-templates
    
    print_success "Email templates created in /opt/email-templates/"
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
    
    cat > /opt/email-templates/README.md << EOF
# Postfix SMTP Email Setup

## Overview
This setup configures Postfix to send verification codes and password reset emails for your client website.

## Configuration Files
- Main config: /etc/postfix/main.cf
- SASL auth: /etc/postfix/sasl_passwd
- Templates: /opt/email-templates/

## Usage Examples

### Send Verification Email
\`\`\`bash
php /opt/email-templates/send_email.php user@example.com verification 123456
\`\`\`

### Send Password Reset Email
\`\`\`bash
php /opt/email-templates/send_email.php user@example.com password-reset 789012
\`\`\`

### Test Basic Email
\`\`\`bash
echo "Test message" | mail -s "Test Subject" recipient@example.com
\`\`\`

## Integration with Your Website

### PHP Integration
\`\`\`php
<?php
function sendVerificationCode(\$email, \$code) {
    \$command = "php /opt/email-templates/send_email.php \$email verification \$code";
    exec(\$command, \$output, \$return_code);
    return \$return_code === 0;
}

function sendPasswordReset(\$email, \$code) {
    \$command = "php /opt/email-templates/send_email.php \$email password-reset \$code";
    exec(\$command, \$output, \$return_code);
    return \$return_code === 0;
}
?>
\`\`\`

### Node.js Integration
\`\`\`javascript
const { exec } = require('child_process');

function sendVerificationCode(email, code) {
    return new Promise((resolve, reject) => {
        exec(\`php /opt/email-templates/send_email.php \${email} verification \${code}\`, (error, stdout, stderr) => {
            if (error) {
                reject(error);
            } else {
                resolve(stdout);
            }
        });
    });
}
\`\`\`

## Security Notes
- Email passwords are stored in /etc/postfix/sasl_passwd (chmod 600)
- Postfix is configured to only listen on loopback interface
- SASL authentication is required for sending emails
- TLS encryption is enabled for secure transmission

## Troubleshooting
- Check Postfix logs: \`tail -f /var/log/mail.log\`
- Test configuration: \`postfix check\`
- Reload configuration: \`postfix reload\`
- Check service status: \`systemctl status postfix\`

## Important Security Considerations
1. Use App Passwords for Gmail (not your main password)
2. Enable 2FA on your email account
3. Regularly rotate email passwords
4. Monitor email logs for suspicious activity
5. Consider using a dedicated email service for production
EOF

    print_success "Documentation created at /opt/email-templates/README.md"
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
    create_templates
    start_postfix
    test_email
    create_documentation
    
    print_success "Postfix SMTP setup completed successfully!"
    print_status "Next steps:"
    echo "1. Check your email for the test message"
    echo "2. Review the documentation at /opt/email-templates/README.md"
    echo "3. Integrate the email functions into your website"
    echo "4. Test with your actual verification and password reset flows"
    
    print_warning "Important: Make sure to use App Passwords for Gmail accounts with 2FA enabled!"
}

# Run main function
main "$@"