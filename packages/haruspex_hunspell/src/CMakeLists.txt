cmake_minimum_required(VERSION 3.10)

project(haruspex_hunspell_library VERSION 1.7.5 LANGUAGES CXX)

file(GLOB HUNSPELL_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/hunspell/*.cxx")

add_library(haruspex_hunspell SHARED ${HUNSPELL_SOURCES})

set_target_properties(haruspex_hunspell PROPERTIES
  OUTPUT_NAME "haruspex_hunspell"
  CXX_STANDARD 14
  CXX_STANDARD_REQUIRED ON
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
)

# Exports the C API (Hunspell_create, Hunspell_spell...).
target_compile_definitions(haruspex_hunspell PRIVATE BUILDING_LIBHUNSPELL)

if (NOT CMAKE_BUILD_TYPE OR CMAKE_BUILD_TYPE STREQUAL "Debug")
  target_compile_options(haruspex_hunspell PRIVATE -O2)
endif()

if (ANDROID)
  # Android 15 16k page size.
  target_link_options(haruspex_hunspell PRIVATE "-Wl,-z,max-page-size=16384")
endif()
