#ifndef RUNNER_PUSH_PAYLOAD_H_
#define RUNNER_PUSH_PAYLOAD_H_

#include <cstddef>
#include <cstdint>
#include <string>

namespace apexo_push {

// The documented maximum size of a WNS raw-notification body, in bytes.
//
// 0 means "not verified yet": no size limit is enforced. The value must be
// confirmed against the current WNS documentation before it is enabled; the
// tests exercise the predicate with an explicit limit so the behaviour is
// covered either way. See the B3 notes in
// .github/instructions/notifications.instructions.md.
constexpr size_t kMaxAcceptedRawPayloadBytes = 0;

// Copies payload bytes verbatim into a std::string.
//
// This is deliberately not a parser: the payload is the relay's JSON envelope
// ({"payload":"<PushData JSON>"}) and JSON is Dart's business. A null pointer
// yields an empty string.
std::string PayloadToUtf8(const uint8_t* data, size_t size);

// Whether the bytes are well-formed UTF-8.
//
// The Flutter platform channel carries a String, not arbitrary bytes, so the
// native side must not hand malformed UTF-8 to the engine. Empty input is
// valid. This checks strictly: overlong forms, surrogate halves and truncated
// sequences are rejected.
bool IsValidUtf8(const uint8_t* data, size_t size);

// Whether |size| bytes fit inside |limit|. A limit of 0 disables the check.
bool IsWithinRawPayloadLimit(size_t size, size_t limit);

// The single acceptance boundary both WNS ingress paths use: a null pointer is
// accepted only for an empty body, the size limit is enforced, and the bytes
// must be well-formed UTF-8 before they can become a Flutter String.
bool IsAcceptedPayload(const uint8_t* data, size_t size);

// Whether a queued exit message still applies to the hidden activation.
//
// Promotion clears |hidden| (and bumps the generation), so an exit message that
// was already posted before promotion becomes a no-op instead of closing the
// now-interactive window.
bool ShouldAcceptExit(bool hidden, bool exit_requested,
                      uint64_t message_generation,
                      uint64_t current_generation);

}  // namespace apexo_push

#endif  // RUNNER_PUSH_PAYLOAD_H_
