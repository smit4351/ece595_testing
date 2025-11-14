/*
 * peripheral_isolation_test.ko - Test Peripheral Isolation Weaknesses
 * 
 * Tests whether peripherals (USB, Ethernet, GPIO) can access
 * Secure World memory, exploiting weak peripheral isolation.
 *
 * TeX Reference: "peripheral isolation and DMA protections are known 
 *                 to be less comprehensive than those in high-end devices"
 *
 * Usage:
 *   insmod peripheral_isolation_test.ko
 *   echo "test usb" > /proc/peripheral_test
 *   cat /proc/peripheral_test
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/io.h>
#include <linux/ioport.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("ECE595 Research Team");
MODULE_DESCRIPTION("Peripheral Isolation Test for TrustZone");
MODULE_VERSION("1.0");

#define PROC_NAME "peripheral_test"

/* BCM2711 (RPi4) Peripheral Base Addresses */
#define BCM2711_PERI_BASE    0xFE000000
#define USB_BASE_OFFSET      0x00980000  // USB controller
#define ETH_BASE_OFFSET      0x001C0000  // Gigabit Ethernet
#define GPIO_BASE_OFFSET     0x00200000  // GPIO
#define DMA_BASE_OFFSET      0x00007000  // DMA controller

/* Test results */
struct peripheral_test_result {
    char peripheral_name[32];
    bool can_map_memory;
    bool can_initiate_dma;
    bool isolation_bypass_possible;
    unsigned long test_address;
    int error_code;
};

static struct peripheral_test_result test_results[4];
static int num_tests = 0;
static struct proc_dir_entry *proc_entry;

/* Test if peripheral can be mapped */
static int test_peripheral_mapping(const char *name, unsigned long phys_addr, size_t size)
{
    void __iomem *virt_addr;
    struct peripheral_test_result *result = &test_results[num_tests++];
    
    strncpy(result->peripheral_name, name, sizeof(result->peripheral_name) - 1);
    result->test_address = phys_addr;
    result->can_map_memory = false;
    result->can_initiate_dma = false;
    result->isolation_bypass_possible = false;
    
    pr_info("[PERIPH_TEST] Testing %s at 0x%lx\n", name, phys_addr);
    
    // Try to map peripheral
    virt_addr = ioremap(phys_addr, size);
    if (!virt_addr) {
        pr_warn("[PERIPH_TEST] %s: Cannot map memory\n", name);
        result->error_code = -ENOMEM;
        return -ENOMEM;
    }
    
    result->can_map_memory = true;
    pr_info("[PERIPH_TEST] %s: Successfully mapped\n", name);
    
    // Check if we can read control registers
    u32 control_reg = ioread32(virt_addr);
    pr_info("[PERIPH_TEST] %s: Control register = 0x%x\n", name, control_reg);
    
    // Check for DMA capability (look for DMA enable bits)
    if (control_reg & 0x1) {  // Common DMA enable bit
        result->can_initiate_dma = true;
        pr_warn("[PERIPH_TEST] %s: DMA capability detected!\n", name);
        
        // If peripheral can do DMA, isolation may be bypassable
        result->isolation_bypass_possible = true;
    }
    
    iounmap(virt_addr);
    return 0;
}

/* Test USB controller */
static void test_usb_peripheral(void)
{
    pr_info("[PERIPH_TEST] === Testing USB Controller ===\n");
    test_peripheral_mapping("USB", BCM2711_PERI_BASE + USB_BASE_OFFSET, 0x1000);
}

/* Test Ethernet controller */
static void test_ethernet_peripheral(void)
{
    pr_info("[PERIPH_TEST] === Testing Ethernet Controller ===\n");
    test_peripheral_mapping("Ethernet", BCM2711_PERI_BASE + ETH_BASE_OFFSET, 0x1000);
}

