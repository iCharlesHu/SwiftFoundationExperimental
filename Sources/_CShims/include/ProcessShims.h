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

#include <unistd.h>
#include "_CShimsTargetConditionals.h"

#if TARGET_OS_MAC
#include <spawn.h>

int _subprocess_spawn(
    pid_t *pid,
    const char *exec_path,
    const posix_spawn_file_actions_t *file_actions,
    const posix_spawnattr_t *spawn_attrs,
    char * const args[],
    char * const env[]
);
#else // TARGET_OS_MAC

int _subprocess_fork_exec(
    pid_t *pid,
    const char *exec_path,
    const int file_descriptors[],
    char * const args[],
    char * const env[]
);

#endif // TARGET_OS_MAC
