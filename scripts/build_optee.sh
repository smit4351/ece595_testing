#!/bin/bash
# Automated OP-TEE Build Script for Raspberry Pi 4
# This script automates the complete OP-TEE build process

set -e  # Exit on error

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPTEE_DIR="${PROJECT_ROOT}/optee-project"
BUILD_DIR="${OPTEE_DIR}/build"
OUTPUT_DIR="${PROJECT_ROOT}/output"
LOG_FILE="${PROJECT_ROOT}/build.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Check if running on supported OS
check_os() {
    log_info "Checking operating system..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        log_info "Running on Linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        log_warn "Running on macOS - cross-compilation only"
    else
        log_error "Unsupported OS: $OSTYPE"
        exit 1
    fi
}

# Install required dependencies
install_dependencies() {
    log_info "Installing dependencies..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y \
                android-tools-adb \
                android-tools-fastboot \
                autoconf \
                automake \
                bc \
                bison \
                build-essential \
                ccache \
                cscope \
                curl \
                device-tree-compiler \
                expect \
                flex \
                ftp-upload \
                gdisk \
                iasl \
                libattr1-dev \
                libcap-dev \
                libfdt-dev \
                libftdi-dev \
                libglib2.0-dev \
                libgmp-dev \
                libhidapi-dev \
                libmpc-dev \
                libncurses5-dev \
                libpixman-1-dev \
                libssl-dev \
                libtool \
                make \
                mtools \
                netcat \
                ninja-build \
                python3-crypto \
                python3-cryptography \
                python3-pip \
                python3-pyelftools \
                python3-serial \
                rsync \
                unzip \
                uuid-dev \
                xdg-utils \
                xterm \
                xz-utils \
                zlib1g-dev \
                gcc-aarch64-linux-gnu \
                g++-aarch64-linux-gnu
                
            log_info "Dependencies installed"
        else
            log_error "apt-get not found. Please install dependencies manually."
            exit 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install \
                gcc-arm-embedded \
                python3 \
                dtc \
                coreutils \
                wget \
                gnu-sed
            log_info "macOS dependencies installed"
        else
            log_error "Homebrew not found. Please install: https://brew.sh"
            exit 1
        fi
    fi
    
    # Install Python packages
    pip3 install --user pyelftools cryptography pycryptodome
}

# Install repo tool
install_repo() {
    log_info "Installing repo tool..."
    
    mkdir -p ~/bin
    curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
    chmod a+x ~/bin/repo
    
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
        export PATH=~/bin:$PATH
        echo 'export PATH=~/bin:$PATH' >> ~/.bashrc
    fi
    
    log_info "Repo tool installed"
}

# Clone OP-TEE source
clone_optee() {
    log_info "Cloning OP-TEE source for Raspberry Pi 4..."
    
    if [ -d "${OPTEE_DIR}/.repo" ]; then
        log_warn "OP-TEE already cloned. Syncing..."
        cd "${OPTEE_DIR}"
        repo sync -j$(nproc) 2>&1 | tee -a "${LOG_FILE}"
    else
        mkdir -p "${OPTEE_DIR}"
        cd "${OPTEE_DIR}"
        
        repo init -u https://github.com/OP-TEE/manifest.git \
            -m rpi4.xml \
            2>&1 | tee -a "${LOG_FILE}"
        
        repo sync -j$(nproc) 2>&1 | tee -a "${LOG_FILE}"
    fi
    
    cd "${PROJECT_ROOT}"
    log_info "OP-TEE source ready"
}

# Configure build environment
configure_environment() {
    log_info "Configuring build environment..."
    
    export ARCH=arm64
    export CROSS_COMPILE=aarch64-linux-gnu-
    export PLATFORM=rpi4
    
    log_info "Environment configured for ${PLATFORM}"
}

# Build OP-TEE
build_optee() {
    log_info "Building OP-TEE for Raspberry Pi 4..."
    log_info "This may take 30-60 minutes depending on your system..."
    
    cd "${OPTEE_DIR}/build"
    
    # Clean previous build if requested
    if [ "$1" == "clean" ]; then
        log_info "Cleaning previous build..."
        make -f rpi4.mk clean 2>&1 | tee -a "${LOG_FILE}"
    fi
    
    # Build all components
    make -f rpi4.mk -j$(nproc) 2>&1 | tee -a "${LOG_FILE}"
    
    cd "${PROJECT_ROOT}"
    log_info "OP-TEE build complete"
}

