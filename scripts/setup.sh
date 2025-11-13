#!/bin/bash
# Master Setup Script - Complete Automated Setup
# Single command to setup entire ARM TrustZone exploitation environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_phase() { echo -e "${MAGENTA}[PHASE]${NC} $1"; }

# Detect environment
detect_environment() {
    log_phase "Detecting environment..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        ENV_TYPE="linux"
        log_info "Environment: Linux"
        
        # Check if Raspberry Pi
        if [ -f "/proc/device-tree/model" ]; then
            model=$(cat /proc/device-tree/model)
            if [[ "$model" == *"Raspberry Pi 4"* ]]; then
                ENV_TYPE="rpi4"
                log_info "Platform: Raspberry Pi 4"
            fi
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        ENV_TYPE="macos"
        log_info "Environment: macOS (development host)"
    else
        log_error "Unsupported OS: $OSTYPE"
        exit 1
    fi
}

# Phase 1: Development Environment Setup
setup_development_environment() {
    log_phase "PHASE 1: Setting up development environment"
    
    log_step "Creating directory structure..."
    mkdir -p "${PROJECT_ROOT}"/{scanners,exploits,fuzzers,analysis,reports,results,logs,output}
    log_info "Directory structure created ✓"
    
    log_step "Installing system dependencies..."
    if [[ "$ENV_TYPE" == "linux" ]] || [[ "$ENV_TYPE" == "rpi4" ]]; then
        if command -v apt-get &> /dev/null; then
            log_info "Installing via apt-get..."
            sudo apt-get update || log_warn "apt-get update failed"
            sudo apt-get install -y \
                build-essential git python3 python3-pip \
                gcc-aarch64-linux-gnu device-tree-compiler \
                libssl-dev flex bison bc || log_warn "Some packages failed"
        fi
    elif [[ "$ENV_TYPE" == "macos" ]]; then
        if command -v brew &> /dev/null; then
            log_info "Installing via Homebrew..."
            brew install python3 dtc coreutils gnu-sed || log_warn "Some packages failed"
        else
            log_warn "Homebrew not found. Install from https://brew.sh"
        fi
    fi
    
    log_step "Installing Python packages..."
    pip3 install --user pyserial pexpect matplotlib pandas colorama tqdm requests || log_warn "Some Python packages failed"
    
    log_info "Development environment setup complete ✓"
}

# Phase 2: OP-TEE Build (if not on Pi)
build_optee() {
    if [[ "$ENV_TYPE" == "rpi4" ]]; then
        log_info "Running on Pi - skipping OP-TEE build (should be pre-built)"
        return
    fi
    
    log_phase "PHASE 2: Building OP-TEE"
    
    read -p "Build OP-TEE from source? This takes 30-60 minutes. (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        bash "${SCRIPT_DIR}/build_optee.sh"
    else
        log_info "Skipping OP-TEE build"
    fi
}

# Phase 3: Compile Attack Tools
compile_attack_tools() {
    log_phase "PHASE 3: Compiling attack tools"
    
    log_step "Compiling hardware scanner..."
    if [ -f "${PROJECT_ROOT}/hardware_scanner.c.template" ]; then
        cp "${PROJECT_ROOT}/hardware_scanner.c.template" "${PROJECT_ROOT}/scanners/hardware_scanner.c"
        cd "${PROJECT_ROOT}/scanners"
        
        if [[ "$ENV_TYPE" == "rpi4" ]]; then
            gcc -o hardware_scanner hardware_scanner.c -Wall || log_warn "Scanner compilation failed"
        else
            aarch64-linux-gnu-gcc -o hardware_scanner hardware_scanner.c -Wall || log_warn "Scanner cross-compilation failed"
        fi
        
        log_info "Hardware scanner compiled ✓"
        cd "${PROJECT_ROOT}"
    fi
    
    log_step "Compiling kernel modules..."
    cd "${PROJECT_ROOT}/kernel_modules"
    
    if [[ "$ENV_TYPE" == "rpi4" ]]; then
        # Native compile on Pi
        make ARCH=arm64 CROSS_COMPILE= || log_warn "Kernel module compilation failed"
    else
        # Cross-compile
        if [ -d "${PROJECT_ROOT}/optee-project/linux" ]; then
            make KERNEL_SRC="${PROJECT_ROOT}/optee-project/linux" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- || log_warn "Kernel module cross-compilation failed"
        else
            log_warn "Kernel source not found. Modules will need to be compiled on Pi."
        fi
    fi
    
    cd "${PROJECT_ROOT}"
    log_info "Attack tools compiled ✓"
}

# Phase 4: Generate Configuration
generate_configuration() {
    log_phase "PHASE 4: Generating configuration"
    
    if [[ "$ENV_TYPE" == "rpi4" ]]; then
        log_step "Parsing device tree..."
        bash "${SCRIPT_DIR}/parse_device_tree.sh" "${PROJECT_ROOT}/optee_memory_config.sh"
        
        if [ -f "${PROJECT_ROOT}/optee_memory_config.sh" ]; then
            log_info "Configuration generated ✓"
            cat "${PROJECT_ROOT}/optee_memory_config.sh"
        fi
    else
        log_info "Not on Pi - device tree parsing skipped"
        log_info "Default configuration will be used on deployment"
    fi
}

