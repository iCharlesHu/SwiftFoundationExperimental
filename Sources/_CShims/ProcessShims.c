//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#include "include/_CShimsTargetConditionals.h"
#include "include/ProcessShims.h"
#include <errno.h>
#include <signal.h>

#if TARGET_OS_MAC

int _subprocess_spawn(
    pid_t *pid,
    const char *exec_path,
    const posix_spawn_file_actions_t *file_actions,
    const posix_spawnattr_t *spawn_attrs,
    char * const args[],
    char * const env[]
) {
    return posix_spawn(pid, exec_path, file_actions, spawn_attrs, args, env);
}

#else

#if _POSIX_SPAWN
static int _subprocess_posix_spawn_fallback(
    pid_t * pid,
    const char * exec_path,
    const int file_descriptors[],
    char * const args[],
    char * const env[]
) {
    // Setup stdin, stdout, and stderr
    posix_spawn_file_actions_t file_actions;
    posix_spawn_file_actions_init(&file_actions);
    posix_spawn_file_actions_adddup2(&file_actions, file_descriptors[0], STDIN_FILENO);
    posix_spawn_file_actions_adddup2(&file_actions, file_descriptors[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&file_actions, file_descriptors[2], STDERR_FILENO);

    // Setup spawnattr
    posix_spawnattr_t spawn_attr;
    posix_spawnattr_init(&spawn_attr);
    // Masks
    sigset_t no_signals;
    sigset_t all_signals;
    sigemptyset(&no_signals);
    sigfillset(&all_signals);
    posix_spawnattr_setsigmask(&spawn_attr, &no_signals);
    posix_spawnattr_setsigdefault(&spawn_attr, &all_signals);
    // Flags
    short flags = POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF;
    posix_spawnattr_setflags(&spawn_attr, flags);

    // Spawn!
    return posix_spawn(pid, exec_path, &file_actions, &spawn_attr, args, env);
}
#endif

int _subprocess_fork_exec(
    pid_t *pid,
    const char *exec_path,
    const char *working_directory,
    const int file_descriptors[],
    char * const args[],
    char * const env[]
) {
    pid_t child_pid = fork();

    // Bind stdin, stdout, and stderr
    if (file_descriptors[0] != 0) {
        dup2(file_descriptors[0], STDIN_FILENO);
    }
    if (file_descriptors[1] != 0) {
        dup2(file_descriptors[1], STDOUT_FILENO);
    }
    if (file_descriptors[2] != 0) {
        dup2(file_descriptors[2], STDERR_FILENO);
    }

    // Finally, exec
    execve(exec_path, args, env);
    // If we got here, something went wrong
    return errno;
}

#endif
