# Hands CMake a ready-made OpenGL::GL target for the PS5 OpenGL SDK, the same
# shim that let projectM configure. Without it find_package(OpenGL) looks for
# GLX, which this console does not have.
# The PacBrew sysroot's homebrew prefix (SDL2, curl and the game's other
# libraries). build.sh passes $PACBREW; set PS5_PACBREW to override.
if(NOT PS5_PACBREW)
    if(DEFINED ENV{PACBREW})
        set(PS5_PACBREW "$ENV{PACBREW}")
    else()
        message(FATAL_ERROR "Set PACBREW to the PacBrew sysroot's user/homebrew directory")
    endif()
endif()

# The PS5 OpenGL SDK: release 1.0.2, unpacked in sdk-102/. It fixes the
# program queries that ended the process (ps5-opengl#9) and no longer prints
# draw statistics while the game runs. -DPS5_OPENGL_SDK=... selects another.
if(NOT PS5_OPENGL_SDK)
    set(PS5_OPENGL_SDK "${CMAKE_CURRENT_LIST_DIR}/sdk-102/unpacked/ps5-opengl-sdk-1.0.2/sdk")
endif()

set(OPENGL_FOUND TRUE)
set(OpenGL_FOUND TRUE)
set(OPENGL_INCLUDE_DIR "${PS5_OPENGL_SDK}/include")
set(OPENGL_gl_LIBRARY "${PS5_OPENGL_SDK}/lib/libPS5OpenGL.a")
set(OPENGL_opengl_LIBRARY "${OPENGL_gl_LIBRARY}")
set(OPENGL_LIBRARIES "${OPENGL_gl_LIBRARY}")
if(NOT TARGET OpenGL::GL)
    add_library(OpenGL::GL STATIC IMPORTED GLOBAL)
    set_target_properties(OpenGL::GL PROPERTIES
        IMPORTED_LOCATION "${OPENGL_gl_LIBRARY}"
        INTERFACE_INCLUDE_DIRECTORIES "${OPENGL_INCLUDE_DIR}"
        INTERFACE_COMPILE_DEFINITIONS "GL_GLEXT_PROTOTYPES=1")
endif()

# pkg-config has to look inside the PacBrew sysroot and nowhere else: the
# toolchain's find-root rules otherwise keep CMake from seeing these, and the
# host's own .pc files would describe the wrong architecture.
set(ENV{PKG_CONFIG_LIBDIR} "${PS5_PACBREW}/lib/pkgconfig")
set(ENV{PKG_CONFIG_PATH} "${PS5_PACBREW}/lib/pkgconfig")
set(ENV{PKG_CONFIG_SYSROOT_DIR} "")
set(PKG_CONFIG_USE_CMAKE_PREFIX_PATH OFF)

# PacBrew ships SDL2 as a plain archive with a pkg-config file, not as the
# CMake package that exports SDL2::SDL2-static. The target is declared here so
# the game can link against it by the name its CMakeLists expects.
if(NOT TARGET SDL2::SDL2-static)
    add_library(SDL2::SDL2-static STATIC IMPORTED GLOBAL)
    set_target_properties(SDL2::SDL2-static PROPERTIES
        IMPORTED_LOCATION "${PS5_PACBREW}/lib/libSDL2.a"
        INTERFACE_INCLUDE_DIRECTORIES "${PS5_PACBREW}/include;${PS5_PACBREW}/include/SDL2"
        INTERFACE_LINK_LIBRARIES "${PS5_PACBREW}/lib/libiconv.a")
endif()
if(NOT TARGET SDL2::SDL2)
    add_library(SDL2::SDL2 ALIAS SDL2::SDL2-static)
endif()

# The .pc files name their libraries with -l and leave the search path to the
# caller, so the PacBrew lib directory is added to every link in this build.
link_directories("${PS5_PACBREW}/lib")

