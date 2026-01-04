#----------------------------------------------------------------
# Generated CMake target import file for configuration "RelWithDebInfo".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "iridescence_viewer::iridescence_viewer" for configuration "RelWithDebInfo"
set_property(TARGET iridescence_viewer::iridescence_viewer APPEND PROPERTY IMPORTED_CONFIGURATIONS RELWITHDEBINFO)
set_target_properties(iridescence_viewer::iridescence_viewer PROPERTIES
  IMPORTED_LOCATION_RELWITHDEBINFO "${_IMPORT_PREFIX}/lib/libiridescence_viewer.so"
  IMPORTED_SONAME_RELWITHDEBINFO "libiridescence_viewer.so"
  )

list(APPEND _cmake_import_check_targets iridescence_viewer::iridescence_viewer )
list(APPEND _cmake_import_check_files_for_iridescence_viewer::iridescence_viewer "${_IMPORT_PREFIX}/lib/libiridescence_viewer.so" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
