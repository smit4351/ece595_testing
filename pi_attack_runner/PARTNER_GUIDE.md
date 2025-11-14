# Automated Attack Execution Guide

## For Your Partner on Raspberry Pi

This guide explains how to use the automated attack runner to deploy and test your attack modules on the Raspberry Pi.

---

## One-Time Setup (First Time Only)

### On Your Raspberry Pi

1. **Receive the attack runner directory:**
   ```bash
   scp -r you@your-mac:ece595_testing/pi_attack_runner ~/
   ```

2. **Make scripts executable:**
   ```bash
   chmod +x ~/pi_attack_runner/*.sh
   ```

3. **Run setup script:**
   ```bash
   sudo ~/pi_attack_runner/partner_setup.sh
   ```

   This will:
   - Verify OP-TEE is installed
   - Create necessary directories
   - Check for required tools
   - Verify system configuration

---

## Workflow: Testing Your Attacks

### Iteration 1: Receive Modules

You (on macOS) send the compiled modules:

```bash
# Build modules
./scripts/run_in_container.sh build-modules

# Send to partner
scp kernel_modules/*.ko pi@raspberrypi.local:/tmp/attacks/
```

Your partner receives them in `/tmp/attacks/`

---

### Iteration 2: Run Attacks

Your partner (on Pi) executes attacks:

```bash
# SSH into Pi
ssh pi@raspberrypi.local

# Navigate to attack runner
cd ~/pi_attack_runner

# Option A: Automated (recommended)
sudo ./run_attacks.sh --batch --local /tmp/attacks

# Option B: Manual/Interactive
sudo ./execute_attack.sh --module dma_attack --timeout 30
sudo ./execute_attack.sh --module smc_fuzzer --timeout 60

# Option C: Quick test first
sudo ./quick_test.sh
```

---

### Iteration 3: Collect Results

Your partner collects results:

```bash
# On Pi
sudo ~/pi_attack_runner/collect_results.sh --output ~/attack_results/

# Send to you
scp -r pi@raspberrypi.local:~/attack_results ~/results_from_pi/
```

---

### Iteration 4: Analyze & Iterate

You (on macOS) analyze:

```bash
# Review results
cat ~/results_from_pi/SUMMARY.txt
grep -i "success\|crash" ~/results_from_pi/logs/dmesg_attacks.log

# Modify attack code
nano kernel_modules/dma_attack.c

# Rebuild and repeat
./scripts/run_in_container.sh build-modules
scp kernel_modules/dma_attack.ko pi@raspberrypi.local:/tmp/attacks/
```

---

## Quick Reference for Partner

### Essential Commands

**Load and test a single module:**
```bash
sudo ~/pi_attack_runner/execute_attack.sh --module dma_attack
```

**Run all modules in sequence:**
```bash
sudo ~/pi_attack_runner/run_attacks.sh --batch --local /tmp/attacks
```

**Collect results after testing:**
```bash
sudo ~/pi_attack_runner/collect_results.sh
```

**View results summary:**
```bash
cat /var/log/optee_attacks/SUMMARY.txt
```

**Check kernel messages live:**
```bash
dmesg -w
```

---

## Common Scenarios

### Scenario 1: Quick Attack Test (5 minutes)

Partner does:
```bash
# Receive modules
scp you@mac:kernel_modules/*.ko /tmp/attacks/

# Run automated test
sudo ./run_attacks.sh --batch --local /tmp/attacks

# Collect results
sudo ./collect_results.sh --output ~/attack_results/

# Send summary
scp ~/attack_results/SUMMARY.txt you@mac:~/
```

---

### Scenario 2: Debug Failed Attack

Partner debugs:
```bash
# Check module loaded
lsmod | grep dma_attack

# Check if /proc interface exists
cat /proc/dma_attack

# View kernel errors
dmesg | grep -i "error\|failed" | tail -20

# Try to reload
sudo rmmod dma_attack
sudo insmod /tmp/attacks/dma_attack.ko
dmesg | tail -10
```

---

### Scenario 3: Overnight Fuzzing Campaign

Partner starts long-running attack:
```bash
# Start monitoring in background
nohup ./monitor_system.sh --capture-crashes > monitor.log 2>&1 &

# Start fuzzing
timeout 28800 ./execute_attack.sh --module smc_fuzzer --timeout 3600

# Wait for completion...

# Collect everything
./collect_results.sh --output ~/overnight_results/

# Send to you
scp -r ~/overnight_results you@mac:~/results/
```

---

## Script Reference

### `run_attacks.sh` — Main orchestrator
**When to use:** Run all attacks with one command

```bash
sudo ./run_attacks.sh --batch --local /tmp/attacks
# or
sudo ./run_attacks.sh --interactive
```

**What it does:**
- Validates environment
- Loads all modules
- Executes attacks in sequence
- Unloads modules
- Generates report

---

### `execute_attack.sh` — Single attack
**When to use:** Test one module at a time

```bash
sudo ./execute_attack.sh --module dma_attack --timeout 60
sudo ./execute_attack.sh --module smc_fuzzer --target 0xc0001000 --timeout 120
```

**Options:**
- `--module NAME` — Module to run
- `--timeout SECONDS` — How long to let attack run
- `--target ADDRESS` — Secure World target address (hex)
- `--verbose` — Show details
- `--keep-loaded` — Don't unload after (for debugging)

---

### `collect_results.sh` — Gather data
**When to use:** After attacks complete

```bash
sudo ./collect_results.sh --output ~/my_results/
```

