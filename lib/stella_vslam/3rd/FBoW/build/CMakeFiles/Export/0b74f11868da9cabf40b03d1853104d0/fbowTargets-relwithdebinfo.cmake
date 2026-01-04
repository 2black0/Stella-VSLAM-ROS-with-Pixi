#----------------------------------------------------------------
# Generated CMake target import file for configuration "RelWithDebInfo".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "fbow::fbow" for configuration "RelWithDebInfo"
set_property(TARGET fbow::fbow APPEND PROPERTY IMPORTED_CONFIGURATIONS RELWITHDEBINFO)
set_target_properties(fbow::fbow PROPERTIES
  IMPORTED_LINK_DEPENDENT_LIBRARIES_RELWITHDEBINFO "opencv_features2d;opencv_highgui"
  IMPORTED_LOCATION_RELWITHDEBINFO "${_IMPORT_PREFIX}/lib/libfbow.so.0.0.1"
  IMPORTED_SONAME_RELWITHDEBINFO "libfbow.so.0.0"
  )

list(APPEND _cmake_import_check_targets fbow::fbow )
list(APPEND _cmake_import_check_files_for_fbow::fbow "${_IMPORT_PREFIX}/lib/libfbow.so.0.0.1" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
