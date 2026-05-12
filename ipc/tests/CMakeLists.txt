add_executable(ipc_tests messages_test.cpp)
target_link_libraries(ipc_tests PRIVATE azookey_ipc)
add_test(NAME ipc_tests COMMAND ipc_tests)

add_executable(ipc_payloads_tests payloads_test.cpp)
target_link_libraries(ipc_payloads_tests PRIVATE azookey_ipc)
add_test(NAME ipc_payloads_tests COMMAND ipc_payloads_tests)
