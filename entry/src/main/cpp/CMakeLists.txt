cmake_minimum_required(VERSION 3.5)
project(qemu_hmos VERSION 1.0.0)

# 设置C++标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 设置构建类型
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release")
endif()

message(STATUS "Building ${PROJECT_NAME} v${PROJECT_VERSION} in ${CMAKE_BUILD_TYPE} mode")

# 鸿蒙开发环境特定配置
# 优先使用环境变量，其次使用用户提供的本机路径，最后再尝试默认安装路径
if(DEFINED ENV{OHOS_NDK_HOME})
    set(OHOS_NDK_HOME $ENV{OHOS_NDK_HOME})
else()
    # 用户本机已安装的 NDK（按需修改）
    set(OHOS_NDK_HOME "/Users/caidingding233/Library/OpenHarmony/Sdk/18/native")
    if(NOT EXISTS "${OHOS_NDK_HOME}")
        # 兼容 DevEco 默认安装位置
        if(EXISTS "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native")
            set(OHOS_NDK_HOME "/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native")
        elseif(EXISTS "/Applications/DevEco-Studio.app/Contents/ohos/ndk")
            set(OHOS_NDK_HOME "/Applications/DevEco-Studio.app/Contents/ohos/ndk")
        else()
            message(FATAL_ERROR "OHOS_NDK_HOME not set and could not be auto-detected; tried /Users/caidingding233/Library/OpenHarmony/Sdk/18/native")
        endif()
    endif()
endif()

# 确保使用HarmonyOS NDK的工具链
# 优先使用环境变量传递的编译器路径，其次使用默认路径
if(DEFINED ENV{CC})
    set(CMAKE_C_COMPILER "$ENV{CC}")
else()
    set(CMAKE_C_COMPILER "${OHOS_NDK_HOME}/llvm/bin/clang")
endif()

if(DEFINED ENV{CXX})
    set(CMAKE_CXX_COMPILER "$ENV{CXX}")
else()
    set(CMAKE_CXX_COMPILER "${OHOS_NDK_HOME}/llvm/bin/clang++")
endif()

if(NOT CMAKE_LINKER)
    set(CMAKE_LINKER "${OHOS_NDK_HOME}/llvm/bin/ld.lld")
endif()

# 设置交叉编译目标
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# 设置sysroot
set(CMAKE_SYSROOT "${OHOS_NDK_HOME}/sysroot")

# 确保不使用主机的工具
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# 设置编译选项，确保不包含macOS特定的选项，并包含aarch64-linux-ohos的头文件路径
# 使用交叉目标与 sysroot 的基础包含路径，避免 -nostdinc/-nostdlib++ 破坏标准库
set(CMAKE_C_FLAGS "-target aarch64-linux-ohos -I${OHOS_NDK_HOME}/sysroot/usr/include -I${OHOS_NDK_HOME}/sysroot/usr/include/aarch64-linux-ohos -I${CMAKE_CURRENT_SOURCE_DIR}")
set(CMAKE_CXX_FLAGS "-target aarch64-linux-ohos -I${OHOS_NDK_HOME}/sysroot/usr/include -I${OHOS_NDK_HOME}/sysroot/usr/include/aarch64-linux-ohos -I${CMAKE_CURRENT_SOURCE_DIR}")

# 根据构建类型设置优化级别
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O0 -g -DDEBUG")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O0 -g -DDEBUG")
elseif(CMAKE_BUILD_TYPE STREQUAL "Release")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O2 -DNDEBUG")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O2 -DNDEBUG")
endif()

# 设置链接器标志，确保使用正确的链接器，并移除macOS特定的选项
set(CMAKE_EXE_LINKER_FLAGS "-fuse-ld=${OHOS_NDK_HOME}/llvm/bin/ld.lld")
set(CMAKE_SHARED_LINKER_FLAGS "-fuse-ld=${OHOS_NDK_HOME}/llvm/bin/ld.lld -shared")

# 确保输出文件扩展名为.so而不是.dylib
# 让工具链按默认规则生成平台后缀（不要强制输出到源码树）

