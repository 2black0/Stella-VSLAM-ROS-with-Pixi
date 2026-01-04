find_path(G2O_INCLUDE_DIR g2o/core/sparse_optimizer.h
  HINTS $ENV{CONDA_PREFIX}/include ${CMAKE_INSTALL_PREFIX}/include)

find_library(G2O_CORE_LIBRARY NAMES g2o_core
  HINTS $ENV{CONDA_PREFIX}/lib ${CMAKE_INSTALL_PREFIX}/lib)
find_library(G2O_STUFF_LIBRARY NAMES g2o_stuff
  HINTS $ENV{CONDA_PREFIX}/lib ${CMAKE_INSTALL_PREFIX}/lib)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(G2O DEFAULT_MSG
  G2O_INCLUDE_DIR G2O_CORE_LIBRARY G2O_STUFF_LIBRARY)

if(G2O_FOUND)
  set(G2O_INCLUDE_DIRS ${G2O_INCLUDE_DIR})
  set(G2O_LIBRARIES ${G2O_CORE_LIBRARY} ${G2O_STUFF_LIBRARY})
endif()
