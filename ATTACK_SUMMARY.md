# What Each Attack Does

This document describes the four attack modules and how they work. Each one targets a different TrustZone weakness on the Raspberry Pi 4.

## 1. DMA Attack

**What it does:** Uses the hardware DMA controller to read and write memory in the Secure World. Most Raspberry Pi 4 peripherals (USB, Ethernet, GPIO) have direct access to physical memory—this attack programs the DMA controller to access addresses that should be protected.

**Why it matters:** The DMA controller doesn't understand TrustZone isolation, so if it can reach an address, it bypasses all software protections.

**How to run:**
```bash
sudo bash execute_attack.sh --module dma_attack
```

**What happens:** The module will attempt to read/write to known OP-TEE memory regions via DMA and report success/failure in kernel logs.

## 2. SMC Fuzzer

**What it does:** Sends malformed and random Secure Monitor Calls (SMCs) to OP-TEE to find bugs. The SMC interface is the boundary between Normal and Secure Worlds—this attack fuzzes that boundary to find crashes, hangs, or logic errors.

**Why it matters:** If the Secure Monitor has bugs in its input validation, an attacker in the Normal World can trigger them to crash or compromise the Secure World.

**How to run:**
```bash
sudo bash execute_attack.sh --module smc_fuzzer
```

**What happens:** The module will send 1000+ malformed SMC calls and watch for kernel panics or hangs. Any crashes are logged.

## 3. Cache Timing Attack

**What it does:** Measures how long it takes to access memory to infer what the Secure World is doing. Modern CPUs cache recently-accessed memory—cache hits are fast, misses are slow. By measuring access times, you can tell whether the Secure World is using certain memory.

**Why it matters:** Even though you can't directly read Secure World memory, cache timing leaks information about what it's doing. This is a side-channel attack (like Spectre).

**How to run:**
```bash
sudo bash execute_attack.sh --module cache_timing_attack
```

**What happens:** The module measures CPU cycle counts for memory accesses before and after triggering SMC calls, then logs timing differences that could reveal Secure World behavior.

## 4. Peripheral Isolation Test

**What it does:** Checks which peripherals (USB, Ethernet, GPIO, DMA) can access memory without going through TrustZone's protection. It tests each peripheral's ability to map memory and perform DMA to see which ones could be weaponized.

**Why it matters:** Ideally, the secure world should restrict which peripherals can initiate DMA. But on RPi4, many peripherals don't go through proper isolation checks.

**How to run:**
```bash
sudo bash execute_attack.sh --module peripheral_isolation_test
```

**What happens:** The module attempts to access and program each peripheral, then reports which ones can read/write physical memory.



---

## Running All Attacks

Once you've built the modules with `BUILD_ON_PI.sh`, running everything is simple:

```bash
# Run all attacks at once
cd ~/ece595_testing/pi_attack_runner
sudo bash run_attacks.sh --local ~/ece595_testing/kernel_modules
```

This will load each module, execute it, capture logs, and look for crashes. Results go to `/tmp/attack_results/`.

---

## Extending the Framework

Want to write your own attack? Use `attack_template.c` as a starting point. It includes:
- Example DMA operations
- Example SMC calls
- Timing measurement utilities
- A `/proc` interface for easy control from userspace

Just copy the template, edit the attack logic, add it to the Makefile, and run `BUILD_ON_PI.sh` again.

---

## Next Steps

1. **[RASPBERRY_PI_DEPLOYMENT.md](RASPBERRY_PI_DEPLOYMENT.md)** — Detailed setup guide if you hit any issues
2. **[pi_attack_runner/PARTNER_GUIDE.md](pi_attack_runner/PARTNER_GUIDE.md)** — Complete walkthrough of running attacks
3. **Run `sudo bash quick_test.sh`** — Verify everything is working


