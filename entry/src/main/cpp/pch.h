#pragma once

// Precompiled header: Ensure C standard library types are available before C++ standard library
// This fixes the "reference to unresolved using declaration" errors with size_t, int32_t, etc.
// 
// Problem: HarmonyOS NDK's libc++ uses "using ::size_t _LIBCPP_USING_IF_EXISTS;" which requires
// size_t to be defined in global namespace from C standard library, but musl libc may not
// provide it correctly in global namespace.
//
// Solution: Explicitly define types in global namespace before C++ standard library headers
// are included. This ensures C++ standard library can find them via "using ::size_t".

// Define __MUSL__ to ensure musl libc compatibility
#ifndef __MUSL__
#define __MUSL__
#endif

// Force define __NEED macros before including headers to ensure types are defined
// These macros tell musl libc's <bits/alltypes.h> to define the types
#define __NEED_size_t
#define __NEED_ptrdiff_t
#define __NEED_wchar_t
#define __NEED_mbstate_t
#define __NEED_int8_t
#define __NEED_int16_t
#define __NEED_int32_t
#define __NEED_int64_t
#define __NEED_uint8_t
#define __NEED_uint16_t
#define __NEED_uint32_t
#define __NEED_uint64_t

// Include C standard headers - these will define types via <bits/alltypes.h>
// Must be included BEFORE any C++ headers, and types must be in global namespace
// We include them within extern "C" block to ensure C functions are in global namespace
// This is critical for libc++ which uses "using ::strchr" etc.
extern "C" {
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <limits.h>
#include <wchar.h>  // For mbstate_t, wcschr, etc.
#include <string.h>  // For strstr, memcpy, etc.
#include <stdlib.h>  // For ldiv_t, etc.
}

// Workaround: Explicitly ensure types are in global namespace for C++ standard library
// HarmonyOS NDK's libc++ uses "using ::size_t _LIBCPP_USING_IF_EXISTS;"
// If types aren't visible, we need to make them visible explicitly
// Check if size_t is defined, if not, define it based on architecture
#ifndef _SIZE_T_DEFINED
#ifdef __SIZE_TYPE__
typedef __SIZE_TYPE__ size_t;
#else
typedef unsigned long size_t;
#endif
#define _SIZE_T_DEFINED
#endif

// Ensure ptrdiff_t is defined
#ifndef _PTRDIFF_T_DEFINED
#ifdef __PTRDIFF_TYPE__
typedef __PTRDIFF_TYPE__ ptrdiff_t;
#else
typedef long ptrdiff_t;
#endif
#define _PTRDIFF_T_DEFINED
#endif

// Ensure standard integer types are defined (if not already defined by stdint.h)
#ifndef _UINT8_T_DEFINED
typedef unsigned char uint8_t;
#define _UINT8_T_DEFINED
#endif

#ifndef _UINT16_T_DEFINED
typedef unsigned short uint16_t;
#define _UINT16_T_DEFINED
#endif

#ifndef _UINT32_T_DEFINED
typedef unsigned int uint32_t;
#define _UINT32_T_DEFINED
#endif

#ifndef _UINT64_T_DEFINED
typedef unsigned long long uint64_t;
#define _UINT64_T_DEFINED
#endif

#ifndef _INT8_T_DEFINED
typedef signed char int8_t;
#define _INT8_T_DEFINED
#endif

#ifndef _INT16_T_DEFINED
typedef short int16_t;
#define _INT16_T_DEFINED
#endif

#ifndef _INT32_T_DEFINED
typedef int int32_t;
#define _INT32_T_DEFINED
#endif

#ifndef _INT64_T_DEFINED
typedef long long int64_t;
#define _INT64_T_DEFINED
#endif

// Ensure mbstate_t is defined
#ifndef _MBSTATE_T_DEFINED
typedef struct {
    unsigned int __count;
    union {
        unsigned int __wch;
        char __wchb[4];
    } __value;
} mbstate_t;
#define _MBSTATE_T_DEFINED
#endif

// Ensure ldiv_t is defined (for stdlib.h)
#ifndef _LDIV_T_DEFINED
typedef struct {
    long quot;
    long rem;
} ldiv_t;
#define _LDIV_T_DEFINED
#endif

// Ensure lldiv_t is defined
#ifndef _LLDIV_T_DEFINED
typedef struct {
    long long quot;
    long long rem;
} lldiv_t;
#define _LLDIV_T_DEFINED
#endif

// C standard library functions are now declared via the included headers above
// They are in global namespace due to extern "C" block, which allows libc++
// to use "using ::strchr" etc. successfully
