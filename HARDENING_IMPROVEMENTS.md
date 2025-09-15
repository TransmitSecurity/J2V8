# J2V8-Transmit Hardening Improvements

## Overview
This document outlines the security hardening improvements implemented in the `rebuild_native_secure.sh` build script. The script implements a **Minimal Security Configuration** focusing on essential security features while maintaining compatibility and performance.

When building with `rebuild_native_secure.sh`, `CMakeLists.txt` and `CMakeLists_secure.txt` are not used.

## Current Configuration: Minimal Security

### **Security Features Implemented** ✅

#### 1. **Stack Canaries** ✅
- **Flag**: `-fstack-protector-strong`
- **Purpose**: Detects buffer overflow attacks by placing canary values on the stack
- **Benefit**: Prevents stack-based buffer overflow exploitation

#### 2. **Fortified Functions** ✅
- **Flag**: `-D_FORTIFY_SOURCE=2`
- **Purpose**: Replaces unsafe functions with safer versions that check buffer bounds
- **Benefit**: Runtime buffer overflow detection for common functions

#### 3. **Static C++ Standard Library** ✅
- **Flag**: `-static-libstdc++` (both compiler and linker)
- **Purpose**: Embeds C++ standard library directly in the binary
- **Benefit**: Eliminates runtime dependency on `libc++_shared.so`

#### 4. **Android 16KB Page Size Support** ✅
- **Flags**: `-Wl,-z,max-page-size=16384` and `-Wl,-z,common-page-size=16384`
- **Purpose**: Aligns memory to 16KB boundaries for Android 14+ compatibility
- **Benefit**: Better memory efficiency and security on modern Android devices

### **Performance Optimizations** ✅

#### 1. **Maximum Optimization** ✅
- **Flag**: `-O3`
- **Purpose**: Enables aggressive optimization for better runtime performance
- **Benefit**: Faster execution at the cost of slightly longer compilation time

#### 2. **Modern C++ Standard** ✅
- **Flag**: `-std=c++20`
- **Purpose**: Uses the latest C++ standard for better language features
- **Benefit**: Access to modern C++ features and optimizations

## Current Compiler Flags

```bash
get_security_flags() {
    local abi=$1
    local flags=""

    # Essential flags for shared library + minimal security
    flags+=" -fPIC -std=c++20 -DSTATIC_V8=1 -O3"
    flags+=" -fstack-protector-strong -D_FORTIFY_SOURCE=2"
    flags+=" -static-libstdc++"  # Static C++ standard library linking

    echo "$flags"
}
```

## Current Linker Flags

```bash
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
```

## Security Benefits Summary

| Protection | Flag | Purpose | Benefit |
|------------|------|---------|---------|
| **Stack Canaries** | `-fstack-protector-strong` | Detects buffer overflows | Prevents stack-based attacks |
| **Fortified Functions** | `-D_FORTIFY_SOURCE=2` | Runtime bounds checking | Catches buffer overflows at runtime |
| **Static C++ STL** | `-static-libstdc++` | Embed C++ library | No external dependencies |
| **16KB Page Alignment** | `-Wl,-z,max-page-size=16384` | Memory alignment | Android 14+ compatibility |
| **Position Independent Code** | `-fPIC` | Relocatable code | Required for shared libraries |
| **Static V8 Linking** | `-DSTATIC_V8=1` | Embed V8 engine | Self-contained library |

## Verification Commands

### **Check Stack Canaries**
```bash
readelf -s libj2v8.so | grep '__stack_chk'
```

### **Check Fortified Functions**
```bash
readelf -s libj2v8.so | grep -E '__(memcpy|memmove|memset|strcpy|strncpy|strcat|strncat|sprintf|vsprintf|snprintf|vsnprintf|strlen|strchr)_chk'
```

### **Check 16KB Page Alignment**
```bash
readelf -l libj2v8.so | awk '/LOAD/ {print "Segment alignment: "$NF; exit}'
```

### **Check Static Linking**
```bash
readelf -d libj2v8.so | grep NEEDED
```

### **Run test script**
```bash
./test_aar_security.sh
```

## Design Philosophy

### **Minimal Security Configuration**
The current configuration focuses on the most essential security features:

1. **Stack Canaries**: Fundamental protection against buffer overflows
2. **Fortified Functions**: Runtime bounds checking for common functions
3. **Static Linking**: Eliminates external dependencies and potential supply chain attacks
4. **16KB Alignment**: Ensures compatibility with modern Android security features

### **Performance Focus**
- Uses `-O3` for maximum optimization
- C++20 standard for modern language features
- Minimal security overhead

### **Compatibility**
- Works across all Android architectures (arm64-v8a, armeabi-v7a, x86, x86_64)
- Compatible with Android 14+ 16KB page size requirements
- No external library dependencies

## Troubleshooting

### **Common Issues**

#### **"dlopen failed: library 'libc++_shared.so' not found"**
- **Cause**: Missing `-static-libstdc++` flag
- **Solution**: Ensure both compiler and linker flags include `-static-libstdc++`

#### **"Stack canaries missing" in verification**
- **Cause**: Timing issue in script verification
- **Solution**: The script includes `sleep 1.0` and file existence checks

#### **Build errors with security flags**
- **Cause**: Incompatible flag combinations
- **Solution**: Current minimal configuration avoids problematic flags

## Future Enhancements

Potential additions for enhanced security (not currently implemented):
- **RELRO Protection**: `-Wl,-z,relro -Wl,-z,now`
- **NX Stack Protection**: `-Wl,-z,noexecstack`
- **Code Segment Separation**: `-Wl,-z,separate-code`
- **Symbol Stripping**: `-Wl,--strip-debug`
- **Dead Code Elimination**: `-Wl,--gc-sections`

## References

- [Android NDK Security Best Practices](https://developer.android.com/ndk/guides/security)
- [Clang Security Features](https://clang.llvm.org/docs/SecurityFeatures.html)
- [Android 16KB Page Size Support](https://developer.android.com/about/versions/14/behavior-changes-14#16kb-page-size) 