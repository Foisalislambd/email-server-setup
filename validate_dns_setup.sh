#!/bin/bash

# =============================================================================
# DNS Validation and Mail Server Testing Script
# For standalone Postfix mail server
# =============================================================================

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DOMAIN="100to1shot.com"
SUBDOMAIN="mail.100to1shot.com"

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

# Function to install required tools
install_tools() {
    print_status "Installing DNS testing tools..."
    
    if command -v apt-get &> /dev/null; then
        apt-get update -y
        apt-get install -y dnsutils telnet nmap
    elif command -v yum &> /dev/null; then
        yum install -y bind-utils telnet nmap
    elif command -v dnf &> /dev/null; then
        dnf install -y bind-utils telnet nmap
    fi
    
    print_success "DNS testing tools installed"
}

# Function to get server IP
get_server_ip() {
    print_status "Detecting server IP address..."
    
    # Try multiple methods to get public IP
    SERVER_IP=""
    
    # Method 1: Using dig
    if command -v dig &> /dev/null; then
        SERVER_IP=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null)
    fi
    
    # Method 2: Using curl
    if [[ -z "$SERVER_IP" ]] && command -v curl &> /dev/null; then
        SERVER_IP=$(curl -s ifconfig.me 2>/dev/null)
    fi
    
    # Method 3: Using wget
    if [[ -z "$SERVER_IP" ]] && command -v wget &> /dev/null; then
        SERVER_IP=$(wget -qO- ifconfig.me 2>/dev/null)
    fi
    
    if [[ -n "$SERVER_IP" ]]; then
        print_success "Server IP detected: $SERVER_IP"
    else
        print_warning "Could not detect public IP automatically"
        read -p "Enter your server's public IP address: " SERVER_IP
    fi
}

# Function to validate A record
validate_a_record() {
    print_status "Validating A record for $SUBDOMAIN..."
    
    local resolved_ip=$(dig +short "$SUBDOMAIN" A)
    
    if [[ -n "$resolved_ip" ]]; then
        if [[ "$resolved_ip" == "$SERVER_IP" ]]; then
            print_success "A record is correct: $SUBDOMAIN -> $resolved_ip"
            return 0
        else
            print_error "A record mismatch: $SUBDOMAIN -> $resolved_ip (expected: $SERVER_IP)"
            return 1
        fi
    else
        print_error "A record not found for $SUBDOMAIN"
        return 1
    fi
}

# Function to validate PTR record
validate_ptr_record() {
    print_status "Validating PTR record for $SERVER_IP..."
    
    local ptr_record=$(dig +short -x "$SERVER_IP")
    
    if [[ -n "$ptr_record" ]]; then
        if [[ "$ptr_record" == "$SUBDOMAIN." ]]; then
            print_success "PTR record is correct: $SERVER_IP -> $ptr_record"
            return 0
        else
            print_warning "PTR record mismatch: $SERVER_IP -> $ptr_record (expected: $SUBDOMAIN)"
            print_warning "This may cause emails to be marked as spam"
            return 1
        fi
    else
        print_warning "PTR record not found for $SERVER_IP"
        print_warning "This may cause emails to be marked as spam"
        return 1
    fi
}

# Function to validate SPF record
validate_spf_record() {
    print_status "Validating SPF record for $DOMAIN..."
    
    local spf_record=$(dig +short "$DOMAIN" TXT | grep -i "v=spf1")
    
    if [[ -n "$spf_record" ]]; then
        print_success "SPF record found: $spf_record"
        
        if echo "$spf_record" | grep -q "include:$SUBDOMAIN"; then
            print_success "SPF record includes $SUBDOMAIN"
            return 0
        else
            print_warning "SPF record does not include $SUBDOMAIN"
            print_warning "Consider adding: v=spf1 a mx include:$SUBDOMAIN ~all"
            return 1
        fi
    else
        print_warning "SPF record not found for $DOMAIN"
        print_warning "Consider adding: v=spf1 a mx include:$SUBDOMAIN ~all"
        return 1
    fi
}

# Function to validate MX record
validate_mx_record() {
    print_status "Validating MX record for $DOMAIN..."
    
    local mx_record=$(dig +short "$DOMAIN" MX)
    
    if [[ -n "$mx_record" ]]; then
        print_success "MX record found: $mx_record"
        
        if echo "$mx_record" | grep -q "$SUBDOMAIN"; then
            print_success "MX record points to $SUBDOMAIN"
            return 0
        else
            print_warning "MX record does not point to $SUBDOMAIN"
            print_warning "Consider adding MX record pointing to $SUBDOMAIN"
            return 1
        fi
    else
        print_warning "MX record not found for $DOMAIN"
        print_warning "Consider adding MX record pointing to $SUBDOMAIN"
        return 1
    fi
}

# Function to test SMTP connectivity
test_smtp_connectivity() {
    print_status "Testing SMTP connectivity..."
    
    # Test port 25
    if nc -z -w5 "$SUBDOMAIN" 25 2>/dev/null; then
        print_success "SMTP port 25 is accessible"
    else
        print_error "SMTP port 25 is not accessible"
    fi
    
    # Test port 587
    if nc -z -w5 "$SUBDOMAIN" 587 2>/dev/null; then
        print_success "SMTP submission port 587 is accessible"
    else
        print_error "SMTP submission port 587 is not accessible"
    fi
    
    # Test port 465
    if nc -z -w5 "$SUBDOMAIN" 465 2>/dev/null; then
        print_success "SMTPS port 465 is accessible"
    else
        print_warning "SMTPS port 465 is not accessible (optional)"
    fi
}

