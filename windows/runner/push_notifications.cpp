#include <windows.h>

#include <appmodel.h>

#include <winrt/Windows.ApplicationModel.Background.h>
#include <winrt/Windows.Foundation.h>

#include <winrt/Microsoft.Windows.AppLifecycle.h>
#include <winrt/Microsoft.Windows.PushNotifications.h>

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cstdint>
#include <ctime>
#include <thread>
#include <utility>
#include <variant>

#include "push_config.h"
#include "push_notifications.h"
#include "push_payload.h"

namespace apexo {

namespace {

using winrt::Microsoft::Windows::AppLifecycle::AppInstance;
using winrt::Microsoft::Windows::AppLifecycle::ExtendedActivationKind;
using winrt::Microsoft::Windows::PushNotifications::PushNotificationChannelStatus;
using winrt::Microsoft::Windows::PushNotifications::PushNotificationManager;
using winrt::Microsoft::Windows::PushNotifications::PushNotificationReceivedEventArgs;

// The official sample's bound for CreateChannelAsync. Windows retries
// internally for longer than this; cancelling here gives up on this attempt and
// a later launch/resume/request starts a fresh one.
constexpr std::chrono::minutes kChannelRequestTimeout{5};

bool IsZeroGuid(const winrt::guid& value) {
  return value == winrt::guid{};
}

winrt::guid GuidFromLiteral(const char* value) {
  try {
    return winrt::guid{value};
  } catch (...) {
    return {};
  }
}

// Debugger-only diagnostics. Never logs payloads, channel URIs or tokens.
void DebugTrace(const char* message) {
  ::OutputDebugStringA("Apexo push: ");
  ::OutputDebugStringA(message);
  ::OutputDebugStringA("\n");
}

}  // namespace

// Bridges Flutter's event-stream lifecycle to the service. OnListen/OnCancel
// arrive on the platform thread, like every other channel call.
class PushEventStreamHandler : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  explicit PushEventStreamHandler(PushNotifications* owner) : owner_(owner) {}

 protected:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnListenInternal(
      const flutter::EncodableValue* /*arguments*/,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) override {
    owner_->OnStreamListen(std::move(events));
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancelInternal(
      const flutter::EncodableValue* /*arguments*/) override {
    owner_->OnStreamCancel();
    return nullptr;
  }

 private:
  PushNotifications* owner_;
};

struct PushNotifications::Impl {
  bool has_identity = false;
  bool supported = false;
  bool registered = false;
  bool background_activation = false;
  bool channel_configured = false;

  winrt::guid object_id{};
  winrt::event_token received_token{};

