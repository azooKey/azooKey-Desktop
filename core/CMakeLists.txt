add_library(azookey_core STATIC
  src/RomajiKanaConverter.cpp
  src/SimpleConverter.cpp
)

target_include_directories(azookey_core
  PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)
