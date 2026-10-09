/*
 * Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
 * SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
 *
 * Deferred Plan 9 assembler bridge.
 */

#ifndef LLVM_C_GOPLAN9_H
#define LLVM_C_GOPLAN9_H
#include "llvm-c/ExternC.h"
#include "llvm-c/Visibility.h"
#include <stddef.h>
LLVM_C_EXTERN_C_BEGIN

/* Experimental GoObj-only interface. Registration is scoped to the current OS
 * thread. The request is JSON {body: string, context: string}; context is the
 * versioned go-plan9-context function attribute. The returned NUL-terminated
 * JSON is released exactly once with Release. Pass NULL callbacks to
 * unregister. The callback must not recursively invoke code generation on this
 * thread. Consumers of Plan 9 carrier bitcode must register an assembler
 * themselves. */
typedef const char *(*LLVMGoPlan9AssembleCallback)(const char *, size_t);
typedef void (*LLVMGoPlan9ReleaseCallback)(const char *);
LLVM_C_ABI void LLVMGoSetPlan9Assembler(LLVMGoPlan9AssembleCallback Assemble,
                                      LLVMGoPlan9ReleaseCallback Release);

LLVM_C_EXTERN_C_END
#endif
