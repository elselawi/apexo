cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "push_notifications.cpp"
  "push_payload.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# === Windows App SDK (push notifications) ====================================
#
# Windows push needs the Windows App SDK 1.7 projections. The packages are
# restored by windows/restore_windows_packages.ps1 into windows/packages (see
# windows/packages.config for the pinned versions); that folder is a build
# artifact and is git-ignored.
set(APEXO_PACKAGES_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../packages")
set(APEXO_WASDK_DIR "${APEXO_PACKAGES_DIR}/Microsoft.WindowsAppSDK")
set(APEXO_WASDK_WINMD_DIR "${APEXO_WASDK_DIR}/lib/uap10.0")
set(APEXO_CPPWINRT_PACKAGE_EXE "${APEXO_PACKAGES_DIR}/Microsoft.Windows.CppWinRT/bin/cppwinrt.exe")
set(APEXO_WINRT_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/winrt_generated")

if(NOT EXISTS "${APEXO_WASDK_WINMD_DIR}/Microsoft.Windows.PushNotifications.winmd")
  message(FATAL_ERROR
    "Windows App SDK 1.7 is not restored.\n"
    "Expected: ${APEXO_WASDK_WINMD_DIR}/Microsoft.Windows.PushNotifications.winmd\n"
    "Run: powershell -ExecutionPolicy Bypass -File windows/restore_windows_packages.ps1")
endif()
if(NOT EXISTS "${APEXO_WASDK_WINMD_DIR}/Microsoft.Windows.AppLifecycle.winmd")
  message(FATAL_ERROR
    "The Windows App SDK activation projection is missing:\n"
    "${APEXO_WASDK_WINMD_DIR}/Microsoft.Windows.AppLifecycle.winmd")
endif()

# The generated headers include <winrt/Windows.Foundation.h>, which comes from
# the Windows SDK itself.
if(DEFINED CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION)
  set(APEXO_WINSDK_VERSION "${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}")
endif()
if(NOT APEXO_WINSDK_VERSION)
  file(GLOB APEXO_WINSDK_VERSION_CANDIDATES LIST_DIRECTORIES true
    "C:/Program Files (x86)/Windows Kits/10/References/*")
  if(APEXO_WINSDK_VERSION_CANDIDATES)
    list(SORT APEXO_WINSDK_VERSION_CANDIDATES)
    list(REVERSE APEXO_WINSDK_VERSION_CANDIDATES)
    list(GET APEXO_WINSDK_VERSION_CANDIDATES 0 APEXO_WINSDK_REFERENCE_DIR)
    get_filename_component(APEXO_WINSDK_VERSION "${APEXO_WINSDK_REFERENCE_DIR}" NAME)
  endif()
endif()
set(APEXO_WINSDK_DIR "C:/Program Files (x86)/Windows Kits/10")
set(APEXO_WINSDK_REFERENCES "${APEXO_WINSDK_DIR}/References/${APEXO_WINSDK_VERSION}")
set(APEXO_WINSDK_UNION_METADATA "${APEXO_WINSDK_DIR}/UnionMetadata/${APEXO_WINSDK_VERSION}/Windows.winmd")
set(APEXO_WINSDK_CPPWINRT "${APEXO_WINSDK_DIR}/Include/${APEXO_WINSDK_VERSION}/cppwinrt")

if(NOT EXISTS "${APEXO_WINSDK_UNION_METADATA}")
  message(FATAL_ERROR
    "The Windows SDK metadata for version ${APEXO_WINSDK_VERSION} is missing:\n"
    "${APEXO_WINSDK_UNION_METADATA}\n"
    "Install that Windows SDK version or select another one in Visual Studio.")
endif()
if(NOT EXISTS "${APEXO_WINSDK_REFERENCES}")
  message(FATAL_ERROR
    "The Windows SDK reference metadata is missing:\n${APEXO_WINSDK_REFERENCES}")
endif()
if(NOT EXISTS "${APEXO_WINSDK_CPPWINRT}/winrt/Windows.Foundation.h")
  message(FATAL_ERROR
    "The Windows SDK C++/WinRT headers are missing:\n${APEXO_WINSDK_CPPWINRT}/winrt/Windows.Foundation.h")
endif()

# The projection generator must be the same version as the C++/WinRT headers it
# targets, so the Windows SDK's own cppwinrt.exe wins; the NuGet copy is only a
# fallback for SDK installations that do not ship it.
set(APEXO_CPPWINRT_EXE "${APEXO_WINSDK_DIR}/bin/${APEXO_WINSDK_VERSION}/x64/cppwinrt.exe")
if(NOT EXISTS "${APEXO_CPPWINRT_EXE}")
  set(APEXO_CPPWINRT_EXE "${APEXO_CPPWINRT_PACKAGE_EXE}")
endif()
if(NOT EXISTS "${APEXO_CPPWINRT_EXE}")
  message(FATAL_ERROR
    "No cppwinrt.exe found. Expected the Windows SDK tool at\n"
    "${APEXO_WINSDK_DIR}/bin/${APEXO_WINSDK_VERSION}/x64/cppwinrt.exe\n"
    "or the pinned package at ${APEXO_CPPWINRT_PACKAGE_EXE}.\n"
    "Run: powershell -ExecutionPolicy Bypass -File windows/restore_windows_packages.ps1")
endif()

# The projections only need the two namespaces the push service uses; asking for
# the whole Windows App SDK surface drags in WinUI types that need more metadata.
set(APEXO_WINRT_PUSH_HEADER "${APEXO_WINRT_GEN_DIR}/winrt/Microsoft.Windows.PushNotifications.h")
set(APEXO_WINRT_LIFECYCLE_HEADER "${APEXO_WINRT_GEN_DIR}/winrt/Microsoft.Windows.AppLifecycle.h")
set(APEXO_WINRT_STAMP "${APEXO_WINRT_GEN_DIR}/.apexo-inputs-v1")

# A single generated header is not proof that the projection tree matches the
# current generator/SDK/package inputs. Fingerprint every consumed input, and
# regenerate unless the stamp matches and both required headers exist.
if(CMAKE_VERSION VERSION_LESS "3.19")
  message(FATAL_ERROR "CMake 3.19 or newer is required for projection input hashing.")
endif()
file(GLOB_RECURSE APEXO_WINRT_REFERENCE_INPUTS CONFIGURE_DEPENDS
  "${APEXO_WINSDK_REFERENCES}/*.winmd")
set(APEXO_WINRT_INPUTS
  "${APEXO_CPPWINRT_EXE}"
  "${APEXO_WASDK_WINMD_DIR}/Microsoft.Windows.PushNotifications.winmd"
  "${APEXO_WASDK_WINMD_DIR}/Microsoft.Windows.AppLifecycle.winmd"
  "${APEXO_WINSDK_UNION_METADATA}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../packages.config"
  ${APEXO_WINRT_REFERENCE_INPUTS})
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  ${APEXO_WINRT_INPUTS})
list(SORT APEXO_WINRT_INPUTS)
set(APEXO_WINRT_INPUT_STATE "recipe-v1\n")
foreach(APEXO_INPUT IN LISTS APEXO_WINRT_INPUTS)
  file(SHA256 "${APEXO_INPUT}" APEXO_INPUT_HASH)
  string(APPEND APEXO_WINRT_INPUT_STATE
    "${APEXO_INPUT}:${APEXO_INPUT_HASH}\n")
endforeach()
string(SHA256 APEXO_WINRT_FINGERPRINT "${APEXO_WINRT_INPUT_STATE}")

set(APEXO_WINRT_PREVIOUS "")
if(EXISTS "${APEXO_WINRT_STAMP}")
  file(READ "${APEXO_WINRT_STAMP}" APEXO_WINRT_PREVIOUS)
endif()
set(APEXO_WINRT_NEEDS_GENERATION FALSE)
if(NOT "${APEXO_WINRT_PREVIOUS}" STREQUAL "${APEXO_WINRT_FINGERPRINT}")
  set(APEXO_WINRT_NEEDS_GENERATION TRUE)
endif()
if(NOT EXISTS "${APEXO_WINRT_PUSH_HEADER}" OR
   NOT EXISTS "${APEXO_WINRT_LIFECYCLE_HEADER}")
  set(APEXO_WINRT_NEEDS_GENERATION TRUE)
endif()

if(APEXO_WINRT_NEEDS_GENERATION)
  message(STATUS "Generating C++/WinRT projections for Windows push")
  # A partial/stale tree must not be reused: recreate the generated directory
  # rather than adding files to it.
  file(REMOVE_RECURSE "${APEXO_WINRT_GEN_DIR}")
  file(MAKE_DIRECTORY "${APEXO_WINRT_GEN_DIR}")
  execute_process(
    COMMAND "${APEXO_CPPWINRT_EXE}"
      -input "${APEXO_WASDK_WINMD_DIR}/Microsoft.Windows.PushNotifications.winmd"
      -input "${APEXO_WASDK_WINMD_DIR}/Microsoft.Windows.AppLifecycle.winmd"
      -reference "${APEXO_WINSDK_REFERENCES}"
      -reference "${APEXO_WINSDK_UNION_METADATA}"
      -out "${APEXO_WINRT_GEN_DIR}"
    RESULT_VARIABLE APEXO_CPPWINRT_RESULT
    OUTPUT_VARIABLE APEXO_CPPWINRT_OUTPUT
    ERROR_VARIABLE APEXO_CPPWINRT_ERROR)
  if(NOT "${APEXO_CPPWINRT_RESULT}" STREQUAL "0" OR
     NOT EXISTS "${APEXO_WINRT_PUSH_HEADER}" OR
     NOT EXISTS "${APEXO_WINRT_LIFECYCLE_HEADER}")
    message(FATAL_ERROR
      "cppwinrt failed to generate both Windows App SDK projections.\n"
      "${APEXO_CPPWINRT_OUTPUT}\n${APEXO_CPPWINRT_ERROR}")
  endif()
  # Write the stamp only after both outputs exist; a failed/incomplete run must
  # not look current on the next configure.
  file(WRITE "${APEXO_WINRT_STAMP}" "${APEXO_WINRT_FINGERPRINT}")
else()
  message(STATUS "Windows push projections are current")
endif()

target_include_directories(${BINARY_NAME} PRIVATE
  "${APEXO_WINRT_GEN_DIR}"
  "${APEXO_WINSDK_CPPWINRT}")

# C++/WinRT activation and error reporting (RoGetActivationFactory,
# RoOriginateLanguageException) come from the Windows Runtime umbrella library.
target_link_libraries(${BINARY_NAME} PRIVATE "WindowsApp.lib")

# === Native payload test =====================================================
#
# Excluded from the default build: it is a console program, not part of the app.
#   cmake --build build\windows\x64 --target push_payload_test --config Debug
#   build\windows\x64\runner\Debug\push_payload_test.exe
add_executable(push_payload_test EXCLUDE_FROM_ALL
  "push_payload_test.cpp"
  "push_payload.cpp"
)
apply_standard_settings(push_payload_test)
# The payload tests carry non-ASCII UTF-8 literals; MSVC must not treat the
# source as the local code page.
target_compile_options(push_payload_test PRIVATE "/utf-8")
target_include_directories(push_payload_test PRIVATE "${CMAKE_SOURCE_DIR}")
