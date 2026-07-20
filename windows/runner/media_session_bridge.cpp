#include "media_session_bridge.h"

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <iostream>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using Session = winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSession;
using SessionManager = winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSessionManager;
using MediaProperties = winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSessionMediaProperties;
using PlaybackStatus = winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSessionPlaybackStatus;

constexpr char kCommandChannel[] = "media_controls/commands";
constexpr char kEventChannel[] = "media_controls/events";
constexpr uint32_t kMaximumArtworkBytes = 4 * 1024 * 1024;
constexpr int64_t kTicksPerMillisecond = 10000;

void Put(EncodableMap& map, const char* key, EncodableValue value) {
  map[EncodableValue(key)] = std::move(value);
}

void Log(const std::string& message) {
  const std::string line = "[media_controls] " + message + "\n";
  ::OutputDebugStringA(line.c_str());
  std::cerr << line;
}

std::string HResultMessage(const winrt::hresult_error& error) {
  return winrt::to_string(error.message());
}

int64_t ToMilliseconds(winrt::Windows::Foundation::TimeSpan value) {
  return std::chrono::duration_cast<std::chrono::milliseconds>(value).count();
}

int64_t ToEpochMilliseconds(winrt::Windows::Foundation::DateTime value) {
  const auto system_time = winrt::clock::to_sys(value);
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             system_time.time_since_epoch())
      .count();
}

std::string PlaybackStatusName(PlaybackStatus status) {
  switch (status) {
    case PlaybackStatus::Closed:
      return "closed";
    case PlaybackStatus::Opened:
      return "opened";
    case PlaybackStatus::Changing:
      return "changing";
    case PlaybackStatus::Stopped:
      return "stopped";
    case PlaybackStatus::Playing:
      return "playing";
    case PlaybackStatus::Paused:
      return "paused";
    default:
      return "unknown";
  }
}

bool SameSession(const Session& first, const Session& second) {
  if (!first || !second) {
    return !first && !second;
  }
  return winrt::get_abi(first) == winrt::get_abi(second);
}

const EncodableValue* FindValue(const EncodableMap& map, const char* key) {
  const auto iterator = map.find(EncodableValue(key));
  return iterator == map.end() ? nullptr : &iterator->second;
}

}  // namespace

