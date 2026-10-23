#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <cstdio>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "push_config.h"
#include "push_notifications.h"
#include "utils.h"
#include "win32_window.h"

namespace {

constexpr char kDiagnosePushFlag[] = "--diagnose-push";

bool HasArgument(const std::vector<std::string>& arguments, const char* flag) {
  return std::any_of(arguments.begin(), arguments.end(),
                     [flag](const std::string& argument) {
                       return argument == flag;
                     });
}

bool HasArgumentPrefix(const std::vector<std::string>& arguments,
                       const char* prefix) {
  const std::string value(prefix);
  return std::any_of(arguments.begin(), arguments.end(),
                     [&value](const std::string& argument) {
                       return argument.rfind(value, 0) == 0;
                     });
}

// Windows starts notification COM servers with these arguments. Such a process
// is not an ordinary duplicate launch: it must still be allowed to create its
// window and receive the activation payload.
bool IsNotificationActivationServer(
    const std::vector<std::string>& arguments) {
  const auto narrow = [](const wchar_t* value) {
    const int size = ::WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0,
                                          nullptr, nullptr);
    if (size <= 1) return std::string();
    std::string result(static_cast<size_t>(size), '\0');
    ::WideCharToMultiByte(CP_UTF8, 0, value, -1, result.data(), size, nullptr,
                          nullptr);
    result.resize(static_cast<size_t>(size - 1));
    return result;
  };
  const std::string push = narrow(APEXO_PUSH_ACTIVATION_ARGUMENTS);
  const std::string toast = narrow(APEXO_TOAST_ACTIVATION_ARGUMENTS);
  return (!push.empty() && HasArgumentPrefix(arguments, push.c_str())) ||
         (!toast.empty() && HasArgumentPrefix(arguments, toast.c_str()));
}

// A WIN32 app has no console of its own. A diagnostic run prints into the
// launching console, so it has to be attached and the streams reopened.
void AttachParentConsoleForDiagnostics() {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS)) {
    return;
  }
  FILE* unused = nullptr;
  freopen_s(&unused, "CONOUT$", "w", stdout);
  freopen_s(&unused, "CONOUT$", "w", stderr);
}

// Reports the push environment without starting Flutter. Never prints a channel
// URI, token or payload.
int RunPushDiagnostics(apexo::PushNotifications& push) {
  AttachParentConsoleForDiagnostics();
  std::printf("package identity: %s\n",
              push.HasPackageIdentity() ? "yes" : "no");
  std::printf("isSupported: %s\n", push.IsSupported() ? "true" : "false");
  std::printf("channel configured: %s\n",
              push.IsChannelConfigured() ? "yes" : "no");
  std::printf("registered: %s\n", push.IsRegistered() ? "yes" : "no");
  std::fflush(stdout);
  return EXIT_SUCCESS;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Ordinary duplicate launches are forwarded to the primary window before any
  // push/local-notification registration. A notification COM server must skip
  // this gate: it still has to accept its activation payload.
  const bool diagnose = HasArgument(command_line_arguments, kDiagnosePushFlag);
  if (!diagnose) {
    if (IsNotificationActivationServer(command_line_arguments)) {
      // A notification COM server still owns the single-instance name when it
      // is the first process: that is what lets a later ordinary launch find
      // and promote it. If a primary already exists, it keeps the name and this
      // process must still be allowed to accept its COM activation payload.
      if (!Win32Window::ClaimSingleInstance()) {
        Win32Window::AllowNotificationActivationServer();
      }
    } else if (!Win32Window::ClaimSingleInstance()) {
      if (Win32Window::ForwardLaunchToPrimaryInstance()) {
        ::CoUninitialize();
        return EXIT_SUCCESS;
      }
      // The primary may have exited between the failed claim and the forward
      // attempt. Try once more rather than discarding the user's launch.
      if (!Win32Window::ClaimSingleInstance()) {
        MessageBoxW(nullptr, L"The application is already running.", L"Apexo",
                    MB_ICONINFORMATION | MB_OK);
        ::CoUninitialize();
        return EXIT_SUCCESS;
      }
    }
  }

  // Push registration must happen before the window (and Dart) exists, and
  // before the activation arguments are inspected. This is a no-op without
  // package identity.
  apexo::PushNotifications& push = apexo::PushNotifications::Instance();
  push.Initialize();

  if (diagnose) {
    const int exit_code = RunPushDiagnostics(push);
    push.Shutdown();
    ::CoUninitialize();
    return exit_code;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"apexo", origin, size)) {
    window.Destroy();
    push.Shutdown();
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // A hidden activation posts WM_QUIT without ever destroying the window. Do it
  // explicitly while the derived window and the COM apartment are still alive,
  // so PushNotifications::Shutdown runs before CoUninitialize and before the
  // Flutter engine is destroyed.
  window.Destroy();

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
