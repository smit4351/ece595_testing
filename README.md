# Raspberry Pi 4 TrustZone Attack Framework

**For Partner: Raspberry Pi Deployment**

## What This Does

Automated TrustZone attack testing on Raspberry Pi 4 with OP-TEE. Four attack modules ready to run.

## Files You Need

```
ece595_testing/
├── BUILD_ON_PI.sh              ← Run this first on Pi
├── kernel_modules/             ← Attack source code
│   ├── dma_attack.c           (DMA memory access)
│   ├── smc_fuzzer.c           (SMC fuzzing)
│   ├── cache_timing_attack.c  (Side-channel)
│   ├── peripheral_isolation_test.c (Peripheral testing)
│   ├── attack_template.c      (Template for new attacks)
│   └── Makefile
└── pi_attack_runner/           ← Automation scripts
    ├── run_attacks.sh          (Main runner)
    ├── execute_attack.sh       (Single attack)
    ├── collect_results.sh      (Gather results)
    ├── partner_setup.sh        (First-time setup)
    ├── config.sh               (Configuration)
    └── quick_test.sh           (Test setup)
```

## Setup (One Time)

```bash
# 1. Copy this entire directory to Pi
scp -r ece595_testing/ pi@raspberrypi.local:~/

# 2. SSH to Pi
ssh pi@raspberrypi.local

# 3. Build kernel modules
cd ~/ece595_testing
bash BUILD_ON_PI.sh

# 4. Setup automation
cd ~/ece595_testing/pi_attack_runner
sudo bash partner_setup.sh
```

## Running Attacks

```bash
# Run all attacks
cd ~/ece595_testing/pi_attack_runner
sudo bash run_attacks.sh --local ~/ece595_testing/kernel_modules

# Or run individually
sudo bash execute_attack.sh --module dma_attack
sudo bash execute_attack.sh --module smc_fuzzer
sudo bash execute_attack.sh --module cache_timing_attack
sudo bash execute_attack.sh --module peripheral_isolation_test

# Collect results
sudo bash collect_results.sh --output ~/attack_results
```

## Results

Outputs go to `/tmp/attack_results/` by default:
- Kernel logs (dmesg)
- Attack output
- Crash reports
- Summary

## Documentation

- `RASPBERRY_PI_DEPLOYMENT.md` - Full deployment guide
- `ATTACK_SUMMARY.md` - Attack descriptions and research alignment
- `pi_attack_runner/PARTNER_GUIDE.md` - Detailed partner instructions

## Requirements

- Raspberry Pi 4 (4GB RAM)
- OP-TEE 3.20.0 installed
- Internet (first time only)
- SSH access

## Quick Test

```bash
cd ~/ece595_testing/pi_attack_runner
sudo bash quick_test.sh
```

Should show: ✓ OP-TEE detected, ✓ Modules built, ✓ Ready to run