class MediaSessionBridge::Impl
    : public std::enable_shared_from_this<MediaSessionBridge::Impl> {
 public:
  Impl(flutter::BinaryMessenger* messenger, HWND window)
      : messenger_(messenger), window_(window) {}

  ~Impl() { Shutdown(); }

  void Start() {
    command_channel_ = std::make_unique<flutter::MethodChannel<>>(
        messenger_, kCommandChannel,
        &flutter::StandardMethodCodec::GetInstance());
    event_channel_ = std::make_unique<flutter::EventChannel<>>(
        messenger_, kEventChannel,
        &flutter::StandardMethodCodec::GetInstance());

    const std::weak_ptr<Impl> weak = shared_from_this();
    command_channel_->SetMethodCallHandler(
        [weak](const flutter::MethodCall<>& call,
               std::unique_ptr<flutter::MethodResult<>> result) {
          if (const auto self = weak.lock()) {
            self->HandleCommand(call, std::move(result));
          } else {
            result->Error("shutdown", "Media controls are shutting down.");
          }
        });

    event_channel_->SetStreamHandler(
        std::make_unique<flutter::StreamHandlerFunctions<>>(
            [weak](const EncodableValue*,
                   std::unique_ptr<flutter::EventSink<>>&& sink)
                -> std::unique_ptr<flutter::StreamHandlerError<>> {
              if (const auto self = weak.lock()) {
                self->event_sink_ = std::move(sink);
                self->RequestRefresh();
              }
              return nullptr;
            },
            [weak](const EncodableValue*)
                -> std::unique_ptr<flutter::StreamHandlerError<>> {
              if (const auto self = weak.lock()) {
                self->event_sink_.reset();
              }
              return nullptr;
            }));

    InitializeAsync();
  }

  bool HandleWindowMessage(UINT message) {
    if (message != MediaSessionBridge::kRefreshMessage) {
      return false;
    }
    refresh_posted_.store(false);
    RefreshAsync();
    return true;
  }

  void Shutdown() {
    if (stopped_.exchange(true)) {
      return;
    }
    RevokeSessionEvents();
    RevokeManagerEvent();
    event_sink_.reset();
    if (event_channel_) {
      event_channel_->SetStreamHandler(nullptr);
    }
    if (command_channel_) {
      command_channel_->SetMethodCallHandler(nullptr);
    }
  }

 private:
  void RevokeManagerEvent() noexcept {
    if (manager_ && manager_token_.value != 0) {
      try {
        manager_.CurrentSessionChanged(manager_token_);
      } catch (const winrt::hresult_error& error) {
        Log("manager event revoke failed hresult=" +
            std::to_string(error.code().value));
      }
    }
    manager_token_ = {};
  }
  winrt::fire_and_forget InitializeAsync() {
    const auto lifetime = shared_from_this();
    if (manager_initializing_ || manager_) {
      co_return;
    }
    manager_initializing_ = true;
    manager_error_code_.clear();
    manager_error_message_.clear();
    const auto started = std::chrono::steady_clock::now();
    try {
      auto manager = co_await SessionManager::RequestAsync();
      if (stopped_) {
        co_return;
      }
      manager_ = manager;
      manager_initializing_ = false;
      const std::weak_ptr<Impl> weak = lifetime;
      manager_token_ = manager_.CurrentSessionChanged(
          [weak](const SessionManager&, const auto&) {
            if (const auto self = weak.lock()) {
              self->RequestRefresh();
            }
          });
      const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now() - started);
      Log("manager initialized duration_ms=" +
          std::to_string(elapsed.count()));
      RequestRefresh();
    } catch (const winrt::hresult_error& error) {
      manager_initializing_ = false;
      Log("manager initialization failed hresult=" +
          std::to_string(error.code().value) + " message=" +
          HResultMessage(error));
      manager_error_code_ = "manager_unavailable";
      manager_error_message_ =
          "Windows did not grant access to system media controls.";
      EmitError(manager_error_code_, manager_error_message_);
    }
  }

  void RequestRefresh() {
    if (stopped_ || !window_) {
      return;
    }
    bool expected = false;
    if (refresh_posted_.compare_exchange_strong(expected, true)) {
      ::PostMessage(window_, MediaSessionBridge::kRefreshMessage, 0, 0);
    }
  }

  winrt::fire_and_forget RefreshAsync() {
    const auto lifetime = shared_from_this();
    if (refresh_in_flight_) {
      refresh_again_ = true;
      co_return;
    }
    refresh_in_flight_ = true;
    const auto started = std::chrono::steady_clock::now();

    try {
      if (!manager_) {
        if (!manager_error_code_.empty()) {
          EmitError(manager_error_code_, manager_error_message_);
        } else {
          EmitUnavailable("initializing");
        }
      } else {
        const auto current = manager_.GetCurrentSession();
        if (!SameSession(current, session_)) {
          BindSession(current);
        }

        if (!session_) {
          EmitUnavailable("no_session");
        } else {
          const uint64_t refresh_revision = session_revision_;
          const auto refresh_session = session_;
          auto media = cached_media_;
          const bool refresh_media = media_dirty_.exchange(false) || !media;
          if (refresh_media) {
            media = co_await refresh_session.TryGetMediaPropertiesAsync();
          }

          if (!stopped_ && refresh_revision == session_revision_ &&
              SameSession(refresh_session, session_) &&
              SameSession(manager_.GetCurrentSession(), refresh_session)) {
            cached_media_ = media;
            const std::string signature =
                winrt::to_string(media.Title()) + "\x1f" +
                winrt::to_string(media.Artist()) + "\x1f" +
                winrt::to_string(media.AlbumTitle());
            if (refresh_media || signature != media_signature_) {
              media_signature_ = signature;
              ++artwork_revision_;
              artwork_loading_ = true;
              artwork_bytes_.clear();
              RefreshArtworkAsync(media.Thumbnail(), refresh_revision,
                                  artwork_revision_);
            }

            if (!stopped_ && refresh_revision == session_revision_) {
              EmitSnapshot(media, refresh_session.GetPlaybackInfo(),
                           refresh_session.GetTimelineProperties());
            }
          }
        }
      }
    } catch (const winrt::hresult_error& error) {
      Log("snapshot refresh failed revision=" +
          std::to_string(session_revision_) + " hresult=" +
          std::to_string(error.code().value) + " message=" +
          HResultMessage(error));
      EmitError("snapshot_failed",
                "The active media session could not be refreshed.");
    }

    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - started);
    Log("snapshot refresh revision=" + std::to_string(session_revision_) +
        " duration_ms=" + std::to_string(elapsed.count()));
    refresh_in_flight_ = false;
    if (refresh_again_) {
      refresh_again_ = false;
      RequestRefresh();
    }
  }

  void BindSession(const Session& session) {
    RevokeSessionEvents();
    session_ = session;
    cached_media_ = nullptr;
    ++session_revision_;
    media_signature_.clear();
    artwork_bytes_.clear();
    artwork_loading_ = false;
    media_dirty_.store(true);
    ++artwork_revision_;

    if (!session_) {
      Log("session cleared revision=" + std::to_string(session_revision_));
      return;
    }

    const std::weak_ptr<Impl> weak = shared_from_this();
    try {
      media_token_ = session_.MediaPropertiesChanged(
          [weak](const Session&, const auto&) {
            if (const auto self = weak.lock()) {
              self->media_dirty_.store(true);
              self->RequestRefresh();
            }
          });
      playback_token_ = session_.PlaybackInfoChanged(
          [weak](const Session&, const auto&) {
            if (const auto self = weak.lock()) {
              self->RequestRefresh();
            }
          });
      timeline_token_ = session_.TimelinePropertiesChanged(
          [weak](const Session&, const auto&) {
            if (const auto self = weak.lock()) {
              self->RequestRefresh();
            }
          });
    } catch (...) {
      RevokeSessionEvents();
      session_ = nullptr;
      throw;
    }
    Log("session bound revision=" + std::to_string(session_revision_) +
        " source=" + winrt::to_string(session_.SourceAppUserModelId()));
  }

  void RevokeSessionEvents() noexcept {
    if (!session_) {
      return;
    }
    try {
      if (media_token_.value != 0) {
        session_.MediaPropertiesChanged(media_token_);
      }
      if (playback_token_.value != 0) {
        session_.PlaybackInfoChanged(playback_token_);
      }
      if (timeline_token_.value != 0) {
        session_.TimelinePropertiesChanged(timeline_token_);
      }
    } catch (const winrt::hresult_error& error) {
      Log("session event revoke failed revision=" +
          std::to_string(session_revision_) + " hresult=" +
          std::to_string(error.code().value));
    }
    media_token_ = {};
    playback_token_ = {};
    timeline_token_ = {};
  }

  winrt::fire_and_forget RefreshArtworkAsync(
      const winrt::Windows::Storage::Streams::IRandomAccessStreamReference&
          thumbnail,
      uint64_t expected_session_revision,
      uint64_t expected_artwork_revision) {
    const auto lifetime = shared_from_this();
    if (!thumbnail) {
      if (!stopped_ && expected_session_revision == session_revision_ &&
          expected_artwork_revision == artwork_revision_) {
        artwork_loading_ = false;
        RequestRefresh();
      }
      co_return;
    }
    try {
      const auto stream = co_await thumbnail.OpenReadAsync();
      if (stopped_ || expected_session_revision != session_revision_ ||
          expected_artwork_revision != artwork_revision_) {
        co_return;
      }
      if (stream.Size() == 0 || stream.Size() > kMaximumArtworkBytes) {
        Log("artwork rejected revision=" +
            std::to_string(expected_session_revision) + " bytes=" +
            std::to_string(stream.Size()));
        if (!stopped_ && expected_session_revision == session_revision_ &&
            expected_artwork_revision == artwork_revision_) {
          artwork_loading_ = false;
          RequestRefresh();
        }
        co_return;
      }
      const uint32_t requested = static_cast<uint32_t>(stream.Size());
      const auto buffer = co_await stream.ReadAsync(
          winrt::Windows::Storage::Streams::Buffer(requested), requested,
          winrt::Windows::Storage::Streams::InputStreamOptions::None);
      if (stopped_ || expected_session_revision != session_revision_ ||
          expected_artwork_revision != artwork_revision_) {
        co_return;
      }
      std::vector<uint8_t> bytes(buffer.Length());
      auto reader =
          winrt::Windows::Storage::Streams::DataReader::FromBuffer(buffer);
      reader.ReadBytes(winrt::array_view<uint8_t>(bytes));
      artwork_bytes_ = std::move(bytes);
    } catch (const winrt::hresult_error& error) {
      Log("artwork read failed revision=" +
          std::to_string(expected_session_revision) + " hresult=" +
          std::to_string(error.code().value));
      artwork_bytes_.clear();
    }
    if (!stopped_ && expected_session_revision == session_revision_ &&
        expected_artwork_revision == artwork_revision_) {
      artwork_loading_ = false;
      RequestRefresh();
    }
  }

  void EmitSnapshot(
      const winrt::Windows::Media::Control::
          GlobalSystemMediaTransportControlsSessionMediaProperties& media,
      const winrt::Windows::Media::Control::
          GlobalSystemMediaTransportControlsSessionPlaybackInfo& playback,
      const winrt::Windows::Media::Control::
          GlobalSystemMediaTransportControlsSessionTimelineProperties&
              timeline) {
    if (!event_sink_ || stopped_) {
      return;
    }
    const auto controls = playback.Controls();
    double playback_rate = 1.0;
    if (const auto rate = playback.PlaybackRate()) {
      playback_rate = rate.Value();
    }

    EncodableMap session;
    Put(session, "sourceAppId",
        EncodableValue(winrt::to_string(session_.SourceAppUserModelId())));
    Put(session, "title", EncodableValue(winrt::to_string(media.Title())));
    Put(session, "artist", EncodableValue(winrt::to_string(media.Artist())));
    Put(session, "albumTitle",
        EncodableValue(winrt::to_string(media.AlbumTitle())));

    EncodableMap playback_map;
    Put(playback_map, "status",
        EncodableValue(PlaybackStatusName(playback.PlaybackStatus())));
    Put(playback_map, "canPlay", EncodableValue(controls.IsPlayEnabled()));
    Put(playback_map, "canPause", EncodableValue(controls.IsPauseEnabled()));
    Put(playback_map, "canToggle",
        EncodableValue(controls.IsPlayPauseToggleEnabled()));
    Put(playback_map, "canPrevious",
        EncodableValue(controls.IsPreviousEnabled()));
    Put(playback_map, "canNext", EncodableValue(controls.IsNextEnabled()));
    Put(playback_map, "canSeek",
        EncodableValue(controls.IsPlaybackPositionEnabled()));
    Put(playback_map, "rate", EncodableValue(playback_rate));

    EncodableMap timeline_map;
    Put(timeline_map, "positionMs",
        EncodableValue(ToMilliseconds(timeline.Position())));
    Put(timeline_map, "startMs",
        EncodableValue(ToMilliseconds(timeline.StartTime())));
    Put(timeline_map, "endMs",
        EncodableValue(ToMilliseconds(timeline.EndTime())));
    Put(timeline_map, "minSeekMs",
        EncodableValue(ToMilliseconds(timeline.MinSeekTime())));
    Put(timeline_map, "maxSeekMs",
        EncodableValue(ToMilliseconds(timeline.MaxSeekTime())));
    Put(timeline_map, "updatedAtEpochMs",
        EncodableValue(ToEpochMilliseconds(timeline.LastUpdatedTime())));

    EncodableMap artwork;
    Put(artwork, "available", EncodableValue(!artwork_bytes_.empty()));
    Put(artwork, "pending", EncodableValue(artwork_loading_));
    Put(artwork, "revision",
        EncodableValue(static_cast<int64_t>(artwork_revision_)));

    EncodableMap snapshot;
    Put(snapshot, "type", EncodableValue("snapshot"));
    Put(snapshot, "revision",
        EncodableValue(static_cast<int64_t>(session_revision_)));
    Put(snapshot, "session", EncodableValue(std::move(session)));
    Put(snapshot, "playback", EncodableValue(std::move(playback_map)));
    Put(snapshot, "timeline", EncodableValue(std::move(timeline_map)));
    Put(snapshot, "artwork", EncodableValue(std::move(artwork)));
    event_sink_->Success(EncodableValue(std::move(snapshot)));
  }

  void EmitUnavailable(const std::string& reason) {
    if (!event_sink_ || stopped_) {
      return;
    }
    EncodableMap event;
    Put(event, "type", EncodableValue("unavailable"));
    Put(event, "reason", EncodableValue(reason));
    event_sink_->Success(EncodableValue(std::move(event)));
  }

  void EmitError(const std::string& code, const std::string& message) {
    if (!event_sink_ || stopped_) {
      return;
    }
    EncodableMap event;
    Put(event, "type", EncodableValue("error"));
    Put(event, "code", EncodableValue(code));
    Put(event, "message", EncodableValue(message));
    event_sink_->Success(EncodableValue(std::move(event)));
  }

  void HandleCommand(const flutter::MethodCall<>& call,
                     std::unique_ptr<flutter::MethodResult<>> result) {
    if (call.method_name() == "getArtwork") {
      HandleArtworkRequest(call, std::move(result));
      return;
    }
    if (call.method_name() == "retry") {
      RevokeSessionEvents();
      session_ = nullptr;
      cached_media_ = nullptr;
      RevokeManagerEvent();
      manager_ = nullptr;
      manager_error_code_.clear();
      manager_error_message_.clear();
      InitializeAsync();
      result->Success(CommandResult(true, session_revision_));
      return;
    }
    ExecuteCommandAsync(call.method_name(), call.arguments(),
                        std::move(result));
  }

  void HandleArtworkRequest(
      const flutter::MethodCall<>& call,
      std::unique_ptr<flutter::MethodResult<>> result) {
    int64_t requested_revision = -1;
    if (call.arguments() &&
        std::holds_alternative<EncodableMap>(*call.arguments())) {
      const auto& arguments = std::get<EncodableMap>(*call.arguments());
      if (const auto* value = FindValue(arguments, "revision")) {
        if (const auto parsed = value->TryGetLongValue()) {
          requested_revision = *parsed;
        }
      }
    }
    if (requested_revision != static_cast<int64_t>(artwork_revision_) ||
        artwork_bytes_.empty()) {
      result->Success(EncodableValue());
      return;
    }
    result->Success(EncodableValue(artwork_bytes_));
  }

  winrt::fire_and_forget ExecuteCommandAsync(
      std::string method,
      const EncodableValue* arguments,
      std::unique_ptr<flutter::MethodResult<>> result) {
    const auto lifetime = shared_from_this();
    const auto command_session = session_;
    const uint64_t command_revision = session_revision_;
    const auto expected_revision = ExpectedRevision(arguments);
    if (!expected_revision || *expected_revision < 0) {
      result->Error("invalid_arguments",
                    "A valid expectedRevision is required.");
      co_return;
    }
    if (!command_session ||
        *expected_revision != static_cast<int64_t>(command_revision) ||
        !manager_ ||
        !SameSession(manager_.GetCurrentSession(), command_session)) {
      result->Success(CommandResult(false, command_revision));
      RequestRefresh();
      co_return;
    }

    try {
      const auto controls = command_session.GetPlaybackInfo().Controls();
      bool accepted = false;
      if (method == "playPause" && controls.IsPlayPauseToggleEnabled()) {
        accepted = co_await command_session.TryTogglePlayPauseAsync();
      } else if (method == "play" && controls.IsPlayEnabled()) {
        accepted = co_await command_session.TryPlayAsync();
      } else if (method == "pause" && controls.IsPauseEnabled()) {
        accepted = co_await command_session.TryPauseAsync();
      } else if (method == "previous" && controls.IsPreviousEnabled()) {
        accepted = co_await command_session.TrySkipPreviousAsync();
      } else if (method == "next" && controls.IsNextEnabled()) {
        accepted = co_await command_session.TrySkipNextAsync();
      } else if (method == "seek" &&
                 controls.IsPlaybackPositionEnabled()) {
        const auto position_ms = SeekPosition(arguments);
        if (!position_ms || *position_ms < 0) {
          result->Error("invalid_arguments",
                        "A non-negative positionMs is required.");
          co_return;
        }
        const auto timeline = command_session.GetTimelineProperties();
        const int64_t minimum = ToMilliseconds(timeline.MinSeekTime());
        const int64_t reported_maximum =
            ToMilliseconds(timeline.MaxSeekTime());
        const int64_t end = ToMilliseconds(timeline.EndTime());
        const int64_t maximum = reported_maximum > minimum
                                    ? reported_maximum
                                    : std::max(minimum, end);
        if (maximum <= minimum ||
            maximum > INT64_MAX / kTicksPerMillisecond) {
          result->Success(CommandResult(false, command_revision));
          co_return;
        }
        const int64_t clamped = std::clamp(*position_ms, minimum, maximum);
        accepted = co_await command_session.TryChangePlaybackPositionAsync(
            clamped * kTicksPerMillisecond);
      } else if (method != "playPause" && method != "play" &&
                 method != "pause" && method != "previous" &&
                 method != "next" && method != "seek") {
        result->NotImplemented();
        co_return;
      }

      if (stopped_) {
        result->Error("shutdown", "Media controls are shutting down.");
        co_return;
      }
      Log("command method=" + method +
          " revision=" + std::to_string(command_revision) +
          " accepted=" + (accepted ? "true" : "false"));
      result->Success(CommandResult(accepted, command_revision));
      RequestRefresh();
    } catch (const winrt::hresult_error& error) {
      Log("command failed method=" + method +
          " revision=" + std::to_string(command_revision) + " hresult=" +
          std::to_string(error.code().value));
      result->Error("command_failed",
                    "Windows could not execute the media command.");
    }
  }

  static EncodableValue CommandResult(bool accepted, uint64_t revision) {
    EncodableMap response;
    Put(response, "accepted", EncodableValue(accepted));
    Put(response, "revision",
        EncodableValue(static_cast<int64_t>(revision)));
    return EncodableValue(std::move(response));
  }

  static std::optional<int64_t> SeekPosition(
      const EncodableValue* arguments) {
    if (!arguments || !std::holds_alternative<EncodableMap>(*arguments)) {
      return std::nullopt;
    }
    const auto& map = std::get<EncodableMap>(*arguments);
    const auto* value = FindValue(map, "positionMs");
    return value ? value->TryGetLongValue() : std::nullopt;
  }

  static std::optional<int64_t> ExpectedRevision(
      const EncodableValue* arguments) {
    if (!arguments || !std::holds_alternative<EncodableMap>(*arguments)) {
      return std::nullopt;
    }
    const auto& map = std::get<EncodableMap>(*arguments);
    const auto* value = FindValue(map, "expectedRevision");
    return value ? value->TryGetLongValue() : std::nullopt;
  }

  flutter::BinaryMessenger* messenger_;
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<>> command_channel_;
  std::unique_ptr<flutter::EventChannel<>> event_channel_;
  std::unique_ptr<flutter::EventSink<>> event_sink_;

  SessionManager manager_{nullptr};
  Session session_{nullptr};
  MediaProperties cached_media_{nullptr};
  winrt::event_token manager_token_{};
  winrt::event_token media_token_{};
  winrt::event_token playback_token_{};
  winrt::event_token timeline_token_{};

  std::atomic_bool stopped_ = false;
  std::atomic_bool refresh_posted_ = false;
  std::atomic_bool media_dirty_ = true;
  bool refresh_in_flight_ = false;
  bool refresh_again_ = false;
  bool manager_initializing_ = false;
  bool artwork_loading_ = false;
  uint64_t session_revision_ = 0;
  uint64_t artwork_revision_ = 0;
  std::string manager_error_code_;
  std::string manager_error_message_;
  std::string media_signature_;
  std::vector<uint8_t> artwork_bytes_;
};

MediaSessionBridge::MediaSessionBridge(flutter::BinaryMessenger* messenger,
                                       HWND window)
    : impl_(std::make_shared<Impl>(messenger, window)) {
  impl_->Start();
}

MediaSessionBridge::~MediaSessionBridge() { Shutdown(); }

bool MediaSessionBridge::HandleWindowMessage(UINT message) {
  return impl_ && impl_->HandleWindowMessage(message);
}

void MediaSessionBridge::Shutdown() {
  if (impl_) {
    impl_->Shutdown();
    impl_.reset();
  }
}
