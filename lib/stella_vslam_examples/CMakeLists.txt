cmake_minimum_required(VERSION 3.1)
project(stella_vslam_examples LANGUAGES CXX C)

# ----- Find dependencies -----

find_package(stella_vslam REQUIRED)

# filesystem
set(filesystem_INCLUDE_DIR ${PROJECT_SOURCE_DIR}/3rd/filesystem/include)

# popl
set(popl_INCLUDE_DIR ${PROJECT_SOURCE_DIR}/3rd/popl/include)

set(USE_STACK_TRACE_LOGGER OFF CACHE BOOL "Enable automatic stack trace logger of backward-cpp")
if(USE_STACK_TRACE_LOGGER)
    find_package(Backward REQUIRED)
    message(STATUS "Stack trace logger: ENABLED")
else()
    message(STATUS "Stack trace logger: DISABLED")
endif()

set(USE_GOOGLE_PERFTOOLS OFF CACHE BOOL "Enable profiler of google-perftools")
if(USE_GOOGLE_PERFTOOLS)
    find_package(Gperftools REQUIRED)
    include_directories(${GPERFTOOLS_INCLUDE_DIRS})
    message(STATUS "Google Perftools: ENABLED")
else()
    message(STATUS "Google Perftools: DISABLED")
endif()

# ----- Show dialog -----

find_package(pangolin_viewer QUIET)
if(pangolin_viewer_FOUND)
    message(STATUS "Viewer for examples: PangolinViewer")
endif()
find_package(socket_publisher QUIET)
if(socket_publisher_FOUND)
    message(STATUS "Viewer for examples: SocketPublisher")
endif()
find_package(iridescence_viewer QUIET)
if(iridescence_viewer_FOUND)
    message(STATUS "Viewer for examples: IridescenceViewer")
endif()

# ----- AirSim -----

set(AIRSIM_ROOT "${PROJECT_SOURCE_DIR}/../AirSim" CACHE PATH "Path to AirSim root")
option(ENABLE_AIRSIM "Build AirSim examples" ON)

set(AIRSIM_AIRLIB_DIR "${AIRSIM_ROOT}/AirLib")
set(AIRSIM_RPCLIB_DIR "${AIRSIM_ROOT}/external/rpclib/rpclib-2.3.0")
set(AIRSIM_EIGEN_DIR "${AIRSIM_AIRLIB_DIR}/deps/eigen3")

if(ENABLE_AIRSIM AND NOT EXISTS "${AIRSIM_AIRLIB_DIR}/include")
    message(STATUS "AirSim not found at ${AIRSIM_AIRLIB_DIR}, disabling AirSim examples.")
    set(ENABLE_AIRSIM OFF)
endif()
if(ENABLE_AIRSIM AND NOT EXISTS "${AIRSIM_RPCLIB_DIR}/CMakeLists.txt")
    message(STATUS "rpclib not found at ${AIRSIM_RPCLIB_DIR}, disabling AirSim examples.")
    set(ENABLE_AIRSIM OFF)
endif()

