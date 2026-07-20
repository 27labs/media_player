#ifndef RUNNER_MEDIA_SESSION_BRIDGE_H_
#define RUNNER_MEDIA_SESSION_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

class MediaSessionBridge {
 public:
  static constexpr UINT kRefreshMessage = WM_APP + 0x42;

  MediaSessionBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~MediaSessionBridge();

  MediaSessionBridge(const MediaSessionBridge&) = delete;
  MediaSessionBridge& operator=(const MediaSessionBridge&) = delete;

  bool HandleWindowMessage(UINT message);
  void Shutdown();

 private:
  class Impl;
  std::shared_ptr<Impl> impl_;
};

#endif  // RUNNER_MEDIA_SESSION_BRIDGE_H_
