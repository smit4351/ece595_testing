# Deploying to Raspberry Pi 4

This is the complete walkthrough for getting the attack framework up and running on your Raspberry Pi.

## The Quick Version

If you just want to get started:

```bash
# 1. Clone the repo on your Pi
git clone https://github.com/smit4351/ece595_testing.git
cd ece595_testing

# 2. Build the modules
bash BUILD_ON_PI.sh

# 3. Run everything
cd pi_attack_runner
sudo bash run_attacks.sh --local ~/ece595_testing/kernel_modules
```

The script handles all the setup automatically. Results appear in `/tmp/attack_results/`.

---

## The Detailed Version

### What You'll Need

- **Raspberry Pi 4** (4GB RAM recommended, though 2GB works)
- **Raspberry Pi OS 64-bit** installed on an SD card
- **OP-TEE 3.20.0** (or compatible version—usually comes pre-installed)
- **Internet connection** on the Pi (for installing build tools, first time only)
- **SSH access** from your computer to the Pi

### Why Each Tool?

- **SSH** - so you don't have to attach a keyboard/monitor to the Pi
- **Internet** - the first time, `BUILD_ON_PI.sh` installs `build-essential` and `linux-headers`
- **4GB RAM** - building kernel modules is memory-intensive; 2GB will work but be slow

### Before You Start

Verify OP-TEE is running on your Pi:

```bash
ssh pi@raspberrypi.local

# Check that OP-TEE is active
ps aux | grep optee
# You should see: /usr/bin/tee-supplicant

# Or check the device
ls -la /dev/tee* 
# Should show /dev/tee0 and /dev/teepriv0
```

If you don't see these, your Pi might not have OP-TEE installed. Contact your instructor.

---

## Step 1: Get the Code

### Option A: Clone from GitHub (Recommended)

```bash
ssh pi@raspberrypi.local
git clone https://github.com/smit4351/ece595_testing.git
cd ece595_testing
```

### Option B: Copy from Your macOS Machine

```bash
scp -r ~/Downloads/ece595_testing pi@raspberrypi.local:~/
ssh pi@raspberrypi.local
cd ~/ece595_testing
```

---

## Step 2: Build the Attack Modules

Just run the build script—it handles everything:

```bash
bash BUILD_ON_PI.sh
```

This will:
1. Install `build-essential` (compiler and tools)
2. Install `linux-headers` matching your kernel version
3. Compile all 4 attack modules (`.ko` files)
4. Show you the compiled files

The script is safe to run multiple times. It cleans up before rebuilding.

**On a Pi with 2GB RAM, this takes 5-10 minutes. On 4GB+ it's usually done in 2-3 minutes.**

### Troubleshooting the Build

**Error: "linux-headers not found"**
```bash
# Your kernel version might not have pre-built headers. Try:
sudo apt install -y linux-headers-generic
```

**Error: "out of memory"**
- Your Pi ran out of RAM. This usually happens on 512MB-1GB Pis.
- Try closing other applications and running again.
- Or add swap: `sudo dphys-swapfile swapon`

**Error: "permission denied"**
- The script needs `sudo` to install tools. Run it with `sudo bash BUILD_ON_PI.sh`

---

## Step 3: First-Time Setup

After building, do this once to set up the automation suite:

```bash
cd ~/ece595_testing/pi_attack_runner
sudo bash partner_setup.sh
```

This creates the results directory and configures the runners. You only need to do this once.

```bash
# Navigate to module directory
cd ~

# Load DMA attack module
sudo insmod dma_attack.ko
# Check if loaded
lsmod | grep dma_attack

# Load SMC fuzzer module
sudo insmod smc_fuzzer.ko
# Check if loaded
lsmod | grep smc_fuzzer

# View kernel logs
dmesg | tail -20

# Check proc interfaces
ls -la /proc/dma_attack
ls -la /proc/smc_fuzzer
```

### Step 5: Test DMA Attack Module

```bash
# Read current status
cat /proc/dma_attack

# Configure target (example)
echo "target_addr=0x3E000000 payload_size=8" | sudo tee /proc/dma_attack

# Check results
cat /proc/dma_attack

# View detailed logs
dmesg | grep dma_attack
```

### Step 6: Test SMC Fuzzer Module

```bash
# Read fuzzer status
cat /proc/smc_fuzzer

# Start fuzzing (example - CAUTION: can crash system)
echo "start" | sudo tee /proc/smc_fuzzer

# Stop fuzzing
echo "stop" | sudo tee /proc/smc_fuzzer

# View results
cat /proc/smc_fuzzer
```

### Step 7: Unload Modules (When Done)

```bash
# Unload modules
sudo rmmod smc_fuzzer
sudo rmmod dma_attack

# Verify removed
lsmod | grep -E "dma_attack|smc_fuzzer"
```

### Troubleshooting Method 1

**Problem: "insmod: ERROR: could not insert module: Invalid module format"**
```bash
# Cause: Module built for different kernel version
# Solution: Rebuild on macOS with correct headers or rebuild on Pi directly

# On Raspberry Pi, build natively:
cd ~/ece595_testing/kernel_modules
make clean
make
sudo insmod dma_attack.ko
```

