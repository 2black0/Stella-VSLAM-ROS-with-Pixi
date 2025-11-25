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

# ----- Optional AirSim support -----

set(AIRSIM_RUNNER_ENABLED OFF)
set(AIRSIM_ROOT_DEFAULT "${PROJECT_SOURCE_DIR}/../../../../.deps/AirSim")
if(NOT DEFINED AIRSIM_ROOT OR AIRSIM_ROOT STREQUAL "")
    if(DEFINED ENV{AIRSIM_ROOT})
        set(AIRSIM_ROOT "$ENV{AIRSIM_ROOT}")
    else()
        set(AIRSIM_ROOT "${AIRSIM_ROOT_DEFAULT}")
    endif()
endif()

if(AIRSIM_ROOT AND EXISTS "${AIRSIM_ROOT}")
    set(AIRSIM_INCLUDE_DIR "${AIRSIM_ROOT}/AirLib/include")
    set(AIRSIM_EIGEN_DIR "${AIRSIM_ROOT}/AirLib/deps/eigen3")
    set(AIRSIM_RPCLIB_ROOT "${AIRSIM_ROOT}/AirLib/deps/rpclib")
    set(AIRSIM_RPCLIB_INCLUDE_DIR "${AIRSIM_RPCLIB_ROOT}/include")
    set(AIRSIM_RPCLIB_LIB_DIR "${AIRSIM_RPCLIB_ROOT}/lib")
    set(AIRSIM_RPCLIB_VERSION_FOLDER "rpclib-2.3.0")
    set(AIRSIM_RPCLIB_EXTERNAL_DIR "${AIRSIM_ROOT}/external/rpclib/${AIRSIM_RPCLIB_VERSION_FOLDER}")
    set(AIRSIM_RPCLIB_READY OFF)

    if(EXISTS "${AIRSIM_RPCLIB_INCLUDE_DIR}" AND EXISTS "${AIRSIM_RPCLIB_LIB_DIR}/librpc.a")
        set(AIRSIM_RPCLIB_READY ON)
        add_library(rpc STATIC IMPORTED GLOBAL)
        set_target_properties(rpc PROPERTIES
                              IMPORTED_LOCATION "${AIRSIM_RPCLIB_LIB_DIR}/librpc.a"
                              INTERFACE_INCLUDE_DIRECTORIES "${AIRSIM_RPCLIB_INCLUDE_DIR}")
    elseif(EXISTS "${AIRSIM_RPCLIB_EXTERNAL_DIR}")
        set(AIRSIM_RPCLIB_INCLUDE_DIR "${AIRSIM_RPCLIB_EXTERNAL_DIR}/include")
        set(AIRSIM_RPCLIB_READY ON)
        add_subdirectory("${AIRSIM_RPCLIB_EXTERNAL_DIR}" "${PROJECT_BINARY_DIR}/AirSimRpcLib")
    endif()

    if(EXISTS "${AIRSIM_INCLUDE_DIR}" AND EXISTS "${AIRSIM_EIGEN_DIR}/Eigen" AND AIRSIM_RPCLIB_READY)
        set(AIRSIM_RUNNER_ENABLED ON)
        # Disable MavLinkTest build (we don't need test executable, only library)
        set(MAVLINK_TEST OFF CACHE BOOL "Disable MavLinkTest build" FORCE)
        add_subdirectory("${AIRSIM_ROOT}/cmake/MavLinkCom" "${PROJECT_BINARY_DIR}/AirSimMavLinkCom")
        add_subdirectory("${AIRSIM_ROOT}/cmake/AirLib" "${PROJECT_BINARY_DIR}/AirSimAirLib")
        message(STATUS "AirSim support for run_camera_airsim_slam: ENABLED (root=${AIRSIM_ROOT})")

    else()
        message(WARNING "AirSim headers were not found below ${AIRSIM_ROOT}. run_camera_airsim_slam will not be built.")
    endif()
else()
    message(STATUS "AirSim root not found. run_camera_airsim_slam will be skipped.")
endif()

# ----- Build example executables -----

set(EXECUTABLE_TARGETS "")

add_executable(run_camera_slam src/run_camera_slam.cc)
list(APPEND EXECUTABLE_TARGETS run_camera_slam)

if(AIRSIM_RUNNER_ENABLED)
    add_executable(run_camera_airsim_slam src/run_camera_airsim_slam.cc)
    list(APPEND EXECUTABLE_TARGETS run_camera_airsim_slam)
    add_executable(run_camera_airsim_log_slam src/run_camera_airsim_log_slam.cc)
    list(APPEND EXECUTABLE_TARGETS run_camera_airsim_log_slam)
    find_package(Threads REQUIRED)
    target_include_directories(run_camera_airsim_slam PRIVATE
                               ${AIRSIM_INCLUDE_DIR}
                               ${AIRSIM_EIGEN_DIR}
                               ${AIRSIM_RPCLIB_INCLUDE_DIR})
    target_link_libraries(run_camera_airsim_slam PRIVATE
                          Threads::Threads
                          AirLib)
    target_include_directories(run_camera_airsim_log_slam PRIVATE
                               ${AIRSIM_INCLUDE_DIR}
                               ${AIRSIM_EIGEN_DIR}
                               ${AIRSIM_RPCLIB_INCLUDE_DIR})
    target_link_libraries(run_camera_airsim_log_slam PRIVATE
                          Threads::Threads
                          AirLib)
endif()

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
