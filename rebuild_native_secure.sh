#!/bin/bash

# Security-Hardened J2V8 Native Library Rebuild Script for Android
# Enhanced version with comprehensive security features

set -euo pipefail  # Enhanced error handling

echo "🛡️  Rebuilding J2V8 Native Libraries (Security Hardened)"
echo "=========================================================="

# Default settings
API_LEVEL="${API_LEVEL:-21}"
ANDROID_ABIS=("arm64-v8a" "armeabi-v7a" "x86" "x86_64")
V8_ARCH_MAP=("arm64-v8a=android.arm64" "armeabi-v7a=android.arm" "x86=android.x86" "x86_64=android.x64")
NDK_TRIPLE_MAP=("arm64-v8a=aarch64-linux-android" "armeabi-v7a=armv7a-linux-androideabi" "x86=i686-linux-android" "x86_64=x86_64-linux-android")

# Security feature toggles
ENABLE_STACK_CANARIES=true
ENABLE_FORTIFY_SOURCE=true
ENABLE_CFI=false
ENABLE_UBSAN=false
ENABLE_ASAN=false

# Validate ANDROID_NDK_HOME
if [[ -z "${ANDROID_NDK_HOME:-}" || ! -d "$ANDROID_NDK_HOME" ]]; then
    echo "❌ ANDROID_NDK_HOME not set or invalid"
    exit 1
fi

NDK_TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
if [ ! -d "$NDK_TOOLCHAIN" ]; then
    echo "❌ Toolchain not found at $NDK_TOOLCHAIN"
    exit 1
fi

# Directories
mkdir -p src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86,x86_64}
mkdir -p build_native/android

get_security_flags() {
    local abi=$1
    local flags=""

    # Compiler hardening flags
    flags+=" -Wall -Wextra -Werror=return-type -Werror=format-security"
    flags+=" -Wformat -Wformat-security -Warray-bounds -Wcast-align"
    flags+=" -Wconversion -Wsign-conversion -Wnull-dereference"
    flags+=" -Wlogical-op -fPIC -fvisibility=default -ffunction-sections -fdata-sections"
    flags+=" -fno-common -fno-strict-aliasing -fwrapv -fno-delete-null-pointer-checks"
    flags+=" -O2 -g1 -DNDEBUG -std=c++20 -DSTATIC_V8=1"

    flags+=" -fstack-protector-strong -D_FORTIFY_SOURCE=2"

    # Stack canaries (buffer overflow detection)
    #[[ "$ENABLE_STACK_CANARIES" == true ]] && flags+=" -fstack-protector-strong"

    # Fortify source (runtime buffer checks)
    #[[ "$ENABLE_FORTIFY_SOURCE" == true ]] && flags+=" -D_FORTIFY_SOURCE=2"

    # Sanitizers
    [[ "$ENABLE_UBSAN" == true ]] && flags+=" -fsanitize=undefined -fno-sanitize-recover=undefined"
    [[ "$ENABLE_ASAN" == true ]] && flags+=" -fsanitize=address -fno-omit-frame-pointer"

    # Branch protection for ARM64
    [[ "$abi" == "arm64-v8a" ]] && flags+=" -mbranch-protection=standard"

    echo "$flags"
}

get_linker_flags() {
    local abi=$1
    local flags=""

    # Security linker flags
    flags+=" -shared -llog"
    flags+=" -Wl,-z,relro -Wl,-z,now"           # RELRO + immediate binding
    flags+=" -Wl,-z,noexecstack"                # DEP/ Non-executable stack
    flags+=" -Wl,-z,separate-code"              # Separate code segments
    flags+=" -Wl,--no-undefined"                # Catch undefined symbols
    flags+=" -Wl,--gc-sections"                 # Remove unused sections
    flags+=" -Wl,--strip-debug"                 # Strip symbols but keeps function symbols like __stack_chk_fail.
    flags+=" -Wl,-z,max-page-size=16384"        # Alignment: 16KB pages
    flags+=" -Wl,-z,common-page-size=16384"
    #flags+=" -static-libstdc++"

    # Stack canaries (buffer overflow detection)
    #[[ "$ENABLE_STACK_CANARIES" == true ]] && flags+=" -fstack-protector-strong"

    # Optional sanitizers
    [[ "$ENABLE_UBSAN" == true ]] && flags+=" -fsanitize=undefined"
    [[ "$ENABLE_ASAN" == true ]] && flags+=" -fsanitize=address"

    echo "$flags"
}

build_arch() {
    local abi=$1
    local v8_arch ndk_triple
    for m in "${V8_ARCH_MAP[@]}"; do [[ $m == "$abi="* ]] && v8_arch="${m#*=}"; done
    for m in "${NDK_TRIPLE_MAP[@]}"; do [[ $m == "$abi="* ]] && ndk_triple="${m#*=}"; done

    echo ""
    echo "🔧 Building $abi → V8: $v8_arch | Toolchain: $ndk_triple$API_LEVEL-clang++"

    local CC="$NDK_TOOLCHAIN/bin/${ndk_triple}${API_LEVEL}-clang"
    local CXX="$NDK_TOOLCHAIN/bin/${ndk_triple}${API_LEVEL}-clang++"
    local V8_LIB="v8.out/$v8_arch/libv8_monolith.a"
    local OUT_SO="src/main/jniLibs/$abi/libj2v8.so"
    local OBJ="build_native/android/v8impl_$abi.o"

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

    # Security checks
    echo "🔍 Verifying security flags for $abi:"
        
    # Check for stack canary
#    if readelf -s "$OUT_SO" | grep -q '__stack_chk_fail'; then
    if readelf -s "$OUT_SO" | grep -q '__stack_chk'; then
      echo "  ✅ Stack canaries enabled"
    else
      echo "  ❌ Stack canaries missing"
    fi

    # Check for fortified functions
    if readelf -s "$OUT_SO" | grep -qE '__(memcpy|memmove|memset|strcpy|strncpy|strcat|strncat|sprintf|vsprintf|snprintf|vsnprintf|strlen|strchr)_chk'; then
      echo "  ✅ Fortified functions enabled (_FORTIFY_SOURCE)"
    else
      echo "  ❌ Fortified functions missing"
    fi

    has_gnu_relro=$(readelf -l "$OUT_SO" | grep -q 'GNU_RELRO' && echo "yes" || echo "no")
    has_bind_now=$(readelf -d "$OUT_SO" | grep -q 'BIND_NOW' && echo "yes" || echo "no")

    if [[ "$has_gnu_relro" == "yes" && "$has_bind_now" == "yes" ]]; then
        echo " ✅ Full RELRO enabled"
    elif [[ "$has_gnu_relro" == "yes" ]]; then
        echo " ⚠️  Partial RELRO (BIND_NOW missing)"
    else
        echo " ❌ RELRO missing"
    fi

    readelf -W -l "$OUT_SO" | grep -q "GNU_STACK.*RW" && echo "  ✅ Non-executable stack" || echo "  ⚠️ Executable stack detected"
    readelf -l "$OUT_SO" | awk '/LOAD/ {print "  Segment alignment: "$NF; exit}'
}

echo ""
echo "🏗️  Building security-hardened native libraries for all ABIs..."
for abi in "${ANDROID_ABIS[@]}"; do
    build_arch "$abi"
done

echo ""
echo "🎉 Build completed."
ls -la src/main/jniLibs/*/libj2v8.so 2>/dev/null || echo "⚠️  No libraries built"