**Problem: "No such device /proc/dma_attack"**
```bash
# Module didn't load properly
sudo dmesg | tail -30  # Check for errors
sudo modprobe configs  # Might need kernel configs
```

**Problem: Module loads but can't access TrustZone**
```bash
# Check if SMC calls are supported
dmesg | grep -i "smc\|psci\|trustzone"

# Some operations may require custom firmware (see Method 2)
```

---

## Method 2: Build and Deploy Full OP-TEE SD Card Image

### Overview
This method builds a **complete bootable SD card** with:
- ARM Trusted Firmware-A (TF-A)
- OP-TEE OS in Secure World
- Custom U-Boot bootloader
- Linux kernel with OP-TEE support
- Your attack modules pre-installed

### Time Required
- Build: 2-4 hours (first time)
- SD card creation: 10 minutes
- Total: ~3-4 hours

### Prerequisites
- macOS with Colima running
- 16GB+ SD card
- SD card reader
- Raspberry Pi 4
- Serial console cable (recommended for debugging)
- 3-4 hours of build time

### Step 1: Build OP-TEE on macOS

```bash
# On macOS, start container
cd ~/Downloads/ece595_testing
./scripts/run_in_container.sh shell

# Inside container:
bash scripts/build_optee.sh --in-container

# This will:
# - Clone OP-TEE 3.20.0 source (~2GB)
# - Build TF-A, OP-TEE OS, U-Boot, Linux kernel (~2-3 hours)
# - Create bootable artifacts
```

**Expected build time:**
- Fast machine (M1/M2 Mac, 8+ cores): 1.5-2 hours
- Medium machine (4 cores): 2-3 hours  
- Slow machine (2 cores): 3-4 hours

### Step 2: Create SD Card Image

Still inside the container:

```bash
cd /work/scripts/optee-project/build

# Generate SD card image
make -f rpi4.mk img

# Image will be created at:
# /work/scripts/optee-project/out-br/images/sdcard.img
# Size: ~500MB-1GB
```

### Step 3: Copy Image to macOS

Exit container and copy the image:

```bash
# Exit container
exit

# On macOS:
cd ~/Downloads/ece595_testing

# Image location in project
ls -lh scripts/optee-project/out-br/images/sdcard.img

# Optional: Compress for transfer
gzip -c scripts/optee-project/out-br/images/sdcard.img > optee-rpi4.img.gz
```

### Step 4: Flash SD Card

**On macOS:**

```bash
# Insert SD card and find its device
diskutil list
# Look for your SD card (usually /dev/disk2 or /dev/disk4)
# BE CAREFUL - wrong disk will destroy data!

# Unmount the SD card (don't eject!)
diskutil unmountDisk /dev/diskX  # Replace X with your disk number

# Flash the image
sudo dd if=scripts/optee-project/out-br/images/sdcard.img \
        of=/dev/rdiskX \
        bs=4m \
        status=progress

# Or if you compressed it:
gunzip -c optee-rpi4.img.gz | sudo dd of=/dev/rdiskX bs=4m

# Eject when done
diskutil eject /dev/diskX
```

**On Linux (if available):**

```bash
# Find SD card
lsblk

# Unmount partitions
sudo umount /dev/sdX*

# Flash image
sudo dd if=sdcard.img of=/dev/sdX bs=4M status=progress conv=fsync

# Eject
sudo eject /dev/sdX
```

### Step 5: Add Your Modules to the Image (Optional)

If you want modules pre-installed on the image:

```bash
# Mount the SD card root partition
# On macOS:
diskutil list  # Find the Linux partition (usually partition 2)
# You'll need a tool to mount ext4 on macOS (like osxfuse + ext4fuse)

# Easier: Boot the Pi first, then transfer modules via network (Method 1)
```

### Step 6: Boot Raspberry Pi 4

1. **Insert SD card** into Raspberry Pi 4
2. **Connect serial console** (optional but recommended):
   - USB-to-TTL cable to GPIO pins
   - GND → Pin 6, TX → Pin 8, RX → Pin 10
   
3. **Connect monitor** and keyboard (or use serial)

4. **Power on** the Pi

### Step 7: Connect via Serial Console

On macOS:

```bash
# Find USB serial device
ls /dev/tty.usb*

# Connect (adjust device name)
screen /dev/tty.usbserial-XXXXXXXX 115200

# Or use minicom:
brew install minicom
minicom -D /dev/tty.usbserial-XXXXXXXX -b 115200
```

You should see boot messages:
```
NOTICE:  Booting Trusted Firmware
NOTICE:  BL1: v2.8(release):v2.8
...
NOTICE:  BL31: Initializing OP-TEE
...
Starting kernel ...
```

### Step 8: Login and Verify OP-TEE

Default credentials (if using default Buildroot):
- Username: `root`
- Password: (none, just press Enter)