  std::mutex deferral_mutex;
  // PushNotificationReceivedEventArgs::GetDeferral() returns the background
  // task deferral, not Windows.Foundation.Deferral.
  std::optional<winrt::Windows::ApplicationModel::Background::BackgroundTaskDeferral>
      deferral;
};

PushNotifications& PushNotifications::Instance() {
  static PushNotifications instance;
  return instance;
}

PushNotifications::PushNotifications() : impl_(std::make_unique<Impl>()) {}

PushNotifications::~PushNotifications() {
  // The app normally calls Shutdown from FlutterWindow::OnDestroy, but a failed
  // window creation or a diagnostic path must not leave a joinable worker.
  channel_stop_requested_.store(true);
  JoinChannelWorker();
}

bool PushNotifications::HasPackageIdentity() const {
  return impl_->has_identity;
}

bool PushNotifications::IsSupported() const {
  return impl_->supported;
}

bool PushNotifications::IsChannelConfigured() const {
  return impl_->channel_configured;
}

bool PushNotifications::IsBackgroundActivation() const {
  return impl_->background_activation;
}

bool PushNotifications::IsRegistered() const {
  return impl_->registered;
}

bool PushNotifications::IsHiddenPushActivation() const {
  return impl_->background_activation && !interactive_activation_;
}

void PushNotifications::PromoteToInteractive() {
  if (shutdown_.load() || !impl_->background_activation) {
    return;
  }
  if (interactive_activation_) {
    return;
  }
  interactive_activation_ = true;
  // Any exit message that was queued before this point carries the old
  // generation and becomes a no-op. A later exitAfterPush must not close the
  // now-interactive app either.
  ++exit_generation_;
  exit_requested_.store(false);
  KillActivationTimers();
  CompleteDeferralOnce();

  const HWND window = window_.load();
  if (window != nullptr) {
    ::ShowWindow(window, ::IsIconic(window) ? SW_RESTORE : SW_SHOW);
    ::SetForegroundWindow(window);
  }
  DebugTrace("promoted hidden activation to an interactive window");
}

void PushNotifications::Initialize() {
  if (initialized_) {
    return;
  }
  initialized_ = true;

  // Configuration is readable without identity (it is just the header), so the
  // diagnostics can report it even in a build Windows will not register.
  impl_->object_id = GuidFromLiteral(APEXO_WNS_OBJECT_ID);
  impl_->channel_configured = !IsZeroGuid(impl_->object_id);

  UINT32 length = 0;
  impl_->has_identity =
      ::GetCurrentPackageFullName(&length, nullptr) != APPMODEL_ERROR_NO_PACKAGE;
  if (!impl_->has_identity) {
    // Apexo policy: a build without package identity does not offer push. The
    // feature is defined as background/terminated activation, which needs
    // identity and COM activation, so "no identity" means "not supported here"
    // rather than a partial mode. Nothing below touches the Windows App SDK.
    DebugTrace("no package identity; push disabled");
    return;
  }

  try {
    impl_->supported = PushNotificationManager::IsSupported();
  } catch (...) {
    impl_->supported = false;
    ReadActivation();
    return;
  }
  if (!impl_->supported) {
    // Still establish whether Windows started this process for a push, so it
    // does not become an unexpected visible window when the SDK is unavailable.
    ReadActivation();
    return;
  }

  if (!RegisterForPush()) {
    impl_->supported = false;
    // The process can still have been started by a push. Read the activation
    // even when registration failed so it stays hidden and is cleaned up by the
    // hard cap rather than showing an unexpected window.
    ReadActivation();
    return;
  }

  // Only after Register(), as the 1.7 guidance requires.
  ReadActivation();
}

bool PushNotifications::RegisterForPush() {
  try {
    auto manager = PushNotificationManager::Default();
    // Handlers must be attached before Register(), or it throws.
    impl_->received_token = manager.PushReceived(
        [this](auto const&, PushNotificationReceivedEventArgs const& args) {
          std::string payload;
          try {
            const auto bytes = args.Payload();  // winrt::array_view<byte>
            if (bytes.data() != nullptr && bytes.size() > 0) {
              payload.assign(reinterpret_cast<const char*>(bytes.data()),
                             bytes.size());
            }
          } catch (...) {
            return;
          }
          PostPayload(std::move(payload));
        });
    manager.Register();
    impl_->registered = true;
    return true;
  } catch (...) {
    try {
      PushNotificationManager::Default().PushReceived(impl_->received_token);
    } catch (...) {
    }
    impl_->registered = false;
    return false;
  }
}

void PushNotifications::ReadActivation() {
  try {
    const auto args = AppInstance::GetCurrent().GetActivatedEventArgs();
    if (args.Kind() != ExtendedActivationKind::Push) {
      return;
    }

    // From this point on the process is a hidden push activation: even a
    // malformed or unreadable payload must not turn it into an ordinary visible
    // launch. Keep the hidden cleanup path armed and complete the deferral once.
    impl_->background_activation = true;

    const auto push_args = args.Data().as<PushNotificationReceivedEventArgs>();
    {
      std::lock_guard<std::mutex> lock(impl_->deferral_mutex);
      impl_->deferral = push_args.GetDeferral();
    }

    const auto bytes = push_args.Payload();
    if (!apexo_push::IsAcceptedPayload(bytes.data(), bytes.size())) {
      DebugTrace("dropped an invalid launch payload");
      CompleteDeferralOnce();
      return;
    }

    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      launch_payload_ =
          apexo_push::PayloadToUtf8(bytes.data(), bytes.size());
    }
    DebugTrace("activated by a push");
  } catch (...) {
    // The kind was not established, or the activation data could not be read.
    // If it was a push, background_activation is already true and the hidden
    // process will still be cleaned up by the hard cap.
    CompleteDeferralOnce();
  }
}