**Collects:**
- dmesg logs (full, attacks, crashes)
- System state (memory, CPU, disk)
- Module info
- Analysis and statistics
- JSON report

---

### `quick_test.sh` — Verify setup
**When to use:** First time, or after system changes

```bash
sudo ./quick_test.sh
```

**Checks:**
- Configuration
- Available modules
- Module loading/unloading
- System readiness

---

### `partner_setup.sh` — One-time setup
**When to use:** First setup only

```bash
sudo ./partner_setup.sh
```

---

## Configuration

Edit `config.sh` to customize behavior:

```bash
# How long each attack runs (seconds)
ATTACK_TIMEOUT_SEC=60

# Where modules are stored
MODULES_DIR="/tmp/attacks"

# Where results are saved
RESULTS_DIR="/var/log/optee_attacks"

# Log level (DEBUG, INFO, WARN, ERROR)
LOG_LEVEL="INFO"

# Default attack target address
DEFAULT_TARGET_ADDR="0xc0000000"
```

---

## Troubleshooting

### Issue: Module won't load

**Symptoms:** "insmod: ERROR: could not insert module"

**Fix:**
```bash
# Check error
dmesg | tail -20

# Verify kernel version matches
uname -r

# Try re-copying module
scp you@mac:kernel_modules/dma_attack.ko /tmp/attacks/
```

---

### Issue: No /proc interface

**Symptoms:** "Proc interface not found"

**Fix:**
```bash
# Check if module loaded
lsmod | grep dma_attack

# Check for module init errors
dmesg | grep dma_attack

# Try manual load with verbose output
sudo insmod /tmp/attacks/dma_attack.ko
dmesg | tail -5
```

---

### Issue: OP-TEE seems to crash

**Symptoms:** "SMC call hangs" or "No response from Secure World"

**Fix:**
```bash
# Verify OP-TEE still running
dmesg | grep -i "optee"

# Check system state
free -h
ps aux | grep optee

# Reboot Pi
sudo reboot
```

---

### Issue: Permission denied

**Symptoms:** "permission denied" when writing to /proc

**Fix:**
```bash
# Run with sudo
sudo ./execute_attack.sh --module dma_attack

# Or add user to sudoers (ask admin)
sudo visudo
# Add: your_username ALL=(ALL) NOPASSWD: /sbin/insmod, /sbin/rmmod
```

---

## Performance Tips

1. **Monitor system while running:**
   ```bash
   watch -n 1 'free -h; echo "---"; dmesg | tail -5'
   ```

2. **Capture crashes in real-time:**
   ```bash
   # Terminal 1: Run attack
   sudo ./execute_attack.sh --module smc_fuzzer
   
   # Terminal 2: Monitor
   dmesg -w | grep -i "panic\|oops\|crash"
   ```

3. **Run multiple attacks:**
   ```bash
   # Sequential (safer)
   sudo ./run_attacks.sh --batch --local /tmp/attacks
   
   # Parallel (faster, more system load)
   for module in dma_attack smc_fuzzer; do
       sudo ./execute_attack.sh --module $module &
   done
   wait
   ```

---

## Sending Results Back

After successful attacks:

```bash
# Option 1: Send entire results directory
scp -r ~/attack_results you@mac:~/pi_results/

# Option 2: Send just summary and crashes
scp ~/attack_results/SUMMARY.txt you@mac:~/
scp -r ~/attack_results/crashes you@mac:~/

# Option 3: Compress and send
tar czf results.tar.gz attack_results/
scp results.tar.gz you@mac:~/
```

---

## What to Expect

### Successful Attack Run Output

```
[OK] Load module: dma_attack
[OK] Proc interface found: /proc/dma_attack
[INFO] Setting target address: 0xc0000000
[INFO] Starting attack (timeout: 60s)...
[OK] Attack started
[INFO] Running... 10/60s
[INFO] Running... 20/60s
[INFO] Attack execution time: 32s
[OK] Results from /proc/dma_attack
   Status: Completed
   Target: 0xc0000000
   Success: true
[OK] Results saved
```

### Results Files Generated

```
/var/log/optee_attacks/
├── attack_dma_attack_20251113_142345.txt
├── attack_smc_fuzzer_20251113_142415.txt
├── SUMMARY.txt
└── logs/
    ├── dmesg_full.log
    ├── dmesg_attacks.log
    └── modules.txt
```

---

## Emergency/Maintenance

### Unload all modules manually

```bash
sudo rmmod dma_attack
sudo rmmod smc_fuzzer
```

### Clear logs and start fresh

```bash
rm -rf /var/log/optee_attacks/*
```

### Reboot system after unstable run

```bash
sudo reboot
```

---

## Support

If you encounter issues:

1. **Collect debug information:**
   ```bash
   sudo ./collect_results.sh --output ~/debug_info/
   dmesg > ~/debug_info/dmesg_full.txt
   ```

2. **Send to developer:**
   ```bash
   scp -r ~/debug_info you@mac:~/pi_debug/
   ```

3. **Include:**
   - Error messages
   - dmesg output
   - Module info
   - System state

---

## Next Steps

1. ✅ Run `partner_setup.sh` to verify everything
2. ✅ Wait for first attack modules from developer
3. ✅ Run `quick_test.sh` to test modules
4. ✅ Execute attacks with `run_attacks.sh`
5. ✅ Collect results with `collect_results.sh`
6. ✅ Send results to developer
7. 🔄 Repeat for next iteration

---

**Good luck with the attacks! 🎯**
