#!/bin/bash

# =============================================================================
# Fix Nodemailer Method Name
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

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to fix the nodemailer method name
fix_nodemailer() {
    print_status "Fixing nodemailer method name in test files..."
    
    # Fix simple-test.js
    if [[ -f simple-test.js ]]; then
        sed -i 's/nodemailer\.createTransporter/nodemailer.createTransport/g' simple-test.js
        print_success "Fixed simple-test.js"
    fi
    
    # Fix test-smtp.js
    if [[ -f test-smtp.js ]]; then
        sed -i 's/nodemailer\.createTransporter/nodemailer.createTransport/g' test-smtp.js
        print_success "Fixed test-smtp.js"
    fi
    
    print_success "All nodemailer method names fixed!"
}

# Function to test the fix
test_fix() {
    print_status "Testing the fix..."
    
    if [[ -f simple-test.js ]]; then
        print_status "Running simple test..."
        node simple-test.js
    else
        print_error "simple-test.js not found"
    fi
}

# Main function
main() {
    print_status "Starting nodemailer fix..."
    
    fix_nodemailer
    test_fix
    
    print_success "Fix completed!"
}

# Run main function
main "$@"