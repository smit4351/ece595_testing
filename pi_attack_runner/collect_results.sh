#!/bin/bash

################################################################################
# COLLECT_RESULTS.SH — Gather Attack Results and Analysis Data
#
# Usage:
#   ./collect_results.sh [--output DIRECTORY] [--export-format json|text|both]
#
# This script collects all attack data and generates a comprehensive report
################################################################################

set -o pipefail

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# =============================================================================
# VARIABLES
# =============================================================================

OUTPUT_DIR="$RESULTS_DIR/collection_$(date +%s)"
EXPORT_FORMAT="both"
INCLUDE_SYSTEM_STATE=1
INCLUDE_CRASH_DATA=1
ANALYZE_DMESG=1

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

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

# Create output structure
setup_output_dir() {
    mkdir -p "$OUTPUT_DIR"/{logs,analysis,system,crashes,json}
    print_ok "Output directory: $OUTPUT_DIR"
}

# Collect dmesg
collect_dmesg() {
    print_info "Collecting kernel messages..."
    
    local dmesg_file="$OUTPUT_DIR/logs/dmesg_full.log"
    dmesg > "$dmesg_file"
    
    print_ok "Full dmesg: $dmesg_file ($(wc -l < "$dmesg_file") lines)"
    
    # Extract attack-related messages
    local attack_dmesg="$OUTPUT_DIR/logs/dmesg_attacks.log"
    grep -i "attack\|dma\|smc\|fuzzer\|optee\|trustzone" "$dmesg_file" > "$attack_dmesg" 2>/dev/null || true
    
    if [[ -s "$attack_dmesg" ]]; then
        print_ok "Attack messages: $attack_dmesg ($(wc -l < "$attack_dmesg") lines)"
    else
        print_warning "No attack-specific messages found in dmesg"
    fi
    
    # Extract crash signatures
    local crash_dmesg="$OUTPUT_DIR/logs/dmesg_crashes.log"
    grep -i "panic\|oops\|segmentation\|fault\|bug:\|killed\|watchdog" "$dmesg_file" > "$crash_dmesg" 2>/dev/null || true
    
    if [[ -s "$crash_dmesg" ]]; then
        print_warning "Crashes found: $crash_dmesg ($(wc -l < "$crash_dmesg") lines)"
    fi
}

# Collect system state
collect_system_state() {
    if [[ $INCLUDE_SYSTEM_STATE -eq 0 ]]; then
        return
    fi
    
    print_info "Collecting system state..."
    
    local state_file="$OUTPUT_DIR/system/system_state.txt"
    
    {
        echo "=== System State Report ==="
        echo "Timestamp: $(date)"
        echo ""
        
        echo "=== Kernel Information ==="
        uname -a
        echo ""
        
        echo "=== Memory Usage ==="
        free -h
        echo ""
        
        echo "=== CPU Temperature ==="
        if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
            echo "$(cat /sys/class/thermal/thermal_zone0/temp | awk '{printf "%.1f°C\n", $1/1000}')"
        fi
        echo ""
        
        echo "=== Loaded Modules ==="
        lsmod | head -20
        echo ""
        
        echo "=== Network ==="
        ip addr show | grep -E "inet " | head -5
        echo ""
        
        echo "=== Disk Usage ==="
        df -h | head -5
        
    } > "$state_file"
    
    print_ok "System state: $state_file"
}