# Extract build artifacts
extract_artifacts() {
    log_info "Extracting build artifacts..."
    
    mkdir -p "${OUTPUT_DIR}"
    
    # Copy kernel image
    if [ -f "${OPTEE_DIR}/linux/arch/arm64/boot/Image" ]; then
        cp "${OPTEE_DIR}/linux/arch/arm64/boot/Image" "${OUTPUT_DIR}/"
        log_info "Copied kernel Image"
    fi
    
    # Copy device tree
    if [ -f "${OPTEE_DIR}/linux/arch/arm64/boot/dts/broadcom/bcm2711-rpi-4-b.dtb" ]; then
        cp "${OPTEE_DIR}/linux/arch/arm64/boot/dts/broadcom/bcm2711-rpi-4-b.dtb" "${OUTPUT_DIR}/"
        log_info "Copied device tree"
    fi
    
    # Copy OP-TEE OS
    if [ -f "${OPTEE_DIR}/optee_os/out/arm/core/tee-pager_v2.bin" ]; then
        cp "${OPTEE_DIR}/optee_os/out/arm/core/tee-pager_v2.bin" "${OUTPUT_DIR}/"
        log_info "Copied OP-TEE OS"
    fi
    
    # Copy U-Boot
    if [ -f "${OPTEE_DIR}/u-boot/u-boot.bin" ]; then
        cp "${OPTEE_DIR}/u-boot/u-boot.bin" "${OUTPUT_DIR}/"
        log_info "Copied U-Boot"
    fi
    
    # Copy root filesystem
    if [ -f "${OPTEE_DIR}/out-br/images/rootfs.cpio.gz" ]; then
        cp "${OPTEE_DIR}/out-br/images/rootfs.cpio.gz" "${OUTPUT_DIR}/"
        log_info "Copied root filesystem"
    fi
    
    log_info "Artifacts extracted to ${OUTPUT_DIR}"
}

# Generate SD card image
generate_sd_image() {
    log_info "Generating SD card image..."
    
    cd "${OPTEE_DIR}/build"
    make -f rpi4.mk img-help 2>&1 | tee -a "${LOG_FILE}"
    
    log_info "To create SD card image, run:"
    log_info "  cd ${OPTEE_DIR}/build"
    log_info "  make -f rpi4.mk img"
    
    cd "${PROJECT_ROOT}"
}

# Print build summary
print_summary() {
    echo ""
    echo "=========================================="
    echo "OP-TEE Build Complete!"
    echo "=========================================="
    echo ""
    echo "Build artifacts:"
    echo "  Output directory: ${OUTPUT_DIR}"
    echo "  Log file: ${LOG_FILE}"
    echo ""
    echo "Next steps:"
    echo "  1. Create SD card image:"
    echo "     cd ${OPTEE_DIR}/build && make -f rpi4.mk img"
    echo ""
    echo "  2. Flash to SD card:"
    echo "     sudo dd if=${OPTEE_DIR}/build/out-br/images/sdcard.img of=/dev/sdX bs=4M status=progress"
    echo "     (Replace /dev/sdX with your SD card device)"
    echo ""
    echo "  3. Insert SD card into Raspberry Pi 4 and boot"
    echo ""
    echo "  4. Connect via serial console:"
    echo "     screen /dev/ttyUSB0 115200"
    echo ""
    echo "For more information, see:"
    echo "  https://optee.readthedocs.io/en/latest/building/devices/rpi4.html"
    echo ""
}

# Main function
main() {
    log_info "================================================"
    log_info "OP-TEE Automated Build Script for Raspberry Pi 4"
    log_info "================================================"
    log_info "Started at: $(date)"
    log_info ""
    
    # Check prerequisites
    check_os
    
    # Install dependencies
    if [ "$1" != "--skip-deps" ]; then
        install_dependencies
        install_repo
    else
        log_warn "Skipping dependency installation"
    fi
    
    # Clone and build
    clone_optee
    configure_environment
    build_optee "$2"
    extract_artifacts
    
    log_info "Completed at: $(date)"
    print_summary
}

# Handle command line arguments
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --skip-deps    Skip dependency installation"
    echo "  --clean        Clean before building"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                      # Full build with dependencies"
    echo "  $0 --skip-deps          # Build without installing dependencies"
    echo "  $0 --skip-deps --clean  # Clean build without installing dependencies"
    exit 0
fi

# Run main function
main "$@"
