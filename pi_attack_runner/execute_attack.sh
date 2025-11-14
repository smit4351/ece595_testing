#!/bin/bash

################################################################################
# EXECUTE_ATTACK.SH — Run Individual Attack Module
#
# Usage:
#   ./execute_attack.sh --module MODULE_NAME [OPTIONS]
#
# OPTIONS:
#   --module NAME       Attack module name (e.g., dma_attack, smc_fuzzer)
#   --timeout SECONDS   Attack execution timeout (default: 60)
#   --target ADDRESS    Target address in hex (default: 0xc0000000)
#   --verbose           Show detailed output
#   --debug             Enable debug output
#   --keep-loaded       Don't unload module after attack
################################################################################

set -o pipefail

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# =============================================================================
# VARIABLES
# =============================================================================

MODULE_NAME=""
TIMEOUT_SEC=60
TARGET_ADDR="0xc0000000"
VERBOSE=0
DEBUG=0
KEEP_LOADED=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

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

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Find module file
find_module_file() {
    local module_name="$1"
    local module_file=""
    
    # Check various locations
    for dir in "$MODULES_DIR" /lib/modules /tmp/attacks /root /home/pi; do
        if [[ -f "${dir}/${module_name}.ko" ]]; then
            module_file="${dir}/${module_name}.ko"
            break
        fi
    done
    
    if [[ -z "$module_file" ]]; then
        print_error "Module file not found: ${module_name}.ko"
        return 1
    fi
    
    echo "$module_file"
    return 0
}

# Get proc interface for module
get_proc_interface() {
    local module_name="$1"
    
    case "$module_name" in
        dma_attack)
            echo "$DMA_INTERFACE"
            ;;
        smc_fuzzer)
            echo "$SMC_INTERFACE"
            ;;
        *)
            echo "/proc/${module_name}"
            ;;
    esac
}

# Load module
load_module() {
    local module_file="$1"
    local module_name=$(basename "$module_file" .ko)
    
    print_info "Loading module: $module_name"
    
    # Check if already loaded
    if lsmod | grep -q "^${module_name}"; then
        print_warning "Module already loaded, unloading first"
        rmmod "$module_name" 2>/dev/null || {
            print_warning "Failed to unload, trying anyway"
        }
        sleep 0.5
    fi
    
    # Load the module
    if insmod "$module_file" 2>&1; then
        print_ok "Module loaded: $module_name"
        sleep 0.5
        return 0
    else
        print_error "Failed to load module"
        dmesg | grep -i "error\|failed" | tail -5 >&2
        return 1
    fi
}

# Verify module loaded
verify_module() {
    local module_name="$1"
    
    if ! lsmod | grep -q "^${module_name}"; then
        print_error "Module not in lsmod: $module_name"
        return 1
    fi
    
    print_ok "Module verified in lsmod"
    return 0
}

# Check if proc interface exists
check_proc_interface() {
    local proc_interface="$1"
    
    if [[ ! -e "$proc_interface" ]]; then
        print_warning "Proc interface not found: $proc_interface"
        print_info "Module initialization may have failed"
        return 1
    fi
    
    print_ok "Proc interface found: $proc_interface"
    return 0
}

