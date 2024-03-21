//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//


#ifndef IOShims_h
#define IOShims_h

#include "_CShimsTargetConditionals.h"

#if TARGET_OS_MAC && (!defined(TARGET_OS_EXCLAVEKIT) || !TARGET_OS_EXCLAVEKIT)

#include <stdio.h>
#include <sys/attr.h>

// See getattrlist for an explanation of the layout of these structs.

#pragma pack(push, 1)
typedef struct PreRenameAttributes {
    u_int32_t length;
    fsobj_type_t fileType;
    u_int32_t mode;
    attrreference_t fullPathAttr;
    u_int32_t nlink;
    char fullPathBuf[PATH_MAX];
} PreRenameAttributes;
#pragma pack(pop)

#pragma pack(push, 1)
typedef struct FullPathAttributes {
    u_int32_t length;
    attrreference_t fullPathAttr;
    char fullPathBuf[PATH_MAX];
} FullPathAttributes;
#pragma pack(pop)

#endif // TARGET_OS_EXCLAVEKIT
#endif /* IOShims_h */
