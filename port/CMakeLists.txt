cmake_minimum_required(VERSION 3.24)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS" AND NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    # plume's iOS paths assume iOS 16 or later (buffer device address).
    set(CMAKE_OSX_DEPLOYMENT_TARGET "16.0" CACHE STRING "Minimum iOS version")
endif()

project(ConkeriOS VERSION 0.3.3 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 17)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CONKER_BUNDLE_ID "io.github.sithewok13.conker" CACHE STRING "iOS bundle identifier")
# CBFD-Recompiled pins the tools it was made with; use them as they are.
set(CONKER_CBFD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/CBFD-Recompiled")
set(CONKER_RUNTIME_DIR "${CONKER_CBFD_DIR}/tools/N64ModernRuntime")
set(CONKER_RT64_DIR "${CONKER_CBFD_DIR}/tools/rt64")
set(CONKER_PLUME_DIR "${CONKER_RT64_DIR}/src/contrib/plume")
set(CONKER_SDL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/SDL")

foreach(dir "${CONKER_RUNTIME_DIR}" "${CONKER_RT64_DIR}" "${CONKER_PLUME_DIR}" "${CONKER_SDL_DIR}")
    if(NOT EXISTS "${dir}/CMakeLists.txt")
        message(FATAL_ERROR "${dir} is missing. Run: git submodule update --init --recursive")
    endif()
endforeach()

# Applies patches to a submodule's working tree, in order, once. The last one
# reverse-applying means the whole stack is already in place.
function(conker_apply_patches repo)
    set(patches ${ARGN})
    if(NOT patches)
        return()
    endif()
    list(GET patches -1 last)
    execute_process(COMMAND git -C "${repo}" apply --reverse --check "${last}"
        RESULT_VARIABLE already_applied OUTPUT_QUIET ERROR_QUIET)
    if(already_applied EQUAL 0)
        return()
    endif()
    foreach(patch IN LISTS patches)
        execute_process(COMMAND git -C "${repo}" apply "${patch}" RESULT_VARIABLE result)
        if(NOT result EQUAL 0)
            message(FATAL_ERROR "Could not apply ${patch} to ${repo}. "
                "If the submodule holds a partial stack, reset it: git -C ${repo} checkout -- .")
        endif()
        message(STATUS "Applied ${patch}")
    endforeach()
endfunction()

# Conker's own changes to the runtime (save states, audio, scheduling).
conker_apply_patches("${CONKER_RUNTIME_DIR}" "${CONKER_CBFD_DIR}/recomp/n64modernruntime.patch")

# ultramodern + librecomp (and N64Recomp/LiveRecomp, which librecomp links).
# Mods are not used on iOS: LiveRecomp's JIT and code patching can't run there.
add_subdirectory("${CONKER_RUNTIME_DIR}" N64ModernRuntime)

# The game code, generated from the ROM where it is (see ios/game).
set(CONKER_GENERATED_DIR "" CACHE PATH "CBFD-Recompiled's RecompiledFuncs folder, generated from your ROM")
if(CONKER_GENERATED_DIR)
    add_subdirectory(ios/game)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    enable_language(OBJC OBJCXX)

    target_compile_options(LiveRecomp PRIVATE
        -include "${CMAKE_CURRENT_SOURCE_DIR}/ios/compat/sljit_ios.h")

    # Conker's RT64 changes (its graphics microcode, widescreen) first, then ours for iOS.
    file(GLOB rt64_ios_patches "${CMAKE_CURRENT_SOURCE_DIR}/patches/rt64/*.patch")
    list(SORT rt64_ios_patches)
    conker_apply_patches("${CONKER_RT64_DIR}" "${CONKER_CBFD_DIR}/recomp/rt64.patch" ${rt64_ios_patches})
    file(GLOB plume_patches "${CMAKE_CURRENT_SOURCE_DIR}/patches/plume/*.patch")
    list(SORT plume_patches)
    conker_apply_patches("${CONKER_PLUME_DIR}" ${plume_patches})

    # RT64's shader tools run during the build, so build them for this machine.
    set(host_tools_build "${CMAKE_BINARY_DIR}/host_tools")
    if(NOT EXISTS "${host_tools_build}/bin/spirv_cross_msl")
        message(STATUS "Building RT64 host tools in ${host_tools_build}")
        execute_process(
            COMMAND "${CMAKE_COMMAND}" -E env --unset=SDKROOT --unset=IPHONEOS_DEPLOYMENT_TARGET
                "${CMAKE_COMMAND}" -S "${CMAKE_CURRENT_SOURCE_DIR}/ios/host_tools" -B "${host_tools_build}"
                -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release "-DRT64_DIR=${CONKER_RT64_DIR}"
            RESULT_VARIABLE result)
        if(NOT result EQUAL 0)
            message(FATAL_ERROR "Configuring RT64 host tools failed")
        endif()
        execute_process(
            COMMAND "${CMAKE_COMMAND}" -E env --unset=SDKROOT --unset=IPHONEOS_DEPLOYMENT_TARGET
                "${CMAKE_COMMAND}" --build "${host_tools_build}" --parallel
            RESULT_VARIABLE result)
        if(NOT result EQUAL 0)
            message(FATAL_ERROR "Building RT64 host tools failed")
        endif()
    endif()
    set(RT64_HOST_TOOLS_DIR "${host_tools_build}/bin")

    # Compile RT64's Metal shaders for the SDK being targeted.
    if(CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
        set(RT64_METAL_SDK "iphonesimulator")
    else()
        set(RT64_METAL_SDK "iphoneos")
    endif()

    # SDL2: RT64 needs it, and the game layer uses it for controllers and audio.
    set(SDL_SHARED OFF CACHE BOOL "" FORCE)
    set(SDL_STATIC ON CACHE BOOL "" FORCE)
    set(SDL_TEST OFF CACHE BOOL "" FORCE)
    add_subdirectory("${CONKER_SDL_DIR}" SDL EXCLUDE_FROM_ALL)
    set(SDL2_INCLUDE_DIRS "$<TARGET_PROPERTY:SDL2-static,INTERFACE_INCLUDE_DIRECTORIES>")
    set(SDL2_LIBRARIES SDL2-static)

    set(RT64_STATIC TRUE)
    add_subdirectory("${CONKER_RT64_DIR}" rt64)

    # plume's Apple window glue is AppKit-only; swap in the UIKit version.
    get_target_property(plume_sources plume SOURCES)
    list(REMOVE_ITEM plume_sources plume_apple.mm)
    list(APPEND plume_sources "${CMAKE_CURRENT_SOURCE_DIR}/ios/plume/plume_apple_uikit.mm")
    set_target_properties(plume PROPERTIES SOURCES "${plume_sources}")
    # RT64 turns Retina off for macOS; on iOS render at the screen's native scale.
    target_compile_definitions(plume PRIVATE PLUME_APPLE_RETINA_ENABLED)

    if(TARGET conker_rom)
        # The game: CBFD-Recompiled's host code, with RecompFrontend's launcher, menus
        # and input (recompui on RmlUi, and recompinput).

        # FreeType, for RmlUi's fonts. RmlUi only needs a Freetype::Freetype target.
        foreach(dependency IN ITEMS ZLIB BZIP2 PNG HARFBUZZ BROTLI)
            set(FT_DISABLE_${dependency} ON CACHE BOOL "" FORCE)
        endforeach()
        add_subdirectory(third_party/freetype freetype EXCLUDE_FROM_ALL)
        add_library(Freetype::Freetype ALIAS freetype)

        set(CONKER_FRONTEND_DIR "${CONKER_CBFD_DIR}/tools/RecompFrontend")
        file(GLOB recompfrontend_ios_patches "${CMAKE_CURRENT_SOURCE_DIR}/patches/recompfrontend/*.patch")
        list(SORT recompfrontend_ios_patches)
        conker_apply_patches("${CONKER_FRONTEND_DIR}" "${CONKER_CBFD_DIR}/recomp/recompfrontend.patch" ${recompfrontend_ios_patches})
        conker_apply_patches("${CONKER_FRONTEND_DIR}/recompui/lib/RmlUi" "${CONKER_CBFD_DIR}/recomp/rmlui.patch")

        # As in CBFD-Recompiled's host/CMakeLists.txt: recompui compiles its shaders with
        # rt64's build_*_shader functions, which read these from the caller's scope. DXC
        # runs on the build machine.
        set(DXC_COMMON_OPTS "-I${CONKER_RT64_DIR}/src")
        set(DXC_DXIL_OPTS "-Wno-ignored-attributes")
        set(DXC_SPV_OPTS "-spirv" "-fspv-target-env=vulkan1.0" "-fvk-use-dx-layout")
        set(DXC_PS_OPTS "${DXC_COMMON_OPTS}" "-E" "PSMain" "-T ps_6_0" "-D DYNAMIC_RENDER_PARAMS")
        set(DXC_VS_OPTS "${DXC_COMMON_OPTS}" "-E" "VSMain" "-T vs_6_0" "-D DYNAMIC_RENDER_PARAMS" "-fvk-invert-y")
        if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
            set(DXC_ARCH x64)
        else()
            set(DXC_ARCH arm64)
        endif()
        set(DXC "DYLD_LIBRARY_PATH=${CONKER_RT64_DIR}/src/contrib/dxc/lib/${DXC_ARCH}"
            "${CONKER_RT64_DIR}/src/contrib/dxc/bin/${DXC_ARCH}/dxc-macos")

        # RmlUi builds shared libraries by default; an iOS app links everything in.
        set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
        set(RECOMP_FRONTEND_N64MODERNRUNTIME_PATH "${CONKER_RUNTIME_DIR}")
        set(RECOMP_FRONTEND_RT64_PATH "${CONKER_RT64_DIR}")
        add_subdirectory("${CONKER_FRONTEND_DIR}" RecompFrontend)
        # They take SDL's headers from its build folder, which SDL fills as it builds.
        add_dependencies(recompui SDL2-static)
        add_dependencies(recompinput SDL2-static)
    endif()

    add_subdirectory(ios)
endif()