/* Test GPIO */
static void test_gpio_peripheral(void)
{
    pr_info("[PERIPH_TEST] === Testing GPIO ===\n");
    test_peripheral_mapping("GPIO", BCM2711_PERI_BASE + GPIO_BASE_OFFSET, 0x1000);
}

/* Test DMA controller */
static void test_dma_peripheral(void)
{
    pr_info("[PERIPH_TEST] === Testing DMA Controller ===\n");
    test_peripheral_mapping("DMA", BCM2711_PERI_BASE + DMA_BASE_OFFSET, 0x1000);
}

/* /proc interface read */
static ssize_t proc_read(struct file *file, char __user *ubuf,
                         size_t count, loff_t *ppos)
{
    char buffer[1024];
    int len = 0;
    int i;
    
    len += snprintf(buffer + len, sizeof(buffer) - len,
                   "=== Peripheral Isolation Test Results ===\n\n");
    
    for (i = 0; i < num_tests; i++) {
        struct peripheral_test_result *r = &test_results[i];
        
        len += snprintf(buffer + len, sizeof(buffer) - len,
                       "Peripheral: %s\n"
                       "  Address: 0x%lx\n"
                       "  Can Map: %s\n"
                       "  DMA Capable: %s\n"
                       "  Isolation Bypass Possible: %s\n\n",
                       r->peripheral_name,
                       r->test_address,
                       r->can_map_memory ? "YES" : "NO",
                       r->can_initiate_dma ? "YES ⚠️" : "NO",
                       r->isolation_bypass_possible ? "YES ⚠️⚠️" : "NO");
    }
    
    if (num_tests == 0) {
        len += snprintf(buffer + len, sizeof(buffer) - len,
                       "No tests run yet.\n"
                       "Use: echo 'test <peripheral>' > /proc/peripheral_test\n"
                       "Options: usb, ethernet, gpio, dma, all\n");
    }
    
    return simple_read_from_buffer(ubuf, count, ppos, buffer, len);
}

/* /proc interface write */
static ssize_t proc_write(struct file *file, const char __user *ubuf,
                          size_t count, loff_t *ppos)
{
    char cmd[64];
    
    if (count >= sizeof(cmd))
        return -EINVAL;
    
    if (copy_from_user(cmd, ubuf, count))
        return -EFAULT;
    
    cmd[count] = '\0';
    
    // Reset test count
    num_tests = 0;
    
    if (strstr(cmd, "usb")) {
        test_usb_peripheral();
    } else if (strstr(cmd, "ethernet")) {
        test_ethernet_peripheral();
    } else if (strstr(cmd, "gpio")) {
        test_gpio_peripheral();
    } else if (strstr(cmd, "dma")) {
        test_dma_peripheral();
    } else if (strstr(cmd, "all")) {
        test_usb_peripheral();
        test_ethernet_peripheral();
        test_gpio_peripheral();
        test_dma_peripheral();
    } else if (strstr(cmd, "reset")) {
        num_tests = 0;
        pr_info("[PERIPH_TEST] Results reset\n");
    }
    
    return count;
}

static const struct file_operations proc_fops = {
    .read = proc_read,
    .write = proc_write,
};

static int __init peripheral_test_init(void)
{
    pr_info("[PERIPH_TEST] Initializing peripheral isolation test module\n");
    
    proc_entry = proc_create(PROC_NAME, 0666, NULL, &proc_fops);
    if (!proc_entry) {
        pr_err("[PERIPH_TEST] Failed to create /proc entry\n");
        return -ENOMEM;
    }
    
    pr_info("[PERIPH_TEST] Module loaded. Use: echo 'test all' > /proc/%s\n", PROC_NAME);
    return 0;
}

static void __exit peripheral_test_exit(void)
{
    if (proc_entry)
        proc_remove(proc_entry);
    
    pr_info("[PERIPH_TEST] Module unloaded\n");
}

module_init(peripheral_test_init);
module_exit(peripheral_test_exit);
