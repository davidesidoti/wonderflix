#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>

#include <cwctype>
#include <string>

#include "flutter_window.h"
#include "utils.h"

// Sviluppo: WONDERFLIX_PROFILE=<nome> avvia un'istanza separata, con dati e
// DeviceId propri (lib/core/device/dev_profile.dart), per provare il watch
// party con due istanze sullo stesso PC. Stesse regole del lato Dart
// (devProfile): spazi esterni tolti, poi da 1 a 16 lettere o cifre ASCII,
// maiuscole ignorate; altrimenti l'istanza normale.
static std::wstring InstanceMutexName() {
  std::wstring name = L"Local\\WonderFlix.SingleInstance";
  wchar_t buffer[64];
  DWORD length = ::GetEnvironmentVariableW(L"WONDERFLIX_PROFILE", buffer, 64);
  if (length == 0 || length >= 64) return name;
  auto is_space = [](wchar_t c) {
    return c == L' ' || c == L'\t' || c == L'\r' || c == L'\n';
  };
  DWORD begin = 0;
  DWORD end = length;
  while (begin < end && is_space(buffer[begin])) begin++;
  while (end > begin && is_space(buffer[end - 1])) end--;
  if (end - begin == 0 || end - begin > 16) return name;
  std::wstring profile;
  for (DWORD i = begin; i < end; i++) {
    wchar_t c = buffer[i];
    bool ascii_alnum = (c >= L'a' && c <= L'z') || (c >= L'A' && c <= L'Z') ||
                       (c >= L'0' && c <= L'9');
    if (!ascii_alnum) return name;
    profile += static_cast<wchar_t>(std::towlower(c));
  }
  return name + L"." + profile;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Una sola istanza: se WonderFlix è già aperto, porta in primo piano quella finestra.
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, InstanceMutexName().c_str());
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"WonderFlix");
    if (existing != nullptr) {
      if (::IsIconic(existing)) ::ShowWindow(existing, SW_RESTORE);
      ::SetForegroundWindow(existing);
    }
    return EXIT_SUCCESS;
  }

  // Identità dell'app per Windows (pannello media, barra delle applicazioni).
  // È la stessa dei collegamenti creati dall'installer (installer/wonderflix.iss):
  // senza collegamento, in sviluppo, il pannello media mostra "Unknown app".
  ::SetCurrentProcessExplicitAppUserModelID(L"it.wonderflix.WonderFlix");

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

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"WonderFlix", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