# Phase 5: Run Tests (if on Pi)
run_tests() {
    if [[ "$ENV_TYPE" != "rpi4" ]]; then
        log_info "Not on Pi - skipping tests"
        return
    fi
    
    log_phase "PHASE 5: Running tests"
    
    read -p "Run deployment and tests now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        bash "${SCRIPT_DIR}/deploy.sh"
    else
        log_info "Skipping deployment. Run manually with: ./scripts/deploy.sh"
    fi
}

# Print final instructions
print_final_instructions() {
    echo ""
    echo "=========================================="
    echo "Setup Complete!"
    echo "=========================================="
    echo ""
    
    if [[ "$ENV_TYPE" == "rpi4" ]]; then
        echo "✓ Running on Raspberry Pi 4"
        echo ""
        echo "Next steps:"
        echo "  1. Deploy and run attacks:"
        echo "     ./scripts/deploy.sh"
        echo ""
        echo "  2. Or load modules manually:"
        echo "     cd kernel_modules"
        echo "     sudo insmod dma_attack.ko"
        echo "     sudo insmod smc_fuzzer.ko"
        echo ""
        echo "  3. Use module interfaces:"
        echo "     cat /proc/dma_attack"
        echo "     cat /proc/smc_fuzzer"
        echo ""
    else
        echo "✓ Development environment configured"
        echo ""
        echo "Next steps:"
        echo "  1. Flash SD card with OP-TEE:"
        if [ -d "${PROJECT_ROOT}/optee-project" ]; then
            echo "     cd optee-project/build"
            echo "     make -f rpi4.mk img"
            echo "     sudo dd if=out-br/images/sdcard.img of=/dev/sdX bs=4M"
        else
            echo "     Build OP-TEE first: ./scripts/build_optee.sh"
        fi
        echo ""
        echo "  2. Copy project to SD card or transfer to Pi:"
        echo "     scp -r ${PROJECT_ROOT} pi@raspberrypi.local:~/"
        echo ""
        echo "  3. On Raspberry Pi, run:"
        echo "     cd ece595_testing"
        echo "     ./scripts/setup.sh"
        echo "     ./scripts/deploy.sh"
        echo ""
    fi
    
    echo "Documentation:"
    echo "  - README.txt                 - Usage guide"
    echo "  - COMPREHENSIVE_ANALYSIS.md  - Gap analysis"
    echo "  - CODE_EVALUATION_REPORT.md  - Technical details"
    echo ""
    echo "Key files:"
    echo "  - kernel_modules/dma_attack.c   - DMA attack kernel module"
    echo "  - kernel_modules/smc_fuzzer.c   - SMC fuzzing kernel module"
    echo "  - scripts/deploy.sh             - Automated deployment"
    echo "  - scripts/build_optee.sh        - OP-TEE build automation"
    echo ""
}

# Print usage
print_usage() {
    echo "ARM TrustZone Exploitation Suite - Master Setup"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "This script provides complete automated setup for the ARM TrustZone"
    echo "exploitation suite. It detects the environment (development machine"
    echo "vs. Raspberry Pi) and performs appropriate setup steps."
    echo ""
    echo "Options:"
    echo "  --help, -h         Show this help"
    echo "  --skip-optee       Skip OP-TEE build"
    echo "  --skip-deps        Skip dependency installation"
    echo "  --auto             Non-interactive mode"
    echo ""
    echo "Examples:"
    echo "  # Full setup on development machine:"
    echo "  ./scripts/setup.sh"
    echo ""
    echo "  # Setup on Raspberry Pi (skip OP-TEE build):"
    echo "  ./scripts/setup.sh --skip-optee"
    echo ""
    echo "  # Quick setup without dependencies:"
    echo "  ./scripts/setup.sh --skip-deps --skip-optee"
    echo ""
}

# Main function
main() {
    # Parse arguments
    SKIP_OPTEE=false
    SKIP_DEPS=false
    AUTO_MODE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                print_usage
                exit 0
                ;;
            --skip-optee)
                SKIP_OPTEE=true
                shift
                ;;
            --skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            --auto)
                AUTO_MODE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    echo ""
    echo "=========================================="
    echo "ARM TrustZone Exploitation Suite"
    echo "Master Setup Script"
    echo "=========================================="
    echo ""
    
    detect_environment
    
    if [ "$SKIP_DEPS" = false ]; then
        setup_development_environment
    else
        log_info "Skipping dependency installation"
    fi
    
    if [ "$SKIP_OPTEE" = false ]; then
        build_optee
    else
        log_info "Skipping OP-TEE build"
    fi
    
    compile_attack_tools
    generate_configuration
    
    if [ "$AUTO_MODE" = false ]; then
        run_tests
    fi
    
    print_final_instructions
}

# Run main
main "$@"
