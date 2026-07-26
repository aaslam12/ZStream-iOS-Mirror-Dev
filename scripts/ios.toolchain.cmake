# Minimal iOS toolchain file for CMake.
#
# Select a platform by passing -DIOS_PLATFORM=<OS64|SIMULATORARM64|SIMULATOR64>
# on the CMake command line. Mirrors the handful of settings BoringSSL's own
# CMakeLists.txt actually looks at (CMAKE_SYSTEM_NAME, CMAKE_OSX_SYSROOT,
# CMAKE_OSX_ARCHITECTURES) — not a general-purpose toolchain.

if(NOT DEFINED IOS_PLATFORM)
    set(IOS_PLATFORM "OS64")
endif()

set(CMAKE_SYSTEM_NAME iOS)

if(IOS_PLATFORM STREQUAL "OS64")
    set(CMAKE_OSX_SYSROOT iphoneos)
    set(CMAKE_OSX_ARCHITECTURES arm64)
    set(CMAKE_SYSTEM_PROCESSOR arm64)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0")
elseif(IOS_PLATFORM STREQUAL "SIMULATORARM64")
    set(CMAKE_OSX_SYSROOT iphonesimulator)
    set(CMAKE_OSX_ARCHITECTURES arm64)
    set(CMAKE_SYSTEM_PROCESSOR arm64)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0")
elseif(IOS_PLATFORM STREQUAL "SIMULATOR64")
    set(CMAKE_OSX_SYSROOT iphonesimulator)
    set(CMAKE_OSX_ARCHITECTURES x86_64)
    set(CMAKE_SYSTEM_PROCESSOR x86_64)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0")
else()
    message(FATAL_ERROR "Unknown IOS_PLATFORM: ${IOS_PLATFORM} (expected OS64, SIMULATORARM64, or SIMULATOR64)")
endif()

set(CMAKE_C_COMPILER   /usr/bin/clang)
set(CMAKE_CXX_COMPILER /usr/bin/clang++)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# When CMAKE_SYSTEM_NAME is iOS, CMake bundles executable targets as .app
# bundles by default. BoringSSL's "bssl" CLI target doesn't opt out of that
# and has no BUNDLE DESTINATION configured, which fails install() at
# configure time. We only need the crypto/ssl static libs, so force plain
# command-line executables instead.
set(CMAKE_MACOSX_BUNDLE OFF)
