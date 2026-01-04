include(CMakeFindDependencyMacro)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_LIST_DIR})
find_dependency(Iridescence)

include("${CMAKE_CURRENT_LIST_DIR}/iridescence_viewerTargets.cmake")
