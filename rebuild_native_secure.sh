#!/bin/bash

# J2V8 Native Library Rebuild Script for Android
# Minimal Security Configuration: Stack Canaries + Fortified Functions Only

set -euo pipefail  # Enhanced error handling

echo "🛡️  Rebuilding J2V8 Native Libraries (Security + Essential Flags)"
echo "================================================================="

# Default settings
API_LEVEL="${API_LEVEL:-21}"
ANDROID_ABIS=("arm64-v8a" "armeabi-v7a" "x86" "x86_64")
V8_ARCH_MAP=("arm64-v8a=android.arm64" "armeabi-v7a=android.arm" "x86=android.x86" "x86_64=android.x64")
NDK_TRIPLE_MAP=("arm64-v8a=aarch64-linux-android" "armeabi-v7a=armv7a-linux-androideabi" "x86=i686-linux-android" "x86_64=x86_64-linux-android")

# Validate ANDROID_NDK_HOME
if [[ -z "${ANDROID_NDK_HOME:-}" || ! -d "$ANDROID_NDK_HOME" ]]; then
    echo "❌ ANDROID_NDK_HOME not set or invalid"
    exit 1
fi

mkdir -p build_native/android

get_security_flags() {
    local abi=$1
    local flags=""

    # Essential flags for shared library + minimal security
    flags+=" -fPIC -std=c++20 -DSTATIC_V8=1 -O3"
    flags+=" -fstack-protector-strong -D_FORTIFY_SOURCE=2"
    flags+=" -static-libstdc++"  # Static C++ standard library linking

    echo "$flags"
}

get_linker_flags() {
    local abi=$1
    local flags=""

    # Basic linking + static C++ standard library
    flags+=" -shared -llog"
    flags+=" -static-libstdc++"  # Static C++ standard library linking
    flags+=" -Wl,-z,max-page-size=16384"        # Alignment: 16KB pages
    flags+=" -Wl,-z,common-page-size=16384"

    echo "$flags"
}

build_arch() {
    local abi=$1
    local v8_arch=""
    local ndk_triple=""

    # Map ABI to V8 architecture and NDK triple
    for mapping in "${V8_ARCH_MAP[@]}"; do
        if [[ "$mapping" == "$abi="* ]]; then
            v8_arch="${mapping#*=}"
            break
        fi
    done

    for mapping in "${NDK_TRIPLE_MAP[@]}"; do
        if [[ "$mapping" == "$abi="* ]]; then
            ndk_triple="${mapping#*=}"
            break
        fi
    done

    if [[ -z "$v8_arch" || -z "$ndk_triple" ]]; then
        echo "❌ Unknown ABI: $abi"
        return 1
    fi

    local V8_LIB="v8.out/$v8_arch/libv8_monolith.a"
    local OBJ="build_native/android/v8impl_${abi}.o"
    local OUT_SO="src/main/jniLibs/$abi/libj2v8.so"

    echo "�� Building $abi → V8: $v8_arch | Toolchain: ${ndk_triple}${API_LEVEL}-clang++"

    # Create output directory
    mkdir -p "src/main/jniLibs/$abi"

    local CXX="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/${ndk_triple}${API_LEVEL}-clang++"

    if [[ ! -x "$CXX" ]]; then
        echo "❌ Compiler not found: $CXX"
        return 1
    fi
    if [[ ! -f "$V8_LIB" ]]; then
        echo "❌ V8 static lib missing: $V8_LIB"
        return 1
    fi

    local CPPFLAGS="-I$ANDROID_NDK_HOME/sysroot/usr/include"
    CPPFLAGS+=" -I$ANDROID_NDK_HOME/sysroot/usr/include/$ndk_triple"
    CPPFLAGS+=" -Iv8.out/include -Ijni $(get_security_flags $abi)"

    local LDFLAGS="$(get_linker_flags $abi)"

    echo "🛠️  Compiling..."
    $CXX $CPPFLAGS -c jni/com_eclipsesource_v8_V8Impl.cpp -o "$OBJ"

    echo "🔗 Linking..."
    $CXX $LDFLAGS "$OBJ" "$V8_LIB" -o "$OUT_SO"

    echo "✅ Built: $OUT_SO"
    ls -lh "$OUT_SO"

    # Wait for file system to sync
    sleep 1.0
    
    # Verify file exists before checking symbols
    if [[ ! -f "$OUT_SO" ]]; then
        echo "  ❌ File not found: $OUT_SO"
        return 1
    fi

    # Minimal security verification
    echo "🔍 Verifying minimal security features for $abi:"
        
    # Check for stack canary
    if readelf -s "$OUT_SO" | grep -q '__stack_chk'; then
      echo "  ✅ Stack canaries enabled"
    else
      echo "  ❌ Stack canaries missing"
    fi

    # Check for fortified functions
    if readelf -s "$OUT_SO" | grep -qE '__.*_chk'; then
      echo "  ✅ Fortified functions enabled (_FORTIFY_SOURCE)"
    else
      echo "  ❌ Fortified functions missing"
    fi
}

echo ""
echo "🏗️  Building native libraries with minimal security + essential compilation flags..."
for abi in "${ANDROID_ABIS[@]}"; do
    build_arch "$abi"
done

echo ""
echo "🎉 Build completed."
echo "⚠️  WARNING: This build uses MINIMAL security configuration."
echo "    Only stack canaries and fortified functions are enabled."
echo "    Advanced security features (RELRO, NX Stack, Symbol Hiding, etc.) are DISABLED."
ls -la src/main/jniLibs/*/libj2v8.so 2>/dev/null || echo "⚠️  No libraries built"
