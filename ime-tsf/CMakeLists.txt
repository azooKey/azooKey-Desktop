add_library(azookey_tsf SHARED
  src/DllMain.cpp
  src/TextService.cpp
  src/TextServiceFactory.cpp
  src/Registrar.cpp
)

target_include_directories(azookey_tsf
  PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(azookey_tsf
  PRIVATE
    azookey_core
    ole32
    uuid
)

target_compile_definitions(azookey_tsf PRIVATE UNICODE _UNICODE)