# SDL2 reaches the pad, the keyboard, the on-screen keyboard and the user
# service through these system modules, and the OpenGL SDK needs its GPU gate
# pulled in by name because nothing references it. Appended to every link in
# this build, which is blunt but keeps the game's own CMakeLists untouched.
set(PS5_SYSTEM_LIBS
    # libkernel first: the OpenGL SDK asks for -lkernel_web, which is the
    # browser environment's copy of the same entry points. A native title has
    # to import libkernel.prx instead, and every homebrew that runs on this
    # console does. Listing it here makes the linker resolve the kernel calls
    # against it before kernel_web gets the chance.
    "/opt/ps5-payload-sdk/target/lib/libkernel.so"
    "/opt/ps5-payload-sdk/target/lib/libScePad.so"
    "/opt/ps5-payload-sdk/target/lib/libSceKeyboard.so"
    "/opt/ps5-payload-sdk/target/lib/libSceUserService.so"
    "/opt/ps5-payload-sdk/target/lib/libSceImeDialog.so"
    "/opt/ps5-payload-sdk/target/lib/libSceSystemService.so"
    "/opt/ps5-payload-sdk/target/lib/libSceVideoOut.so"
    "/opt/ps5-payload-sdk/target/lib/libSceAudioOut.so"
    "${PS5_OPENGL_SDK}/lib/libSceAgc.so"
    "${PS5_OPENGL_SDK}/lib/libSceAgcDriver.so")
string(REPLACE ";" " " PS5_SYSTEM_LIBS_STR "${PS5_SYSTEM_LIBS}")

# curl, psl, zstd and OpenSSL refer to each other in both directions, and a
# static archive only resolves symbols from what is listed after it. A link
# group makes the linker loop over them until nothing is left undefined.
set(PS5_CURL_GROUP
    "-Wl,--start-group"
    "${PS5_PACBREW}/lib/libcurl.a"
    "${PS5_PACBREW}/lib/libpsl.a"
    "${PS5_PACBREW}/lib/libzstd.a"
    "${PS5_PACBREW}/lib/libssl.a"
    "${PS5_PACBREW}/lib/libcrypto.a"
    "-Wl,--end-group")
string(REPLACE ";" " " PS5_CURL_GROUP_STR "${PS5_CURL_GROUP}")

set(CMAKE_EXE_LINKER_FLAGS
    "${CMAKE_EXE_LINKER_FLAGS} -Wl,-u,ps5_agc_gate2_run ${PS5_CURL_GROUP_STR} ${PS5_SYSTEM_LIBS_STR}")

# The native converter refuses a binary that publishes application exports, and
# an ordinary link exports 451 symbols. This keeps them all internal, the way
# the native app boilerplate does for its own builds.
set(CMAKE_EXE_LINKER_FLAGS
    "${CMAKE_EXE_LINKER_FLAGS} -Wl,--version-script=${CMAKE_CURRENT_LIST_DIR}/ps5-symbols.map")

# A native title has nowhere for stderr to go and a libc heap far too small for
# a game, so two support files are compiled into it: one points the log at a
# file in the title folder, the other is the OpenGL SDK's allocator, which
# takes its memory from direct memory. The allocator owns malloc for the whole
# executable, and wrapping it only in part is unsafe, so the complete set of
# names goes together.
# ps5-crt.cpp is the boilerplate's own entry point. A PS5 title is handed its
# process parameters at _start and has to pass them to _init_env before
# anything else runs; without that the process never gets going, and the
# console answers CE-107750-0 with no [GAME] started line in the mount log.
# ps5-cpp-runtime.cpp bridges the C++ allocation operators to that runtime.
set(PROSPERO_SUPPORT_SOURCES
    "${CMAKE_CURRENT_LIST_DIR}/ps5-posix.c"
    "${CMAKE_CURRENT_LIST_DIR}/ps5-crt.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/ps5-cpp-runtime.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/ps5-support.c"
    "${CMAKE_CURRENT_LIST_DIR}/ps5-heap.c")
