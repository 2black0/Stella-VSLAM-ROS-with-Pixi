add_compile_options(-Wno-array-bounds -Wno-stringop-overflow)
cmake_minimum_required(VERSION 3.5)
project(stella_vslam_ros LANGUAGES CXX C)

if(POLICY CMP0042)
    cmake_policy(SET CMP0042 NEW)
endif()
if(POLICY CMP0072)
    cmake_policy(SET CMP0072 NEW)
    set(OpenGL_GL_PREFERENCE GLVND)
endif()
if(POLICY CMP0074)
    cmake_policy(SET CMP0074 NEW)
endif()

list(APPEND CMAKE_MODULE_PATH ${PROJECT_SOURCE_DIR}/cmake)

##################
# Set build type #
##################

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Release")
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Release" "MinSizeRel" "RelWithDebInfo")
endif()

message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")

###########################
# Set application options #
###########################

set(USE_SANITIZER OFF CACHE BOOL "Enable Address/Memory sanitizer (set env as ASAN_OPTIONS=detect_leaks=1)")

if(USE_SANITIZER)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fno-omit-frame-pointer -fsanitize=address")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-omit-frame-pointer -fsanitize=address")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fno-omit-frame-pointer -fsanitize=address")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -fno-omit-frame-pointer -fsanitize=address")
    message(STATUS "Address/Memory sanitizer: ENABLED")
else()
    message(STATUS "Address/Memory sanitizer: DISABLED")
endif()

set(USE_STACK_TRACE_LOGGER OFF CACHE BOOL "Enable automatic stack trace logger of backward-cpp")
if(USE_STACK_TRACE_LOGGER)
    find_package(Backward REQUIRED)
    message(STATUS "Stack trace logger: ENABLED")
else()
    message(STATUS "Stack trace logger: DISABLED")
endif()

set(USE_GOOGLE_PERFTOOLS OFF CACHE BOOL "Enable profiler of google-perftools")

if(USE_GOOGLE_PERFTOOLS)
    message(STATUS "Google Perftools: ENABLED")
    find_package(Gperftools REQUIRED)
    include_directories(${GPERFTOOLS_INCLUDE_DIRS})
else()
    message(STATUS "Google Perftools: DISABLED")
endif()

########################
# Set compiler options #
########################

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra")

set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -Og")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -Og")

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -O3 -ffast-math")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -ffast-math")

set(BUILD_WITH_MARCH_NATIVE OFF CACHE BOOL "Enable architecture-aware optimization (-march=native)")

if(BUILD_WITH_MARCH_NATIVE)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mtune=native -march=native")
    set(CMAKE_CXX_FLAGS "${CMAKE_C_FLAGS} -mtune=native -march=native")
endif()

##########################
# Set C++ standard (C14) #
##########################

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

##########################
# Extract version number #
##########################

find_package(inja)
find_package(nlohmann_json)
if(inja_FOUND AND nlohmann_json_FOUND)
    find_package(Python3 COMPONENTS Interpreter)
    if(Python3_Interpreter_FOUND)
        message(STATUS "inja: FOUND")
        message(STATUS "nlohmann_json: FOUND")
        message(STATUS "Python3 Interpreter: FOUND")
        set(VERSION_SCRIPT "${PROJECT_SOURCE_DIR}/script/version.py")
        if(NOT EXISTS "${VERSION_SCRIPT}")
            set(VERSION_SCRIPT "${PROJECT_SOURCE_DIR}/scripts/version.py")
        endif()
        if(EXISTS "${VERSION_SCRIPT}")
            execute_process(COMMAND ${Python3_EXECUTABLE} ${VERSION_SCRIPT}
                WORKING_DIRECTORY ${PROJECT_SOURCE_DIR}
                RESULT_VARIABLE ret)
            if(NOT ret EQUAL 0)
                message(FATAL_ERROR "failed to extract version number")
            endif()
            message(STATUS "version number: FOUND")
        else()
            message(STATUS "version script not found, skipping version extraction")
        endif()
    else()
        message(STATUS "Python3 Interpreter: NOT FOUND")
    endif()
else()
    message(STATUS "inja: NOT FOUND")
    message(STATUS "nlohmann_json: NOT FOUND")
