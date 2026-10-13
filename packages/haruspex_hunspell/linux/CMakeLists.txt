# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "haruspex_hunspell")
project(${PROJECT_NAME} LANGUAGES CXX)

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# Bundled into the app's lib folder by the runner.
set(haruspex_hunspell_bundled_libraries
  $<TARGET_FILE:haruspex_hunspell>
  PARENT_SCOPE
)
