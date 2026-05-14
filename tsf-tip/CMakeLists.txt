add_library(azookey_tsf_tip SHARED
  src/CandidateWindow.cpp
  src/DllMain.cpp
  src/DisplayAttribute.cpp
  src/TextService.cpp
  src/TextServiceFactory.cpp
)

target_include_directories(azookey_tsf_tip PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(azookey_tsf_tip PRIVATE azookey_core azookey_ipc ole32 uuid shlwapi msctf)
target_compile_definitions(azookey_tsf_tip PRIVATE UNICODE _UNICODE)
