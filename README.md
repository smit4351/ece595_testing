# Raspberry Pi 4 TrustZone Attack Framework

This repo contains everything you need to run TrustZone security testing on a Raspberry Pi 4. Just copy, build, and execute—all four attack modules are ready to go.

## What's Included

Four attack modules that test different TrustZone weaknesses:

- **DMA Attack** — Uses hardware DMA controllers to read/write Secure World memory
- **SMC Fuzzer** — Sends malformed SMC calls to find bugs in the Secure Monitor
- **Cache Timing** — Exploits cache side-channels to leak Secure World behavior
- **Peripheral Isolation Test** — Checks which peripherals can bypass TrustZone isolation

Plus a complete automation suite to build, deploy, and run everything.

## Quick Start

### First Time Setup (on your Pi)

```bash
# 1. Get the code onto your Pi
git clone https://github.com/smit4351/ece595_testing.git
cd ece595_testing

# 2. Build all the attack modules
bash BUILD_ON_PI.sh

# 3. One-time setup
cd pi_attack_runner
sudo bash partner_setup.sh
```

### Running Attacks

```bash
# Run everything at once
cd ~/ece595_testing/pi_attack_runner
sudo bash run_attacks.sh --local ~/ece595_testing/kernel_modules

# Or pick specific attacks
sudo bash execute_attack.sh --module dma_attack
sudo bash execute_attack.sh --module smc_fuzzer
sudo bash execute_attack.sh --module cache_timing_attack
sudo bash execute_attack.sh --module peripheral_isolation_test
```

### Getting Results

```bash
sudo bash collect_results.sh --output ~/attack_results
```

Results include kernel logs, crash dumps, and a summary report.

## Files You'll Use

```
├── BUILD_ON_PI.sh              # Run this first
├── kernel_modules/
│   ├── dma_attack.c
│   ├── smc_fuzzer.c
│   ├── cache_timing_attack.c
│   └── peripheral_isolation_test.c
└── pi_attack_runner/
    ├── run_attacks.sh          # Main orchestrator
    ├── execute_attack.sh       # Single attack
    ├── collect_results.sh      # Gather results
    └── config.sh               # Customize behavior
```

## What You Need

- Raspberry Pi 4 with at least 4GB RAM
- OP-TEE 3.20.0 (or compatible version)
- Internet connection (first time only, to install build tools)
- SSH access to the Pi
