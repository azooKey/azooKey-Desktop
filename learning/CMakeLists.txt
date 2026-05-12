add_library(azookey_learning STATIC
  src/LearningStore.cpp
  src/Reranker.cpp
  src/UserDictionary.cpp
)

target_include_directories(azookey_learning PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(azookey_learning PUBLIC azookey_core azookey_ipc)