# Analyze dmesg for patterns
analyze_dmesg() {
    if [[ $ANALYZE_DMESG -eq 0 ]]; then
        return
    fi
    
    print_info "Analyzing kernel messages..."
    
    local analysis_file="$OUTPUT_DIR/analysis/dmesg_analysis.txt"
    local dmesg_file="$OUTPUT_DIR/logs/dmesg_full.log"
    
    {
        echo "=== Dmesg Analysis Report ==="
        echo "Timestamp: $(date)"
        echo ""
        
        echo "=== Message Summary ==="
        echo "Total lines: $(wc -l < "$dmesg_file")"
        echo ""
        
        echo "=== Error Messages ==="
        grep -i "error" "$dmesg_file" | wc -l
        echo "errors found"
        grep -i "error" "$dmesg_file" | tail -5
        echo ""
        
        echo "=== Warning Messages ==="
        grep -i "warning\|warn" "$dmesg_file" | wc -l
        echo "warnings found"
        grep -i "warning\|warn" "$dmesg_file" | tail -5
        echo ""
        
        echo "=== Crash Indicators ==="
        grep -i "panic\|oops\|segmentation\|fault" "$dmesg_file" | wc -l
        echo "crash indicators found"
        echo ""
        
        echo "=== Attack Module Messages ==="
        grep -i "attack\|dma\|smc\|fuzzer" "$dmesg_file" | wc -l
        echo "attack-related messages"
        grep -i "attack\|dma\|smc\|fuzzer" "$dmesg_file" | tail -10
        echo ""
        
        echo "=== OP-TEE Related ==="
        grep -i "optee\|trustzone\|tee" "$dmesg_file" | wc -l
        echo "OP-TEE messages"
        
    } > "$analysis_file"
    
    print_ok "Analysis: $analysis_file"
}

# Collect module information
collect_module_info() {
    print_info "Collecting module information..."
    
    local module_file="$OUTPUT_DIR/logs/modules.txt"
    
    {
        echo "=== Loaded Modules ==="
        lsmod
        echo ""
        
        echo "=== Module Details ==="
        for module in dma_attack smc_fuzzer; do
            if modinfo "$module" 2>/dev/null; then
                echo ""
                echo "---"
            fi
        done
        
    } > "$module_file"
    
    print_ok "Module info: $module_file"
}

# Look for crash dumps
collect_crash_data() {
    if [[ $INCLUDE_CRASH_DATA -eq 0 ]]; then
        return
    fi
    
    print_info "Checking for crash data..."
    
    # Check for kernel panic info
    if [[ -f /proc/sys/kernel/oops_dump_all ]]; then
        cp /proc/sys/kernel/oops_dump_all "$OUTPUT_DIR/crashes/oops_dump.txt" 2>/dev/null || true
    fi
    
    # Check for OP-TEE crash data
    if [[ -d "$OPTEE_DEBUG_DIR" ]]; then
        cp -r "$OPTEE_DEBUG_DIR" "$OUTPUT_DIR/crashes/optee_debug/" 2>/dev/null || true
        print_ok "Copied OP-TEE debug data"
    fi
    
    print_ok "Crash data collection complete"
}

# Generate JSON report
generate_json_report() {
    local json_file="$OUTPUT_DIR/json/report.json"
    
    print_info "Generating JSON report..."
    
    # Count various statistics
    local total_dmesg=$(wc -l < "$OUTPUT_DIR/logs/dmesg_full.log" 2>/dev/null || echo 0)
    local error_count=$(grep -ci "error" "$OUTPUT_DIR/logs/dmesg_full.log" 2>/dev/null || echo 0)
    local warning_count=$(grep -ci "warning" "$OUTPUT_DIR/logs/dmesg_full.log" 2>/dev/null || echo 0)
    local crash_count=$(grep -ci "panic\|oops\|segmentation" "$OUTPUT_DIR/logs/dmesg_full.log" 2>/dev/null || echo 0)
    
    {
        echo "{"
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"collection_dir\": \"$OUTPUT_DIR\","
        echo "  \"statistics\": {"
        echo "    \"dmesg_lines\": $total_dmesg,"
        echo "    \"error_count\": $error_count,"
        echo "    \"warning_count\": $warning_count,"
        echo "    \"crash_count\": $crash_count"
        echo "  },"
        echo "  \"files\": {"
        echo "    \"dmesg_full\": \"logs/dmesg_full.log\","
        echo "    \"dmesg_attacks\": \"logs/dmesg_attacks.log\","
        echo "    \"dmesg_crashes\": \"logs/dmesg_crashes.log\","
        echo "    \"system_state\": \"system/system_state.txt\","
        echo "    \"analysis\": \"analysis/dmesg_analysis.txt\","
        echo "    \"modules\": \"logs/modules.txt\""
        echo "  }"
        echo "}"
    } > "$json_file"
    
    print_ok "JSON report: $json_file"
}

