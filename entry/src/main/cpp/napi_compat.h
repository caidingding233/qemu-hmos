#pragma once

// Compatibility layer: use real OHOS N-API on device, fallback to simple stub on host

#if defined(__OHOS__)
#  include <napi/native_api.h>
#else
#  include "napi_simple.h"
#endif
