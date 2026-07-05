cmake_minimum_required(VERSION 3.16)
project(voicenote C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt5 REQUIRED COMPONENTS Core Gui Qml Quick Multimedia Network Concurrent)

# ---------------------------------------------------------------------------
# whisper.cpp — expected as a git submodule / clone at libs/whisper.cpp
#   git clone https://github.com/ggml-org/whisper.cpp libs/whisper.cpp
# ---------------------------------------------------------------------------
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
add_subdirectory(libs/whisper.cpp EXCLUDE_FROM_ALL)

# Click architecture for the manifest
execute_process(
  COMMAND dpkg-architecture -qDEB_HOST_ARCH
  OUTPUT_VARIABLE CLICK_ARCH
  OUTPUT_STRIP_TRAILING_WHITESPACE
)

configure_file(manifest.json.in ${CMAKE_CURRENT_BINARY_DIR}/manifest.json)
configure_file(voicenote.desktop.in ${CMAKE_CURRENT_BINARY_DIR}/voicenote.desktop)

add_executable(voicenote
  src/main.cpp
  src/transcriber.cpp
  qml/qml.qrc
)

target_link_libraries(voicenote
  Qt5::Core Qt5::Gui Qt5::Qml Qt5::Quick
  Qt5::Multimedia Qt5::Network Qt5::Concurrent
  whisper
)

install(TARGETS voicenote RUNTIME DESTINATION .)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/manifest.json DESTINATION .)
install(FILES voicenote.apparmor DESTINATION .)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/voicenote.desktop DESTINATION .)
install(DIRECTORY assets DESTINATION .)
