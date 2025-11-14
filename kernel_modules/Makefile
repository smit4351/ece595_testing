# Makefile for ARM TrustZone Kernel Modules
# Supports both cross-compilation and native builds on Raspberry Pi 4

# Module version (for reproducibility)
MODULE_VERSION := 2.0

# Kernel module objects
obj-m += dma_attack.o
obj-m += smc_fuzzer.o
obj-m += cache_timing_attack.o
obj-m += peripheral_isolation_test.o

# Detect architecture and set defaults
ARCH ?= arm64
CROSS_COMPILE ?= aarch64-linux-gnu-

# Kernel source directory auto-detection
ifndef KERNEL_SRC
    # Try native kernel headers first (for on-device compilation)
    ifneq ($(wildcard /lib/modules/$(shell uname -r)/build),)
        KERNEL_SRC := /lib/modules/$(shell uname -r)/build
        $(info Auto-detected kernel source: $(KERNEL_SRC))
    # Try OP-TEE project tree
    else ifneq ($(wildcard ../optee-project/linux),)
        KERNEL_SRC := $(PWD)/../optee-project/linux
        $(info Using OP-TEE kernel source: $(KERNEL_SRC))
    # Try parent directory optee-project
    else ifneq ($(wildcard ../../optee-project/linux),)
        KERNEL_SRC := $(realpath ../../optee-project/linux)
        $(info Using OP-TEE kernel source: $(KERNEL_SRC))
    else
        $(error KERNEL_SRC not set and could not auto-detect. Set KERNEL_SRC=/path/to/kernel)
    endif
endif

# Build flags
EXTRA_CFLAGS := -Wall -Wextra -DMODULE_VERSION=\"$(MODULE_VERSION)\"

# Check if kernel source exists
$(shell test -d $(KERNEL_SRC) || (echo "ERROR: Kernel source not found: $(KERNEL_SRC)" >&2 && exit 1))

# Default target
all: modules

# Build kernel modules
modules:
	@echo "============================================="
	@echo "Building ARM TrustZone Kernel Modules v$(MODULE_VERSION)"
	@echo "============================================="
	@echo "Architecture:     $(ARCH)"
	@echo "Cross-compiler:   $(CROSS_COMPILE)"
	@echo "Kernel source:    $(KERNEL_SRC)"
	@echo "Build directory:  $(PWD)"
	@echo "============================================="
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
		-C $(KERNEL_SRC) M=$(PWD) modules
	@echo ""
	@echo "Build complete!"
	@ls -lh *.ko 2>/dev/null || echo "No .ko files found - build may have failed"

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
		-C $(KERNEL_SRC) M=$(PWD) clean 2>/dev/null || true
	rm -f *.ko.cmd *.mod.cmd *.o.cmd .*.cmd
	rm -rf .tmp_versions Module.symvers modules.order
	@echo "Clean complete."

# Install modules (for native compilation on Pi)
install: modules
	@echo "Installing kernel modules..."
	@echo "Unloading old versions if present..."
	-sudo rmmod smc_fuzzer 2>/dev/null
	-sudo rmmod dma_attack 2>/dev/null
	@echo "Loading new modules..."
	sudo insmod dma_attack.ko
	sudo insmod smc_fuzzer.ko
	@echo ""
	@echo "Modules loaded successfully!"
	@lsmod | grep -E "dma_attack|smc_fuzzer"
	@echo ""
	@echo "Module interfaces:"
	@echo "  /proc/dma_attack"
	@echo "  /proc/smc_fuzzer"

# Uninstall modules
uninstall:
	@echo "Unloading kernel modules..."
	-sudo rmmod smc_fuzzer 2>/dev/null
	-sudo rmmod dma_attack 2>/dev/null
	@echo "Modules unloaded."

# Verify modules
verify:
	@echo "Verifying kernel modules..."
	@if [ -f dma_attack.ko ]; then \
		echo "✓ dma_attack.ko:"; \
		modinfo dma_attack.ko | grep -E "filename|version|description|depends|vermagic"; \
	else \
		echo "✗ dma_attack.ko not found"; \
	fi
	@echo ""
	@if [ -f smc_fuzzer.ko ]; then \
		echo "✓ smc_fuzzer.ko:"; \
		modinfo smc_fuzzer.ko | grep -E "filename|version|description|depends|vermagic"; \
	else \
		echo "✗ smc_fuzzer.ko not found"; \
	fi

# Help target
help:
	@echo "ARM TrustZone Kernel Module Build System v$(MODULE_VERSION)"
	@echo "============================================="
	@echo ""
	@echo "Targets:"
	@echo "  make              - Build kernel modules"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make install      - Load modules (on Raspberry Pi)"
	@echo "  make uninstall    - Unload modules"
	@echo "  make verify       - Check module information"
	@echo "  make help         - Show this help"
	@echo ""
	@echo "Environment variables:"
	@echo "  KERNEL_SRC        - Path to kernel source (auto-detected if not set)"
	@echo "  ARCH              - Target architecture (default: arm64)"
	@echo "  CROSS_COMPILE     - Cross-compiler prefix (default: aarch64-linux-gnu-)"
	@echo ""
	@echo "Examples:"
	@echo ""
	@echo "  Cross-compile for RPi4 (on x86_64 host):"
	@echo "    make KERNEL_SRC=/path/to/linux ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-"
	@echo ""
	@echo "  Native compile on RPi4:"
	@echo "    make ARCH=arm64 CROSS_COMPILE="
	@echo ""
	@echo "  Install on RPi4:"
	@echo "    sudo make install"
	@echo ""
	@echo "  Clean and rebuild:"
	@echo "    make clean && make"
	@echo ""
	@echo "Current configuration:"
	@echo "  KERNEL_SRC    = $(KERNEL_SRC)"
	@echo "  ARCH          = $(ARCH)"
	@echo "  CROSS_COMPILE = $(CROSS_COMPILE)"

.PHONY: all modules clean install uninstall verify help