set(PS5_HEAP_WRAPS
    "-Wl,--wrap=malloc" "-Wl,--wrap=calloc" "-Wl,--wrap=realloc"
    "-Wl,--wrap=free" "-Wl,--wrap=posix_memalign"
    "-Wl,--wrap=malloc_usable_size"
    # A title has no environment, working directory or argv, and the C
    # library's versions of these end the process rather than failing. The
    # game calls getenv alone 57 times, so they are replaced once here.
    "-Wl,--wrap=getenv" "-Wl,--wrap=setenv" "-Wl,--wrap=putenv"
    "-Wl,--wrap=unsetenv" "-Wl,--wrap=getcwd" "-Wl,--wrap=chdir"
    # The same goes for these, each for a reason given in ps5-posix.c: two
    # go straight to the kernel from the static C library, the others need a
    # working directory, symbolic links or a shell.
    "-Wl,--wrap=access" "-Wl,--wrap=realpath" "-Wl,--wrap=readlink"
    "-Wl,--wrap=pathconf" "-Wl,--wrap=system"
    # A title may not read a directory; these list from dirs.txt instead.
    "-Wl,--wrap=opendir" "-Wl,--wrap=readdir" "-Wl,--wrap=closedir"
    # Diagnostics: the reason the process ended goes into stk.log as well.
    "-Wl,--wrap=sceKernelDebugOutText" "-Wl,--wrap=_Exit"
    "-Wl,--wrap=abort" "-Wl,--wrap=__assert"
    # Every thread gets a stack that fits a shader compile; see ps5-posix.c.
    "-Wl,--wrap=pthread_create"
    # Kernel devices: /dev/crypto is refused, the rest is logged.
    "-Wl,--wrap=open" "-Wl,--wrap=_open" "-Wl,--wrap=ioctl"
    # printf from the system library reaches no log; see ps5-posix.c.
    "-Wl,--wrap=printf" "-Wl,--wrap=vprintf" "-Wl,--wrap=puts"
    "-Wl,--wrap=putchar"
    # Who creates the descriptor the main thread blocks on.
    "-Wl,--wrap=pipe" "-Wl,--wrap=socketpair" "-Wl,--wrap=socket")
string(REPLACE ";" " " PS5_HEAP_WRAPS_STR "${PS5_HEAP_WRAPS}")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${PS5_HEAP_WRAPS_STR}")

# --as-needed drops a module from the import list when nothing actually calls
# into it. Without it the SDK's weak kernel stub drags in libkernel_web.prx,
# the browser environment's copy of libkernel, and a native title that imports
# it does not launch: the console answers CE-107750-0 and the sandbox is torn
# down a second later without the process ever starting. The boilerplate links
# this way for the same reason.
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--as-needed")

# The entry point comes from ps5-crt.cpp, so the C library's own startup files
# must stay out: -nostartfiles drops its crt1, which defines _start as well.
#
# ps5-pie.ld is the boilerplate's own layout: code, immutable data, RELRO and
# writable data in separate ranges, with the dynamic metadata where the native
# converter expects it. An ordinary clang layout links and signs fine but the
# console will not load it, which is what CE-107750-0 turned out to be.
# These belong to the game executable only. CMake's own feature tests build
# small programs with the same flags, and a custom entry point plus linker
# script makes every one of them fail, which silently turns off things like
# ENet's socklen_t detection.
#
# The OpenGL SDK goes here too. The game loads its GL functions through glad,
# so nothing pulled the SDK in until the screen came from its EGL: SDL's
# video driver does not run inside a title. libPS5OpenGL.a is a linker script
# naming the Mesa archives next to it, hence the -L.
get_filename_component(PS5_OPENGL_LIB_DIR "${OPENGL_gl_LIBRARY}" DIRECTORY)
set(PS5_FINAL_LINK_FLAGS
    "-nostartfiles -Wl,-e,_start -Wl,-T,${CMAKE_CURRENT_LIST_DIR}/ps5-pie.ld -L${PS5_OPENGL_LIB_DIR} ${OPENGL_gl_LIBRARY}")

# Several of the bundled libraries link against Threads::Threads. The target
# comes from find_package(Threads), which has to run before they are defined;
# on this toolchain pthreads is in libc, so the target carries no extra flag.
set(CMAKE_THREAD_LIBS_INIT "")
set(CMAKE_HAVE_THREADS_LIBRARY 1)
set(CMAKE_USE_WIN32_THREADS_INIT 0)
set(CMAKE_USE_PTHREADS_INIT 1)
set(THREADS_PREFER_PTHREAD_FLAG ON)
if(NOT TARGET Threads::Threads)
    add_library(Threads::Threads INTERFACE IMPORTED GLOBAL)
endif()