void PushNotifications::Attach(flutter::BinaryMessenger* messenger) {
  if (messenger == nullptr || method_channel_ != nullptr) {
    return;
  }
  messenger_ = messenger;

  method_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "apexo/windows_push", &flutter::StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult> result) {
        HandleMethodCall(call, std::move(result));
      });

  event_channel_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      messenger, "apexo/windows_push/events",
      &flutter::StandardMethodCodec::GetInstance());
  event_channel_->SetStreamHandler(
      std::make_unique<PushEventStreamHandler>(this));

  lifecycle_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "apexo/windows_push/lifecycle",
      &flutter::StandardMethodCodec::GetInstance());
  lifecycle_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult> result) {
        HandleLifecycleCall(call, std::move(result));
      });
}

void PushNotifications::SetWindow(HWND window) {
  std::lock_guard<std::mutex> lock(posting_mutex_);
  if (shutdown_.load()) {
    window_.store(nullptr);
    prewindow_payloads_.clear();
    return;
  }
  window_.store(window);
  if (window == nullptr) {
    return;
  }
  // Drain in arrival order while holding the same mutex PostPayload takes.
  // A callback racing with HWND publication therefore cannot overtake an older
  // buffered payload.
  for (auto& payload : prewindow_payloads_) {
    PostValidatedPayloadLocked(window, std::move(payload));
  }
  prewindow_payloads_.clear();
}

void PushNotifications::PostValidatedPayloadLocked(HWND window,
                                                   std::string payload) {
  // Caller holds posting_mutex_.
  if (window == nullptr || shutdown_.load()) {
    return;
  }
  const int in_flight = posted_payloads_.fetch_add(1);
  if (in_flight >= static_cast<int>(kMaxBufferedPayloads)) {
    posted_payloads_.fetch_sub(1);
    return;
  }

  auto* owned = new std::string(std::move(payload));
  if (!::PostMessage(window, kPayloadMessage, 0,
                     reinterpret_cast<LPARAM>(owned))) {
    posted_payloads_.fetch_sub(1);
    delete owned;
  }
}

void PushNotifications::ArmActivationTimers() {
  const HWND window = window_.load();
  if (window == nullptr || !IsHiddenPushActivation()) {
    return;
  }
  ::SetTimer(window, kHardCapTimerId, kHardCapDelayMs, nullptr);
}

void PushNotifications::OnTimer(UINT_PTR timer_id) {
  if (shutdown_.load()) {
    return;
  }
  const HWND window = window_.load();
  if (window != nullptr) {
    ::KillTimer(window, timer_id);
  }
  if (!IsHiddenPushActivation()) {
    return;
  }
  switch (timer_id) {
    case kExitGraceTimerId:
      RequestExit("dart-handled");
      break;
    case kFallbackTimerId:
      RequestExit("payload-timeout");
      break;
    case kHardCapTimerId:
      RequestExit("activation-hard-cap");
      break;
    default:
      break;
  }
}

