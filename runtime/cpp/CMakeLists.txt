cmake_minimum_required(VERSION 3.10)
include(GNUInstallDirs)

########################################################################################################################
# LIBRARY
########################################################################################################################
option(FLETCHER_PYTHON
        "Build Fletcher for use in building pyfletcher"
        OFF)

#Only needed when building for Python
set(PYARROW_DIR "/usr/" CACHE STRING "pyarrow install directory")

set(FLETCHER fletcher)

project(${FLETCHER} VERSION 0.0.1 DESCRIPTION "Fletcher C++ runtime library")

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_FLAGS "-Wall -Wextra -fPIC")
set(CMAKE_CXX_FLAGS_DEBUG "-g")
set(CMAKE_CXX_FLAGS_RELEASE "-Ofast -march=native")

if (FLETCHER_PYTHON)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -D_GLIBCXX_USE_CXX11_ABI=0")
    message("Building for Pyfletcher")
endif()

set(SOURCES
        src/fletcher/platform.cc
        src/fletcher/context.cc
        src/fletcher/usercore.cc)

# CPP runtime library uses global C header
set(GLOBAL_C_HEADER
        ../../common/c/src/fletcher/fletcher.h)

set(HEADERS
        src/fletcher/platform.h
        src/fletcher/context.h
        src/fletcher/usercore.h)

add_library(${FLETCHER} SHARED ${COMMON_HEADERS} ${HEADERS} ${SOURCES})

set_target_properties(${FLETCHER} PROPERTIES VERSION ${PROJECT_VERSION})
set_target_properties(${FLETCHER} PROPERTIES SOVERSION 1)
set_target_properties(${FLETCHER} PROPERTIES PUBLIC_HEADER src/fletcher/api.h)

if (FLETCHER_PYTHON)
    find_library(LIB_ARROW arrow PATHS ${PYARROW_DIR} NO_DEFAULT_PATH)
    include_directories(${PYARROW_DIR}/include)
else()
    find_library(LIB_ARROW arrow)
endif()
message(${LIB_ARROW})

# Common library (static), if not already built
if (NOT TARGET fletcher-common)
    add_subdirectory(../../common/cpp fletcher-common)
endif()

# For now, we want to include all symbols from the common static library into the runtime shared library.
# At some point they should be exposed more programatically (in the api header, for example).
target_link_libraries(${FLETCHER} -Wl,-whole-archive fletcher-common -Wl,-no-whole-archive)
include_directories(../../common/cpp/src)
include_directories(../../common/c/src)

# Dynamically link the dynamically library linking library
target_link_libraries(${FLETCHER} ${CMAKE_DL_LIBS})

# Dynamically link Arrow
target_link_libraries(${FLETCHER} ${LIB_ARROW})

# Install .so
install(TARGETS ${FLETCHER}
        LIBRARY DESTINATION ${CMAKE_INSTALL_FULL_LIBDIR}
        PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/${FLETCHER})

# Install headers from cpp runtime
install(FILES ${HEADERS}
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/${FLETCHER}
        )

# Headers from common library
set(COMMON_HEADERS
        ../../common/cpp/src/fletcher/common/status.h
        ../../common/cpp/src/fletcher/common/arrow-utils.h
        ../../common/cpp/src/fletcher/common/hex-view.h
        ../../common/cpp/src/fletcher/common/timer.h)

install(FILES ${COMMON_HEADERS}
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/${FLETCHER}/common
        )

# Install C header
install(FILES ${GLOBAL_C_HEADER}
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/${FLETCHER}
        )

########################################################################################################################
# TESTS
########################################################################################################################
if (FLETCHER_TESTS)
    # Include GoogleTest CMake functionality
    include(GoogleTest)
    find_package(GTest REQUIRED)

    set(TEST_SOURCES test/test.cpp)
    add_executable(${FLETCHER}-test ${TEST_HEADERS} ${TEST_SOURCES})
    target_link_libraries(${FLETCHER}-test ${FLETCHER})
    target_link_libraries(${FLETCHER}-test ${LIB_ARROW})
    target_link_libraries(${FLETCHER}-test GTest::GTest GTest::Main)
    target_include_directories(${FLETCHER}-test PUBLIC ../../platforms/echo/runtime/src)

    gtest_discover_tests(${FLETCHER}-test WORKING_DIRECTORY ../../platforms/echo/runtime)
endif (FLETCHER_TESTS)