# QEMU库路径
set(QEMU_BUILD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/qemu/build")

# 检查实际的QEMU构建目录（可能因构建配置而异）
if(NOT EXISTS "${QEMU_BUILD_DIR}")
    # 尝试其他可能的构建目录
    set(QEMU_BUILD_DIR_CANDIDATES
        "${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/qemu/build_harmonyos_full"
        "${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/qemu/build_local_test"
        "${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/qemu/build_mac_local"
    )

    foreach(candidate ${QEMU_BUILD_DIR_CANDIDATES})
        if(EXISTS "${candidate}")
            set(QEMU_BUILD_DIR "${candidate}")
            message(STATUS "Found QEMU build directory: ${QEMU_BUILD_DIR}")
            break()
        endif()
    endforeach()
endif()

message(STATUS "Using QEMU build directory: ${QEMU_BUILD_DIR}")
set(QEMU_INCLUDE_DIRS
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/qemu/include"
    "${QEMU_BUILD_DIR}"
)

# 检测操作系统
if(APPLE)
    # macOS 主机上也走 OpenHarmony NDK 交叉编译，不使用 /usr/bin/clang++
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++17")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=c99")
    # 包含/库目录
    include_directories(
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${QEMU_INCLUDE_DIRS}
        ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libvncclient/include
    )
    link_directories(
        "${QEMU_BUILD_DIR}"
    )
else()
    # HarmonyOS构建（沿用上面已解析出的 OHOS_NDK_HOME）
    # 设置工具链
    set(CMAKE_SYSTEM_NAME Linux)
    set(CMAKE_SYSTEM_PROCESSOR aarch64)
    
    # 设置编译器路径（使用环境变量或默认路径）
    if(DEFINED ENV{CC})
        set(CMAKE_C_COMPILER "$ENV{CC}")
    else()
        set(CMAKE_C_COMPILER "${OHOS_NDK_HOME}/llvm/bin/clang")
    endif()

    if(DEFINED ENV{CXX})
        set(CMAKE_CXX_COMPILER "$ENV{CXX}")
    else()
        set(CMAKE_CXX_COMPILER "${OHOS_NDK_HOME}/llvm/bin/clang++")
    endif()
    
    # 设置查找根路径
    set(CMAKE_FIND_ROOT_PATH "${OHOS_NDK_HOME}/sysroot")
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
    
    # 包含目录
include_directories(
        ${CMAKE_CURRENT_SOURCE_DIR}
        "${OHOS_NDK_HOME}/sysroot/usr/include"
        "${OHOS_NDK_HOME}/sysroot/usr/include/aarch64-linux-ohos"
        ${QEMU_INCLUDE_DIRS}
        ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libvncclient/include
)
    
    # 库目录
    link_directories(
        "${OHOS_NDK_HOME}/sysroot/usr/lib/aarch64-linux-ohos"
        "${OHOS_NDK_HOME}/sysroot/usr/lib"
        "${QEMU_BUILD_DIR}"
    )
endif()

# 源文件
set(SOURCES
    napi_init.cpp
    qemu_wrapper.cpp
    rdp_client.cpp
)

# 仅在本机仿真或显式启用时使用简化 NAPI 实现（避免在设备端与系统 NAPI 冲突）
option(USE_FAKE_NAPI "Build with simplified NAPI shim (host only)" OFF)

# 仅允许在主机侧启用简化NAPI；设备端强制关闭以避免ABI冲突
if(USE_FAKE_NAPI AND NOT APPLE)
    message(FATAL_ERROR "USE_FAKE_NAPI is only allowed for host builds (APPLE). Disable it for device builds.")
endif()

if(USE_FAKE_NAPI)
    list(APPEND SOURCES napi_impl.cpp)
endif()

# 创建共享库
if(APPLE)
    add_library(qemu_hmos SHARED ${SOURCES})
else()
    add_library(qemu_hmos SHARED ${SOURCES})
endif()