bool PushNotifications::HandleWindowMessage(UINT message, WPARAM wparam,
                                            LPARAM lparam) {
  switch (message) {
    case kPayloadMessage: {
      posted_payloads_.fetch_sub(1);
      std::unique_ptr<std::string> payload(
          reinterpret_cast<std::string*>(lparam));
      if (payload) {
        DeliverPayload(*payload);
      }
      return true;
    }
    case kChannelMessage: {
      std::unique_ptr<ChannelOutcome> outcome(
          reinterpret_cast<ChannelOutcome*>(lparam));
      if (!outcome) {
        {
          std::lock_guard<std::mutex> lock(channel_mutex_);
          channel_request_running_ = false;
        }
        JoinChannelWorker();
        CompletePendingResults(std::nullopt);
        return true;
      }
      std::optional<std::string> result;
      bool complete = false;
      uint64_t generation = 0;
      {
        std::lock_guard<std::mutex> lock(channel_mutex_);
        generation = channel_generation_;
        if (outcome->generation == channel_generation_) {
          channel_request_running_ = false;
          if (!shutdown_.load()) {
            if (outcome->uri && !outcome->uri->empty()) {
              RememberChannel(*outcome);
              result = outcome->uri;
            }
            complete = true;
          }
        }
      }
      // The worker posts this message immediately before returning; joining it
      // here keeps a joinable thread from being overwritten by the next
      // request. Never hold channel_mutex_ while joining.
      JoinChannelWorker();
      if (complete && outcome->generation == generation) {
        CompletePendingResults(result);
      }
      return true;
    }
    case kExitMessage:
      if (apexo_push::ShouldAcceptExit(
              IsHiddenPushActivation(), exit_requested_.load(),
              static_cast<uint64_t>(wparam), exit_generation_)) {
        ::PostQuitMessage(0);
      }
      return true;
    case WM_TIMER:
      if (wparam == kFallbackTimerId || wparam == kHardCapTimerId ||
          wparam == kExitGraceTimerId) {
        OnTimer(static_cast<UINT_PTR>(wparam));
        return true;
      }
      return false;
    default:
      return false;
  }
}

void PushNotifications::RememberChannel(const ChannelOutcome& outcome) {
  // Caller holds channel_mutex_.
  if (outcome.uri && !outcome.uri->empty()) {
    channel_uri_ = outcome.uri;
  }
  if (outcome.has_expiry) {
    channel_expiry_ = std::chrono::system_clock::from_time_t(
        static_cast<std::time_t>(outcome.expiry_unix_seconds));
  }
}

std::optional<std::string> PushNotifications::CurrentChannelUri() {
  std::lock_guard<std::mutex> lock(channel_mutex_);
  if (!channel_uri_) {
    return std::nullopt;
  }
  if (channel_expiry_ && std::chrono::system_clock::now() >= *channel_expiry_) {
    channel_uri_.reset();
    channel_expiry_.reset();
    return std::nullopt;
  }
  return channel_uri_;
}