```bash
# Check OP-TEE is running
ls -la /dev/tee*
# Should show: /dev/tee0, /dev/teepriv0

# Check kernel
uname -a

# View OP-TEE version
cat /proc/device-tree/firmware/optee/compatible

# Test OP-TEE example
tee-supplicant &
optee_example_hello_world
```

### Step 9: Transfer and Load Your Modules

Use Method 1 steps to transfer and load your modules via network.

### Step 10: Make Modules Auto-Load (Optional)

```bash
# On the Pi, create a script
sudo nano /etc/init.d/load_modules.sh

# Add content:
#!/bin/sh
insmod /root/dma_attack.ko
insmod /root/smc_fuzzer.ko

# Make executable
sudo chmod +x /etc/init.d/load_modules.sh

# Link to run at boot
sudo ln -s /etc/init.d/load_modules.sh /etc/rc5.d/S99loadmodules
```

---

## Verification Checklist

### For Method 1 (Standard RPi OS):
- [ ] Modules compile on macOS without errors
- [ ] Modules transfer to Pi successfully  
- [ ] `insmod` loads modules without errors
- [ ] `/proc/dma_attack` and `/proc/smc_fuzzer` exist
- [ ] `lsmod` shows modules loaded
- [ ] `dmesg` shows module init messages
- [ ] Can write to proc interfaces
- [ ] Can read results from proc interfaces

### For Method 2 (Custom OP-TEE):
- [ ] OP-TEE build completes successfully
- [ ] SD card image is created (~500MB-1GB)
- [ ] SD card flashes without errors
- [ ] Pi boots from SD card
- [ ] Serial console shows TF-A and OP-TEE messages
- [ ] Linux kernel boots
- [ ] `/dev/tee0` device exists
- [ ] OP-TEE examples run successfully
- [ ] Your modules load and run

---

## Performance Notes

### Method 1:
- **Pros:**
  - Very fast (10 minutes total)
  - Easy to iterate and test changes
  - Standard, stable base system
  - Familiar Raspberry Pi OS environment

- **Cons:**
  - Limited TrustZone access (depends on RPi firmware)
  - Can't modify Secure World
  - Can't add custom Trusted Applications

### Method 2:
- **Pros:**
  - Full control over TrustZone/OP-TEE
  - Can add custom Trusted Applications
  - Complete understanding of boot chain
  - Research-grade setup

- **Cons:**
  - Very long build time (2-4 hours)
  - More complex debugging
  - Requires more expertise
  - Harder to iterate

---

## Recommended Workflow

**For Development & Testing:**
1. Use **Method 1** for rapid iteration
2. Develop and test your attack modules
3. Validate exploits work on standard kernel

**For Production Research:**
1. Once modules are stable, build **Method 2**
2. Test on full OP-TEE stack
3. Add custom Trusted Applications if needed
4. Document findings with full stack

---

## Common Issues

### Module Version Mismatch
```
Error: disagrees about version of symbol module_layout
```

**Solution:** Rebuild modules with exact kernel headers:
```bash
# On Pi:
uname -r  # Note the version
cd ~/kernel_modules
make clean
make KERNELRELEASE=$(uname -r)
```

### SMC Calls Failing
```
SMC call returned error: -1
```

**Possible causes:**
1. TrustZone not enabled in firmware → Use Method 2
2. Wrong SMC ID → Check valid IDs for your platform
3. Security violation → Operation blocked by Secure World

### System Crashes During Fuzzing
This is **expected** for some SMC IDs. The fuzzer tests undefined behavior.

**Safety tips:**
- Save work before fuzzing
- Use serial console to see crash logs
- Test on dedicated Pi, not production system
- Start with known-safe SMC IDs

---

## Next Steps

### After Deployment:

1. **Read the attack module documentation:**
   ```bash
   cat ~/ece595_testing/kernel_modules/dma_attack.c  # Read header comments
   cat ~/ece595_testing/kernel_modules/smc_fuzzer.c
   ```

2. **Test individual features:**
   - DMA mapping
   - Memory scanning
   - SMC call fuzzing
   - Results collection

3. **Document your findings:**
   - Create experiment logs
   - Record successful exploits
   - Note crash conditions

4. **Expand research:**
   - Modify modules for new attacks
   - Add custom Trusted Applications (Method 2)
   - Test on different firmware versions

---

## Support

### Getting Help:

**Build issues:** See `build.log` in project root  
**Module issues:** Check `dmesg` output on Pi  
**OP-TEE issues:** Read official docs at https://optee.readthedocs.io

### Useful Commands:

```bash
# View all kernel messages
dmesg | less

# Monitor kernel log live
dmesg -w

# Check loaded modules
lsmod

# Get module info
modinfo dma_attack.ko

# View module parameters
cat /sys/module/dma_attack/parameters/*

# Check system resources
free -h
df -h
```

---

## Summary

- **Quick testing:** Use Method 1 (10 minutes)
- **Full research:** Use Method 2 (3-4 hours)
- **Both methods** support your kernel modules
- **Method 2 required** for custom Trusted Applications
- **Start simple**, upgrade to complex as needed

Good luck with your TrustZone research! 🔒🔓
