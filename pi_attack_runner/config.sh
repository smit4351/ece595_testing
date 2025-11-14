#!/bin/bash

################################################################################
# CONFIG.SH — Automated Attack Runner Configuration
# 
# Edit these variables to customize attack execution behavior on Raspberry Pi
################################################################################

# =============================================================================
# PATHS & DIRECTORIES
# =============================================================================

# Where kernel modules (.ko files) are stored
MODULES_DIR="${MODULES_DIR:-/tmp/attacks}"

# Where to save attack results and logs
RESULTS_DIR="${RESULTS_DIR:-/var/log/optee_attacks}"

# OP-TEE debug directory (if available)
OPTEE_DEBUG_DIR="/sys/kernel/debug/optee"

# =============================================================================
# TIMEOUT & EXECUTION
# =============================================================================

# Default timeout for each attack (seconds)
ATTACK_TIMEOUT_SEC=60

# Monitoring interval during attack (seconds)
MONITOR_INTERVAL_SEC=1

# Maximum number of crashes before stopping run
MAX_CRASH_COUNT=10

# Retry failed modules N times
RETRY_ATTEMPTS=1

# =============================================================================
# LOGGING & OUTPUT
# =============================================================================

# Log level: DEBUG, INFO, WARN, ERROR
LOG_LEVEL="INFO"

# Verbose output to console
VERBOSE_OUTPUT=1

# Log file path
LOG_FILE="${RESULTS_DIR}/attack_runner.log"

# =============================================================================
# /PROC INTERFACE PATHS
# =============================================================================

# DMA attack control interface
DMA_INTERFACE="/proc/dma_attack"

# SMC fuzzer control interface
SMC_INTERFACE="/proc/smc_fuzzer"

# Generic attack template interface
TEMPLATE_INTERFACE="/proc/attack_template"

# =============================================================================
# ATTACK PARAMETERS
# =============================================================================

# Default target address (Secure World base, modify if needed)
DEFAULT_TARGET_ADDR="0xc0000000"

# Memory access size (bytes)
MEMORY_ACCESS_SIZE=8

# DMA operation timeout (milliseconds)
DMA_TIMEOUT_MS=5000

# SMC fuzzing iterations
SMC_FUZZ_ITERATIONS=1000

# =============================================================================
# MONITORING & DETECTION
# =============================================================================

# Max memory usage before warning (MB)
MAX_MEMORY_USAGE_MB=500

# CPU temperature threshold (Celsius)
CPU_TEMP_THRESHOLD_C=80

# Watch for these keywords indicating crashes
CRASH_KEYWORDS=("Segmentation fault" "BUG:" "panic" "Oops" "Unable to handle kernel" "FATAL")

# =============================================================================
# MODULE HANDLING
# =============================================================================

# Verify module checksums before loading
VERIFY_CHECKSUMS=1

# Automatically unload previous version before loading new one
AUTO_UNLOAD_PREVIOUS=1

# Keep module log files (dmesg) after unload
KEEP_MODULE_LOGS=1

# =============================================================================
# RESULT COLLECTION
# =============================================================================

# Capture full dmesg for each attack
CAPTURE_FULL_DMESG=1

# Parse dmesg for success indicators
PARSE_SUCCESS_INDICATORS=1

# Success keywords (module found these)
SUCCESS_KEYWORDS=("SUCCESS" "Exploit" "verified" "written" "completed")

# Export results as JSON
EXPORT_JSON=1

# Export results as human-readable text
EXPORT_TEXT=1

# =============================================================================
# SYSTEM-SPECIFIC (Update for your Pi)
# =============================================================================

# Raspberry Pi model
PI_MODEL="Raspberry Pi 4 Model B"

# CPU cores
CPU_CORES=4

# RAM available (MB)
RAM_MB=4096

# OP-TEE version (for reference)
OPTEE_VERSION="3.20.0"

# Linux kernel version
KERNEL_VERSION=$(uname -r)

# =============================================================================
# ADVANCED OPTIONS
# =============================================================================

# Run attacks in parallel (0=serial, N=parallel processes)
PARALLEL_EXECUTION=0

# Enable crash dump collection (requires crash handler setup)
ENABLE_CRASH_DUMPS=0

# Path to crash dumps
CRASH_DUMP_DIR="${RESULTS_DIR}/crashes"

# Continuous mode: keep running until manually stopped
CONTINUOUS_MODE=0

# Clean up old logs after N days
CLEANUP_LOGS_DAYS=7

# =============================================================================
# NETWORK SETTINGS (for remote result upload)
# =============================================================================

# Send results to remote server (optional)
REMOTE_UPLOAD_ENABLED=0

# Remote server URL
REMOTE_SERVER="https://your-server.com/api/results"

# API key for remote upload
REMOTE_API_KEY=""

# =============================================================================
# HELPER FUNCTIONS (do not edit below)
# =============================================================================

# Create results directory if needed
ensure_results_dir() {
    if [[ ! -d "$RESULTS_DIR" ]]; then
        mkdir -p "$RESULTS_DIR" || {
            echo "ERROR: Cannot create results directory $RESULTS_DIR" >&2
            exit 1
        }
    fi
    
    # Also create subdirectories
    mkdir -p "${RESULTS_DIR}/logs"
    mkdir -p "${RESULTS_DIR}/crashes"
}

# Log function
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[${timestamp}] [${level}] ${msg}" | tee -a "$LOG_FILE"
}

# Load configuration from this file
load_config() {
    ensure_results_dir
    log "INFO" "Configuration loaded from $(basename "$0")"
}

# Export configuration as environment variables (for subshells)
export_config() {
    export MODULES_DIR
    export RESULTS_DIR
    export ATTACK_TIMEOUT_SEC
    export MONITOR_INTERVAL_SEC
    export LOG_LEVEL
    export VERBOSE_OUTPUT
    export DEFAULT_TARGET_ADDR
    export DMA_INTERFACE
    export SMC_INTERFACE
}

# =============================================================================
# Initialize on import
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script was executed directly
    load_config
    
    echo "=== Attack Runner Configuration ==="
    echo "Modules Directory:   $MODULES_DIR"
    echo "Results Directory:   $RESULTS_DIR"
    echo "Log Level:           $LOG_LEVEL"
    echo "Attack Timeout:      ${ATTACK_TIMEOUT_SEC}s"
    echo "Monitor Interval:    ${MONITOR_INTERVAL_SEC}s"
    echo "Parallel Execution:  $PARALLEL_EXECUTION"
    echo "Target Address:      $DEFAULT_TARGET_ADDR"
    echo "OP-TEE Version:      $OPTEE_VERSION"
    echo "Kernel Version:      $KERNEL_VERSION"
    echo ""
    echo "Config loaded successfully!"
else
    # Script was sourced
    load_config
    export_config
fi
