#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/delay.h>
#include <linux/string.h>
#include <linux/types.h>
#include <asm/io.h>

/*
 * ATTACK_TEMPLATE.C
 *
 * A skeleton for rapid TrustZone attack development.
 * Copy this file to create a new attack module.
 *
 * Usage:
 *   cp kernel_modules/attack_template.c kernel_modules/my_new_attack.c
 *   Edit the ATTACK LOGIC section below
 *   Update kernel_modules/Makefile: add "obj-m += my_new_attack.o"
 *   Build: ./scripts/run_in_container.sh build-modules
 *
 * Interface:
 *   /proc/attack_template — read for status, write commands
 */

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Attack Developer");
MODULE_DESCRIPTION("Template for TrustZone Attack Module");

#define PROC_NAME "attack_template"
#define ATTACK_NAME "TemplateAttack"

/* =================================================================
 * ATTACK CONFIGURATION — EDIT THESE FOR YOUR ATTACK
 * ================================================================= */

/* Target address in Secure World (update based on reconnaissance) */
static uint64_t target_address = 0xc0000000;

/* Attack timeout in milliseconds */
#define ATTACK_TIMEOUT_MS 5000

/* Payload data (customize for your attack) */
static const char ATTACK_PAYLOAD[] = {
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77
};
#define PAYLOAD_SIZE sizeof(ATTACK_PAYLOAD)

/* =================================================================
 * ATTACK STATE TRACKING
 * ================================================================= */

struct attack_state {
    int running;
    unsigned long iterations;
    int last_result;
    char status_msg[256];\n};

static struct attack_state state = {
    .running = 0,
    .iterations = 0,
    .last_result = 0,
    .status_msg = "Idle",
};

static struct proc_dir_entry *proc_entry;

/* =================================================================
 * ATTACK LOGIC — IMPLEMENT YOUR EXPLOIT HERE
 * ================================================================= */

/*
 * execute_attack() — Main attack logic
 *
 * This is where your exploit happens.
 * Modify this function to implement your specific attack.
 *
 * Examples:
 *   - DMA read/write to target_address
 *   - SMC call with crafted parameters
 *   - Memory timing attack
 *   - Cache-based side channel
 */
static int execute_attack(void)
{
    int result = -1;
    
    // Log attack parameters
    pr_info("=== %s Attack Starting ===\n", ATTACK_NAME);
    pr_info("Target Address: 0x%llx\n", target_address);
    pr_info("Payload Size: %lu bytes\n", (unsigned long)PAYLOAD_SIZE);
    
    /* ============================================================
     * REPLACE THIS SECTION WITH YOUR ATTACK CODE
     * ============================================================ */
    
    // Example 1: Simple DMA read attempt
    // uint64_t read_value = perform_dma_read(target_address);
    // if (read_value == 0xDEADBEEF) {
    //     pr_info("Successfully read Secure World memory!\n");
    //     result = 1;  // Success
    // }
    
    // Example 2: SMC fuzzing
    // for (int i = 0; i < 100; i++) {
    //     uint32_t smc_cmd = 0xc6000000 + i;
    //     invoke_smc(smc_cmd);
    //     if (detect_panic()) {
    //         pr_info("SMC 0x%x caused panic\n", smc_cmd);
    //         result = 1;
    //     }
    // }
    
    // Example 3: Memory write attack
    // void *vaddr = phys_to_virt(target_address);
    // if (vaddr) {
    //     memcpy(vaddr, ATTACK_PAYLOAD, PAYLOAD_SIZE);
    //     pr_info("Payload written to 0x%llx\n", target_address);
    //     result = 1;
    // }
    
    // Placeholder: just log for testing
    pr_info("Attack executed (placeholder)\n");
    result = 0;  // 0 = executed, 1 = success, -1 = error
    
    /* ============================================================
     * END OF ATTACK CODE
     * ============================================================ */
    
    pr_info("=== %s Attack Complete (result: %d) ===\n", ATTACK_NAME, result);
    return result;
}

/* =================================================================
 * HELPER FUNCTIONS (Generic, reusable)
 * ================================================================= */

/*
 * invoke_smc() — Make an SMC call to Secure Monitor
 * Useful for SMC-based attacks and fuzzing
 */
static uint32_t invoke_smc(uint32_t smc_id)
{
    uint32_t result;
    register uint32_t r0 asm("r0") = smc_id;
    
    asm volatile (
        "smc #0"
        : "+r"(r0)
        :
        : "memory"
    );
    
    result = r0;
    return result;
}

/*
 * perform_dma_read() — Example: read via DMA
 * Placeholder for DMA operations
 */
static uint64_t perform_dma_read(uint64_t physical_address)
{
    // TODO: Implement actual DMA read via BCM2711 controller
    // For now, just read directly (works if memory is accessible)
    volatile uint64_t *addr = phys_to_virt(physical_address);
    
    if (!addr) {
        pr_err("Cannot map physical address 0x%llx\n", physical_address);
        return 0;
    }
    
    uint64_t value = *addr;
    pr_info("DMA read from 0x%llx: 0x%llx\n", physical_address, value);
    return value;
}

/*
 * detect_panic() — Check if Secure World crashed
 * Placeholder for panic detection
 */
static int detect_panic(void)
{
    /* TODO: Implement actual panic detection
       Could monitor:
       - Serial console output
       - Secure World heartbeat (if available)
       - SMC response codes
       - /sys/kernel/debug/optee/panic (if exposed) */
    
    return 0;
}

