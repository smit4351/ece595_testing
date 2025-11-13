# Makefile for ARM TrustZone Kernel Modules
# Cross-compilation for Raspberry Pi 4 (BCM2711 / ARMv8)

# Kernel module objects
obj-m += dma_attack.o
obj-m += smc_fuzzer.o

# Detect architecture and set defaults
ARCH ?= arm64
CROSS_COMPILE ?= aarch64-linux-gnu-

# Kernel source directory (must be set for cross-compilation)
# Default to common locations, can be overridden via environment
ifndef KERNEL_SRC
    ifneq ($(wildcard ../optee-project/linux),)
        KERNEL_SRC := $(PWD)/../optee-project/linux
    else ifneq ($(wildcard /lib/modules/$(shell uname -r)/build),)
        KERNEL_SRC := /lib/modules/$(shell uname -r)/build
    else
        KERNEL_SRC := /path/to/rpi4/kernel/source
    endif
endif

# Build flags
EXTRA_CFLAGS := -Wall -Wextra

# Default target
all: modules

# Build kernel modules
modules:
	@echo "Building kernel modules for $(ARCH)..."
	@echo "Kernel source: $(KERNEL_SRC)"
	@echo "Cross compiler: $(CROSS_COMPILE)"
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
		-C $(KERNEL_SRC) M=$(PWD) modules

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
		-C $(KERNEL_SRC) M=$(PWD) clean
	rm -f *.ko.cmd *.mod.cmd *.o.cmd .*.cmd
	rm -rf .tmp_versions

# Install modules (for native compilation on Pi)
install: modules
	@echo "Installing kernel modules..."
	sudo insmod dma_attack.ko
	sudo insmod smc_fuzzer.ko
	@echo "Modules loaded. Check with: lsmod | grep -E 'dma_attack|smc_fuzzer'"

# Uninstall modules
uninstall:
	@echo "Unloading kernel modules..."
	-sudo rmmod smc_fuzzer 2>/dev/null
	-sudo rmmod dma_attack 2>/dev/null
	@echo "Modules unloaded."

# Help target
help:
	@echo "ARM TrustZone Kernel Module Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make              - Build kernel modules (cross-compile)"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make install      - Load modules (on Raspberry Pi)"
	@echo "  make uninstall    - Unload modules"
	@echo "  make help         - Show this help"
	@echo ""
	@echo "Environment variables:"
	@echo "  KERNEL_SRC        - Path to kernel source tree"
	@echo "  ARCH              - Target architecture (default: arm64)"
	@echo "  CROSS_COMPILE     - Cross-compiler prefix (default: aarch64-linux-gnu-)"
	@echo ""
	@echo "Examples:"
	@echo "  # Cross-compile for RPi4:"
	@echo "  make KERNEL_SRC=/path/to/linux ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-"
	@echo ""
	@echo "  # Native compile on RPi4:"
	@echo "  make ARCH=arm64 CROSS_COMPILE="
	@echo ""
	@echo "  # Install on RPi4:"
	@echo "  make install"

.PHONY: all modules clean install uninstall help
