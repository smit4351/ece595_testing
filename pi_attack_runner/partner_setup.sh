#!/bin/bash

################################################################################
# PARTNER_SETUP.SH — Setup Guide for Pi Partner
#
# One-time setup script for the partner to prepare the Pi
################################################################################

set -o pipefail

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

main() {
    print_header "OP-TEE Attack Runner Setup for Raspberry Pi"
    
    # Check if running on Pi
    if ! uname -m | grep -q "aarch64\|armv7l"; then
        print_error "This script should run on Raspberry Pi (ARM architecture)"
        exit 1
    fi
    
    # Step 1: Verify OP-TEE
    print_header "Step 1: Verifying OP-TEE Installation"
    
    if command -v optee-os &> /dev/null; then
        print_ok "OP-TEE found"
    else
        print_info "Checking if OP-TEE is already running..."
        if dmesg | grep -qi "optee"; then
            print_ok "OP-TEE is running (found in dmesg)"
        else
            print_error "OP-TEE not detected. Please install OP-TEE first."
            exit 1
        fi
    fi
    echo ""
    
    # Step 2: Create directories
    print_header "Step 2: Creating Directories"
    
    mkdir -p /tmp/attacks
    mkdir -p /var/log/optee_attacks
    mkdir -p ~/attack_results
    
    print_ok "Created /tmp/attacks"
    print_ok "Created /var/log/optee_attacks"
    print_ok "Created ~/attack_results"
    echo ""
    
    # Step 3: Check permissions
    print_header "Step 3: Checking Permissions"
    
    if [[ -w /proc ]]; then
        print_ok "Can write to /proc (good for /proc interfaces)"
    else
        print_error "Cannot write to /proc. May need sudo for full functionality."
    fi
    
    if [[ -w /tmp/attacks ]]; then
        print_ok "Can write to /tmp/attacks"
    else
        print_error "Cannot write to /tmp/attacks"
    fi
    echo ""
    
    # Step 4: Verify tools
    print_header "Step 4: Verifying Required Tools"
    
    local required_tools=("insmod" "rmmod" "modinfo" "dmesg" "grep" "curl" "unzip")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            print_ok "Found: $tool"
        else
            print_error "Missing: $tool"
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing tools: ${missing_tools[@]}"
        print_info "Install with: sudo apt-get install -y ${missing_tools[@]}"
        exit 1
    fi
    echo ""
    
    # Step 5: System info
    print_header "Step 5: System Information"
    
    print_info "Device: $(cat /proc/device-tree/model 2>/dev/null || echo 'Unknown')"
    print_info "Kernel: $(uname -r)"
    print_info "Architecture: $(uname -m)"
    print_info "CPU Cores: $(nproc)"
    print_info "Memory: $(free -h | grep Mem | awk '{print $2}')"
    echo ""
    
    # Step 6: Download attack runner (if needed)
    print_header "Step 6: Download Attack Runner"
    
    if [[ -f "$(dirname "$0")/run_attacks.sh" ]]; then
        print_ok "Attack runner already present"
    else
        print_info "Download from your macOS:"
        print_info "  scp -r pi_attack_runner pi@raspberrypi.local:~/"
    fi
    echo ""
    
    # Step 7: Summary
    print_header "Setup Complete!"
    
    echo "Next steps:"
    echo ""
    echo "1. Ask for kernel modules from your partner:"
    echo "   scp -r you@your-mac:ece595_testing/kernel_modules/*.ko /tmp/attacks/"
    echo ""
    echo "2. Make attack runner executable:"
    echo "   chmod +x ~/pi_attack_runner/*.sh"
    echo ""
    echo "3. Run a quick test:"
    echo "   sudo ~/pi_attack_runner/quick_test.sh"
    echo ""
    echo "4. Execute attacks:"
    echo "   sudo ~/pi_attack_runner/run_attacks.sh --local /tmp/attacks"
    echo ""
    echo "5. Collect results:"
    echo "   sudo ~/pi_attack_runner/collect_results.sh --output ~/attack_results/"
    echo ""
    echo "6. Send results back to your partner:"
    echo "   scp -r ~/attack_results you@your-mac:~/results/"
    echo ""
    
    print_ok "Ready to run attacks!"
}

main "$@"
