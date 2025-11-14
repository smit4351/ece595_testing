# Raspberry Pi Attack Runner
## Automated Attack Deployment & Execution for OP-TEE

This directory contains scripts and tools for your partner to run on the Raspberry Pi to automatically deploy, load, and execute the attack modules you develop.

---

## Quick Start (For Your Partner)

### 1. Transfer This Directory to Pi

```bash
# On your macOS, copy the runner to Pi:
scp -r pi_attack_runner pi@raspberrypi.local:~/
```

### 2. SSH into Pi and Run

```bash
# On Pi:
ssh pi@raspberrypi.local
cd ~/pi_attack_runner

# Make scripts executable
chmod +x *.sh

# Run the main runner (downloads modules from you)
./run_attacks.sh --url https://path/to/modules.zip
```

Or, if modules are already on Pi:

```bash
./run_attacks.sh --local /path/to/kernel_modules/
```

---

## Directory Structure

```
pi_attack_runner/
├── README.md                    # This file
├── run_attacks.sh              # Main orchestrator script
├── deploy_modules.sh           # Download and install .ko files
├── execute_attack.sh           # Run individual attack
├── monitor_system.sh           # Watch for crashes/results
├── collect_results.sh          # Gather dmesg, logs, crash data
├── config.sh                   # Configuration (addresses, timeouts, etc.)
└── examples/
    ├── dma_attack_demo.sh      # Example: run DMA attack
    ├── smc_fuzzer_demo.sh      # Example: run SMC fuzzer
    └── full_suite.sh           # Run all attacks in sequence
```

---

## Scripts Overview

### `run_attacks.sh` — Main Entry Point

**Usage:**
```bash
./run_attacks.sh [--local PATH | --url URL | --interactive]
```

**Modes:**
- `--local /path/to/modules` — Use modules already on Pi
- `--url https://...zip` — Download modules from URL
- `--interactive` — Prompt for each step
- `--batch` — Run without prompts (automated)

**What it does:**
1. Validates environment (OP-TEE running, permissions)
2. Deploys modules (downloads or copies from local path)
3. Loads modules with insmod
4. Executes attack sequence
5. Collects results and crashes
6. Generates report

**Example:**
```bash
./run_attacks.sh --batch --local ~/kernel_modules/
```

---

### `deploy_modules.sh` — Install Kernel Modules

**Usage:**
```bash
./deploy_modules.sh --source /path/to/modules/ [--verify]
```

**What it does:**
1. Copies `.ko` files to `/tmp/attacks/`
2. Checks file sizes and checksums
3. Verifies modules with `modinfo`
4. Reports readiness

**Example:**
```bash
./deploy_modules.sh --source ~/modules/ --verify
```

---

### `execute_attack.sh` — Run Single Attack

**Usage:**
```bash
./execute_attack.sh --module MODULENAME [--target 0xADDRESS] [--timeout 60]
```

**What it does:**
1. Loads module with `sudo insmod`
2. Sends commands via `/proc` interface
3. Monitors for crashes
4. Captures dmesg output
5. Unloads module
6. Saves results to timestamped log

**Example:**
```bash
./execute_attack.sh --module dma_attack --target 0xc0000000 --timeout 30
```

---

### `monitor_system.sh` — Real-time System Monitoring

**Usage:**
```bash
./monitor_system.sh [--watch-interval 1] [--capture-crashes]
```

**What it does:**
1. Monitors OP-TEE status
2. Watches for kernel panics
3. Tracks memory usage
4. Captures crash signatures
5. Logs anomalies

**Example (run in separate terminal):**
```bash
./monitor_system.sh --watch-interval 1 --capture-crashes
```

---

### `collect_results.sh` — Gather Exploitation Data

**Usage:**
```bash
./collect_results.sh --output DIRECTORY
```

**What it collects:**
- dmesg logs (filtered for attack messages)
- OP-TEE logs (if available)
- Kernel panics
- Memory maps
- Module information
- Attack success/failure indicators

**Example:**
```bash
./collect_results.sh --output ~/attack_results/
# Creates: ~/attack_results/dmesg.log, crash_log.txt, results.json
```

---

## Configuration

Edit `config.sh` to customize:

```bash
# Module paths
MODULES_DIR="/tmp/attacks"
RESULTS_DIR="/var/log/optee_attacks"

# Timeouts
ATTACK_TIMEOUT_SEC=60
MONITOR_INTERVAL_SEC=1

# Logging
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
VERBOSE_OUTPUT=1

# OP-TEE specifics
OPTEE_LOGS="/sys/kernel/debug/optee/"
SMC_INTERFACE="/proc/smc_fuzzer"
DMA_INTERFACE="/proc/dma_attack"

# Thresholds
MAX_CRASH_COUNT=10
MAX_MEMORY_USAGE_MB=500
```

---

## Example Workflows

### Workflow 1: Quick Attack (5 minutes)

```bash
# On macOS, send modules:
scp kernel_modules/*.ko pi@raspberrypi.local:~/

# On Pi:
ssh pi@raspberrypi.local
cd ~/pi_attack_runner
./execute_attack.sh --module dma_attack --timeout 30
./execute_attack.sh --module smc_fuzzer --timeout 30
./collect_results.sh --output ~/results/
```

### Workflow 2: Unattended Overnight Run

```bash
# On Pi, start monitoring in background:
nohup ./monitor_system.sh --capture-crashes > monitor.log 2>&1 &

# Run attack suite
./run_attacks.sh --batch --local ~/kernel_modules/

# Collect all results
./collect_results.sh --output ~/overnight_results/

# View results
cat ~/overnight_results/results_summary.txt
```

