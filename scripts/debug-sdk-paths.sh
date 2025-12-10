#!/bin/bash
set -euo pipefail

echo "=== HarmonyOS SDK Path Debug ==="
echo ""

# Check if SDK root exists
SDK_ROOT="/opt/harmonyos-sdk"
echo "SDK Root: $SDK_ROOT"
echo "SDK Root exists: $([ -d "$SDK_ROOT" ] && echo "Yes" || echo "No")"
echo ""

if [ ! -d "$SDK_ROOT" ]; then
    echo "❌ SDK root does not exist!"
    echo "Please make sure HarmonyOS SDK is installed at $SDK_ROOT"
    exit 1
fi

echo "=== SDK Root Contents ==="
ls -la "$SDK_ROOT"
echo ""

echo "=== Searching for NDK Structure ==="
echo "Looking for common NDK paths..."

# Check common paths
COMMON_PATHS=(
    "$SDK_ROOT/sdk/default/openharmony/native"
    "$SDK_ROOT/default/openharmony/native"
    "$SDK_ROOT/native"
    "$SDK_ROOT/openharmony/native"
    "$SDK_ROOT/sdk/native"
)

for path in "${COMMON_PATHS[@]}"; do
    if [ -d "$path" ]; then
        echo "✅ Found: $path"
        ls -la "$path"
        echo ""
    else
        echo "❌ Not found: $path"
    fi
done

echo "=== Searching for Clang Compiler ==="
echo "Looking for aarch64-unknown-linux-ohos-clang..."

# Find all clang files
CLANG_FILES=$(find "$SDK_ROOT" -name "*clang*" -type f 2>/dev/null || true)
if [ -n "$CLANG_FILES" ]; then
    echo "Found clang files:"
    echo "$CLANG_FILES"
    echo ""
    
    # Look specifically for the target compiler
    TARGET_CLANG=$(find "$SDK_ROOT" -name "aarch64-unknown-linux-ohos-clang" -type f 2>/dev/null | head -1)
    if [ -n "$TARGET_CLANG" ]; then
        echo "✅ Found target compiler: $TARGET_CLANG"
        
        # Get NDK path
        NDK_PATH=$(dirname "$TARGET_CLANG")
        NDK_PATH=$(dirname "$NDK_PATH")
        NDK_PATH=$(dirname "$NDK_PATH")
        echo "✅ NDK Path: $NDK_PATH"
        
        # Check if it's a valid NDK structure
        if [ -d "$NDK_PATH/llvm/bin" ] && [ -d "$NDK_PATH/sysroot" ]; then
            echo "✅ Valid NDK structure found!"
            echo "LLVM bin: $NDK_PATH/llvm/bin"
            echo "Sysroot: $NDK_PATH/sysroot"
        else
            echo "❌ Invalid NDK structure"
        fi
    else
        echo "❌ Target compiler not found"
    fi
else
    echo "❌ No clang files found"
fi

echo ""
echo "=== Searching for LLVM Directory ==="
LLVM_DIRS=$(find "$SDK_ROOT" -name "llvm" -type d 2>/dev/null || true)
if [ -n "$LLVM_DIRS" ]; then
    echo "Found LLVM directories:"
    echo "$LLVM_DIRS"
    echo ""
    
    for llvm_dir in $LLVM_DIRS; do
        echo "Checking: $llvm_dir"
        if [ -d "$llvm_dir/bin" ]; then
            echo "  ✅ Has bin directory"
            ls -la "$llvm_dir/bin" | grep -E "(clang|ar|strip)" | head -5
        else
            echo "  ❌ No bin directory"
        fi
        echo ""
    done
else
    echo "❌ No LLVM directories found"
fi

echo "=== Searching for Sysroot ==="
SYSROOT_DIRS=$(find "$SDK_ROOT" -name "sysroot" -type d 2>/dev/null || true)
if [ -n "$SYSROOT_DIRS" ]; then
    echo "Found sysroot directories:"
    echo "$SYSROOT_DIRS"
    echo ""
    
    for sysroot_dir in $SYSROOT_DIRS; do
        echo "Checking: $sysroot_dir"
        if [ -d "$sysroot_dir/usr/include" ]; then
            echo "  ✅ Has include directory"
        else
            echo "  ❌ No include directory"
        fi
        if [ -d "$sysroot_dir/usr/lib" ]; then
            echo "  ✅ Has lib directory"
        else
            echo "  ❌ No lib directory"
        fi
        echo ""
    done
else
    echo "❌ No sysroot directories found"
fi

echo "=== Summary ==="
echo "If you see valid NDK structure above, you can set:"
echo "export OHOS_NDK_HOME=\"<path_to_native_directory>\""
echo "export SYSROOT=\"\$OHOS_NDK_HOME/sysroot\""
echo "export CC=\"\$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang\""
echo ""
echo "If no valid structure is found, please check:"
echo "1. SDK download and extraction was successful"
echo "2. SDK is installed at the correct location"
echo "3. SDK version is compatible with this build script"
