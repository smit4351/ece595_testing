#!/bin/bash

################################################################################
# RUN_ATTACKS.SH — Main Orchestrator for Attack Execution
#
# Usage:
#   ./run_attacks.sh --local /path/to/modules
#   ./run_attacks.sh --url https://example.com/modules.zip
#   ./run_attacks.sh --interactive
#   ./run_attacks.sh --batch
#
# This script coordinates the full attack lifecycle:
#   1. Validate environment (OP-TEE running, permissions)
#   2. Deploy modules (download or copy)
#   3. Load kernel modules
#   4. Execute attacks in sequence
#   5. Monitor for crashes
#   6. Collect results
#   7. Generate report
################################################################################

set -o pipefail

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# =============================================================================
# VARIABLES
# =============================================================================

DEPLOY_MODE=""           # "local", "url", "interactive", or unset
MODULES_SOURCE=""        # Path or URL to modules
INTERACTIVE_MODE=0
BATCH_MODE=0
VERBOSE_DEBUG=0

MODULES_LOADED=()        # Track which modules we loaded
ATTACK_RESULTS=()        # Store results from each attack
CRASHES_DETECTED=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if running as root (needed for insmod)
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use: sudo $0)"
        exit 1
    fi
}

# Validate environment
validate_environment() {
    print_header "Environment Validation"
    
    # Check if OP-TEE is running
    if systemctl is-active --quiet optee-service; then
        print_ok "OP-TEE service running"
    else
        print_warning "OP-TEE service not running (may already be loaded)"
    fi
    
    # Check kernel version
    local kernel=$(uname -r)
    print_ok "Kernel version: $kernel"
    
    # Check if we can create results dir
    if mkdir -p "$RESULTS_DIR" 2>/dev/null; then
        print_ok "Results directory ready: $RESULTS_DIR"
    else
        print_error "Cannot write to results directory"
        exit 1
    fi
    
    # Check for required tools
    for tool in insmod rmmod modinfo dmesg grep awk; do
        if command -v "$tool" &> /dev/null; then
            print_ok "Tool available: $tool"
        else
            print_error "Required tool not found: $tool"
            exit 1
        fi
    done
    
    print_ok "Environment validation passed"
    echo ""
}

