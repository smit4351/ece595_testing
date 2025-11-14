#!/bin/bash

################################################################################
# BUILD_ON_PI.SH — Build kernel modules on Raspberry Pi 4
#
# Run this script ON the Raspberry Pi after copying the project
#
# Usage:
#   scp -r /path/to/ece595_testing pi@raspberrypi.local:~/
#   ssh pi@raspberrypi.local
#   cd ~/ece595_testing
#   bash BUILD_ON_PI.sh
#
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Building Kernel Modules on Raspberry Pi${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if running on RPi
if ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    echo -e "${RED}[ERROR]${NC} This script must run on Raspberry Pi 4"
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Running on Raspberry Pi"
echo -e "${GREEN}[OK]${NC} Kernel: $(uname -r)"
echo -e "${GREEN}[OK]${NC} Architecture: $(uname -m)"
echo ""

# Install build dependencies
echo -e "${BLUE}Installing build dependencies...${NC}"
sudo apt-get update -qq
sudo apt-get install -y -qq \
    build-essential \
    linux-headers-$(uname -r) \
    device-tree-compiler \
    git \
    make

echo -e "${GREEN}[OK]${NC} Dependencies installed"
echo ""

# Build modules
echo -e "${BLUE}Building kernel modules...${NC}"
cd "$(dirname "$0")/kernel_modules"

make clean 2>&1 | tail -3
echo -e "${GREEN}[OK]${NC} Cleaned build artifacts"
echo ""

make ARCH=arm64 CROSS_COMPILE="" KERNEL_SRC=/lib/modules/$(uname -r)/build 2>&1 | tail -30

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} Build failed"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}Kernel Modules:${NC}"
ls -lh *.ko
echo ""
echo "Next steps:"
echo "  1. Copy to Pi attack runner:"
echo "     cp kernel_modules/*.ko ~/pi_attack_runner/"
echo ""
echo "  2. Load modules:"
echo "     cd ~/pi_attack_runner"
echo "     sudo bash run_attacks.sh --local /path/to/modules"
echo ""
