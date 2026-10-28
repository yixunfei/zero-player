#ifndef RUNNER_RADIO_TRAY_H_
#define RUNNER_RADIO_TRAY_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <string>

// Owns the shell icon; application lifetime and audio stay in Dart services.
class RadioTray {
 public:
  RadioTray(HWND window, flutter::BinaryMessenger* messenger);
  ~RadioTray();
  RadioTray(const RadioTray&) = delete;
  RadioTray& operator=(const RadioTray&) = delete;
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void HandleCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  bool UpdateIcon();
  void RemoveIcon();
  void ShowWindow();
  void ShowMenu();
  void Notify(const char* method);

  HWND window_;
  const UINT taskbar_created_;
  bool registered_ = false;
  bool hidden_ = false;
  bool active_ = false;
  bool playing_ = false;
  bool loading_ = false;
  std::wstring title_ = L"Zero Player";
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_RADIO_TRAY_H_
