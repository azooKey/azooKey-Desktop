add_library(azookey_host STATIC
  src/InferenceEngine.cpp
  src/RequestScheduler.cpp
)

target_include_directories(azookey_host PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(azookey_host PUBLIC azookey_core azookey_learning azookey_ipc)

add_executable(azookey_inference_host src/main.cpp)
target_link_libraries(azookey_inference_host PRIVATE azookey_host)
