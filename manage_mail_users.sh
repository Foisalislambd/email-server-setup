#!/bin/bash

# =============================================================================
# Mail User Management Script
# For standalone Postfix mail server
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

# Function to create mail user
create_mail_user() {
    print_status "Creating mail user..."
    
    read -p "Enter username for mail user: " USERNAME
    read -s -p "Enter password for $USERNAME: " PASSWORD
    echo
    
    # Check if user already exists
    if id "$USERNAME" &>/dev/null; then
        print_warning "User $USERNAME already exists"
        read -p "Do you want to update the password? (y/N): " update_pass
        if [[ $update_pass =~ ^[Yy]$ ]]; then
            echo "$USERNAME:$PASSWORD" | chpasswd
            print_success "Password updated for user $USERNAME"
        fi
    else
        # Create user
        useradd -m -s /bin/bash "$USERNAME"
        echo "$USERNAME:$PASSWORD" | chpasswd
        
        # Add to mail group
        usermod -a -G mail "$USERNAME"
        
        print_success "User $USERNAME created successfully"
    fi
    
    # Create mail directory
    mkdir -p "/home/$USERNAME/Maildir"
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/Maildir"
    chmod 755 "/home/$USERNAME/Maildir"
    
    print_status "Mail directory created for $USERNAME"
}

# Function to list mail users
list_mail_users() {
    print_status "Mail users on this system:"
    echo
    
    # Get users in mail group
    getent group mail | cut -d: -f4 | tr ',' '\n' | while read -r user; do
        if [[ -n "$user" ]]; then
            echo "Username: $user"
            echo "Home: $(getent passwd "$user" | cut -d: -f6)"
            echo "Shell: $(getent passwd "$user" | cut -d: -f7)"
            echo "Last login: $(last -1 "$user" 2>/dev/null | head -1 | awk '{print $4, $5, $6, $7}' || echo "Never")"
            echo "---"
        fi
    done
}

# Function to delete mail user
delete_mail_user() {
    print_status "Delete mail user..."
    
    read -p "Enter username to delete: " USERNAME
    
    if ! id "$USERNAME" &>/dev/null; then
        print_error "User $USERNAME does not exist"
        return 1
    fi
    
    print_warning "This will permanently delete user $USERNAME and all their data"
    read -p "Are you sure? (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # Remove from mail group
        deluser "$USERNAME" mail 2>/dev/null || true
        
        # Delete user and home directory
        userdel -r "$USERNAME" 2>/dev/null || userdel "$USERNAME"
        
        print_success "User $USERNAME deleted"
    else
        print_status "Operation cancelled"
    fi
}

# Function to change user password
change_user_password() {
    print_status "Change user password..."
    
    read -p "Enter username: " USERNAME
    
    if ! id "$USERNAME" &>/dev/null; then
        print_error "User $USERNAME does not exist"
        return 1
    fi
    
    read -s -p "Enter new password for $USERNAME: " NEW_PASSWORD
    echo
    
    echo "$USERNAME:$NEW_PASSWORD" | chpasswd
    print_success "Password changed for user $USERNAME"
}

# Function to test mail user authentication
test_mail_auth() {
    print_status "Testing mail authentication..."
    
    read -p "Enter username to test: " USERNAME
    read -s -p "Enter password: " PASSWORD
    echo
    
    if ! id "$USERNAME" &>/dev/null; then
        print_error "User $USERNAME does not exist"
        return 1
    fi
    
    # Test authentication using saslauthd
    if command -v testsaslauthd &> /dev/null; then
        if echo "$PASSWORD" | testsaslauthd -u "$USERNAME" -r "$DOMAIN" -s smtp; then
            print_success "Authentication successful for $USERNAME"
        else
            print_error "Authentication failed for $USERNAME"
        fi
    else
        print_warning "testsaslauthd not available, cannot test authentication"
        print_status "You can test by sending an email from your website"
    fi
}

# Function to show mail user statistics
show_mail_stats() {
    print_status "Mail server statistics:"
    echo
    
    # Count mail users
    local user_count=$(getent group mail | cut -d: -f4 | tr ',' '\n' | grep -c . || echo "0")
    echo "Total mail users: $user_count"
    
    # Show mail queue
    echo
    print_status "Current mail queue:"
    mailq | head -20
    
    # Show recent mail logs
    echo
    print_status "Recent mail activity (last 10 entries):"
    tail -10 /var/log/mail.log 2>/dev/null || echo "No mail logs found"
}

# Function to configure mail aliases
configure_aliases() {
    print_status "Configuring mail aliases..."
    
    echo
    echo "Current aliases:"
    cat /etc/postfix/aliases | grep -v "^#" | grep -v "^$"
    echo
    
    read -p "Add new alias? (y/N): " add_alias
    
    if [[ $add_alias =~ ^[Yy]$ ]]; then
        read -p "Enter alias name (e.g., admin): " ALIAS_NAME
        read -p "Enter destination (e.g., realuser@100to1shot.com): " ALIAS_DEST
        
        # Add alias
        echo "$ALIAS_NAME: $ALIAS_DEST" >> /etc/postfix/aliases
        
        # Update aliases database
        newaliases
        
        print_success "Alias $ALIAS_NAME -> $ALIAS_DEST added"
    fi
}

# Function to show SMTP configuration
show_smtp_config() {
    print_status "Current SMTP configuration:"
    echo
    
    echo "Hostname: $(postconf -h myhostname)"
    echo "Domain: $(postconf -h mydomain)"
    echo "SASL Auth: $(postconf -h smtpd_sasl_auth_enable)"
    echo "TLS: $(postconf -h smtpd_use_tls)"
    echo "Submission Port: $(netstat -tlnp | grep :587 || echo "Not listening")"
    echo "SMTP Port: $(netstat -tlnp | grep :25 || echo "Not listening")"
    
    echo
    print_status "Website SMTP settings:"
    echo "Server: mail.100to1shot.com"
    echo "Port: 587 (TLS) or 465 (SSL)"
    echo "Authentication: Required"
    echo "Use local system user credentials"
}

# Main menu
show_menu() {
    echo
    print_status "Mail User Management Menu"
    echo
    echo "1. Create mail user"
    echo "2. List mail users"
    echo "3. Delete mail user"
    echo "4. Change user password"
    echo "5. Test mail authentication"
    echo "6. Show mail statistics"
    echo "7. Configure mail aliases"
    echo "8. Show SMTP configuration"
    echo "9. Exit"
    echo
}

# Main function
main() {
    check_root
    
    # Set domain
    DOMAIN="100to1shot.com"
    
    while true; do
        show_menu
        read -p "Select an option (1-9): " choice
        
        case $choice in
            1)
                create_mail_user
                ;;
            2)
                list_mail_users
                ;;
            3)
                delete_mail_user
                ;;
            4)
                change_user_password
                ;;
            5)
                test_mail_auth
                ;;
            6)
                show_mail_stats
                ;;
            7)
                configure_aliases
                ;;
            8)
                show_smtp_config
                ;;
            9)
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