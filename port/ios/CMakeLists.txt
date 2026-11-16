# iOS app. Built only when CMAKE_SYSTEM_NAME is iOS.
#
# With the ROM-derived code (the conker_rom target, see ios/game) it is the game;
# without it, the ROM-free self-test shell.

if(TARGET conker_rom)
    set(cbfd_host "${CONKER_CBFD_DIR}/host")
    file(GLOB cbfd_ios_patches "${CMAKE_SOURCE_DIR}/patches/cbfd/*.patch")
    list(SORT cbfd_ios_patches)
    conker_apply_patches("${CONKER_CBFD_DIR}" ${cbfd_ios_patches})

    add_executable(conker MACOSX_BUNDLE
        app/ConkerGame.mm
        app/rom_import.cpp
        app/rom_import.h
        app/nfd_ios.cpp
        app/conker_ios_game.cpp
        app/conker_ios_game.h
        app/touch_controls.mm
        app/touch_controls.h
        # CBFD-Recompiled's host program (host/CMakeLists.txt's ConkerRecomp, window build).
        "${cbfd_host}/src/main.cpp"
        "${cbfd_host}/src/null_renderer.cpp"
        "${cbfd_host}/src/overlays.cpp"
        "${cbfd_host}/src/ultra_extras.cpp"
        "${cbfd_host}/src/mod_api.cpp"
        "${cbfd_host}/src/rom_versions.cpp"
        "${cbfd_host}/src/widescreen.cpp"
        "${cbfd_host}/src/cutscene_aspect.cpp"
        "${cbfd_host}/src/field_of_view.cpp"
        "${cbfd_host}/src/interpolation.cpp"
        "${cbfd_host}/src/model_detail.cpp"
        "${cbfd_host}/src/render_fixes.cpp"
        "${cbfd_host}/src/look_aim.cpp"
        "${cbfd_host}/src/mouse_camera.cpp"
        "${cbfd_host}/src/frontend.cpp"
        "${cbfd_host}/src/conker_config.cpp"
        "${cbfd_host}/src/audio_output.cpp"
        "${cbfd_host}/src/rumble.cpp"
        "${cbfd_host}/src/fps_counter.cpp"
        "${cbfd_host}/src/reticle.cpp"
        "${cbfd_host}/src/pad_mappings.cpp"
        "${cbfd_host}/src/texture_packs.cpp"
        "${cbfd_host}/src/gliden64_packs.cpp"
        "${cbfd_host}/src/notices.cpp"
        "${cbfd_host}/src/local_achievements.cpp"
        "${cbfd_host}/src/save_states.cpp"
    )
    # CONKER_RT64 is CBFD-Recompiled's window build; HLSL_CPU is what rt64 compiles its
    # own headers with.
    target_compile_definitions(conker PRIVATE CONKER_IOS CONKER_RT64 HLSL_CPU)
    target_include_directories(conker PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/app"
        "${CONKER_GENERATED_DIR}"
        "${CONKER_RT64_DIR}/src"
        "${CONKER_RT64_DIR}/src/contrib"
        "${CONKER_RT64_DIR}/src/contrib/plume"
        "${CONKER_RT64_DIR}/src/contrib/imgui"
        "${CONKER_RT64_DIR}/src/contrib/hlslpp/include"
        "${CONKER_RT64_DIR}/src/contrib/mupen64plus-core/src/api"
        "${CONKER_RT64_DIR}/src/contrib/nativefiledialog-extended/src/include"
    )
    target_link_libraries(conker PRIVATE
        conker_rom
        recompui
        recompinput
        SDL2-static
        miniz
        "-framework AVFoundation"
        "-framework AudioToolbox"
        "-framework CoreAudio"
        "-framework CoreGraphics"
        "-framework CoreHaptics"
        "-framework CoreMotion"
        "-framework GameController"
        "-framework CoreBluetooth"
        "-framework OpenGLES"
    )
    # SDL's UIKit code is Objective-C in a static library: load all of it, categories too.
    target_link_options(conker PRIVATE -ObjC)
    # recompui loads its fonts, icons and style sheet from assets/ in the bundle.
    add_custom_command(TARGET conker POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory "${cbfd_host}/assets" "$<TARGET_BUNDLE_CONTENT_DIR:conker>/assets")
    # SDL 2's app delegate keeps its own window, so no UIKit scenes (InfoGame.plist.in).
    set(conker_info_plist "${CMAKE_CURRENT_SOURCE_DIR}/InfoGame.plist.in")
else()
    add_executable(conker MACOSX_BUNDLE
        app/ConkerApp.mm
        app/memory_probe.cpp
        app/memory_probe.h
        app/plume_clear.cpp
        app/plume_clear.h
        app/conker_log.h
        app/conker_log.mm
    )
    set(conker_info_plist "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in")
endif()

set_target_properties(conker PROPERTIES
    OUTPUT_NAME "Conker"
    MACOSX_BUNDLE_INFO_PLIST "${conker_info_plist}"
    MACOSX_BUNDLE_GUI_IDENTIFIER "${CONKER_BUNDLE_ID}"
    MACOSX_BUNDLE_BUNDLE_NAME "Conker"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${CONKER_BUNDLE_ID}"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
    XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE NO
)
target_compile_options(conker PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)

# librecomp's headers include recomp.h from N64Recomp, which it links privately.
target_include_directories(conker PRIVATE "${CONKER_RUNTIME_DIR}/N64Recomp/include")

target_link_libraries(conker PRIVATE
    librecomp
    ultramodern
    plume
    rt64
    "-framework UIKit"
    "-framework Foundation"
    "-framework Metal"
    "-framework QuartzCore"
)