# QEMU库文件 - 动态检测存在的库文件（可能是静态库或动态库）
set(QEMU_LIBS_CANDIDATES
    # 静态库（如果QEMU配置为静态库）
    "${QEMU_BUILD_DIR}/libqemu-aarch64-softmmu.a"
    "${QEMU_BUILD_DIR}/libqemuutil.a"
    "${QEMU_BUILD_DIR}/libui-dbus.a"
    "${QEMU_BUILD_DIR}/libmodule-common.a"
    "${QEMU_BUILD_DIR}/libblock-curl.a"
    "${QEMU_BUILD_DIR}/libblock-ssh.a"
    "${QEMU_BUILD_DIR}/libhw-display-virtio-gpu.a"
    "${QEMU_BUILD_DIR}/libhw-display-virtio-gpu-pci.a"
    "${QEMU_BUILD_DIR}/libhw-uefi-vars.a"
    "${QEMU_BUILD_DIR}/subprojects/dtc/libfdt/libfdt.a"
    "${QEMU_BUILD_DIR}/subprojects/berkeley-softfloat-3/libsoftfloat.a"
    "${QEMU_BUILD_DIR}/qemu-bundle/usr/local/lib/libfdt.a"
    # 动态库（如果QEMU配置为动态库）
    "${QEMU_BUILD_DIR}/libqemu-aarch64-softmmu.so"
    "${QEMU_BUILD_DIR}/libqemuutil.so"
    "${QEMU_BUILD_DIR}/libui-dbus.so"
    "${QEMU_BUILD_DIR}/libmodule-common.so"
    "${QEMU_BUILD_DIR}/libblock-curl.so"
    "${QEMU_BUILD_DIR}/libblock-ssh.so"
    "${QEMU_BUILD_DIR}/libhw-display-virtio-gpu.so"
    "${QEMU_BUILD_DIR}/libhw-display-virtio-gpu-pci.so"
    "${QEMU_BUILD_DIR}/libhw-uefi-vars.so"
)

set(QEMU_LIBS "")
foreach(lib ${QEMU_LIBS_CANDIDATES})
    if(EXISTS ${lib})
        list(APPEND QEMU_LIBS ${lib})
        message(STATUS "Found QEMU library: ${lib}")
    else()
        message(STATUS "QEMU library not found (skipping): ${lib}")
    endif()
endforeach()

# QEMU库检测已在上面完成

# 链接QEMU库
if(QEMU_LIBS)
    target_link_libraries(qemu_hmos ${QEMU_LIBS})
    # QEMU依赖库
    target_link_libraries(qemu_hmos 
        -lpthread
        -ldl
        -lm
        -lz
        -lssl
        -lcrypto
        -lcurl
        -lssh
        -lgmp
        -lglib-2.0
        -lgio-2.0
        -lgobject-2.0
        -lpixman-1
        -lgnutls
        -ltasn1
        -lsasl2
        -lpam
        -lbz2
        -lzstd
    )
endif()

# 查找并链接必要的库
find_library(LOG_LIB hilog_ndk
    PATHS
    "${OHOS_NDK_HOME}/sysroot/usr/lib"
    "${OHOS_NDK_HOME}/sysroot/usr/lib/aarch64-linux-ohos"
    NO_DEFAULT_PATH
)

# 在鸿蒙环境中，android库可能不存在，我们跳过它
set(ANDROID_LIB "")

# 如果找不到日志库，使用空值避免链接错误
if(NOT LOG_LIB)
    message(WARNING "LOG library not found, skipping...")
    set(LOG_LIB "")
endif()

message(STATUS "LOG_LIB: ${LOG_LIB}")
message(STATUS "ANDROID_LIB: ${ANDROID_LIB}")

# 查找鸿蒙NAPI库
set(NAPI_LIB_PATH "${OHOS_NDK_HOME}/sysroot/usr/lib/aarch64-linux-ohos/libace_napi.z.so")

if(EXISTS ${NAPI_LIB_PATH})
    set(NAPI_LIB ${NAPI_LIB_PATH})
    message(STATUS "Found NAPI library: ${NAPI_LIB}")
else()
    message(WARNING "NAPI library not found at: ${NAPI_LIB_PATH}")
    set(NAPI_LIB "")
endif()