endif()

##############
# Catkin GUI #
##############

set(CATKIN_TOPLEVEL "${CMAKE_CURRENT_SOURCE_DIR}/../catkin_ws/src/.catkin")

################################
# System & ROS dependecies     #
################################

find_package(Threads REQUIRED)
find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(rclcpp_components REQUIRED)
find_package(rclpy REQUIRED)
find_package(cv_bridge REQUIRED)
find_package(image_transport REQUIRED)
find_package(message_filters REQUIRED)
find_package(rcutils REQUIRED)
find_package(geometry_msgs REQUIRED)
find_package(nav_msgs REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(tf2 REQUIRED)
find_package(tf2_eigen REQUIRED)
find_package(tf2_geometry_msgs REQUIRED)
find_package(tf2_msgs REQUIRED)
find_package(tf2_ros REQUIRED)

###################
# YAML-CPP (req.) #
###################

find_package(yaml-cpp REQUIRED)

################################
# Stargazer (req.)             #
################################

find_package(stella_vslam REQUIRED)
find_package(G2O REQUIRED)

###################
# Pangolin Viewer #
###################

find_package(pangolin_viewer QUIET)

#####################
# Socket Publisher  #
#####################

find_package(socket_publisher QUIET)

######################
# Iridescence Viewer #
######################

find_package(iridescence_viewer QUIET)

#########
# Build #
#########

add_subdirectory(src)

add_library(stella_vslam_ros_system SHARED
  src/system.cc
  src/stella_vslam_ros.cc
  src/video_publisher.cc
)
if(pangolin_viewer_FOUND)
    target_compile_definitions(stella_vslam_ros_system
        PRIVATE HAVE_PANGOLIN_VIEWER)
    target_link_libraries(stella_vslam_ros_system PRIVATE
        pangolin_viewer::pangolin_viewer)
endif()
if(socket_publisher_FOUND)
    target_compile_definitions(stella_vslam_ros_system
        PRIVATE HAVE_SOCKET_PUBLISHER)
    target_link_libraries(stella_vslam_ros_system PRIVATE
        socket_publisher::socket_publisher ${SIOCLIENT_LIBRARY} ${PROTOBUF_LIBRARIES})
endif()
if(iridescence_viewer_FOUND)
    target_compile_definitions(stella_vslam_ros_system
        PRIVATE HAVE_IRIDESCENCE_VIEWER)
    target_link_libraries(stella_vslam_ros_system PRIVATE
        iridescence_viewer::iridescence_viewer)
endif()

target_include_directories(stella_vslam_ros_system PRIVATE
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
  $<INSTALL_INTERFACE:src>
  ${CMAKE_CURRENT_SOURCE_DIR}/3rd/popl/include
  ${CMAKE_CURRENT_SOURCE_DIR}/3rd/filesystem/include)
rclcpp_components_register_node(stella_vslam_ros_system PLUGIN "stella_vslam_ros::System" EXECUTABLE system)
rclcpp_components_register_node(stella_vslam_ros_system PLUGIN "stella_vslam_ros::VideoPublisher" EXECUTABLE video_publisher_component)
ament_export_targets(export_${PROJECT_NAME} HAS_LIBRARY_TARGET)
ament_target_dependencies(stella_vslam_ros_system
  PUBLIC
  rclcpp
  rclcpp_components
  cv_bridge
  image_transport
  message_filters
  rcutils
  geometry_msgs
  nav_msgs
  sensor_msgs
  tf2
  tf2_eigen
  tf2_geometry_msgs
  tf2_msgs
  tf2_ros)
target_link_libraries(stella_vslam_ros_system PRIVATE
  yaml-cpp
  stella_vslam::stella_vslam)
if(spdlog_FOUND)
  target_link_libraries(stella_vslam_ros_system PRIVATE
    spdlog::spdlog)
endif()
if(NOT WIN32)
  ament_environment_hooks(
    "${ament_cmake_package_templates_ENVIRONMENT_HOOK_LIBRARY_PATH}")
endif()
install(TARGETS
  stella_vslam_ros_system
  EXPORT export_${PROJECT_NAME}
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin
)

ament_package()
