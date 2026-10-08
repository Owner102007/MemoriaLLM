#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <map>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

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

// SNO-F-EYE-05: имена мониторов, какими их называет сам монитор
// («DELL P2419H»), по имени устройства GDI («\\.\DISPLAY1»). Где
// система имени не знает, его нет и в ответе.
std::map<std::wstring, std::wstring> FriendlyMonitorNames() {
  std::map<std::wstring, std::wstring> names;
  UINT32 path_count = 0;
  UINT32 mode_count = 0;
  if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &path_count,
                                  &mode_count) != ERROR_SUCCESS) {
    return names;
  }
  std::vector<DISPLAYCONFIG_PATH_INFO> paths(path_count);
  std::vector<DISPLAYCONFIG_MODE_INFO> modes(mode_count);
  if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &path_count, paths.data(),
                         &mode_count, modes.data(),
                         nullptr) != ERROR_SUCCESS) {
    return names;
  }
  for (UINT32 i = 0; i < path_count; ++i) {
    DISPLAYCONFIG_SOURCE_DEVICE_NAME source = {};
    source.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
    source.header.size = sizeof(source);
    source.header.adapterId = paths[i].sourceInfo.adapterId;
    source.header.id = paths[i].sourceInfo.id;
    DISPLAYCONFIG_TARGET_DEVICE_NAME target = {};
    target.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
    target.header.size = sizeof(target);
    target.header.adapterId = paths[i].targetInfo.adapterId;
    target.header.id = paths[i].targetInfo.id;
    if (DisplayConfigGetDeviceInfo(&source.header) == ERROR_SUCCESS &&
        DisplayConfigGetDeviceInfo(&target.header) == ERROR_SUCCESS &&
        target.monitorFriendlyDeviceName[0] != L'\0') {
      names[source.viewGdiDeviceName] = target.monitorFriendlyDeviceName;
    }
  }
  return names;
}

// Монитор системы: имя устройства, прямоугольник, основной ли он.
struct MonitorEntry {
  HMONITOR handle;
  std::wstring device;
  RECT rect;
  bool primary;
};

BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  MONITORINFOEXW info = {};
  info.cbSize = sizeof(MONITORINFOEXW);
  if (GetMonitorInfoW(monitor, &info)) {
    reinterpret_cast<std::vector<MonitorEntry>*>(data)->push_back(
        {monitor, info.szDevice, info.rcMonitor,
         (info.dwFlags & MONITORINFOF_PRIMARY) != 0});
  }
  return TRUE;
}

std::vector<MonitorEntry> AllMonitors() {
  std::vector<MonitorEntry> monitors;
  EnumDisplayMonitors(nullptr, nullptr, CollectMonitor,
                      reinterpret_cast<LPARAM>(&monitors));
  return monitors;
}

// Монитор окна: тот, на котором окно стоит больше всего.
std::optional<MonitorEntry> MonitorOf(HWND window) {
  HMONITOR handle = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  for (const MonitorEntry& entry : AllMonitors()) {
    if (entry.handle == handle) {
      return entry;
    }
  }
  return std::nullopt;
}

