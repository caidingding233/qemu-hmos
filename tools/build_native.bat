@echo off
setlocal

echo ========================================
echo Building libqemu_hmos.so (standalone)
echo ========================================

REM 设置 NDK 路径
set OHOS_NDK=C:\Users\djnhd\AppData\Local\OpenHarmony\Sdk\20\native

if not exist "%OHOS_NDK%" (
    echo ERROR: OpenHarmony NDK not found at %OHOS_NDK%
    exit /b 1
)

REM 设置项目路径
set PROJECT_ROOT=%~dp0..
set CPP_DIR=%PROJECT_ROOT%\entry\src\main\cpp
set BUILD_DIR=%PROJECT_ROOT%\entry\native_build
set OUTPUT_DIR=%PROJECT_ROOT%\entry\src\main\libs\arm64-v8a

REM 清理旧的构建目录
if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
mkdir "%BUILD_DIR%"

REM 设置 CMake 和 Ninja 路径
set CMAKE_EXE=%OHOS_NDK%\build-tools\cmake\bin\cmake.exe
set NINJA_EXE=%OHOS_NDK%\build-tools\cmake\bin\ninja.exe

echo.
echo Using NDK: %OHOS_NDK%
echo Build dir: %BUILD_DIR%
echo Output dir: %OUTPUT_DIR%
echo.

REM 运行 CMake 配置
echo [1/3] Configuring CMake...
"%CMAKE_EXE%" ^
    -G Ninja ^
    -DCMAKE_MAKE_PROGRAM="%NINJA_EXE%" ^
    -DCMAKE_TOOLCHAIN_FILE="%OHOS_NDK%\build\cmake\ohos.toolchain.cmake" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DOHOS_ARCH=arm64-v8a ^
    -DUSE_PREBUILT_LIB=OFF ^
    -DOHOS_NDK_HOME="%OHOS_NDK%" ^
    -S "%CPP_DIR%" ^
    -B "%BUILD_DIR%"

if errorlevel 1 (
    echo ERROR: CMake configuration failed!
    exit /b 1
)

REM 运行编译
echo.
echo [2/3] Building...
"%CMAKE_EXE%" --build "%BUILD_DIR%" --target qemu_hmos -j8

if errorlevel 1 (
    echo ERROR: Build failed!
    exit /b 1
)

REM 复制到目标目录
echo.
echo [3/3] Copying to libs directory...
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

REM 查找编译输出
if exist "%BUILD_DIR%\libqemu_hmos.so" (
    copy /y "%BUILD_DIR%\libqemu_hmos.so" "%OUTPUT_DIR%\"
) else if exist "%OUTPUT_DIR%\libqemu_hmos.so" (
    echo Library already in output directory
) else (
    echo ERROR: libqemu_hmos.so not found!
    exit /b 1
)

echo.
echo ========================================
echo Build completed successfully!
echo Output: %OUTPUT_DIR%\libqemu_hmos.so
echo ========================================

REM 显示文件大小
dir "%OUTPUT_DIR%\libqemu_hmos.so"

endlocal
