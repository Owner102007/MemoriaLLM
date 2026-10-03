#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // F-READ-35: чтение во весь экран. Убирает рамку окна и ставит его на
  // весь монитор либо возвращает прежние рамку, место и размер. Отвечает,
  // оказалось ли окно в запрошенном состоянии.
  bool SetFullScreen(bool on);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Канал `memoria/window`: Dart решает, когда разворачивать окно, а
  // разворачивает его этот класс.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  // Развёрнуто ли окно во весь экран, и каким оно было до этого.
  bool full_screen_ = false;
  LONG_PTR windowed_style_ = 0;
  WINDOWPLACEMENT windowed_placement_ = {};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
