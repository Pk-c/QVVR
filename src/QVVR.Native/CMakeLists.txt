cmake_minimum_required(VERSION 3.20)
project(QVVRNative LANGUAGES CXX)

if(NOT DEFINED OPENVR_SDK)
    message(FATAL_ERROR "OPENVR_SDK must point to the official OpenVR SDK checkout")
endif()

add_library(QVVR.Native SHARED QVVR.Native.cpp ShaderClip.cpp OpenXrBackend.cpp)
target_compile_features(QVVR.Native PRIVATE cxx_std_17)
set(QVVR_DEPS "${CMAKE_CURRENT_SOURCE_DIR}/../../.deps")
target_include_directories(QVVR.Native PRIVATE "${OPENVR_SDK}/headers" "${QVVR_DEPS}/directx-headers" "${QVVR_DEPS}/openxr/sdk/include")
target_link_libraries(QVVR.Native PRIVATE "${OPENVR_SDK}/lib/win64/openvr_api.lib" "${QVVR_DEPS}/openxr/sdk/native/x64/lib/openxr_loader.lib" d3d11 d3dcompiler advapi32 shell32 ole32)

set_target_properties(QVVR.Native PROPERTIES
    OUTPUT_NAME "QVVR.Native"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_CURRENT_SOURCE_DIR}/bin/Debug"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}/bin/Release"
    RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_CURRENT_SOURCE_DIR}/bin/Release"
    RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_CURRENT_SOURCE_DIR}/bin/Release")

if(MSVC)
    target_compile_options(QVVR.Native PRIVATE /W4 /permissive- /EHsc)
endif()