if(ENABLE_AIRSIM)
    set(RPCLIB_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(RPCLIB_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    add_subdirectory("${AIRSIM_RPCLIB_DIR}" "${CMAKE_BINARY_DIR}/rpclib")

    file(GLOB_RECURSE AIRSIM_AIRLIB_SRCS "${AIRSIM_AIRLIB_DIR}/src/*.cpp")
    add_library(airsim_airlib STATIC ${AIRSIM_AIRLIB_SRCS})
    target_include_directories(airsim_airlib PUBLIC
        ${AIRSIM_AIRLIB_DIR}/include
        ${AIRSIM_EIGEN_DIR}
        ${AIRSIM_RPCLIB_DIR}/include
    )
    target_compile_features(airsim_airlib PUBLIC cxx_std_17)
    target_link_libraries(airsim_airlib PUBLIC rpc)
endif()

# ----- Build example executables -----

set(EXECUTABLE_TARGETS "")

add_executable(run_camera_slam src/run_camera_slam.cc)
list(APPEND EXECUTABLE_TARGETS run_camera_slam)

add_executable(run_image_slam src/run_image_slam.cc src/util/image_util.cc)
list(APPEND EXECUTABLE_TARGETS run_image_slam)

add_executable(run_video_slam src/run_video_slam.cc)
list(APPEND EXECUTABLE_TARGETS run_video_slam)

add_executable(run_euroc_slam src/run_euroc_slam.cc src/util/euroc_util.cc)
list(APPEND EXECUTABLE_TARGETS run_euroc_slam)

add_executable(run_kitti_slam src/run_kitti_slam.cc src/util/kitti_util.cc)
list(APPEND EXECUTABLE_TARGETS run_kitti_slam)

add_executable(run_tum_rgbd_slam src/run_tum_rgbd_slam.cc src/util/tum_rgbd_util.cc)
list(APPEND EXECUTABLE_TARGETS run_tum_rgbd_slam)

add_executable(run_loop_closure src/run_loop_closure.cc)
list(APPEND EXECUTABLE_TARGETS run_loop_closure)

if(ENABLE_AIRSIM)
    add_executable(run_camera_airsim_slam src/run_camera_airsim_slam.cc)
    list(APPEND EXECUTABLE_TARGETS run_camera_airsim_slam)

    add_executable(run_camera_airsim_log_slam src/run_camera_airsim_log_slam.cc)
    list(APPEND EXECUTABLE_TARGETS run_camera_airsim_log_slam)
endif()

foreach(EXECUTABLE_TARGET IN LISTS EXECUTABLE_TARGETS)
    # Set output directory for executables
    set_target_properties(${EXECUTABLE_TARGET} PROPERTIES
                          RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}"
                          RUNTIME_OUTPUT_DIRECTORY_DEBUG "${PROJECT_BINARY_DIR}"
                          RUNTIME_OUTPUT_DIRECTORY_RELEASE "${PROJECT_BINARY_DIR}"
                          RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL "${PROJECT_BINARY_DIR}"
                          RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${PROJECT_BINARY_DIR}")

    # PangolinViewer is used on a priority basis
    if(pangolin_viewer_FOUND)
        # Set macro flag
        target_compile_definitions(${EXECUTABLE_TARGET} PRIVATE HAVE_PANGOLIN_VIEWER)
        # Link viewer
        target_link_libraries(${EXECUTABLE_TARGET} PRIVATE pangolin_viewer::pangolin_viewer)
    endif()
    if(socket_publisher_FOUND)
        # Set macro flag
        target_compile_definitions(${EXECUTABLE_TARGET} PRIVATE HAVE_SOCKET_PUBLISHER)
        # Link viewer
        target_link_libraries(${EXECUTABLE_TARGET} PRIVATE socket_publisher::socket_publisher)
    endif()
    if(iridescence_viewer_FOUND)
        # Set macro flag
        target_compile_definitions(${EXECUTABLE_TARGET} PRIVATE HAVE_IRIDESCENCE_VIEWER)
        # Link viewer
        target_link_libraries(${EXECUTABLE_TARGET} PRIVATE iridescence_viewer::iridescence_viewer)
    endif()

    if(ENABLE_AIRSIM AND (EXECUTABLE_TARGET STREQUAL "run_camera_airsim_slam" OR EXECUTABLE_TARGET STREQUAL "run_camera_airsim_log_slam"))
        target_link_libraries(${EXECUTABLE_TARGET} PRIVATE airsim_airlib)
    endif()

    # Setup stack trace logger
    if(USE_STACK_TRACE_LOGGER)
        target_compile_definitions(${EXECUTABLE_TARGET} PRIVATE USE_STACK_TRACE_LOGGER)
        target_link_libraries(${EXECUTABLE_TARGET} PRIVATE Backward::Backward)
    endif()

    # Setup google-perftools
    if(USE_GOOGLE_PERFTOOLS)
        target_compile_definitions(${EXECUTABLE_TARGET} PRIVATE USE_GOOGLE_PERFTOOLS)
        target_link_libraries(${EXECUTABLE_TARGET} PRIVATE ${GPERFTOOLS_LIBRARIES})
    endif()

    # Link stella_vslam
    target_link_libraries(${EXECUTABLE_TARGET}
                          PRIVATE
                          stella_vslam::stella_vslam
                          opencv_imgcodecs
                          opencv_videoio)

    # include 3rd party library headers
    target_include_directories(${EXECUTABLE_TARGET}
                               PRIVATE
                               $<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/3rd/popl/include>
                               $<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/3rd/filesystem/include>
                               $<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/3rd/spdlog/include>)
endforeach()
