// Tests for the push payload boundary: bytes -> string, UTF-8 validity and the
// raw-payload size guard. Built as an excluded CMake target and run from a
// console; it deliberately has no dependency on Flutter or the Windows App SDK.
//
//   cmake --build build\windows\x64 --target push_payload_test --config Debug
//   build\windows\x64\runner\Debug\push_payload_test.exe
//
// It exits non-zero and prints the failing case on the first failure.

#include "push_payload.h"

#include <cstdint>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

namespace {

int g_failures = 0;

void Check(bool condition, const char* what) {
  if (!condition) {
    ++g_failures;
    std::cerr << "FAIL: " << what << "\n";
  }
}

std::vector<uint8_t> Bytes(const std::string& value) {
  return std::vector<uint8_t>(value.begin(), value.end());
}

void TestPayloadToUtf8() {
  using apexo_push::PayloadToUtf8;

  Check(PayloadToUtf8(nullptr, 0).empty(), "null payload is empty");
  Check(PayloadToUtf8(reinterpret_cast<const uint8_t*>(""), 0).empty(),
        "zero-length payload is empty");

  const std::string json = R"({"payload":"{\"store\":\"appointments\"}"})";
  Check(PayloadToUtf8(Bytes(json).data(), json.size()) == json,
        "ordinary JSON is copied verbatim");

  // Non-ASCII UTF-8 survives byte-for-byte.
  const std::string unicode =
      "{\"payload\":\"{\\\"readableIdentifier\\\":\\\"Zo\u00eb \u0639\u0644\u064a\u0627\\\"}\"}";
  Check(PayloadToUtf8(Bytes(unicode).data(), unicode.size()) == unicode,
        "non-ASCII UTF-8 is preserved");

  // Invalid bytes are copied too; the service decides to drop them.
  const uint8_t invalid[] = {0xC3, 0x28};
  const std::string copied = PayloadToUtf8(invalid, sizeof(invalid));
  Check(copied.size() == 2 && static_cast<uint8_t>(copied[0]) == 0xC3 &&
            static_cast<uint8_t>(copied[1]) == 0x28,
        "invalid UTF-8 is copied without alteration");
}

void TestUtf8Validation() {
  using apexo_push::IsValidUtf8;

  Check(IsValidUtf8(nullptr, 0), "empty input is valid UTF-8");

  const std::string ascii = "hello";
  Check(IsValidUtf8(Bytes(ascii).data(), ascii.size()), "ASCII is valid");

  const std::string unicode = "Zo\u00eb \u0639\u0644\u064a\u0627 \u20AC";
  Check(IsValidUtf8(Bytes(unicode).data(), unicode.size()),
        "multi-byte UTF-8 is valid");

  const uint8_t truncated[] = {0xE2, 0x82};
  Check(!IsValidUtf8(truncated, sizeof(truncated)),
        "truncated sequence is rejected");

  const uint8_t overlong[] = {0xC0, 0xAF};
  Check(!IsValidUtf8(overlong, sizeof(overlong)),
        "overlong encoding is rejected");

  const uint8_t surrogate[] = {0xED, 0xA0, 0x80};
  Check(!IsValidUtf8(surrogate, sizeof(surrogate)),
        "surrogate half is rejected");

  const uint8_t invalid_byte[] = {0xFF};
  Check(!IsValidUtf8(invalid_byte, sizeof(invalid_byte)),
        "0xFF is rejected");
}

void TestSizeGuard() {
  using apexo_push::IsWithinRawPayloadLimit;

  // The constant is 0 (unverified) today; the predicate is exercised with an
  // explicit limit so the boundary behaviour is covered regardless.
  constexpr size_t kLimit = 5 * 1024;  // 5120-byte convention under test

  Check(IsWithinRawPayloadLimit(0, kLimit), "empty fits");
  Check(IsWithinRawPayloadLimit(kLimit - 1, kLimit), "one below the limit fits");
  Check(IsWithinRawPayloadLimit(kLimit, kLimit), "exactly the limit fits");
  Check(!IsWithinRawPayloadLimit(kLimit + 1, kLimit),
        "one above the limit does not fit");
  Check(IsWithinRawPayloadLimit(1ull << 40, 0),
        "a zero limit disables the guard");
}

void TestSharedAcceptance() {
  using apexo_push::IsAcceptedPayload;

  Check(IsAcceptedPayload(nullptr, 0), "an empty payload is accepted");
  Check(!IsAcceptedPayload(nullptr, 1),
        "a null pointer with a nonzero size is rejected");

  const std::string valid = R"({"payload":"{}"})";
  Check(IsAcceptedPayload(Bytes(valid).data(), valid.size()),
        "a valid UTF-8 stream payload is accepted");

  // The same malformed bytes must be rejected at both ingress paths; the
  // service calls this one helper from PostPayload and ReadActivation.
  const uint8_t invalid[] = {0xC3, 0x28};
  Check(!IsAcceptedPayload(invalid, sizeof(invalid)),
        "malformed UTF-8 is rejected at the shared boundary");

  // The size guard is part of the same boundary, even though the current
  // documented constant disables the check until WNS's limit is confirmed.
  Check(IsAcceptedPayload(Bytes(valid).data(), valid.size()),
        "a small payload passes both acceptance checks");
}

void TestExitGeneration() {
  using apexo_push::ShouldAcceptExit;

  Check(ShouldAcceptExit(true, true, 7, 7),
        "a current queued exit is accepted");
  Check(!ShouldAcceptExit(false, true, 7, 9),
        "promotion (hidden false, new generation) invalidates a queued exit");
  Check(!ShouldAcceptExit(true, true, 6, 7),
        "an older generation is ignored");
  Check(!ShouldAcceptExit(true, false, 7, 7),
        "an exit that was not requested is ignored");
}

// The number that matters to WNS is the UTF-8 length of the serialized relay
// body — {"payload":"<PushData JSON>"} with its escapes — not the inner JSON.
void TestSerializedEnvelopeSize() {
  const std::string push_data =
      R"({"store":"appointments","id":"appointment_01",)"
      R"("readableIdentifier":"Zo\u00eb","isCreation":false,)"
      R"("isUpdate":true,"updatedFields":["date"],"oldVals":[100],)"
      R"("newVals":[200],"targetIDs":["account_01"]})";

  std::string envelope = "{\"payload\":\"";
  for (char c : push_data) {
    if (c == '"' || c == '\\') {
      envelope.push_back('\\');
    }
    envelope.push_back(c);
  }
  envelope += "\"}";

  Check(envelope.size() > push_data.size(),
        "the envelope is larger than the inner payload (escaping counts)");
  Check(apexo_push::IsWithinRawPayloadLimit(envelope.size(), 5 * 1024),
        "a realistic envelope fits the 5 KB class limit");

  const std::string oversized(6 * 1024, 'x');
  Check(!apexo_push::IsWithinRawPayloadLimit(oversized.size(), 5 * 1024),
        "an oversized body does not fit");
}

}  // namespace

int main() {
  TestPayloadToUtf8();
  TestUtf8Validation();
  TestSizeGuard();
  TestSharedAcceptance();
  TestExitGeneration();
  TestSerializedEnvelopeSize();

  if (g_failures == 0) {
    std::cout << "push_payload_test: all cases passed\n";
    return 0;
  }
  std::cerr << "push_payload_test: " << g_failures << " case(s) failed\n";
  return 1;
}