if(NAPI_LIB)
    target_link_libraries(qemu_hmos ${NAPI_LIB})
endif()
if(LOG_LIB)
    target_link_libraries(qemu_hmos ${LOG_LIB})
endif()
if(ANDROID_LIB)
    target_link_libraries(qemu_hmos ${ANDROID_LIB})
endif()

# 不静态链接 QEMU 核心库，改为运行时 dlopen("libqemu_full.so")

# 2. VNC库 (LibVNC: server/client)
set(VNC_LIB_PATH "${CMAKE_CURRENT_SOURCE_DIR}/third_party/libvncserver/libvncserver.a")
set(VNC_CLIENT_LIB_PATH "${CMAKE_CURRENT_SOURCE_DIR}/third_party/libvncclient/libvncclient.a")

# 检查VNC库状态
if(EXISTS ${VNC_LIB_PATH})
    message(STATUS "✅ Found VNC server library: ${VNC_LIB_PATH}")
    set(HAVE_VNC_SERVER ON)
else()
    message(WARNING "❌ VNC server library not found, VNC server support will be limited")
    set(VNC_LIB_PATH "")
    set(HAVE_VNC_SERVER OFF)
endif()

if(EXISTS ${VNC_CLIENT_LIB_PATH})
    message(STATUS "✅ Found VNC client library: ${VNC_CLIENT_LIB_PATH}")
    add_definitions(-DLIBVNC_HAVE_CLIENT=1)
    set(HAVE_VNC_CLIENT ON)
else()
    message(WARNING "❌ VNC client library not found, Native VNC viewer will be stubbed")
    set(VNC_CLIENT_LIB_PATH "")
    set(HAVE_VNC_CLIENT OFF)
endif()

# 3. FreeRDP库
set(FREERDP_LIB_PATH "${CMAKE_CURRENT_SOURCE_DIR}/third_party/freerdp/libfreerdp.a")
if(EXISTS ${FREERDP_LIB_PATH})
    message(STATUS "✅ Found FreeRDP library: ${FREERDP_LIB_PATH}")
    set(HAVE_FREERDP ON)
else()
    message(WARNING "❌ FreeRDP library not found, RDP support will be limited")
    set(FREERDP_LIB_PATH "")
    set(HAVE_FREERDP OFF)
endif()

if(NAPI_LIB)
    target_link_libraries(qemu_hmos ${NAPI_LIB})
endif()
if(LOG_LIB)
    target_link_libraries(qemu_hmos ${LOG_LIB})
endif()
if(ANDROID_LIB)
    target_link_libraries(qemu_hmos ${ANDROID_LIB})
endif()

# 链接QEMU相关库
# no direct link to libqemu_full.so

if(VNC_LIB_PATH)
    target_link_libraries(qemu_hmos ${VNC_LIB_PATH})
endif()
if(VNC_CLIENT_LIB_PATH)
    target_link_libraries(qemu_hmos ${VNC_CLIENT_LIB_PATH})
endif()

# VNC依赖库（两者共享）
target_link_libraries(qemu_hmos 
    -lpthread
    -lz
)

if(FREERDP_LIB_PATH)
    target_link_libraries(qemu_hmos ${FREERDP_LIB_PATH})
    # FreeRDP依赖库
    target_link_libraries(qemu_hmos 
        -lpthread
        -lssl
        -lcrypto
        -lwinpr
        -lfreerdp
    )
endif()

# 设置编译选项
if(APPLE)
    target_compile_options(qemu_hmos PRIVATE
        -fPIC
        -Wall
        -Wextra
        -O2
        -std=c++17
        -fdata-sections
        -ffunction-sections
        -funwind-tables
        -fstack-protector-strong
        -no-canonical-prefixes
        -fno-addrsig
        -Wa,--noexecstack
        -Wformat
        -Werror=format-security
        -fuse-ld=lld
        -Wl,--build-id=sha1
        -Wl,--warn-shared-textrel
        -Wl,--fatal-warnings
        -lunwind
        -Wl,--no-undefined
        -Qunused-arguments
        -Wl,-z,noexecstack
        # QEMU特定编译选项
        -DCONFIG_VNC=1
        -DCONFIG_SLIRP=1
        -DCONFIG_TCG=1
        -DCONFIG_MODULES=1
        -DCONFIG_UI_DBUS=1
        -DCONFIG_VIRTIO_GPU=1
        -DCONFIG_VIRTIO_GPU_PCI=1
        -DCONFIG_BLOCK_CURL=1
        -DCONFIG_BLOCK_SSH=1
        -DCONFIG_UEFI_VARS=1
    )
