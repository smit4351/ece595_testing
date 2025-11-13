/*
 * smc_fuzzer.ko - Kernel Module for SMC Interface Fuzzing
 * 
 * This kernel module provides a safe interface for fuzzing the
 * Secure Monitor Call (SMC) interface from kernel context.
 *
 * Usage:
 *   insmod smc_fuzzer.ko
 *   echo "fuzz 100" > /proc/smc_fuzzer  # Run 100 fuzz iterations
 *   cat /proc/smc_fuzzer                # Get status
 *   rmmod smc_fuzzer
 *
 * Copyright (C) 2025 - Educational/Research Purposes Only
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/random.h>
#include <linux/slab.h>
#include <linux/arm-smccc.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("ECE595 Research Team");
MODULE_DESCRIPTION("SMC Fuzzing Module for ARM TrustZone Research");
MODULE_VERSION("1.0");

#define PROC_NAME "smc_fuzzer"

/* OP-TEE SMC Function IDs */
#define OPTEE_SMC_CALL_RETURN_FROM_RPC     0xb2000003
#define OPTEE_SMC_CALL_WITH_ARG            0xb2000004
#define OPTEE_SMC_GET_SHM_CONFIG           0xb2000007
#define OPTEE_SMC_EXCHANGE_CAPABILITIES    0xb2000009
#define OPTEE_SMC_DISABLE_SHM_CACHE        0xb200000a
#define OPTEE_SMC_ENABLE_SHM_CACHE         0xb200000b

/* Fuzzing statistics */
struct fuzz_stats {
    u64 total_iterations;
    u64 crashes;
    u64 hangs;
    u64 interesting_cases;
    u64 valid_responses;
    u64 error_responses;
    u32 last_smc_id;
    s64 last_result;
};

static struct fuzz_stats stats = {0};
static bool fuzzing_enabled = true;

/* Known OP-TEE SMC IDs for seed corpus */
static u32 known_smc_ids[] = {
    OPTEE_SMC_CALL_RETURN_FROM_RPC,
    OPTEE_SMC_CALL_WITH_ARG,
    OPTEE_SMC_GET_SHM_CONFIG,
    OPTEE_SMC_EXCHANGE_CAPABILITIES,
    OPTEE_SMC_DISABLE_SHM_CACHE,
    OPTEE_SMC_ENABLE_SHM_CACHE,
};

/*
 * Execute a single SMC call with given parameters
 * Returns: 0 on success, negative on error
 */
static int execute_smc(u32 func_id, u64 a1, u64 a2, u64 a3, 
                      u64 a4, u64 a5, u64 a6, struct arm_smccc_res *res)
{
    /* Use ARM SMCCC interface for safe SMC invocation */
    arm_smccc_smc(func_id, a1, a2, a3, a4, a5, a6, 0, res);
    
    stats.last_smc_id = func_id;
    stats.last_result = res->a0;
    
    /* Check for standard error codes */
    if (res->a0 == 0) {
        stats.valid_responses++;
        return 0;
    } else if ((s64)res->a0 < 0) {
        stats.error_responses++;
        return -1;
    }
    
    stats.interesting_cases++;
    return 0;
}

/*
 * Generate a random SMC function ID
 */
static u32 generate_random_smc_id(bool use_known)
{
    u32 id;
    
    if (use_known && (get_random_u32() % 2)) {
        /* 50% chance: use known OP-TEE SMC ID */
        int idx = get_random_u32() % ARRAY_SIZE(known_smc_ids);
        return known_smc_ids[idx];
    }
    
    /* Generate random ID in OP-TEE range (0xb2000000 - 0xb2ffffff) */
    id = 0xb2000000 | (get_random_u32() & 0x00ffffff);
    return id;
}

/*
 * Generate random parameter value with various patterns
 */
static u64 generate_random_param(void)
{
    u32 pattern = get_random_u32() % 10;
    
    switch (pattern) {
    case 0: return 0;                          /* Zero */
    case 1: return 0xFFFFFFFFFFFFFFFFULL;      /* All ones */
    case 2: return 0x8000000000000000ULL;      /* Sign bit */
    case 3: return 0x7FFFFFFFFFFFFFFFULL;      /* Max positive */
    case 4: return get_random_u32();           /* Random 32-bit */
    case 5: return get_random_u64();           /* Random 64-bit */
    case 6: return 0x1000;                     /* Page size */
    case 7: return 0x1000 + (get_random_u32() & 0xFFF); /* Near page */
    case 8: return (u64)(-1L);                 /* -1 */
    default: return get_random_u64() & 0xFFFFFFFFULL; /* Random low 32-bit */
    }
}

/*
 * Perform one fuzzing iteration
 */
static int fuzz_iteration(void)
{
    struct arm_smccc_res res;
    u32 func_id;
    u64 params[6];
    int i, ret;
    
    stats.total_iterations++;
    
    /* Generate function ID */
    func_id = generate_random_smc_id(true);
    
    /* Generate parameters */
    for (i = 0; i < 6; i++)
        params[i] = generate_random_param();
    
    /* Execute SMC */
    ret = execute_smc(func_id, params[0], params[1], params[2],
                     params[3], params[4], params[5], &res);
    
    /* Log interesting cases */
    if (ret < 0 || res.a0 != 0) {
        pr_debug("smc_fuzzer: func_id=0x%08x result=0x%llx\n", 
                func_id, (unsigned long long)res.a0);
    }
    
    return 0;
}

