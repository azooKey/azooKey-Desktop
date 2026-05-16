add_library(azookey_tsf_tip SHARED
  src/DllMain.cpp
  src/exports.def
  src/TextService.cpp
  src/TextServiceFactory.cpp
)

target_include_directories(azookey_tsf_tip PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(azookey_tsf_tip PRIVATE azookey_core azookey_ipc advapi32 ole32 uuid)
target_compile_definitions(azookey_tsf_tip PRIVATE UNICODE _UNICODE)

if(AZOOKEY_BUILD_TESTS)
  add_executable(tsf_tip_com_smoke_tests
    tests/com_smoke_test.cpp
  )
  target_include_directories(tsf_tip_com_smoke_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include)
  target_compile_definitions(tsf_tip_com_smoke_tests PRIVATE
    AZOOKEY_TSF_TIP_DLL_PATH="$<TARGET_FILE:azookey_tsf_tip>"
  )
  target_compile_definitions(tsf_tip_com_smoke_tests PRIVATE UNICODE _UNICODE)
  add_dependencies(tsf_tip_com_smoke_tests azookey_tsf_tip)
  add_test(NAME tsf_tip_com_smoke_tests COMMAND tsf_tip_com_smoke_tests)
endif()