else()
    target_compile_options(qemu_hmos PRIVATE
        -fPIC
        -Wall
        -Wextra
        -O2
        -D__MUSL__
        -D__OHOS__
        --target=aarch64-linux-ohos
        -fdata-sections
        -ffunction-sections
        -funwind-tables
        -fstack-protector-strong
        -no-canonical-prefixes
        -fno-addrsig
        -Wa,--noexecstack
        -Wformat
        -Werror=format-security
        -fuse-ld=lld
        -Wl,--build-id=sha1
        -Wl,--warn-shared-textrel
        -Wl,--fatal-warnings
        -lunwind
        -Wl,--no-undefined
        -Qunused-arguments
        -Wl,-z,noexecstack
        # QEMU特定编译选项
        -DCONFIG_VNC=1
        -DCONFIG_SLIRP=1
        -DCONFIG_TCG=1
        -DCONFIG_MODULES=1
        -DCONFIG_UI_DBUS=1
        -DCONFIG_VIRTIO_GPU=1
        -DCONFIG_VIRTIO_GPU_PCI=1
        -DCONFIG_BLOCK_CURL=1
        -DCONFIG_BLOCK_SSH=1
        -DCONFIG_UEFI_VARS=1
    )
endif()

# 设置输出名称和路径 - 使用Hvigor期望的目录结构
set_target_properties(qemu_hmos PROPERTIES
    OUTPUT_NAME "qemu_hmos"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../libs/arm64-v8a"
)

