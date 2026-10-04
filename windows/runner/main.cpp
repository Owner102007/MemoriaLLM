#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// Имя окна (SNO-F-CFG-01). У сборок ветвей СНО2026 оно своё — то же, что
// под иконкой на телефоне и в `appNameFor` (`lib/sno/flags.dart`); какая
// ветвь собирается, говорит `CMakeLists.txt` раннера. Буквы вне ASCII
// записаны кодами: файл без BOM, и компилятор прочёл бы кириллицу в
// кодовой странице машины сборки.
#if defined(SNO_BRANCH_II)
#define MEMORIA_WINDOW_TITLE L"Memoria \u00B7 \u0421\u041D\u041E2026 \u00B7 II"
#elif defined(SNO_BRANCH_I)
#define MEMORIA_WINDOW_TITLE L"Memoria \u00B7 \u0421\u041D\u041E2026 \u00B7 I"
#else
#define MEMORIA_WINDOW_TITLE L"Memoria LLM HB"
#endif

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

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(MEMORIA_WINDOW_TITLE, origin, size)) {
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