# Execute attack via /proc interface
execute_via_proc() {
    local proc_interface="$1"
    local target_addr="$2"
    local timeout_sec="$3"
    
    print_header "Executing Attack"
    
    # Save dmesg before
    local dmesg_before_file="/tmp/dmesg_before_$$.txt"
    dmesg > "$dmesg_before_file"
    
    # Set target address if supported
    print_info "Setting target address: $target_addr"
    if echo "target:$target_addr" > "$proc_interface" 2>/dev/null; then
        print_ok "Target address set"
    else
        print_warning "Could not set target address (interface may not support it)"
    fi
    
    # Start attack
    print_info "Starting attack (timeout: ${timeout_sec}s)..."
    local start_time=$(date +%s)
    
    if ! echo "start" > "$proc_interface" 2>&1; then
        print_error "Failed to start attack"
        return 1
    fi
    
    print_ok "Attack started"
    
    # Monitor execution
    local elapsed=0
    local last_dmesg_line=0
    
    while [[ $elapsed -lt $timeout_sec ]]; do
        sleep 0.5
        elapsed=$(($(date +%s) - start_time))
        
        # Check for crash indicators
        if dmesg | tail -5 | grep -qi "panic\|oops\|segmentation\|fault\|killed"; then
            print_warning "Crash detected!"
            break
        fi
        
        # Show progress every 10 seconds
        if [[ $((elapsed % 10)) -eq 0 ]] && [[ $elapsed -gt 0 ]]; then
            print_info "Running... ${elapsed}/${timeout_sec}s"
        fi
    done
    
    print_info "Attack execution time: ${elapsed}s"
    
    # Get results from /proc
    print_header "Attack Results"
    
    local proc_output=""
    if [[ -e "$proc_interface" ]]; then
        proc_output=$(cat "$proc_interface" 2>/dev/null)
        echo "$proc_output" | head -20
        print_ok "Results from $proc_interface"
    else
        print_warning "Proc interface no longer available (module may have crashed)"
    fi
    
    # Extract relevant dmesg output
    print_header "Kernel Messages"
    
    local dmesg_after_file="/tmp/dmesg_after_$$.txt"
    dmesg > "$dmesg_after_file"
    
    # Show new dmesg lines
    local new_lines=$(comm -13 <(sort "$dmesg_before_file") <(sort "$dmesg_after_file"))
    if [[ -n "$new_lines" ]]; then
        echo "$new_lines" | head -30
        print_ok "$(echo "$new_lines" | wc -l) kernel messages captured"
    else
        print_warning "No new kernel messages"
    fi
    
    # Save to file
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local results_file="$RESULTS_DIR/attack_${MODULE_NAME}_${timestamp}.txt"
    
    {
        echo "=== Attack Execution: $MODULE_NAME ==="
        echo "Timestamp: $(date)"
        echo "Target Address: $target_addr"
        echo "Timeout: ${timeout_sec}s"
        echo "Actual Duration: ${elapsed}s"
        echo ""
        echo "=== Proc Interface Output ==="
        echo "$proc_output"
        echo ""
        echo "=== Kernel Messages ==="
        echo "$new_lines"
    } > "$results_file"
    
    print_ok "Results saved to: $results_file"
    
    # Cleanup
    rm -f "$dmesg_before_file" "$dmesg_after_file"
    
    return 0
}

# Unload module
unload_module() {
    local module_name="$1"
    
    print_info "Unloading module: $module_name"
    
    if ! lsmod | grep -q "^${module_name}"; then
        print_warning "Module not loaded"
        return 0
    fi
    
    if rmmod "$module_name" 2>&1; then
        print_ok "Module unloaded"
        return 0
    else
        print_error "Failed to unload module"
        return 1
    fi
}

# Print usage
print_usage() {
    cat << EOF
Usage: $0 --module MODULE_NAME [OPTIONS]

REQUIRED:
  --module NAME           Attack module name (e.g., dma_attack, smc_fuzzer)

OPTIONS:
  --timeout SECONDS       Execution timeout in seconds (default: 60)
  --target ADDRESS        Target Secure World address in hex (default: 0xc0000000)
  --verbose              Verbose output
  --debug                Debug mode (set -x)
  --keep-loaded          Don't unload module after execution
  --help                 Show this help message

EXAMPLES:
  $0 --module dma_attack
  $0 --module dma_attack --target 0xc0001000 --timeout 30
  $0 --module smc_fuzzer --timeout 120 --verbose
  $0 --module dma_attack --keep-loaded

REQUIREMENTS:
  - Run as root (sudo)
  - Attack module .ko file must exist
  - OP-TEE must be running

EOF
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --module)
                MODULE_NAME="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT_SEC="$2"
                shift 2
                ;;
            --target)
                TARGET_ADDR="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=1
                shift
                ;;
            --debug)
                DEBUG=1
                shift
                ;;
            --keep-loaded)
                KEEP_LOADED=1
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Validate arguments
    if [[ -z "$MODULE_NAME" ]]; then
        print_error "Module name required"
        print_usage
        exit 1
    fi
    
    # Enable debug if requested
    if [[ $DEBUG -eq 1 ]]; then
        set -x
    fi
    
    # Check permissions
    check_root
    
    # Ensure results directory
    mkdir -p "$RESULTS_DIR"
    
    # Find module file
    local module_file
    module_file=$(find_module_file "$MODULE_NAME") || exit 1
    
    print_header "Attack Execution: $MODULE_NAME"
    print_ok "Module file: $module_file"
    
    # Load module
    load_module "$module_file" || exit 1
    
    # Verify module
    verify_module "$MODULE_NAME" || exit 1
    
    # Get proc interface
    local proc_interface
    proc_interface=$(get_proc_interface "$MODULE_NAME")
    
    # Check proc interface
    check_proc_interface "$proc_interface" || print_warning "Proceeding anyway"
    
    # Execute attack
    execute_via_proc "$proc_interface" "$TARGET_ADDR" "$TIMEOUT_SEC"
    
    # Unload module (unless --keep-loaded)
    if [[ $KEEP_LOADED -eq 0 ]]; then
        sleep 1
        unload_module "$MODULE_NAME"
    else
        print_info "Module left loaded (use rmmod to unload)"
    fi
    
    print_ok "Attack execution complete"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
