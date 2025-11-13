#!/bin/bash
# Device Tree Parser for OP-TEE Memory Regions
# Extracts secure memory addresses from device tree

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Parse device tree for OP-TEE reserved memory
parse_optee_memory() {
    log_info "Parsing device tree for OP-TEE memory regions..."
    
    # Check if running on Raspberry Pi
    if [ ! -d "/proc/device-tree" ]; then
        log_warn "Not running on device with device tree. Using default values."
        echo "# OP-TEE Memory Configuration (DEFAULT VALUES)"
        echo "OPTEE_SECURE_BASE=0x3E000000"
        echo "OPTEE_SECURE_SIZE=0x01000000"
        return
    fi
    
    # Find reserved-memory node
    if [ -d "/proc/device-tree/reserved-memory" ]; then
        log_info "Found /proc/device-tree/reserved-memory"
        
        # Look for OP-TEE node
        for node in /proc/device-tree/reserved-memory/*; do
            if [ -d "$node" ]; then
                node_name=$(basename "$node")
                
                # Check if this is an OP-TEE node
                if [[ "$node_name" == optee* ]] || [ -f "$node/compatible" ]; then
                    compatible=$(cat "$node/compatible" 2>/dev/null | tr '\0' '\n' | head -1)
                    
                    if [[ "$compatible" == *"optee"* ]] || [[ "$node_name" == optee* ]]; then
                        log_info "Found OP-TEE node: $node_name"
                        
                        # Read reg property (address and size)
                        if [ -f "$node/reg" ]; then
                            # Extract hex values from reg property
                            # Format: <address-high address-low size-high size-low>
                            reg_hex=$(xxd -p "$node/reg" | tr -d '\n')
                            
                            # Parse as 64-bit values (8 hex chars each for 32-bit, 16 for 64-bit)
                            # BCM2711 uses 32-bit addresses, so we take pairs of 32-bit values
                            addr_high=${reg_hex:0:8}
                            addr_low=${reg_hex:8:8}
                            size_high=${reg_hex:16:8}
                            size_low=${reg_hex:24:8}
                            
                            # Convert to decimal
                            addr=$(printf "%d" "0x$addr_low")
                            size=$(printf "%d" "0x$size_low")
                            
                            echo "# OP-TEE Memory Configuration (from device tree)"
                            echo "OPTEE_SECURE_BASE=0x$(printf '%08X' $addr)"
                            echo "OPTEE_SECURE_SIZE=0x$(printf '%08X' $size)"
                            echo "OPTEE_SECURE_END=0x$(printf '%08X' $((addr + size)))"
                            echo ""
                            echo "# Human-readable"
                            echo "# Base: $addr ($(($addr / 1024 / 1024)) MB)"
                            echo "# Size: $size ($(($size / 1024 / 1024)) MB)"
                            
                            return 0
                        fi
                    fi
                fi
            fi
        done
    fi
    
    log_warn "OP-TEE memory region not found in device tree"
    log_warn "Using default values for Raspberry Pi 4"
    
    echo "# OP-TEE Memory Configuration (DEFAULT VALUES)"
    echo "OPTEE_SECURE_BASE=0x3E000000"
    echo "OPTEE_SECURE_SIZE=0x01000000"
}

# Parse and save to file
OUTPUT_FILE="${1:-optee_memory_config.sh}"

log_info "Parsing OP-TEE memory configuration..."
parse_optee_memory > "$OUTPUT_FILE"

log_info "Configuration saved to: $OUTPUT_FILE"
log_info "Source this file to use: source $OUTPUT_FILE"

cat "$OUTPUT_FILE"
