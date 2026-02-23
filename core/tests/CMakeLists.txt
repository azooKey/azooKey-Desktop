add_executable(core_tests
  romaji_kana_converter_test.cpp
  simple_converter_test.cpp
)

target_link_libraries(core_tests PRIVATE azookey_core)

add_test(NAME core_tests COMMAND core_tests)