# Function to test SMTP handshake
test_smtp_handshake() {
    print_status "Testing SMTP handshake..."
    
    # Test basic SMTP connection
    local smtp_test=$(echo -e "QUIT" | nc -w5 "$SUBDOMAIN" 25 2>/dev/null | head -1)
    
    if [[ -n "$smtp_test" ]]; then
        print_success "SMTP handshake successful: $smtp_test"
    else
        print_error "SMTP handshake failed"
    fi
}

# Function to test TLS
test_tls() {
    print_status "Testing TLS configuration..."
    
    # Test TLS on port 587
    local tls_test=$(echo -e "EHLO test.com\nSTARTTLS\nQUIT" | nc -w5 "$SUBDOMAIN" 587 2>/dev/null)
    
    if echo "$tls_test" | grep -q "STARTTLS"; then
        print_success "TLS/STARTTLS is supported on port 587"
    else
        print_warning "TLS/STARTTLS may not be properly configured"
    fi
}

# Function to test email sending
test_email_sending() {
    print_status "Testing email sending..."
    
    read -p "Enter email address to send test email to: " TEST_EMAIL
    
    if [[ -z "$TEST_EMAIL" ]]; then
        print_warning "No email address provided, skipping email test"
        return 0
    fi
    
    # Send test email
    local test_subject="Test Email from $SUBDOMAIN"
    local test_message="This is a test email from your standalone mail server at $SUBDOMAIN. If you receive this, your mail server is working correctly!"
    
    echo "$test_message" | mail -s "$test_subject" -a "From: noreply@$DOMAIN" "$TEST_EMAIL"
    
    print_success "Test email sent to $TEST_EMAIL"
    print_status "Check the recipient's inbox (and spam folder) for the test email"
}

# Function to check mail logs
check_mail_logs() {
    print_status "Checking recent mail logs..."
    
    if [[ -f /var/log/mail.log ]]; then
        echo "Recent mail log entries:"
        tail -20 /var/log/mail.log
    else
        print_warning "Mail log file not found at /var/log/mail.log"
    fi
}

# Function to generate DNS configuration
generate_dns_config() {
    print_status "Generating DNS configuration recommendations..."
    
    local dns_file="/root/dns_configuration.txt"
    
    cat > "$dns_file" << EOF
=============================================================================
DNS Configuration for $DOMAIN
Server IP: $SERVER_IP
Mail Server: $SUBDOMAIN
=============================================================================

REQUIRED DNS RECORDS:

1. A Record:
   $SUBDOMAIN    A    $SERVER_IP

2. PTR Record (Reverse DNS):
   $SERVER_IP    PTR    $SUBDOMAIN
   (Configure this with your hosting provider)

3. MX Record:
   $DOMAIN    MX    10    $SUBDOMAIN

4. SPF Record:
   $DOMAIN    TXT    "v=spf1 a mx include:$SUBDOMAIN ~all"

5. DMARC Record:
   _dmarc.$DOMAIN    TXT    "v=DMARC1; p=quarantine; rua=mailto:admin@$DOMAIN"

OPTIONAL RECORDS:

6. DKIM Record (if you set up DKIM signing):
   default._domainkey.$DOMAIN    TXT    "v=DKIM1; k=rsa; p=YOUR_PUBLIC_KEY"

7. CNAME for www (if needed):
   www.$DOMAIN    CNAME    $DOMAIN

=============================================================================
NOTES:
- The PTR record must be configured with your hosting provider
- SPF record helps prevent email spoofing
- DMARC record helps with email authentication
- DKIM signing can be configured later for better deliverability

=============================================================================
EOF
    
    print_success "DNS configuration saved to $dns_file"
    cat "$dns_file"
}

# Function to run all validations
run_all_validations() {
    print_status "Running complete DNS and mail server validation..."
    echo
    
    local errors=0
    
    # DNS validations
    validate_a_record || ((errors++))
    echo
    
    validate_ptr_record || ((errors++))
    echo
    
    validate_spf_record || ((errors++))
    echo
    
    validate_mx_record || ((errors++))
    echo
    
    # Connectivity tests
    test_smtp_connectivity
    echo
    
    test_smtp_handshake
    echo
    
    test_tls
    echo
    
    # Summary
    if [[ $errors -eq 0 ]]; then
        print_success "All validations passed! Your mail server is properly configured."
    else
        print_warning "$errors validation(s) failed. Please check the DNS configuration."
    fi
    
    echo
    generate_dns_config
}

# Main menu
show_menu() {
    echo
    print_status "DNS Validation and Mail Server Testing Menu"
    echo
    echo "1. Run all validations"
    echo "2. Validate A record"
    echo "3. Validate PTR record"
    echo "4. Validate SPF record"
    echo "5. Validate MX record"
    echo "6. Test SMTP connectivity"
    echo "7. Test SMTP handshake"
    echo "8. Test TLS configuration"
    echo "9. Send test email"
    echo "10. Check mail logs"
    echo "11. Generate DNS configuration"
    echo "12. Exit"
    echo
}

# Main function
main() {
    check_root
    install_tools
    get_server_ip
    
    while true; do
        show_menu
        read -p "Select an option (1-12): " choice
        
        case $choice in
            1)
                run_all_validations
                ;;
            2)
                validate_a_record
                ;;
            3)
                validate_ptr_record
                ;;
            4)
                validate_spf_record
                ;;
            5)
                validate_mx_record
                ;;
            6)
                test_smtp_connectivity
                ;;
            7)
                test_smtp_handshake
                ;;
            8)
                test_tls
                ;;
            9)
                test_email_sending
                ;;
            10)
                check_mail_logs
                ;;
            11)
                generate_dns_config
                ;;
            12)
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