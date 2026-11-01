#include "radio_tray.h"

#include <shellapi.h>
#include <windowsx.h>

#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 100;
constexpr UINT kTrayId = 1;
constexpr UINT kShow = 1;
constexpr UINT kToggle = 2;
constexpr UINT kStop = 3;
constexpr UINT kExit = 4;

bool ReadBool(const flutter::EncodableMap& values, const char* key) {
  auto entry = values.find(flutter::EncodableValue(key));
  if (entry == values.end()) return false;
  const auto* value = std::get_if<bool>(&entry->second);
  return value != nullptr && *value;
}

std::wstring ReadTitle(const flutter::EncodableMap& values) {
  auto entry = values.find(flutter::EncodableValue("title"));
  if (entry == values.end()) return L"Zero Player";
  const auto* text = std::get_if<std::string>(&entry->second);
  if (text == nullptr || text->empty()) return L"Zero Player";
  const int length = static_cast<int>(text->size());
  const int count = MultiByteToWideChar(CP_UTF8, 0, text->data(), length, nullptr, 0);
  if (count <= 0) return L"Zero Player";
  std::wstring converted(count, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text->data(), length, converted.data(), count);
  return L"Zero Player - " + converted;
}
}  // namespace

RadioTray::RadioTray(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window), taskbar_created_(RegisterWindowMessageW(L"TaskbarCreated")) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "zero_player/radio_tray", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleCall(call, std::move(result));
  });
}

RadioTray::~RadioTray() {
  channel_->SetMethodCallHandler(nullptr);
  RemoveIcon();
}

void RadioTray::HandleCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "update") {
    const auto* values = call.arguments() == nullptr ? nullptr
        : std::get_if<flutter::EncodableMap>(call.arguments());
    if (values == nullptr) {
      result->Error("invalid_arguments", "Playback state is required");
      return;
    }
    active_ = ReadBool(*values, "active");
    playing_ = ReadBool(*values, "playing");
    loading_ = ReadBool(*values, "loading");
    title_ = ReadTitle(*values);
    if (active_ || hidden_) {
      if (!UpdateIcon()) {
        result->Error("tray_unavailable", "Unable to register the notification icon");
        return;
      }
    } else {
      RemoveIcon();
    }
  } else if (call.method_name() == "hide") {
    if (!UpdateIcon()) {
      result->Error("tray_unavailable", "Window remains visible because the tray is unavailable");
      return;
    }
    hidden_ = true;
    ::ShowWindow(window_, SW_HIDE);
  } else if (call.method_name() == "show") {
    ShowWindow();
  } else if (call.method_name() == "dispose") {
    RemoveIcon();
  } else if (call.method_name() == "status") {
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("registered"), flutter::EncodableValue(registered_)},
        {flutter::EncodableValue("hidden"), flutter::EncodableValue(hidden_)}}));
    return;
  } else {
    result->NotImplemented();
    return;
  }
  result->Success();
}

bool RadioTray::UpdateIcon() {
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = window_;
  icon.uID = kTrayId;
  icon.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
  icon.uCallbackMessage = kTrayMessage;
  icon.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  wcsncpy_s(icon.szTip, title_.c_str(), _TRUNCATE);
  if (!Shell_NotifyIconW(registered_ ? NIM_MODIFY : NIM_ADD, &icon)) return false;
  if (!registered_) {
    icon.uVersion = NOTIFYICON_VERSION_4;
    if (!Shell_NotifyIconW(NIM_SETVERSION, &icon)) {
      Shell_NotifyIconW(NIM_DELETE, &icon);
      return false;
    }
  }
  registered_ = true;
  return true;
}

void RadioTray::RemoveIcon() {
  if (!registered_) return;
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = window_;
  icon.uID = kTrayId;
  Shell_NotifyIconW(NIM_DELETE, &icon);
  registered_ = false;
}

void RadioTray::ShowWindow() {
  hidden_ = false;
  ::ShowWindow(window_, IsIconic(window_) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(window_);
  if (!active_) RemoveIcon();
}

void RadioTray::Notify(const char* method) {
  channel_->InvokeMethod(method, nullptr);
}

void RadioTray::ShowMenu() {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;
  AppendMenuW(menu, MF_STRING, kShow, L"\u663e\u793a\u4e3b\u7a97\u53e3");
  AppendMenuW(menu, MF_STRING | (active_ && !loading_ ? 0 : MF_GRAYED), kToggle,
              playing_ ? L"\u6682\u505c\u97f3\u9891" : L"\u7ee7\u7eed\u97f3\u9891");
  AppendMenuW(menu, MF_STRING | (active_ ? 0 : MF_GRAYED), kStop,
              L"\u505c\u6b62\u97f3\u9891");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kExit, L"\u9000\u51fa Zero Player");
  SetMenuDefaultItem(menu, kShow, FALSE);
  POINT point{};
  GetCursorPos(&point);
  SetForegroundWindow(window_);
  const UINT command = TrackPopupMenuEx(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                                        point.x, point.y, window_, nullptr);
  DestroyMenu(menu);
  PostMessageW(window_, WM_NULL, 0, 0);
  switch (command) {
    case kShow: ShowWindow(); break;
    case kToggle: Notify("toggle"); break;
    case kStop: Notify("stop"); break;
    case kExit: Notify("exit"); break;
  }
}

std::optional<LRESULT> RadioTray::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == taskbar_created_) {
    registered_ = false;
    if ((active_ || hidden_) && !UpdateIcon() && hidden_) ShowWindow();
    return 0;
  }
  if (message != kTrayMessage) return std::nullopt;
  const UINT event = LOWORD(lparam);
  if (event == NIN_SELECT || event == NIN_KEYSELECT || event == WM_LBUTTONDBLCLK) {
    ShowWindow();
  } else if (event == WM_CONTEXTMENU) {
    ShowMenu();
  }
  return 0;
}
