//
//  jit_enabler.h
//  DarkJIT
//

#ifndef jit_enabler_h
#define jit_enabler_h

#import <Foundation/Foundation.h>
#include <stdint.h>
#include <unistd.h>

// CS flags from XNU bsd/sys/codesign.h
#define CS_VALID                    0x00000001
#define CS_GET_TASK_ALLOW           0x00000004
#define CS_INSTALLER                0x00000008
#define CS_HARD                     0x00000100
#define CS_KILL                     0x00000200
#define CS_RESTRICT                 0x00000800
#define CS_ENFORCEMENT              0x00001000
#define CS_REQUIRE_LV               0x00002000
#define CS_RUNTIME                  0x00010000
#define CS_DEBUGGED                 0x10000000

// proc p_flag bits from XNU bsd/sys/proc.h
#define P_TRACED                    0x00000800

/// Enable JIT for a process by PID.
/// Patches csflags to add CS_DEBUGGED | CS_GET_TASK_ALLOW and optionally
/// sets P_TRACED for pmap_cs W^X bypass on iOS 18.6+.
/// Returns 0 on success, -1 on failure.
int enable_jit_for_pid(pid_t pid);

/// Check if JIT is currently enabled for a process.
/// Returns YES if CS_DEBUGGED is set in the process's csflags.
BOOL is_jit_enabled_for_pid(pid_t pid);

/// Get a human-readable description of the current csflags for a process.
NSString *csflags_description_for_pid(pid_t pid);

#endif /* jit_enabler_h */
