cmake_minimum_required(VERSION 3.1)
project(iridescence_viewer LANGUAGES CXX C)

# ----- Find dependencies -----
list(APPEND CMAKE_MODULE_PATH ${PROJECT_SOURCE_DIR}/cmake)

find_package(stella_vslam REQUIRED)

# Iridescence 
find_package(Iridescence REQUIRED)

# ----- Set build type -----

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Release")
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Release")
endif()
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")

option(BUILD_SHARED_LIBS "Build stella_vslam as a shared library" ON)

# ----- Configure IridescenceViewer library -----

add_library(iridescence_viewer
    ${CMAKE_CURRENT_SOURCE_DIR}/src/viewer.cc)

set_target_properties(iridescence_viewer PROPERTIES
    OUTPUT_NAME iridescence_viewer
    ARCHIVE_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/lib
    LIBRARY_OUTPUT_DIRECTORY ${PROJECT_BINARY_DIR}/lib)

target_include_directories(iridescence_viewer 
    PUBLIC
    "$<BUILD_INTERFACE:${Iridescence_INCLUDE_DIRS}>"
    "$<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include/>"
    "$<INSTALL_INTERFACE:include/>")

target_link_libraries(iridescence_viewer
    PUBLIC
    "${Iridescence_LIBRARIES}"
    stella_vslam::stella_vslam)

# ----- Install configuration -----

include(CMakePackageConfigHelpers)

set(IRIDESCENCE_VIEWER_GENERATED_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated)
set(IRIDESCENCE_VIEWER_VERSION_CONFIG ${IRIDESCENCE_VIEWER_GENERATED_DIR}/${PROJECT_NAME}ConfigVersion.cmake)
set(IRIDESCENCE_VIEWER_PROJECT_CONFIG ${IRIDESCENCE_VIEWER_GENERATED_DIR}/${PROJECT_NAME}Config.cmake)
set(IRIDESCENCE_VIEWER_TARGETS_EXPORT_NAME ${PROJECT_NAME}Targets)
set(IRIDESCENCE_VIEWER_CONFIG_INSTALL_DIR lib/cmake/${PROJECT_NAME})
set(IRIDESCENCE_VIEWER_NAMESPACE "${PROJECT_NAME}::")
set(IRIDESCENCE_VIEWER_VERSION 0.1.0)

# Create a version config file
write_basic_package_version_file(${IRIDESCENCE_VIEWER_VERSION_CONFIG}
    VERSION ${IRIDESCENCE_VIEWER_VERSION}
    COMPATIBILITY SameMajorVersion)

configure_file(${PROJECT_SOURCE_DIR}/cmake/Config.cmake.in ${IRIDESCENCE_VIEWER_PROJECT_CONFIG} @ONLY)

# Install to the specified directory
install(FILES ${IRIDESCENCE_VIEWER_VERSION_CONFIG} ${IRIDESCENCE_VIEWER_PROJECT_CONFIG} cmake/FindIridescence.cmake
    DESTINATION ${IRIDESCENCE_VIEWER_CONFIG_INSTALL_DIR})
install(EXPORT ${IRIDESCENCE_VIEWER_TARGETS_EXPORT_NAME}
    NAMESPACE ${IRIDESCENCE_VIEWER_NAMESPACE}
    DESTINATION ${IRIDESCENCE_VIEWER_CONFIG_INSTALL_DIR})

# Set standard installation directories
set(RUNTIME_DESTINATION bin)
set(LIBRARY_DESTINATION lib)
set(ARCHIVE_DESTINATION lib)
set(INCLUDES_DESTINATION include)

set(IRIDESCENCE_VIEWER_INCLUDE_INSTALL_DIR ${INCLUDES_DESTINATION}/iridescence_viewer)

install(TARGETS iridescence_viewer
    EXPORT ${IRIDESCENCE_VIEWER_TARGETS_EXPORT_NAME}
    RUNTIME DESTINATION ${RUNTIME_DESTINATION}
    LIBRARY DESTINATION ${LIBRARY_DESTINATION}
    ARCHIVE DESTINATION ${ARCHIVE_DESTINATION}
    INCLUDES DESTINATION ${IRIDESCENCE_VIEWER_INCLUDE_INSTALL_DIR})

file(GLOB HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/include/iridescence_viewer/*.h")
install(FILES ${HEADERS}
    DESTINATION ${IRIDESCENCE_VIEWER_INCLUDE_INSTALL_DIR})