bool PushNotifications::StartChannelRequest() {
  if (!impl_->supported || !impl_->channel_configured || shutdown_.load()) {
    return false;
  }
  const HWND window = window_.load();
  if (window == nullptr) {
    return false;
  }

  {
    std::lock_guard<std::mutex> lock(channel_mutex_);
    if (channel_request_running_) {
      return true;  // coalesced: the in-flight request completes every caller
    }
  }

  // The previous worker posts its outcome immediately before returning; join it
  // here so a joinable std::thread is never overwritten.
  JoinChannelWorker();

  uint64_t generation = 0;
  {
    std::lock_guard<std::mutex> lock(channel_mutex_);
    if (channel_request_running_) {
      return true;
    }
    channel_request_running_ = true;
    generation = ++channel_generation_;
  }

  channel_stop_requested_.store(false);
  const winrt::guid object_id = impl_->object_id;
  try {
    std::thread worker([this, generation, window, object_id] {
      auto outcome = std::make_unique<ChannelOutcome>();
      outcome->generation = generation;
      bool apartment_initialized = false;
      bool stopped = false;
      try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        apartment_initialized = true;

        auto operation = PushNotificationManager::Default().CreateChannelAsync(
            object_id);
        const auto deadline =
            std::chrono::steady_clock::now() + kChannelRequestTimeout;
        auto status = operation.Status();
        while (status == winrt::Windows::Foundation::AsyncStatus::Started &&
               !channel_stop_requested_.load() &&
               std::chrono::steady_clock::now() < deadline) {
          status = operation.wait_for(std::chrono::milliseconds(100));
        }
        stopped = channel_stop_requested_.load() || shutdown_.load();
        if (stopped ||
            status == winrt::Windows::Foundation::AsyncStatus::Started) {
          // A timeout is still a completed request with a null result, so the
          // pending method calls can be answered. Shutdown is different: there
          // is no Dart caller left to answer.
          try {
            operation.Cancel();
          } catch (...) {
          }
        } else if (status ==
                   winrt::Windows::Foundation::AsyncStatus::Completed) {
          const auto result = operation.GetResults();
          if (result.Status() ==
              PushNotificationChannelStatus::CompletedSuccess) {
            const auto channel = result.Channel();
            outcome->uri = winrt::to_string(channel.Uri().ToString());
            outcome->has_expiry = true;
            outcome->expiry_unix_seconds = static_cast<int64_t>(
                winrt::clock::to_time_t(channel.ExpirationTime()));
          }
        }
      } catch (...) {
        // Unsupported, unregistered (PFN not mapped), network or activation
        // failures all end as "no channel"; the next request retries.
      }
      if (apartment_initialized) {
        try {
          winrt::uninit_apartment();
        } catch (...) {
        }
      }

      if (stopped || shutdown_.load()) {
        return;
      }
      // Post even a null outcome: it completes getChannelUri with null and
      // clears the request-running state.
      auto* raw = outcome.release();
      if (!::PostMessage(window, kChannelMessage,
                         static_cast<WPARAM>(generation),
                         reinterpret_cast<LPARAM>(raw))) {
        delete raw;
      }
    });
    {
      std::lock_guard<std::mutex> lock(worker_mutex_);
      channel_worker_ = std::move(worker);
    }
    return true;
  } catch (...) {
    {
      std::lock_guard<std::mutex> lock(channel_mutex_);
      channel_request_running_ = false;
      ++channel_generation_;
    }
    return false;
  }
}

void PushNotifications::JoinChannelWorker() {
  std::thread worker;
  {
    std::lock_guard<std::mutex> lock(worker_mutex_);
    if (!channel_worker_.joinable()) {
      return;
    }
    worker = std::move(channel_worker_);
  }
  if (worker.joinable()) {
    worker.join();
  }
}

void PushNotifications::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult> result) {
  const std::string& method = call.method_name();

  if (method == "isSupported") {
    result->Success(EncodableValue(impl_->supported));
    return;
  }

  if (method == "getChannelUri") {
    bool refresh = false;
    if (const auto* arguments = call.arguments()) {
      if (!arguments->IsNull()) {
        const auto* map = std::get_if<flutter::EncodableMap>(
            static_cast<const EncodableValue::super*>(arguments));
        if (map == nullptr) {
          result->Error("invalid_arguments", "Expected an argument map.");
          return;
        }
        const auto it = map->find(EncodableValue("refresh"));
        if (it != map->end()) {
          const auto* value = std::get_if<bool>(
              static_cast<const EncodableValue::super*>(&it->second));
          if (value == nullptr) {
            result->Error("invalid_arguments", "refresh must be a bool.");
            return;
          }
          refresh = *value;
        }
      }
    }

    if (!refresh) {
      const auto uri = CurrentChannelUri();
      if (uri) {
        result->Success(EncodableValue(*uri));
        return;
      }
    }

    pending_results_.push_back(PendingResult{method, std::move(result)});
    if (!StartChannelRequest()) {
      // No asynchronous completion can arrive (unsupported, unconfigured,
      // shutdown, no window, thread failure): complete every caller now with a
      // nullable result instead of leaving them pending forever.
      CompletePendingResults(std::nullopt);
    }
    return;
  }

  if (method == "getLaunchPayload") {
    if (IsHiddenPushActivation()) {
      const HWND window = window_.load();
      if (window != nullptr) {
        ::SetTimer(window, kFallbackTimerId, kFallbackDelayMs, nullptr);
      }
    }
    std::string payload;
    {
      std::lock_guard<std::mutex> lock(state_mutex_);
      if (!launch_payload_) {
        result->Success(EncodableValue());
        return;
      }
      payload = std::move(*launch_payload_);
      launch_payload_.reset();  // at most once
    }
    result->Success(EncodableValue(payload));
    return;
  }

  result->NotImplemented();
}

