#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Путь из UTF-8, каким его присылает Dart, в UTF-16 для Win32. Пустая
// строка — путь не разобрался.
std::wstring WideFromUtf8(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  const int size = static_cast<int>(text.size());
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         text.data(), size, nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), size,
                      wide.data(), length);
  return wide;
}

// SNO-F-REC-01: три вопроса записи сессии к устройству. Плагина ради
// них нет по той же причине, что и для окна во весь экран.
void HandleDeviceCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "battery") {
    SYSTEM_POWER_STATUS power = {};
    // 128 во флагах — батареи нет вовсе; процент больше ста (255) —
    // система его не знает.
    if (!GetSystemPowerStatus(&power) || (power.BatteryFlag & 128) != 0 ||
        power.BatteryLifePercent > 100) {
      result->Success(flutter::EncodableValue());
      return;
    }
    result->Success(flutter::EncodableValue(
        static_cast<int32_t>(power.BatteryLifePercent)));
    return;
  }
  if (method == "freeBytes") {
    const std::string* path = std::get_if<std::string>(call.arguments());
    const std::wstring wide =
        path == nullptr ? std::wstring() : WideFromUtf8(*path);
    ULARGE_INTEGER available = {};
    if (wide.empty() ||
        !GetDiskFreeSpaceExW(wide.c_str(), &available, nullptr, nullptr)) {
      result->Success(flutter::EncodableValue());
      return;
    }
    result->Success(flutter::EncodableValue(
        static_cast<int64_t>(available.QuadPart)));
    return;
  }
  if (method == "keepScreenOn") {
    const bool* on = std::get_if<bool>(call.arguments());
    if (on == nullptr) {
      result->Error("bad_arguments", "keepScreenOn expects a bool");
      return;
    }
    // Просьба к системе не гасить экран и не засыпать; снимается той же
    // функцией, а с концом процесса — сама.
    SetThreadExecutionState(*on ? (ES_CONTINUOUS | ES_DISPLAY_REQUIRED |
                                   ES_SYSTEM_REQUIRED)
                                : ES_CONTINUOUS);
    result->Success(flutter::EncodableValue());
    return;
  }
  result->NotImplemented();
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // F-READ-35: окно во весь экран по слову Dart. Плагина ради этого нет:
  // вся работа — снять рамку и занять монитор.
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "memoria/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "setFullScreen") {
          result->NotImplemented();
          return;
        }
        const bool* on = std::get_if<bool>(call.arguments());
        if (on == nullptr) {
          result->Error("bad_arguments", "setFullScreen expects a bool");
          return;
        }
        result->Success(flutter::EncodableValue(SetFullScreen(*on)));
      });

  device_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "memoria/device",
          &flutter::StandardMethodCodec::GetInstance());
  device_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) { HandleDeviceCall(call, std::move(result)); });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Обработчик канала держит указатель на это окно: снимаем его раньше,
  // чем окно начнёт разбираться.
  if (window_channel_) {
    window_channel_->SetMethodCallHandler(nullptr);
    window_channel_ = nullptr;
  }
  if (device_channel_) {
    device_channel_->SetMethodCallHandler(nullptr);
    device_channel_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::SetFullScreen(bool on) {
  HWND window = GetHandle();
  if (window == nullptr) {
    return false;
  }
  if (on == full_screen_) {
    return true;
  }
  if (on) {
    // Запоминаем окно как есть — место, размер и развёрнутость, — чтобы
    // вернуть его ровно таким же. Монитор берём тот, на котором окно
    // стоит сейчас.
    WINDOWPLACEMENT placement = {};
    placement.length = sizeof(WINDOWPLACEMENT);
    MONITORINFO monitor = {};
    monitor.cbSize = sizeof(MONITORINFO);
    if (!GetWindowPlacement(window, &placement) ||
        !GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                        &monitor)) {
      return false;
    }
    // Развёрнутое окно сначала возвращаем к обычному: над развёрнутым
    // Windows панель задач не прячет, а его рамка после возврата легла бы
    // не туда. Развёрнутость записана в `placement` и вернётся с ним.
    if (IsZoomed(window)) {
      SendMessage(window, WM_SYSCOMMAND, SC_RESTORE, 0);
    }
    windowed_placement_ = placement;
    windowed_style_ = GetWindowLongPtr(window, GWL_STYLE);
    // Весь монитор, а не рабочая область: панель задач тоже уходит.
    const LONG_PTR frame = static_cast<LONG_PTR>(WS_OVERLAPPEDWINDOW);
    SetWindowLongPtr(window, GWL_STYLE, windowed_style_ & ~frame);
    SetWindowPos(window, HWND_TOP, monitor.rcMonitor.left,
                 monitor.rcMonitor.top,
                 monitor.rcMonitor.right - monitor.rcMonitor.left,
                 monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                 SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    full_screen_ = true;
    return true;
  }
  SetWindowLongPtr(window, GWL_STYLE, windowed_style_);
  SetWindowPlacement(window, &windowed_placement_);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                   SWP_FRAMECHANGED);
  full_screen_ = false;
  return true;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
