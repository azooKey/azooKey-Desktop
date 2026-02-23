add_library(azookey_ipc STATIC
  src/Messages.cpp
)

target_include_directories(azookey_ipc PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