# ---- Bundle prebuilt QEMU core into native outputs (so Hvigor packs it) ----
# Copy prebuilt core from cpp folder to Hvigor expected directory
set(QEMU_FULL_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../libs/arm64-v8a/libqemu_full.so")
set(QEMU_FULL_DST_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../build/default/intermediates/libs/default/arm64-v8a")
set(QEMU_FULL_DST "${QEMU_FULL_DST_DIR}/libqemu_full.so")

# Also copy to oh_modules for runtime loading
set(QEMU_FULL_OH_DST "${CMAKE_CURRENT_SOURCE_DIR}/../../oh_modules/libqemu_full.so")

if(EXISTS ${QEMU_FULL_SRC})
    add_custom_command(
        OUTPUT ${QEMU_FULL_DST} ${QEMU_FULL_OH_DST}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${QEMU_FULL_DST_DIR}
        COMMAND ${CMAKE_COMMAND} -E copy ${QEMU_FULL_SRC} ${QEMU_FULL_DST}
        COMMAND ${CMAKE_COMMAND} -E copy ${QEMU_FULL_SRC} ${QEMU_FULL_OH_DST}
        DEPENDS ${QEMU_FULL_SRC}
        COMMENT "Copying prebuilt libqemu_full.so to libs/arm64-v8a and oh_modules"
    )
    add_custom_target(copy_qemu_full ALL DEPENDS ${QEMU_FULL_DST} ${QEMU_FULL_OH_DST})
    add_dependencies(qemu_hmos copy_qemu_full)

    # Also link the prebuilt core to force a DT_NEEDED entry so packager keeps it
    add_library(qemu_full_prebuilt SHARED IMPORTED GLOBAL)
    set_target_properties(qemu_full_prebuilt PROPERTIES IMPORTED_LOCATION ${QEMU_FULL_SRC})
    # Disable as-needed so the linker emits NEEDED even if no symbols referenced
    if (CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
        target_link_options(qemu_hmos PRIVATE "-Wl,--no-as-needed")
    endif()
    target_link_libraries(qemu_hmos qemu_full_prebuilt)
    if (CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
        target_link_options(qemu_hmos PRIVATE "-Wl,--as-needed")
    endif()
else()
    message(WARNING "Prebuilt core not found at ${QEMU_FULL_SRC}; libqemu_full.so will not be packaged. You can still place it under src/main/libs/arm64-v8a/ manually or push to files/ at runtime.")
endif()

# 添加自定义目标用于调试
add_custom_target(debug_info
    COMMAND ${CMAKE_COMMAND} -E echo "OHOS_NDK_HOME: ${OHOS_NDK_HOME}"
    COMMAND ${CMAKE_COMMAND} -E echo "CMAKE_C_COMPILER: ${CMAKE_C_COMPILER}"
    COMMAND ${CMAKE_COMMAND} -E echo "CMAKE_CXX_COMPILER: ${CMAKE_CXX_COMPILER}"
    COMMAND ${CMAKE_COMMAND} -E echo "CMAKE_FIND_ROOT_PATH: ${CMAKE_FIND_ROOT_PATH}"
    COMMAND ${CMAKE_COMMAND} -E echo "NAPI_LIB: ${NAPI_LIB}"
    COMMAND ${CMAKE_COMMAND} -E echo "HAVE_VNC_CLIENT: ${HAVE_VNC_CLIENT}"
    COMMAND ${CMAKE_COMMAND} -E echo "HAVE_VNC_SERVER: ${HAVE_VNC_SERVER}"
    COMMAND ${CMAKE_COMMAND} -E echo "HAVE_FREERDP: ${HAVE_FREERDP}"
)

# 构建配置摘要
message(STATUS "=== QEMU on HarmonyOS Build Configuration ===")
message(STATUS "Target: ${CMAKE_SYSTEM_NAME}-${CMAKE_SYSTEM_PROCESSOR}")
message(STATUS "Build Type: ${CMAKE_BUILD_TYPE}")
message(STATUS "C++ Standard: ${CMAKE_CXX_STANDARD}")

if(HAVE_VNC_CLIENT)
    message(STATUS "✅ VNC Client: Enabled")
else()
    message(STATUS "❌ VNC Client: Disabled (missing libvncclient.a)")
endif()

if(HAVE_VNC_SERVER)
    message(STATUS "✅ VNC Server: Enabled")
else()
    message(STATUS "❌ VNC Server: Disabled (missing libvncserver.a)")
endif()

if(HAVE_FREERDP)
    message(STATUS "✅ FreeRDP: Enabled")
else()
    message(STATUS "❌ FreeRDP: Disabled (missing libfreerdp.a)")
endif()

# 检查核心库
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/libqemu_full.so")
    message(STATUS "✅ Core Library: Found (libqemu_full.so)")
else()
    message(STATUS "❌ Core Library: Missing (libqemu_full.so)")
endif()

message(STATUS "Output Directory: ${CMAKE_CURRENT_SOURCE_DIR}/../libs/arm64-v8a")
message(STATUS "================================================")

# 添加构建验证目标
add_custom_target(verify_build
    COMMAND ${CMAKE_COMMAND} -E echo "=== Build Verification ==="
    COMMAND ${CMAKE_COMMAND} -E echo "Checking output files..."
    COMMAND test -f "${CMAKE_CURRENT_SOURCE_DIR}/../libs/arm64-v8a/libqemu_hmos.so" && echo "✅ libqemu_hmos.so found" || echo "❌ libqemu_hmos.so missing"
    COMMAND test -f "${CMAKE_CURRENT_SOURCE_DIR}/../../oh_modules/libqemu_full.so" && echo "✅ libqemu_full.so found in oh_modules" || echo "❌ libqemu_full.so missing in oh_modules"
    COMMAND test -f "${CMAKE_CURRENT_SOURCE_DIR}/../libs/arm64-v8a/libqemu_full.so" && echo "✅ libqemu_full.so found in libs" || echo "❌ libqemu_full.so missing in libs"
    COMMAND ${CMAKE_COMMAND} -E echo "=== Verification Complete ==="
    DEPENDS qemu_hmos copy_qemu_full
    COMMENT "Verifying that all required files are built and copied correctly"
)