void PushNotifications::HandleLifecycleCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult> result) {
  if (call.method_name() == "promoteToInteractive") {
    PromoteToInteractive();
    result->Success(EncodableValue(true));
    return;
  }
  if (call.method_name() == "exitAfterPush") {
    if (shutdown_.load() || !IsHiddenPushActivation()) {
      result->Success(EncodableValue(false));
      return;
    }
    const HWND window = window_.load();
    if (window != nullptr) {
      ::SetTimer(window, kExitGraceTimerId, kExitGraceMs, nullptr);
    }
    result->Success(EncodableValue(true));
    return;
  }
  result->NotImplemented();
}

void PushNotifications::OnStreamListen(
    std::unique_ptr<flutter::EventSink<EncodableValue>> sink) {
  if (shutdown_.load()) {
    return;
  }
  {
    std::lock_guard<std::mutex> lock(sink_mutex_);
    sink_ = std::move(sink);
  }
  FlushBufferedPayloads();
}

void PushNotifications::OnStreamCancel() {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  sink_.reset();
  buffered_payloads_.clear();
}

void PushNotifications::FlushBufferedPayloads() {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  if (!sink_) {
    return;
  }
  for (const auto& payload : buffered_payloads_) {
    sink_->Success(EncodableValue(payload));
  }
  buffered_payloads_.clear();
}

void PushNotifications::PostPayload(std::string payload) {
  if (shutdown_.load()) {
    return;
  }

  // A Flutter String must be valid UTF-8, so malformed bytes are dropped here
  // rather than handed to the engine. The payload itself is never logged.
  const auto* bytes = reinterpret_cast<const uint8_t*>(payload.data());
  if (!apexo_push::IsAcceptedPayload(bytes, payload.size())) {
    DebugTrace("dropped a payload that is not valid UTF-8 or exceeds the limit");
    return;
  }

  std::lock_guard<std::mutex> lock(posting_mutex_);
  if (shutdown_.load()) {
    return;
  }
  const HWND window = window_.load();
  if (window == nullptr) {
    if (prewindow_payloads_.size() >= kMaxBufferedPayloads) {
      prewindow_payloads_.erase(prewindow_payloads_.begin());
    }
    prewindow_payloads_.push_back(std::move(payload));
    return;
  }
  PostValidatedPayloadLocked(window, std::move(payload));
}

void PushNotifications::DeliverPayload(const std::string& payload) {
  if (shutdown_.load()) {
    return;
  }
  std::lock_guard<std::mutex> lock(sink_mutex_);
  if (!sink_) {
    if (buffered_payloads_.size() >= kMaxBufferedPayloads) {
      buffered_payloads_.erase(buffered_payloads_.begin());
    }
    buffered_payloads_.push_back(payload);
    return;
  }
  sink_->Success(EncodableValue(payload));
}

void PushNotifications::CompletePendingResults(
    const std::optional<std::string>& uri) {
  std::vector<PendingResult> pending;
  pending.swap(pending_results_);
  for (auto& entry : pending) {
    if (entry.method == "getChannelUri") {
      if (uri) {
        entry.result->Success(EncodableValue(*uri));
      } else {
        entry.result->Success(EncodableValue());
      }
    } else if (entry.method == "isSupported") {
      // isSupported is answered synchronously; this keeps the contract if that
      // ever changes. Never a null bool.
      entry.result->Success(EncodableValue(false));
    } else {
      entry.result->Success(EncodableValue());
    }
  }
}

void PushNotifications::CompletePendingOnShutdown() {
  std::vector<PendingResult> pending;
  pending.swap(pending_results_);
  for (auto& entry : pending) {
    if (entry.method == "isSupported") {
      entry.result->Success(EncodableValue(false));
    } else {
      // getChannelUri / getLaunchPayload are nullable strings.
      entry.result->Success(EncodableValue());
    }
  }
}

