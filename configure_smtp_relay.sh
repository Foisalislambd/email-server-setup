#!/bin/bash

# =============================================================================
# SMTP Relay Configuration Script
# Companion script for Postfix mail system setup
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

# Function to display SMTP provider options
show_smtp_providers() {
    echo
    print_status "Available SMTP providers:"
    echo
    echo "1. Gmail (smtp.gmail.com:587)"
    echo "2. Outlook/Hotmail (smtp-mail.outlook.com:587)"
    echo "3. Yahoo (smtp.mail.yahoo.com:587)"
    echo "4. Mailgun (smtp.mailgun.org:587)"
    echo "5. SendGrid (smtp.sendgrid.net:587)"
    echo "6. Amazon SES (email-smtp.us-east-1.amazonaws.com:587)"
    echo "7. Custom SMTP server"
    echo
}

# Function to get SMTP provider details
get_smtp_details() {
    local choice
    read -p "Select SMTP provider (1-7): " choice
    
    case $choice in
        1)
            SMTP_HOST="smtp.gmail.com"
            SMTP_PORT="587"
            print_warning "For Gmail, you need to use an App Password, not your regular password"
            print_warning "Enable 2FA and generate an App Password in your Google Account settings"
            ;;
        2)
            SMTP_HOST="smtp-mail.outlook.com"
            SMTP_PORT="587"
            ;;
        3)
            SMTP_HOST="smtp.mail.yahoo.com"
            SMTP_PORT="587"
            ;;
        4)
            SMTP_HOST="smtp.mailgun.org"
            SMTP_PORT="587"
            ;;
        5)
            SMTP_HOST="smtp.sendgrid.net"
            SMTP_PORT="587"
            ;;
        6)
            SMTP_HOST="email-smtp.us-east-1.amazonaws.com"
            SMTP_PORT="587"
            ;;
        7)
            read -p "Enter SMTP server hostname: " SMTP_HOST
            read -p "Enter SMTP server port (default 587): " SMTP_PORT
            SMTP_PORT=${SMTP_PORT:-587}
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
}

# Function to configure SMTP relay
configure_smtp_relay() {
    print_status "Configuring SMTP relay..."
    
    # Get SMTP details
    show_smtp_providers
    get_smtp_details
    
    # Get credentials
    echo
    read -p "Enter your email address: " EMAIL_ADDRESS
    read -s -p "Enter your email password/app password: " EMAIL_PASSWORD
    echo
    
    # Create SASL password file
    print_status "Creating SASL password file..."
    cat > /etc/postfix/sasl_passwd << EOF
[$SMTP_HOST]:$SMTP_PORT $EMAIL_ADDRESS:$EMAIL_PASSWORD
EOF
    
    # Set permissions
    chmod 600 /etc/postfix/sasl_passwd
    chown root:postfix /etc/postfix/sasl_passwd
    
    # Create hash database
    postmap /etc/postfix/sasl_passwd
    
    # Configure Postfix for relay
    postconf -e "relayhost = [$SMTP_HOST]:$SMTP_PORT"
    postconf -e "smtp_sasl_auth_enable = yes"
    postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
    postconf -e "smtp_sasl_security_options = noanonymous"
    postconf -e "smtp_sasl_tls_security_options = noanonymous"
    postconf -e "smtp_use_tls = yes"
    postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
    
    print_success "SMTP relay configured successfully"
}

# Function to test SMTP relay
test_smtp_relay() {
    print_status "Testing SMTP relay configuration..."
    
    # Test Postfix configuration
    if postfix check; then
        print_success "Postfix configuration is valid"
    else
        print_error "Postfix configuration has errors"
        postfix check
        exit 1
    fi
    
    # Restart Postfix
    systemctl restart postfix
    
    # Get test email address
    read -p "Enter email address to send test email to: " TEST_EMAIL
    
    # Send test email
    print_status "Sending test email to $TEST_EMAIL..."
    echo "This is a test email from your Postfix mail server configured with SMTP relay." | \
        mail -s "Test Email - SMTP Relay Working" -a "From: noreply@100to1shot.com" "$TEST_EMAIL"
    
    print_success "Test email sent to $TEST_EMAIL"
    print_status "Check the recipient's inbox (and spam folder) for the test email"
}

# Function to show current configuration
show_configuration() {
    print_status "Current SMTP relay configuration:"
    echo
    echo "Relay host: $(postconf -h relayhost)"
    echo "SASL auth enabled: $(postconf -h smtp_sasl_auth_enable)"
    echo "TLS enabled: $(postconf -h smtp_use_tls)"
    echo
    if [[ -f /etc/postfix/sasl_passwd ]]; then
        print_status "SMTP credentials configured"
    else
        print_warning "No SMTP credentials configured"
    fi
}

# Function to remove SMTP relay
remove_smtp_relay() {
    print_warning "This will remove SMTP relay configuration"
    read -p "Are you sure? (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # Remove relay configuration
        postconf -e "relayhost ="
        postconf -e "smtp_sasl_auth_enable = no"
        postconf -e "smtp_sasl_password_maps ="
        postconf -e "smtp_use_tls = yes"
        
        # Remove credentials file
        rm -f /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
        
        # Restart Postfix
        systemctl restart postfix
        
        print_success "SMTP relay configuration removed"
    else
        print_status "Operation cancelled"
    fi
}

# Main menu
show_menu() {
    echo
    print_status "SMTP Relay Configuration Menu"
    echo
    echo "1. Configure SMTP relay"
    echo "2. Test SMTP relay"
    echo "3. Show current configuration"
    echo "4. Remove SMTP relay"
    echo "5. Exit"
    echo
}

# Main function
main() {
    check_root
    
    while true; do
        show_menu
        read -p "Select an option (1-5): " choice
        
        case $choice in
            1)
                configure_smtp_relay
                ;;
            2)
                test_smtp_relay
                ;;
            3)
                show_configuration
                ;;
            4)
                remove_smtp_relay
                ;;
            5)
                print_status "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Run main function
main "$@"