# Deploy modules from local path
deploy_from_local() {
    local source_path="$1"
    
    print_header "Deploying Modules from Local Path"
    
    if [[ ! -d "$source_path" ]]; then
        print_error "Source directory not found: $source_path"
        return 1
    fi
    
    # Find all .ko files
    local ko_files=($(find "$source_path" -name "*.ko" -type f))
    
    if [[ ${#ko_files[@]} -eq 0 ]]; then
        print_error "No .ko files found in $source_path"
        return 1
    fi
    
    # Create modules directory
    mkdir -p "$MODULES_DIR"
    
    # Copy modules
    print_info "Found ${#ko_files[@]} module(s)"
    for ko in "${ko_files[@]}"; do
        cp "$ko" "$MODULES_DIR/" || {
            print_error "Failed to copy $(basename "$ko")"
            return 1
        }
        print_ok "Copied $(basename "$ko")"
    done
    
    print_ok "Module deployment complete"
    echo ""
    return 0
}

# Deploy modules from URL
deploy_from_url() {
    local url="$1"
    
    print_header "Deploying Modules from URL"
    
    print_info "Downloading from: $url"
    
    # Download ZIP
    local temp_zip="/tmp/attack_modules_$$.zip"
    if curl -f -o "$temp_zip" "$url" 2>/dev/null; then
        print_ok "Download complete"
    else
        print_error "Failed to download from $url"
        return 1
    fi
    
    # Extract
    mkdir -p "$MODULES_DIR"
    if unzip -q -o "$temp_zip" -d "$MODULES_DIR" 2>/dev/null; then
        print_ok "Extracted modules"
    else
        print_error "Failed to extract ZIP"
        rm -f "$temp_zip"
        return 1
    fi
    
    rm -f "$temp_zip"
    print_ok "Module deployment complete"
    echo ""
    return 0
}

# Interactive module selection
deploy_interactive() {
    print_header "Interactive Module Selection"
    
    echo "Provide path to kernel modules directory:"
    read -p "> " modules_path
    
    if [[ -z "$modules_path" ]]; then
        print_error "No path provided"
        return 1
    fi
    
    deploy_from_local "$modules_path"
}

# Load kernel module
load_module() {
    local module_path="$1"
    local module_name=$(basename "$module_path" .ko)
    
    print_info "Loading module: $module_name"
    
    # Check if already loaded
    if lsmod | grep -q "^${module_name}"; then
        print_warning "$module_name already loaded, unloading first"
        rmmod "$module_name" 2>/dev/null || true
    fi
    
    # Load module
    if insmod "$module_path" 2>&1 | tee -a "$LOG_FILE"; then
        MODULES_LOADED+=("$module_name")
        print_ok "Loaded: $module_name"
        sleep 0.5  # Give module time to initialize
        return 0
    else
        print_error "Failed to load $module_name"
        return 1
    fi
}

# Verify module loaded
verify_module() {
    local module_name="$1"
    
    if lsmod | grep -q "^${module_name}"; then
        print_ok "Module verified: $module_name"
        return 0
    else
        print_error "Module not found in lsmod: $module_name"
        return 1
    fi
}

# Load all modules
load_all_modules() {
    print_header "Loading Attack Modules"
    
    local ko_files=($(find "$MODULES_DIR" -name "*.ko" -type f))
    
    if [[ ${#ko_files[@]} -eq 0 ]]; then
        print_error "No modules found in $MODULES_DIR"
        return 1
    fi
    
    print_info "Found ${#ko_files[@]} module(s)"
    
    for ko in "${ko_files[@]}"; do
        load_module "$ko" || print_warning "Continuing despite load failure"
    done
    
    echo ""
    
    if [[ ${#MODULES_LOADED[@]} -eq 0 ]]; then
        print_error "No modules loaded successfully"
        return 1
    fi
    
    print_ok "Loaded ${#MODULES_LOADED[@]} module(s)"
    echo ""
    return 0
}

# Execute single attack
execute_single_attack() {
    local module_name="$1"
    local timeout="${2:-60}"
    local target_addr="${3:-$DEFAULT_TARGET_ADDR}"
    
    print_header "Executing Attack: $module_name"
    
    # Get proc interface based on module
    local proc_interface=""
    case "$module_name" in
        dma_attack)
            proc_interface="$DMA_INTERFACE"
            ;;
        smc_fuzzer)
            proc_interface="$SMC_INTERFACE"
            ;;
        *)
            proc_interface="/proc/${module_name}"
            ;;
    esac
    
    # Check if proc interface exists
    if [[ ! -e "$proc_interface" ]]; then
        print_warning "Proc interface not found: $proc_interface"
        print_info "Module may not have initialized properly"
        return 1
    fi
    
    # Clear dmesg buffer (save previous)
    local dmesg_before="$RESULTS_DIR/logs/${module_name}_before_${SECONDS}.txt"
    dmesg > "$dmesg_before"
    
    # Start attack
    print_info "Target address: $target_addr"
    print_info "Timeout: ${timeout}s"
    print_info "Starting attack..."
    
    local start_time=$(date +%s)
    
    # Send start command
    if echo "start" > "$proc_interface" 2>&1; then
        print_ok "Attack started"
    else
        print_error "Failed to start attack"
        return 1
    fi
    
    # Monitor for completion
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        sleep 1
        elapsed=$(($(date +%s) - start_time))
        
        # Check for crashes
        if dmesg | tail -10 | grep -qi "panic\|oops\|crash\|fault"; then
            print_warning "Possible crash detected!"
            CRASHES_DETECTED=$((CRASHES_DETECTED + 1))
            break
        fi
        
        # Show progress
        if [[ $((elapsed % 10)) -eq 0 ]]; then
            print_info "Running... (${elapsed}s/${timeout}s)"
        fi
    done
    
    # Get results
    local result_status="UNKNOWN"
    if [[ -e "$proc_interface" ]]; then
        if cat "$proc_interface" | grep -qi "success"; then
            result_status="SUCCESS"
            print_ok "Attack appears successful!"
        elif cat "$proc_interface" | grep -qi "completed"; then
            result_status="COMPLETED"
            print_ok "Attack completed"
        else
            result_status="UNKNOWN"
            print_info "Attack status: $(cat "$proc_interface" | head -1)"
        fi
    fi
    
    # Capture new dmesg
    local dmesg_after="$RESULTS_DIR/logs/${module_name}_after_${SECONDS}.txt"
    dmesg > "$dmesg_after"
    
    # Extract attack-related messages
    local dmesg_diff="$RESULTS_DIR/logs/${module_name}_output_${SECONDS}.txt"
    comm -13 <(sort "$dmesg_before") <(sort "$dmesg_after") > "$dmesg_diff"
    
    print_ok "Attack complete - results saved to $dmesg_diff"
    
    # Store result
    ATTACK_RESULTS+=("$module_name: $result_status")
    
    echo ""
    return 0
}

# Unload all modules
unload_all_modules() {
    print_header "Unloading Modules"
    
    for module in "${MODULES_LOADED[@]}"; do
        print_info "Unloading $module"
        rmmod "$module" 2>&1 | tee -a "$LOG_FILE"
        print_ok "Unloaded: $module"
    done
    
    echo ""
}

# Generate results report
generate_report() {
    print_header "Attack Execution Report"
    
    local report_file="$RESULTS_DIR/attack_report_${SECONDS}.txt"
    
    echo "=== Attack Execution Report ===" > "$report_file"
    echo "Timestamp: $(date)" >> "$report_file"
    echo "" >> "$report_file"
    
    echo "Modules Loaded: ${#MODULES_LOADED[@]}" >> "$report_file"
    for mod in "${MODULES_LOADED[@]}"; do
        echo "  - $mod" >> "$report_file"
    done
    echo "" >> "$report_file"
    
    echo "Attack Results: ${#ATTACK_RESULTS[@]}" >> "$report_file"
    for result in "${ATTACK_RESULTS[@]}"; do
        echo "  - $result" >> "$report_file"
    done
    echo "" >> "$report_file"
    
    echo "Crashes Detected: $CRASHES_DETECTED" >> "$report_file"
    echo "" >> "$report_file"
    
    echo "Log Files:" >> "$report_file"
    ls -la "$RESULTS_DIR/logs/" | tail -10 >> "$report_file"
    
    cat "$report_file"
    cp "$report_file" "${RESULTS_DIR}/LATEST_REPORT.txt"
    
    print_ok "Report saved to: $report_file"
    echo ""
}

# =============================================================================
# USAGE & HELP
# =============================================================================

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
  --local PATH          Use modules from local directory
  --url URL             Download modules from URL
  --interactive         Prompt for module path
  --batch               Run without prompts (use defaults)
  --verbose             Enable debug output
  --help                Show this help message

EXAMPLES:
  $0 --local ~/kernel_modules/
  $0 --url https://example.com/modules.zip
  $0 --interactive
  $0 --batch --local ~/kernel_modules/

REQUIREMENTS:
  - Run as root (sudo)
  - OP-TEE installed and running on Raspberry Pi
  - Kernel modules (.ko files) built for ARM64

EOF
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --local)
                DEPLOY_MODE="local"
                MODULES_SOURCE="$2"
                shift 2
                ;;
            --url)
                DEPLOY_MODE="url"
                MODULES_SOURCE="$2"
                shift 2
                ;;
            --interactive)
                DEPLOY_MODE="interactive"
                INTERACTIVE_MODE=1
                shift
                ;;
            --batch)
                BATCH_MODE=1
                shift
                ;;
            --verbose)
                VERBOSE_DEBUG=1
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
    
    # Enable verbose output if requested
    if [[ $VERBOSE_DEBUG -eq 1 ]]; then
        set -x
    fi
    
    print_header "OP-TEE Attack Runner"
    
    # Check permissions
    check_root
    
    # Validate environment
    validate_environment
    
    # Deploy modules
    case "$DEPLOY_MODE" in
        local)
            deploy_from_local "$MODULES_SOURCE" || exit 1
            ;;
        url)
            deploy_from_url "$MODULES_SOURCE" || exit 1
            ;;
        interactive)
            deploy_interactive || exit 1
            ;;
        *)
            if [[ $BATCH_MODE -eq 1 ]]; then
                print_info "Using modules from: $MODULES_DIR"
            else
                print_error "No deployment mode specified"
                print_usage
                exit 1
            fi
            ;;
    esac
    
    # Load modules
    load_all_modules || exit 1
    
    # Execute attacks
    print_header "Attack Execution"
    
    for module in "${MODULES_LOADED[@]}"; do
        if [[ $BATCH_MODE -eq 1 ]]; then
            execute_single_attack "$module" "$ATTACK_TIMEOUT_SEC" "$DEFAULT_TARGET_ADDR"
        else
            # Interactive: ask before each attack
            read -p "Execute attack: $module? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                execute_single_attack "$module" "$ATTACK_TIMEOUT_SEC" "$DEFAULT_TARGET_ADDR"
            fi
        fi
        
        if [[ $CRASHES_DETECTED -ge $MAX_CRASH_COUNT ]]; then
            print_warning "Max crashes reached, stopping"
            break
        fi
    done
    
    # Unload modules
    unload_all_modules
    
    # Generate report
    generate_report
    
    print_ok "Attack runner completed successfully"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
