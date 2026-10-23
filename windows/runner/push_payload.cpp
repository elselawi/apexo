#include "push_payload.h"

#include <climits>
#include <string>

#include <windows.h>

namespace apexo_push {

std::string PayloadToUtf8(const uint8_t* data, size_t size) {
  if (data == nullptr || size == 0) {
    return std::string();
  }
  return std::string(reinterpret_cast<const char*>(data), size);
}

bool IsValidUtf8(const uint8_t* data, size_t size) {
  if (data == nullptr || size == 0) {
    return true;
  }
  if (size > static_cast<size_t>(INT_MAX)) {
    return false;
  }

  // MB_ERR_INVALID_CHARS rejects overlong encodings, surrogate halves and
  // truncated sequences — exactly what a Dart String must never receive.
  const int length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS,
      reinterpret_cast<const char*>(data), static_cast<int>(size), nullptr, 0);
  if (length == 0) {
    return false;
  }

  // A second pass confirms the bytes round-trip to the same count, catching
  // inputs that decode but do not re-encode identically.
  std::wstring wide(static_cast<size_t>(length), L'\0');
  if (::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                            reinterpret_cast<const char*>(data),
                            static_cast<int>(size), wide.data(), length) == 0) {
    return false;
  }

  const int round_trip = ::WideCharToMultiByte(
      CP_UTF8, 0, wide.data(), length, nullptr, 0, nullptr, nullptr);
  if (round_trip != static_cast<int>(size)) {
    return false;
  }

  std::string encoded(static_cast<size_t>(round_trip), '\0');
  if (::WideCharToMultiByte(CP_UTF8, 0, wide.data(), length, encoded.data(),
                            round_trip, nullptr, nullptr) == 0) {
    return false;
  }

  return encoded.compare(0, encoded.size(),
                         reinterpret_cast<const char*>(data), size) == 0;
}

bool IsWithinRawPayloadLimit(size_t size, size_t limit) {
  if (limit == 0) {
    return true;
  }
  return size <= limit;
}

bool IsAcceptedPayload(const uint8_t* data, size_t size) {
  if (data == nullptr && size != 0) {
    return false;
  }
  return IsWithinRawPayloadLimit(size, kMaxAcceptedRawPayloadBytes) &&
         IsValidUtf8(data, size);
}

bool ShouldAcceptExit(bool hidden, bool exit_requested,
                      uint64_t message_generation,
                      uint64_t current_generation) {
  return hidden && exit_requested && message_generation == current_generation;
}

}  // namespace apexo_push
