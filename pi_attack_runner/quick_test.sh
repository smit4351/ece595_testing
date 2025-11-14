#!/bin/bash

################################################################################
# QUICK_TEST.SH — Fast Test of Attack Modules
#
# Quick demonstration of how to use the attack runner
# Run this to get familiar with the system
################################################################################

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

main() {
    print_header "OP-TEE Attack Quick Test"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_warning "This script needs root. Run: sudo $0"
        exit 1
    fi
    
    # Step 1: Show configuration
    print_header "Step 1: Configuration"
    print_info "Modules directory: $MODULES_DIR"
    print_info "Results directory: $RESULTS_DIR"
    print_info "Default timeout: ${ATTACK_TIMEOUT_SEC}s"
    print_info "Target address: $DEFAULT_TARGET_ADDR"
    echo ""
    
    # Step 2: Check for modules
    print_header "Step 2: Available Modules"
    
    if [[ ! -d "$MODULES_DIR" ]]; then
        print_warning "Modules directory doesn't exist yet"
        print_info "Copy your .ko files here: cp kernel_modules/*.ko $MODULES_DIR/"
        exit 1
    fi
    
    local ko_files=($(find "$MODULES_DIR" -name "*.ko" -type f))
    
    if [[ ${#ko_files[@]} -eq 0 ]]; then
        print_warning "No .ko files found in $MODULES_DIR"
        exit 1
    fi
    
    print_ok "Found ${#ko_files[@]} module(s):"
    for ko in "${ko_files[@]}"; do
        echo "  - $(basename "$ko")"
    done
    echo ""
    
    # Step 3: Test module loading
    print_header "Step 3: Module Loading Test"
    
    for ko in "${ko_files[@]}"; do
        local module_name=$(basename "$ko" .ko)
        print_info "Testing: $module_name"
        
        # Load
        if insmod "$ko" 2>&1 | grep -v "^$"; then
            print_ok "Loaded successfully"
        else
            print_warning "Load failed (may already be loaded)"
        fi
        
        # Verify
        if lsmod | grep -q "^${module_name}"; then
            print_ok "Verified in lsmod"
        else
            print_warning "Not in lsmod"
        fi
        
        # Unload
        if rmmod "$module_name" 2>/dev/null; then
            print_ok "Unloaded successfully"
        else
            print_warning "Unload failed"
        fi
        
        echo ""
    done
    
    # Step 4: Show next steps
    print_header "Next Steps"
    
    echo "To run attacks:"
    echo "  1. Load a module:   insmod $MODULES_DIR/dma_attack.ko"
    echo "  2. Check status:    cat /proc/dma_attack"
    echo "  3. Start attack:    echo 'start' > /proc/dma_attack"
    echo "  4. Collect results: ./collect_results.sh --output ~/results/"
    echo ""
    
    echo "Or use the automated runner:"
    echo "  sudo ./run_attacks.sh --local $MODULES_DIR"
    echo ""
    
    print_ok "Quick test complete!"
}

main "$@"