# Generate text summary
generate_text_summary() {
    local summary_file="$OUTPUT_DIR/SUMMARY.txt"
    
    print_info "Generating text summary..."
    
    {
        echo "========================================="
        echo "    ATTACK RESULTS SUMMARY"
        echo "========================================="
        echo ""
        echo "Collection Timestamp: $(date)"
        echo "Collection Directory: $OUTPUT_DIR"
        echo ""
        
        echo "--- FILES COLLECTED ---"
        echo "Kernel Messages: logs/dmesg_full.log"
        echo "Attack Messages: logs/dmesg_attacks.log"
        echo "Crash Data: logs/dmesg_crashes.log"
        echo "System State: system/system_state.txt"
        echo "Analysis: analysis/dmesg_analysis.txt"
        echo "Modules: logs/modules.txt"
        echo ""
        
        if [[ -f "$OUTPUT_DIR/logs/dmesg_full.log" ]]; then
            echo "--- STATISTICS ---"
            echo "Total dmesg lines: $(wc -l < "$OUTPUT_DIR/logs/dmesg_full.log")"
            echo "Error messages: $(grep -ci "error" "$OUTPUT_DIR/logs/dmesg_full.log" || echo 0)"
            echo "Warnings: $(grep -ci "warning" "$OUTPUT_DIR/logs/dmesg_full.log" || echo 0)"
            echo "Crashes: $(grep -ci "panic\|oops" "$OUTPUT_DIR/logs/dmesg_full.log" || echo 0)"
            echo ""
        fi
        
        echo "--- NEXT STEPS ---"
        echo "1. Review: cat $OUTPUT_DIR/SUMMARY.txt"
        echo "2. View logs: less $OUTPUT_DIR/logs/dmesg_attacks.log"
        echo "3. Check analysis: cat $OUTPUT_DIR/analysis/dmesg_analysis.txt"
        echo "4. Transfer to macOS:"
        echo "   scp -r pi@raspberrypi.local:$OUTPUT_DIR ~/attack_results/"
        echo ""
        
        echo "========================================="
        
    } > "$summary_file"
    
    cat "$summary_file"
    print_ok "Summary: $summary_file"
}

# Print usage
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
  --output DIR          Output directory for results (default: auto-generated)
  --format FORMAT       Export format: json, text, or both (default: both)
  --no-system           Skip system state collection
  --no-crashes          Skip crash data collection
  --no-analysis         Skip dmesg analysis
  --help                Show this help message

EXAMPLES:
  $0
  $0 --output ~/my_results/
  $0 --format json --output ~/results/

OUTPUT:
  - logs/              Kernel messages and module logs
  - analysis/          Analyzed patterns and summaries
  - system/            System state (memory, CPU, etc.)
  - crashes/           Crash dumps and OP-TEE debug data
  - json/              Structured data in JSON format
  - SUMMARY.txt        Quick reference summary

EOF
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --format)
                EXPORT_FORMAT="$2"
                shift 2
                ;;
            --no-system)
                INCLUDE_SYSTEM_STATE=0
                shift
                ;;
            --no-crashes)
                INCLUDE_CRASH_DATA=0
                shift
                ;;
            --no-analysis)
                ANALYZE_DMESG=0
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
    
    # Create output structure
    setup_output_dir
    
    # Collect data
    collect_dmesg
    collect_system_state
    collect_module_info
    collect_crash_data
    
    # Analyze
    analyze_dmesg
    
    # Generate reports
    if [[ "$EXPORT_FORMAT" == "json" ]] || [[ "$EXPORT_FORMAT" == "both" ]]; then
        generate_json_report
    fi
    
    if [[ "$EXPORT_FORMAT" == "text" ]] || [[ "$EXPORT_FORMAT" == "both" ]]; then
        generate_text_summary
    fi
    
    print_ok "Collection complete!"
    echo ""
    echo "Results saved to: $OUTPUT_DIR"
    echo ""
    echo "To transfer to macOS:"
    echo "  scp -r pi@raspberrypi.local:$OUTPUT_DIR ~/attack_results/"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
