cmake_minimum_required(VERSION 3.10.2)
add_library(encrypt SHARED encrypt.cpp)

include_directories(${CMAKE_SOURCE_DIR}/../../../native/seal/include)
link_directories(${CMAKE_SOURCE_DIR}/../../../native/seal/lib)

find_library(log-lib log)

target_link_libraries(encrypt seal ${log-lib})
