# The game code generated from the player's ROM (CBFD-Recompiled's
# recomp/recompile.py), built only where the ROM is: pass
# -DCONKER_GENERATED_DIR=<path to RecompiledFuncs>. Nothing made from the ROM
# is in this repository.

if(NOT EXISTS "${CONKER_GENERATED_DIR}/funcs.h")
    message(FATAL_ERROR "${CONKER_GENERATED_DIR} has no funcs.h. Run CBFD-Recompiled's recomp/recompile.py first.")
endif()

file(GLOB conker_recompiled_funcs "${CONKER_GENERATED_DIR}/funcs_*.c")
add_library(conker_rom STATIC
    ${conker_recompiled_funcs}
    "${CONKER_GENERATED_DIR}/tlb_pages.c"
    # The audio microcode, recompiled by RSPRecomp.
    "${CONKER_GENERATED_DIR}/rsp/audio_ucode.cpp"
)
target_include_directories(conker_rom PRIVATE
    "${CONKER_RUNTIME_DIR}/N64Recomp/include"
    "${CONKER_GENERATED_DIR}"
)
target_link_libraries(conker_rom PRIVATE librecomp ultramodern)
# The same flags as CBFD-Recompiled's host/CMakeLists.txt: funcs.h does not
# declare the libultra functions the runtime provides, the generated code has
# many unused labels and variables, and conker.toml's hooks use setjmp.
target_compile_options(conker_rom PRIVATE
    $<$<COMPILE_LANGUAGE:C>:-include setjmp.h -Wno-implicit-function-declaration>
    -Wno-unused-label
    -Wno-unused-variable
    -Wno-unused-but-set-variable
    -fno-strict-aliasing
)
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
    # The audio microcode's vector unit uses SSSE3 and SSE4.1 intrinsics on x86
    # (desktop test builds); on arm64 it goes through sse2neon.
    target_compile_options(conker_rom PRIVATE -msse4.1)
endif()
