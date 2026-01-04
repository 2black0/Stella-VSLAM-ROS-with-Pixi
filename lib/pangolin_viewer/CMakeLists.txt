cmake_minimum_required(VERSION 3.1)
project(pangolin_viewer LANGUAGES CXX C)

# ----- Find dependencies -----

find_package(stella_vslam REQUIRED)

# Pangolin
find_package(Pangolin REQUIRED)

# ----- Set build type -----

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Release")
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Release")
endif()
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")

option(BUILD_SHARED_LIBS "Build stella_vslam as a shared library" ON)

# ----- Configure PangolinViewer library -----

add_library(pangolin_viewer
    ${CMAKE_CURRENT_SOURCE_DIR}/src/viewer.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/color_scheme.cc)

set_target_properties(pangolin_viewer PROPERTIES
    OUTPUT_NAME pangolin_viewer
    ARCHIVE_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/lib
    LIBRARY_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/lib)
if(${Pangolin_VERSION} VERSION_GREATER 0.5)
    message(STATUS "Build pangolin_viewer with c++17")
    set_property(TARGET pangolin_viewer PROPERTY CXX_STANDARD 17)
endif()

target_include_directories(pangolin_viewer 
    PUBLIC
    "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include/>"
    "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/3rd/tinycolormap/include>"
    "$<INSTALL_INTERFACE:include/>")

if(${Pangolin_VERSION} VERSION_GREATER 0.5)
    target_link_libraries(pangolin_viewer
        PUBLIC
        stella_vslam::stella_vslam
        opencv_highgui
        pango_display
        pango_opengl)
else()
    target_link_libraries(pangolin_viewer
        PUBLIC
        stella_vslam::stella_vslam
        opencv_highgui
        pangolin)
endif()

# ----- Install configuration -----

include(CMakePackageConfigHelpers)

set(PANGOLIN_VIEWER_GENERATED_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated)
set(PANGOLIN_VIEWER_VERSION_CONFIG ${PANGOLIN_VIEWER_GENERATED_DIR}/${PROJECT_NAME}ConfigVersion.cmake)
set(PANGOLIN_VIEWER_PROJECT_CONFIG ${PANGOLIN_VIEWER_GENERATED_DIR}/${PROJECT_NAME}Config.cmake)
set(PANGOLIN_VIEWER_TARGETS_EXPORT_NAME ${PROJECT_NAME}Targets)
set(PANGOLIN_VIEWER_CONFIG_INSTALL_DIR lib/cmake/${PROJECT_NAME})
set(PANGOLIN_VIEWER_NAMESPACE "${PROJECT_NAME}::")
set(PANGOLIN_VIEWER_VERSION 0.0.1)

# Create a version config file
write_basic_package_version_file(${PANGOLIN_VIEWER_VERSION_CONFIG}
    VERSION ${PANGOLIN_VIEWER_VERSION}
    COMPATIBILITY SameMajorVersion)

configure_file(${PROJECT_SOURCE_DIR}/cmake/Config.cmake.in ${PANGOLIN_VIEWER_PROJECT_CONFIG} @ONLY)

# Install to the specified directory
install(FILES ${PANGOLIN_VIEWER_VERSION_CONFIG} ${PANGOLIN_VIEWER_PROJECT_CONFIG}
    DESTINATION ${PANGOLIN_VIEWER_CONFIG_INSTALL_DIR})
install(EXPORT ${PANGOLIN_VIEWER_TARGETS_EXPORT_NAME}
    NAMESPACE ${PANGOLIN_VIEWER_NAMESPACE}
    DESTINATION ${PANGOLIN_VIEWER_CONFIG_INSTALL_DIR})

# Set standard installation directories
set(RUNTIME_DESTINATION bin)
set(LIBRARY_DESTINATION lib)
set(ARCHIVE_DESTINATION lib)
set(INCLUDES_DESTINATION include)

set(PANGOLIN_VIEWER_INCLUDE_INSTALL_DIR ${INCLUDES_DESTINATION}/pangolin_viewer)

install(TARGETS pangolin_viewer
    EXPORT ${PANGOLIN_VIEWER_TARGETS_EXPORT_NAME}
    RUNTIME DESTINATION ${RUNTIME_DESTINATION}
    LIBRARY DESTINATION ${LIBRARY_DESTINATION}
    ARCHIVE DESTINATION ${ARCHIVE_DESTINATION}
    INCLUDES DESTINATION ${PANGOLIN_VIEWER_INCLUDE_INSTALL_DIR})

file(GLOB HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/include/pangolin_viewer/*.h")
install(FILES ${HEADERS}
    DESTINATION ${PANGOLIN_VIEWER_INCLUDE_INSTALL_DIR})