/* =================================================================
 * /PROC INTERFACE — For user-space control
 * ================================================================= */

static ssize_t proc_read(struct file *file, char __user *ubuf,
                         size_t count, loff_t *ppos)
{
    char buffer[512];
    int len;
    
    len = snprintf(buffer, sizeof(buffer),
        "=== %s ===\n"
        "Status: %s\n"
        "Running: %s\n"
        "Iterations: %lu\n"
        "Last Result: %d\n"
        "Target Address: 0x%llx\n"
        "\nUsage:\n"
        "  echo 'start' > /proc/%s          # Start attack\n"
        "  echo 'stop' > /proc/%s           # Stop attack\n"
        "  echo 'target:0x12345678' > /proc/%s  # Set target address\n"
        "  cat /proc/%s                     # Read status\n",
        ATTACK_NAME,
        state.status_msg,
        state.running ? "yes" : "no",
        state.iterations,
        state.last_result,
        target_address,
        PROC_NAME,
        PROC_NAME,
        PROC_NAME,
        PROC_NAME
    );
    
    return simple_read_from_buffer(ubuf, count, ppos, buffer, len);
}

static ssize_t proc_write(struct file *file, const char __user *ubuf,
                          size_t count, loff_t *ppos)
{
    char cmd[64];
    unsigned long addr;
    
    if (count >= sizeof(cmd))
        return -EINVAL;
    
    if (copy_from_user(cmd, ubuf, count))
        return -EFAULT;
    
    cmd[count] = '\0';
    
    /* Parse commands */
    if (strncmp(cmd, "start", 5) == 0) {
        pr_info("Starting %s attack...\n", ATTACK_NAME);
        state.running = 1;
        state.iterations++;
        state.last_result = execute_attack();
        state.running = 0;
        snprintf(state.status_msg, sizeof(state.status_msg),
                 "Completed (result: %d)", state.last_result);
        
    } else if (strncmp(cmd, "stop", 4) == 0) {
        pr_info("Stopping %s attack\n", ATTACK_NAME);
        state.running = 0;
        snprintf(state.status_msg, sizeof(state.status_msg), "Stopped");
        
    } else if (strncmp(cmd, "target:", 7) == 0) {
        if (kstrtoul(cmd + 7, 16, &addr) == 0) {
            target_address = (uint64_t)addr;
            pr_info("Target address set to 0x%lx\n", addr);
            snprintf(state.status_msg, sizeof(state.status_msg),
                     "Target updated to 0x%lx", addr);
        }
        
    } else if (strncmp(cmd, "reset", 5) == 0) {
        state.iterations = 0;
        state.last_result = 0;
        snprintf(state.status_msg, sizeof(state.status_msg), "Reset");
        
    } else {
        pr_warn("Unknown command: %s\n", cmd);
        return -EINVAL;
    }
    
    return count;
}

static const struct file_operations proc_fops = {
    .read = proc_read,
    .write = proc_write,
};

/* =================================================================
 * MODULE INIT/EXIT
 * ================================================================= */

static int __init attack_template_init(void)
{
    pr_info("Loading %s kernel module\n", ATTACK_NAME);
    
    proc_entry = proc_create(PROC_NAME, 0666, NULL, &proc_fops);
    if (!proc_entry) {
        pr_err("Failed to create /proc/%s\n", PROC_NAME);
        return -ENOMEM;
    }
    
    snprintf(state.status_msg, sizeof(state.status_msg), "Loaded");
    pr_info("Module loaded successfully. Use: echo start > /proc/%s\n", PROC_NAME);
    
    return 0;
}

static void __exit attack_template_exit(void)
{
    pr_info("Unloading %s kernel module\n", ATTACK_NAME);
    
    if (proc_entry)
        proc_remove(proc_entry);
    
    state.running = 0;
}

module_init(attack_template_init);
module_exit(attack_template_exit);

/* =================================================================
 * CUSTOMIZATION GUIDE
 * ================================================================= */

/*
 * To create your attack:
 *
 * 1. Copy this file:
 *    cp kernel_modules/attack_template.c kernel_modules/my_attack.c
 *
 * 2. Edit these sections:
 *    - ATTACK CONFIGURATION (lines 38-53)
 *      Set target_address, timeout, payload
 *
 *    - execute_attack() (lines 66-113)
 *      Replace placeholder with your actual attack code
 *      Use helper functions: invoke_smc(), perform_dma_read(), etc.
 *
 *    - MODULE_DESCRIPTION (line 18)
 *      Describe your attack
 *
 *    - ATTACK_NAME constant (line 27)
 *      Name your attack for logging
 *
 * 3. Add to Makefile:
 *    echo "obj-m += my_attack.o" >> kernel_modules/Makefile
 *
 * 4. Build:
 *    ./scripts/run_in_container.sh build-modules
 *
 * 5. Have partner deploy:
 *    scp kernel_modules/my_attack.ko pi@raspberrypi.local:~/
 *    ssh pi@raspberrypi.local "sudo insmod my_attack.ko"
 *
 * 6. Test via /proc interface:
 *    ssh pi@raspberrypi.local "echo start > /proc/my_attack"
 *    ssh pi@raspberrypi.local "cat /proc/my_attack"
 *    ssh pi@raspberrypi.local "dmesg | tail -20"
 *
 * 7. Iterate based on results!
 */
