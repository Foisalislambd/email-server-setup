#!/bin/bash

# =============================================================================
# Install Script for SMTP Test Project
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

# Function to check if Node.js is installed
check_nodejs() {
    if command -v node &> /dev/null; then
        print_success "Node.js is installed: $(node --version)"
    else
        print_error "Node.js is not installed"
        print_status "Installing Node.js..."
        
        # Install Node.js
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        apt-get install -y nodejs
        
        print_success "Node.js installed: $(node --version)"
    fi
}

# Function to install npm dependencies
install_dependencies() {
    print_status "Installing npm dependencies..."
    
    if [[ -f package.json ]]; then
        npm install
        print_success "Dependencies installed"
    else
        print_error "package.json not found"
        exit 1
    fi
}

# Function to set up test files
setup_test_files() {
    print_status "Setting up test files..."
    
    # Make scripts executable
    chmod +x *.js 2>/dev/null || true
    
    print_success "Test files set up"
}

# Function to setup environment file
setup_env() {
    print_status "Setting up environment configuration..."
    
    if [[ ! -f .env ]]; then
        cp .env.example .env
        print_success "Created .env file from .env.example"
    else
        print_warning ".env file already exists"
    fi
}

# Function to show usage instructions
show_instructions() {
    print_success "SMTP Test Project installed successfully!"
    echo
    print_status "Next steps:"
    echo
    echo "1. Configure your environment variables:"
    echo "   nano .env"
    echo
    echo "2. Set your password in the .env file:"
    echo "   SMTP_PASS=your_actual_password_here"
    echo
    echo "3. Run the tests:"
    echo "   npm run test-simple  # Quick test"
    echo "   npm run test         # Comprehensive test"
    echo "   npm run test-debug   # Debug mode"
    echo
    echo "4. Check the README.md for more details"
    echo
    print_warning "Don't forget to set your password in the .env file!"
}

# Main function
main() {
    print_status "Installing SMTP Test Project..."
    
    check_nodejs
    install_dependencies
    setup_test_files
    setup_env
    show_instructions
    
    print_success "Installation complete!"
}

# Run main function
main "$@"