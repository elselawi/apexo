#ifndef RUNNER_PUSH_NOTIFICATIONS_H_
#define RUNNER_PUSH_NOTIFICATIONS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>

#include <windows.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace apexo {

// The outcome of one WNS channel request, posted from the worker thread.
struct ChannelOutcome {
  uint64_t generation = 0;
  std::optional<std::string> uri;
  bool has_expiry = false;
  int64_t expiry_unix_seconds = 0;
};

// Windows push notifications (WNS) through the Windows App SDK.
//
// The Dart side owns everything the user sees; this service owns the native
// half: package-identity/support detection, registration, the WNS channel, the
// foreground stream and the activation payload. It never parses or logs
// payloads, channel URIs or tokens.
//
// Threading: Flutter channel handlers, timers and window messages run on the
// platform thread. The WNS event callback and the channel worker only copy data
// and post a message; they never touch the messenger.
class PushNotifications {
 public:
  static PushNotifications& Instance();

  // Window messages posted by worker threads. LPARAM owns a heap object that
  // the receiver deletes.
  static constexpr UINT kPayloadMessage = WM_APP + 0x51;
  static constexpr UINT kChannelMessage = WM_APP + 0x52;
  static constexpr UINT kExitMessage = WM_APP + 0x53;

  // Timers used by a hidden push activation only.
  static constexpr UINT_PTR kFallbackTimerId = 0xA31;
  static constexpr UINT_PTR kHardCapTimerId = 0xA32;
  static constexpr UINT_PTR kExitGraceTimerId = 0xA33;

  // Bounds of the hidden-activation shutdown. The fallback is deliberately
  // longer than the Dart session wait so a slow-but-successful restore can
  // still display; the hard cap remains the final backstop.
  static constexpr UINT kFallbackDelayMs = 60 * 1000;
  static constexpr UINT kHardCapDelayMs = 90 * 1000;
  static constexpr UINT kExitGraceMs = 2 * 1000;

  // Reads package identity and the activation arguments, and registers for
  // pushes when the environment supports it. Safe to call once, before the
  // window exists; never throws.
  void Initialize();

  bool HasPackageIdentity() const;
  bool IsSupported() const;
  bool IsChannelConfigured() const;
  bool IsBackgroundActivation() const;
  bool IsRegistered() const;

  // True only while the process was started by a push and no click/launch has
  // promoted it to a normal interactive window.
  bool IsHiddenPushActivation() const;

  // Reveals a hidden activation, cancels every pending exit and completes the
  // background deferral. Platform thread only; idempotent.
  void PromoteToInteractive();

  // Wires the Flutter channels. Safe to call more than once (the first call
  // wins); |messenger| must outlive the service.
  void Attach(flutter::BinaryMessenger* messenger);

  // The window that receives the posted messages and owns the activation
  // timers. Set to nullptr before the window is destroyed.
  void SetWindow(HWND window);

  // Arms the hard cap for a hidden activation; no-op otherwise.
  void ArmActivationTimers();
  void OnTimer(UINT_PTR timer_id);

  // Returns true when the message belonged to this service.
  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

  // Starts (or joins) a channel request. Returns false when no asynchronous
  // completion can arrive, so every caller's pending result is completed now.
  bool StartChannelRequest();

  // Releases channel handlers, joins the owned worker and revokes the WNS event
  // token. Deliberately does not unregister the push manager: 1.7 documents
  // Unregister()/UnregisterAll() as removing registration data, which would
  // stop a later background activation.
  void Shutdown();

 private:
  PushNotifications();
  ~PushNotifications();
  PushNotifications(const PushNotifications&) = delete;
  PushNotifications& operator=(const PushNotifications&) = delete;

  friend class PushEventStreamHandler;

  using EncodableValue = flutter::EncodableValue;
  using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

  void HandleMethodCall(const flutter::MethodCall<EncodableValue>& call,
                        std::unique_ptr<MethodResult> result);
  void HandleLifecycleCall(const flutter::MethodCall<EncodableValue>& call,
                           std::unique_ptr<MethodResult> result);

  void OnStreamListen(std::unique_ptr<flutter::EventSink<EncodableValue>> sink);
  void OnStreamCancel();
  void FlushBufferedPayloads();

  // Validates a payload and hands it to the platform thread.
  void PostPayload(std::string payload);
  void DeliverPayload(const std::string& payload);

  // Caller holds |posting_mutex_|. Allocates and posts one validated payload,
  // deleting it if PostMessage fails.
  void PostValidatedPayloadLocked(HWND window, std::string payload);

  // Removes only this service's queued messages for |window|, deleting the
  // heap objects they own. Called on the platform thread during shutdown.
  void RemovePostedMessagesLocked(HWND window);

  void JoinChannelWorker();

  std::optional<std::string> CurrentChannelUri();
  void CompletePendingResults(const std::optional<std::string>& uri);
  void CompletePendingOnShutdown();
  void RememberChannel(const ChannelOutcome& outcome);

  void RequestExit(const char* reason);
  void CompleteDeferralOnce();
  void KillActivationTimers();

  bool RegisterForPush();
  void ReadActivation();

  // PIMPL keeps the Windows App SDK / C++/WinRT headers out of this header.
  struct Impl;
  std::unique_ptr<Impl> impl_;

  bool initialized_ = false;

  flutter::BinaryMessenger* messenger_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<EncodableValue>> event_channel_;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> lifecycle_channel_;

  std::atomic<HWND> window_{nullptr};

  std::atomic<bool> shutdown_{false};
  std::atomic<bool> exit_requested_{false};
  std::atomic<int> posted_payloads_{0};

  // A push-activated process is hidden until a user click or an ordinary launch
  // promotes it. |exit_generation_| invalidates exit messages already queued
  // when promotion happens.
  bool interactive_activation_ = false;
  uint64_t exit_generation_ = 0;

  // Buffer for pushes that arrive before Dart listens. Bounded on purpose.
  static constexpr size_t kMaxBufferedPayloads = 16;
  std::mutex sink_mutex_;
  std::unique_ptr<flutter::EventSink<EncodableValue>> sink_;
  std::vector<std::string> buffered_payloads_;

  // Callbacks can arrive after registration but before SetWindow publishes the
  // HWND. Keep those validated payloads in a separate bounded buffer so they
  // are not lost; the pre-listen buffer above starts only after the window.
  std::mutex posting_mutex_;
  std::vector<std::string> prewindow_payloads_;

  std::mutex state_mutex_;
  std::optional<std::string> launch_payload_;

  // Pending asynchronous method results, completed exactly once each. Only the
  // platform thread touches this vector.
  struct PendingResult {
    std::string method;
    std::unique_ptr<MethodResult> result;
  };
  std::vector<PendingResult> pending_results_;

  std::mutex channel_mutex_;
  std::optional<std::string> channel_uri_;
  std::optional<std::chrono::system_clock::time_point> channel_expiry_;
  bool channel_request_running_ = false;
  uint64_t channel_generation_ = 0;

  // The acquisition worker is owned so shutdown can cancel and join it without
  // waiting for the SDK's five-minute window.
  std::mutex worker_mutex_;
  std::thread channel_worker_;
  std::atomic<bool> channel_stop_requested_{false};
};

}  // namespace apexo

#endif  // RUNNER_PUSH_NOTIFICATIONS_H_
