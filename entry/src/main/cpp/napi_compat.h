#pragma once

// Compatibility layer: use real OHOS N-API on device, fallback to simple stub on host

#if defined(__OHOS__)
// Include standard C headers first to provide basic types (int32_t, size_t, etc.)
#  include <stdint.h>
#  include <stddef.h>
#  include <stdbool.h>
#  include <napi/native_api.h>
#else
#  include "napi_simple.h"
#endif
