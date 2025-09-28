#!/bin/bash

# Check if SDK is properly set up
echo "=== Checking SDK Setup ==="

# Check if we're in the right directory
echo "Current directory: $(pwd)"
echo "Contents:"
ls -la

# Check if SDK exists
if [ -d "ohos-sdk" ]; then
  echo "✅ SDK directory exists"
  cd ohos-sdk/linux
  
  echo "SDK linux contents:"
  ls -la
  
  # Look for native zip
  NATIVE_ZIP=$(find . -name "native-linux-x64-*.zip" | head -1)
  if [ -n "$NATIVE_ZIP" ]; then
    echo "✅ Found native zip: $NATIVE_ZIP"
  else
    echo "❌ No native zip found"
    echo "Available zip files:"
    find . -name "*.zip" -type f
  fi
  
  # Look for native directory
  NATIVE_DIR=$(find . -name "native-linux-x64-*" -type d | head -1)
  if [ -n "$NATIVE_DIR" ]; then
    echo "✅ Found native directory: $NATIVE_DIR"
    echo "Contents:"
    ls -la "$NATIVE_DIR"
    
    # Check for llvm
    if [ -d "$NATIVE_DIR/llvm" ]; then
      echo "✅ llvm directory exists"
      echo "llvm/bin contents:"
      ls -la "$NATIVE_DIR/llvm/bin" || echo "Cannot list llvm/bin"
    else
      echo "❌ llvm directory not found"
    fi
    
    # Check for build-tools
    if [ -d "$NATIVE_DIR/build-tools" ]; then
      echo "✅ build-tools directory exists"
      echo "build-tools/cmake/bin contents:"
      ls -la "$NATIVE_DIR/build-tools/cmake/bin" || echo "Cannot list cmake/bin"
    else
      echo "❌ build-tools directory not found"
    fi
  else
    echo "❌ No native directory found"
    echo "Available directories:"
    find . -type d | head -10
  fi
else
  echo "❌ SDK directory does not exist"
  echo "You need to run the build script first to download the SDK"
fi