### Workflow 3: Iterative Development

```bash
# Each iteration:
# 1. You send new module from macOS:
scp kernel_modules/dma_attack.ko pi@raspberrypi.local:~/

# 2. Partner runs:
./execute_attack.sh --module dma_attack --verbose

# 3. Partner sends results back:
scp pi@raspberrypi.local:~/pi_attack_runner/logs/* ~/dma_results/

# 4. You analyze and iterate
```

---

## Expected Output

### During Execution
```
[INFO] 2025-11-13 14:23:45 — Loading attack modules...
[OK]   dma_attack.ko loaded successfully
[OK]   smc_fuzzer.ko loaded successfully
[INFO] Starting dma_attack...
[INFO] Target address: 0xc0000000
[INFO] Timeout: 60 seconds
[...attack running...]
[INFO] Attack completed
[INFO] Checking for crashes...
[WARN] Secure World may have crashed (no SMC response)
[INFO] Collecting results...
[OK]   Results saved to /var/log/optee_attacks/dma_attack_20251113_142345.log
```

### Results File (JSON)
```json
{
  "timestamp": "2025-11-13T14:23:45Z",
  "attack_module": "dma_attack",
  "status": "completed",
  "result": {
    "success": true,
    "target_address": "0xc0000000",
    "data_read": "0xdeadbeef",
    "secure_world_response": "no_response",
    "kernel_panic": false
  },
  "logs": {
    "dmesg_lines": 42,
    "crash_detected": false,
    "anomalies": ["Secure World timeout after 5s"]
  },
  "system_state": {
    "memory_mb": 312,
    "cpu_temp_c": 45
  }
}
```

---

## Troubleshooting

### Module Won't Load
```bash
# Check error:
sudo dmesg | grep dma_attack | tail -5

# Verify module compatibility:
modinfo ~/kernel_modules/dma_attack.ko

# Check kernel version:
uname -r

# If kernel mismatch, ask you to rebuild with correct headers
```

### No Crash Detected
```bash
# Monitor Secure World in real-time:
./monitor_system.sh --watch-interval 1

# Check OP-TEE status:
ps aux | grep optee
cat /proc/cmdline | grep tee

# Try with verbose logging:
./execute_attack.sh --module smc_fuzzer --verbose --debug
```

### Permission Denied
```bash
# Scripts need sudo for insmod/rmmod:
sudo ./run_attacks.sh --batch --local ~/kernel_modules/

# Or add to sudoers (ask your admin):
sudo visudo
# Add: your_username ALL=(ALL) NOPASSWD: /sbin/insmod, /sbin/rmmod, /bin/dmesg
```

---

## Advanced Usage

### Custom Attack Sequence

Create `custom_attacks.txt`:
```
dma_attack:target=0xc0000000:timeout=30
dma_attack:target=0xc0001000:timeout=30
smc_fuzzer:timeout=60
dma_attack:target=0xc0010000:timeout=30
```

Then run:
```bash
./run_attacks.sh --batch --sequence custom_attacks.txt
```

### Parallel Execution

```bash
# Run multiple attacks simultaneously (careful with system load!):
./execute_attack.sh --module dma_attack &
./execute_attack.sh --module smc_fuzzer &
wait
./collect_results.sh --output ~/parallel_results/
```

### Continuous Fuzzing

```bash
# Run SMC fuzzer for 1 hour, collecting crashes:
timeout 3600 ./execute_attack.sh --module smc_fuzzer --timeout 600 --continuous
```

---

## Integration with Your macOS Workflow

### Automated Testing Loop

On your macOS, create a wrapper script:

```bash
#!/bin/bash
# test_and_deploy.sh

echo "Building modules..."
./scripts/run_in_container.sh build-modules

echo "Deploying to Pi..."
scp kernel_modules/*.ko pi@raspberrypi.local:~/

echo "Running attacks on Pi..."
ssh pi@raspberrypi.local "cd ~/pi_attack_runner && ./run_attacks.sh --batch --local ~/"

echo "Collecting results..."
mkdir -p results/
scp -r pi@raspberrypi.local:~/pi_attack_runner/logs/* results/

echo "Analysis..."
grep -i "crash\|panic\|success" results/*.log
```

---

## Files Your Partner Should Keep

After each run, save:
- `logs/*.log` — dmesg and module output
- `results/*.json` — structured attack results
- `crashes/*.dump` — crash dumps if Secure World panics
- `system_state.txt` — memory, CPU, temps during attack

Transfer these to you for analysis and iteration.

---

## Next Steps for You

1. **Build your modules** locally:
   ```bash
   ./scripts/run_in_container.sh build-modules
   ```

2. **Transfer runner to Pi** (once):
   ```bash
   scp -r pi_attack_runner pi@raspberrypi.local:~/
   ```

3. **For each iteration:**
   - Modify attack code
   - Rebuild modules
   - Send `.ko` to partner (or direct scp to Pi)
   - Partner runs attack using these scripts
   - Collect results and analyze

---

## Support & Debugging

For issues, collect:
```bash
# On Pi:
./pi_attack_runner/collect_results.sh --output ~/debug/
scp -r pi@raspberrypi.local:~/debug ~/debug_from_pi/
```

Then review:
- `debug/dmesg.log` — kernel messages
- `debug/optee_logs/` — OP-TEE output
- `debug/module_info.txt` — module details
- `debug/system_state.txt` — resource usage