/*
 * Run fuzzing campaign with specified number of iterations
 */
static int run_fuzzing_campaign(u32 iterations)
{
    u32 i;
    
    pr_info("smc_fuzzer: Starting fuzzing campaign (%u iterations)\n", iterations);
    
    for (i = 0; i < iterations; i++) {
        if (!fuzzing_enabled) {
            pr_info("smc_fuzzer: Fuzzing stopped by user\n");
            break;
        }
        
        fuzz_iteration();
        
        /* Yield CPU periodically to avoid lockup */
        if ((i % 100) == 0)
            cond_resched();
    }
    
    pr_info("smc_fuzzer: Campaign complete. Iterations=%u\n", i);
    return 0;
}

/*
 * Test known OP-TEE SMC IDs with valid parameters
 */
static int test_known_smcs(void)
{
    struct arm_smccc_res res;
    int i;
    
    pr_info("smc_fuzzer: Testing known OP-TEE SMC IDs\n");
    
    for (i = 0; i < ARRAY_SIZE(known_smc_ids); i++) {
        execute_smc(known_smc_ids[i], 0, 0, 0, 0, 0, 0, &res);
        
        pr_info("smc_fuzzer: SMC 0x%08x -> result=0x%llx\n",
                known_smc_ids[i], (unsigned long long)res.a0);
    }
    
    return 0;
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
                   "SMC Fuzzer Status\n"
                   "=================\n"
                   "Fuzzing Enabled: %s\n"
                   "Total Iterations: %llu\n"
                   "Crashes: %llu\n"
                   "Hangs: %llu\n"
                   "Interesting Cases: %llu\n"
                   "Valid Responses: %llu\n"
                   "Error Responses: %llu\n"
                   "Last SMC ID: 0x%08x\n"
                   "Last Result: 0x%llx\n"
                   "\nCommands:\n"
                   "  echo \"fuzz N\" > /proc/" PROC_NAME "     # Run N iterations\n"
                   "  echo \"test\" > /proc/" PROC_NAME "       # Test known SMCs\n"
                   "  echo \"enable\" > /proc/" PROC_NAME "     # Enable fuzzing\n"
                   "  echo \"disable\" > /proc/" PROC_NAME "    # Disable fuzzing\n"
                   "  echo \"reset\" > /proc/" PROC_NAME "      # Reset statistics\n",
                   fuzzing_enabled ? "yes" : "no",
                   stats.total_iterations,
                   stats.crashes,
                   stats.hangs,
                   stats.interesting_cases,
                   stats.valid_responses,
                   stats.error_responses,
                   stats.last_smc_id,
                   (unsigned long long)stats.last_result);
    
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
    char buf[128];
    u32 iterations;
    
    if (count >= sizeof(buf))
        return -EINVAL;
    
    if (copy_from_user(buf, ubuf, count))
        return -EFAULT;
    
    buf[count] = '\0';
    
    /* Parse command */
    if (sscanf(buf, "fuzz %u", &iterations) == 1) {
        run_fuzzing_campaign(iterations);
        
    } else if (strncmp(buf, "test", 4) == 0) {
        test_known_smcs();
        
    } else if (strncmp(buf, "enable", 6) == 0) {
        fuzzing_enabled = true;
        pr_info("smc_fuzzer: Fuzzing enabled\n");
        
    } else if (strncmp(buf, "disable", 7) == 0) {
        fuzzing_enabled = false;
        pr_info("smc_fuzzer: Fuzzing disabled\n");
        
    } else if (strncmp(buf, "reset", 5) == 0) {
        memset(&stats, 0, sizeof(stats));
        pr_info("smc_fuzzer: Statistics reset\n");
        
    } else {
        pr_err("smc_fuzzer: Unknown command\n");
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
static int __init smc_fuzzer_init(void)
{
    struct proc_dir_entry *proc_entry;
    
    pr_info("smc_fuzzer: Initializing SMC Fuzzing Module\n");
    
    /* Create /proc entry */
    proc_entry = proc_create(PROC_NAME, 0666, NULL, &proc_fops);
    if (!proc_entry) {
        pr_err("smc_fuzzer: Failed to create /proc entry\n");
        return -ENOMEM;
    }
    
    pr_info("smc_fuzzer: Module loaded successfully\n");
    pr_info("smc_fuzzer: Interface available at /proc/%s\n", PROC_NAME);
    
    /* Run initial test of known SMCs */
    test_known_smcs();
    
    return 0;
}

/*
 * Module cleanup
 */
static void __exit smc_fuzzer_exit(void)
{
    pr_info("smc_fuzzer: Cleaning up\n");
    
    remove_proc_entry(PROC_NAME, NULL);
    
    pr_info("smc_fuzzer: Final statistics:\n");
    pr_info("  Total iterations: %llu\n", stats.total_iterations);
    pr_info("  Interesting cases: %llu\n", stats.interesting_cases);
    pr_info("  Crashes: %llu\n", stats.crashes);
    
    pr_info("smc_fuzzer: Module unloaded\n");
}

module_init(smc_fuzzer_init);
module_exit(smc_fuzzer_exit);
