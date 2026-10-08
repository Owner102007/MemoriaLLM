#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <optional>
#include <string>

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

  // SNO-F-EYE-07: окно записи на весь монитор айтрекера. Ставит окно без
  // рамки на весь монитор с именем устройства |monitor| (`\\.\DISPLAY1`)
  // и держит его там, пока замок не снят: перенос, изменение размера,
  // сворачивание и разворот окна не проходят. Нет такого монитора —
  // окно встаёт на тот, где стоит сейчас, и это сказано в ответе.
  std::optional<flutter::EncodableMap> LockToMonitor(
      const std::wstring& monitor);

  // Снимает замок и возвращает окну прежние рамку, место и размер.
  bool Unlock();

  // Монитор замка сменил размер или пропал: окно переставляется и Dart
  // узнаёт об этом сообщением `lockChanged`.
  void Relock();

  // Что сказать Dart о замке: монитор, нашёлся ли он, размер окна в
  // пикселях и масштаб.
  flutter::EncodableMap LockState(bool found);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Канал `memoria/window`: Dart решает, когда разворачивать окно, а
  // разворачивает его этот класс.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  // Канал `memoria/device` (SNO-F-REC-01): запись сессии спрашивает
  // заряд и свободное место и просит не гасить экран.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      device_channel_;

  // Развёрнуто ли окно во весь экран, и каким оно было до этого.
  bool full_screen_ = false;

  // SNO-F-EYE-07: стоит ли окно под замком айтрекера, на каком мониторе
  // и в каком прямоугольнике.
  bool locked_ = false;
  std::wstring lock_monitor_;
  RECT lock_rect_ = {};
  LONG_PTR windowed_style_ = 0;
  WINDOWPLACEMENT windowed_placement_ = {};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