void PushNotifications::CompleteDeferralOnce() {
  winrt::Windows::ApplicationModel::Background::BackgroundTaskDeferral deferral{
      nullptr};
  {
    std::lock_guard<std::mutex> lock(impl_->deferral_mutex);
    if (!impl_->deferral) {
      return;
    }
    deferral = *impl_->deferral;
    impl_->deferral.reset();
  }
  try {
    deferral.Complete();
  } catch (...) {
  }
}

void PushNotifications::KillActivationTimers() {
  const HWND window = window_.load();
  if (window == nullptr) {
    return;
  }
  ::KillTimer(window, kFallbackTimerId);
  ::KillTimer(window, kHardCapTimerId);
  ::KillTimer(window, kExitGraceTimerId);
}

void PushNotifications::RequestExit(const char* reason) {
  // Ordinary launches, foreground pushes and promoted activations never take
  // this path.
  if (shutdown_.load() || !IsHiddenPushActivation()) {
    return;
  }
  if (exit_requested_.exchange(true)) {
    return;
  }
  DebugTrace(reason);
  KillActivationTimers();
  CompleteDeferralOnce();

  const HWND window = window_.load();
  if (window != nullptr) {
    ::PostMessage(window, kExitMessage, static_cast<WPARAM>(exit_generation_), 0);
  }
}

void PushNotifications::RemovePostedMessagesLocked(HWND window) {
  // Caller holds posting_mutex_ and is on the platform thread. Do not dispatch
  // these messages during teardown; delete only the heap objects they own.
  if (window == nullptr) {
    return;
  }
  ::MSG msg;
  while (::PeekMessage(&msg, window, kPayloadMessage, kPayloadMessage,
                       PM_REMOVE)) {
    delete reinterpret_cast<std::string*>(msg.lParam);
  }
  while (::PeekMessage(&msg, window, kChannelMessage, kChannelMessage,
                       PM_REMOVE)) {
    delete reinterpret_cast<ChannelOutcome*>(msg.lParam);
  }
  while (::PeekMessage(&msg, window, kExitMessage, kExitMessage, PM_REMOVE)) {
  }
  posted_payloads_.store(0);
}

void PushNotifications::Shutdown() {
  if (shutdown_.exchange(true)) {
    return;
  }

  channel_stop_requested_.store(true);
  KillActivationTimers();
  // An activation that never reached Dart must not leave the deferral open.
  CompleteDeferralOnce();

  // The worker is owned and cancellation-aware: signal it, then join outside
  // every lock the worker or callbacks use. It abandons GetResults after
  // cancellation.
  JoinChannelWorker();

  {
    std::lock_guard<std::mutex> lock(posting_mutex_);
    const HWND window = window_.load();
    RemovePostedMessagesLocked(window);
    prewindow_payloads_.clear();
  }
  {
    std::lock_guard<std::mutex> lock(sink_mutex_);
    sink_.reset();
    buffered_payloads_.clear();
  }
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    launch_payload_.reset();
  }
  CompletePendingOnShutdown();

  if (messenger_ != nullptr) {
    messenger_->SetMessageHandler("apexo/windows_push", nullptr);
    messenger_->SetMessageHandler("apexo/windows_push/events", nullptr);
    messenger_->SetMessageHandler("apexo/windows_push/lifecycle", nullptr);
  }
  method_channel_.reset();
  event_channel_.reset();
  lifecycle_channel_.reset();
  messenger_ = nullptr;

  if (impl_->registered) {
    try {
      PushNotificationManager::Default().PushReceived(impl_->received_token);
    } catch (...) {
    }
    impl_->registered = false;
  }

  // No Unregister()/UnregisterAll() on purpose: 1.7 documents them as removing
  // the registration, which would stop the next background activation after
  // the app closes. Revoking the event token is the only cleanup needed here.
}

}  // namespace apexo