// Размер экрана в миллиметрах, как его знает система; часто неверен
// (переходники, телевизоры), поэтому это только подсказка: главный
// источник — банковская карта (SNO-F-EYE-05).
std::pair<int, int> MonitorMillimetres(const std::wstring& device) {
  HDC dc = CreateDCW(L"DISPLAY", device.c_str(), nullptr, nullptr);
  if (dc == nullptr) {
    return {0, 0};
  }
  const int width = GetDeviceCaps(dc, HORZSIZE);
  const int height = GetDeviceCaps(dc, VERTSIZE);
  DeleteDC(dc);
  return {width, height};
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
        const std::string& method = call.method_name();
        if (method == "monitors") {
          // SNO-F-EYE-05: мониторы для «Места записи».
          const std::map<std::wstring, std::wstring> names =
              FriendlyMonitorNames();
          const std::optional<MonitorEntry> current =
              MonitorOf(GetHandle());
          flutter::EncodableList list;
          for (const MonitorEntry& entry : AllMonitors()) {
            const auto named = names.find(entry.device);
            const std::pair<int, int> mm = MonitorMillimetres(entry.device);
            flutter::EncodableMap item;
            item[flutter::EncodableValue("id")] =
                flutter::EncodableValue(Utf8FromUtf16(entry.device.c_str()));
            item[flutter::EncodableValue("name")] = flutter::EncodableValue(
                named == names.end() ? std::string()
                                     : Utf8FromUtf16(named->second.c_str()));
            item[flutter::EncodableValue("left")] =
                flutter::EncodableValue(static_cast<int32_t>(entry.rect.left));
            item[flutter::EncodableValue("top")] =
                flutter::EncodableValue(static_cast<int32_t>(entry.rect.top));
            item[flutter::EncodableValue("w_px")] = flutter::EncodableValue(
                static_cast<int32_t>(entry.rect.right - entry.rect.left));
            item[flutter::EncodableValue("h_px")] = flutter::EncodableValue(
                static_cast<int32_t>(entry.rect.bottom - entry.rect.top));
            item[flutter::EncodableValue("w_mm")] =
                flutter::EncodableValue(static_cast<int32_t>(mm.first));
            item[flutter::EncodableValue("h_mm")] =
                flutter::EncodableValue(static_cast<int32_t>(mm.second));
            item[flutter::EncodableValue("primary")] =
                flutter::EncodableValue(entry.primary);
            item[flutter::EncodableValue("current")] = flutter::EncodableValue(
                current.has_value() && current->handle == entry.handle);
            list.push_back(flutter::EncodableValue(item));
          }
          result->Success(flutter::EncodableValue(list));
          return;
        }
        if (method == "lock") {
          const std::string* monitor =
              std::get_if<std::string>(call.arguments());
          if (monitor == nullptr) {
            result->Error("bad_arguments", "lock expects a monitor id");
            return;
          }
          const std::optional<flutter::EncodableMap> state =
              LockToMonitor(WideFromUtf8(*monitor));
          if (!state.has_value()) {
            result->Success(flutter::EncodableValue());
            return;
          }
          result->Success(flutter::EncodableValue(*state));
          return;
        }
        if (method == "unlock") {
          result->Success(flutter::EncodableValue(Unlock()));
          return;
        }
        if (method != "setFullScreen") {
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
  // SNO-F-EYE-07: под замком айтрекера окно не разворачивается и не
  // возвращается словом чтения — им распоряжается только замок.
  if (locked_) {
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

std::optional<flutter::EncodableMap> FlutterWindow::LockToMonitor(
    const std::wstring& monitor) {
  HWND window = GetHandle();
  if (window == nullptr) {
    return std::nullopt;
  }
  std::optional<MonitorEntry> target;
  for (const MonitorEntry& entry : AllMonitors()) {
    if (entry.device == monitor) {
      target = entry;
    }
  }
  const bool found = target.has_value();
  if (!found) {
    target = MonitorOf(window);
  }
  if (!target.has_value()) {
    return std::nullopt;
  }
  if (!full_screen_) {
    // Окно запоминается как есть, чтобы вернуть его после записи ровно
    // таким же — как у чтения во весь экран.
    WINDOWPLACEMENT placement = {};
    placement.length = sizeof(WINDOWPLACEMENT);
    if (!GetWindowPlacement(window, &placement)) {
      return std::nullopt;
    }
    if (IsZoomed(window) || IsIconic(window)) {
      SendMessage(window, WM_SYSCOMMAND, SC_RESTORE, 0);
    }
    windowed_placement_ = placement;
    windowed_style_ = GetWindowLongPtr(window, GWL_STYLE);
    const LONG_PTR frame = static_cast<LONG_PTR>(WS_OVERLAPPEDWINDOW);
    SetWindowLongPtr(window, GWL_STYLE, windowed_style_ & ~frame);
    full_screen_ = true;
  }
  locked_ = true;
  lock_monitor_ = target->device;
  lock_rect_ = target->rect;
  SetWindowPos(window, HWND_TOP, lock_rect_.left, lock_rect_.top,
               lock_rect_.right - lock_rect_.left,
               lock_rect_.bottom - lock_rect_.top,
               SWP_NOOWNERZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  return LockState(found);
}

flutter::EncodableMap FlutterWindow::LockState(bool found) {
  RECT client = {};
  HWND window = GetHandle();
  if (window != nullptr) {
    GetClientRect(window, &client);
  }
  const UINT dpi = window == nullptr ? 96 : GetDpiForWindow(window);
  const std::map<std::wstring, std::wstring> names = FriendlyMonitorNames();
  const auto named = names.find(lock_monitor_);
  flutter::EncodableMap state;
  state[flutter::EncodableValue("monitor")] =
      flutter::EncodableValue(Utf8FromUtf16(lock_monitor_.c_str()));
  state[flutter::EncodableValue("name")] = flutter::EncodableValue(
      named == names.end() ? std::string()
                           : Utf8FromUtf16(named->second.c_str()));
  state[flutter::EncodableValue("found")] = flutter::EncodableValue(found);
  state[flutter::EncodableValue("w_px")] =
      flutter::EncodableValue(static_cast<int32_t>(client.right - client.left));
  state[flutter::EncodableValue("h_px")] =
      flutter::EncodableValue(static_cast<int32_t>(client.bottom - client.top));
  state[flutter::EncodableValue("dpr")] =
      flutter::EncodableValue(static_cast<double>(dpi == 0 ? 96 : dpi) / 96.0);
  return state;
}

bool FlutterWindow::Unlock() {
  if (!locked_) {
    return true;
  }
  locked_ = false;
  return SetFullScreen(false);
}

void FlutterWindow::Relock() {
  if (!locked_) {
    return;
  }
  HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }
  bool found = false;
  for (const MonitorEntry& entry : AllMonitors()) {
    if (entry.device == lock_monitor_) {
      lock_rect_ = entry.rect;
      found = true;
    }
  }
  if (!found) {
    // Монитор отключили: окно встаёт на тот, что остался под ним.
    const std::optional<MonitorEntry> current = MonitorOf(window);
    if (current.has_value()) {
      lock_monitor_ = current->device;
      lock_rect_ = current->rect;
    }
  }
  SetWindowPos(window, HWND_TOP, lock_rect_.left, lock_rect_.top,
               lock_rect_.right - lock_rect_.left,
               lock_rect_.bottom - lock_rect_.top,
               SWP_NOOWNERZORDER | SWP_NOACTIVATE);
  if (window_channel_) {
    window_channel_->InvokeMethod(
        "lockChanged",
        std::make_unique<flutter::EncodableValue>(LockState(found)));
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // SNO-F-EYE-07: окно под замком айтрекера стоит на весь монитор, что
  // бы с ним ни делали: точки калибровки и кадры раскладки заданы в
  // пикселях окна. Alt+Tab и клавишу Windows замок не перехватывает —
  // уход из приложения виден в журнале записи.
  if (locked_) {
    switch (message) {
      case WM_WINDOWPOSCHANGING: {
        auto* pos = reinterpret_cast<WINDOWPOS*>(lparam);
        if (!IsIconic(hwnd)) {
          if ((pos->flags & SWP_NOMOVE) == 0) {
            pos->x = lock_rect_.left;
            pos->y = lock_rect_.top;
          }
          if ((pos->flags & SWP_NOSIZE) == 0) {
            pos->cx = lock_rect_.right - lock_rect_.left;
            pos->cy = lock_rect_.bottom - lock_rect_.top;
          }
        }
        break;
      }
      case WM_SYSCOMMAND: {
        const WPARAM command = wparam & 0xFFF0;
        if (command == SC_MOVE || command == SC_SIZE ||
            command == SC_MAXIMIZE || command == SC_RESTORE ||
            command == SC_MINIMIZE) {
          return 0;
        }
        break;
      }
      case WM_NCLBUTTONDBLCLK:
        return 0;
      case WM_DISPLAYCHANGE:
        Relock();
        break;
    }
  }

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
