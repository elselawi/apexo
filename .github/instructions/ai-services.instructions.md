---
description: Apexo AI services — the AIService base class, token caching, dental history transcription, receipt scanning, post-op notes, and the dataextraction Worker contract.
applyTo: "{lib/services/ai_services/**,lib/services/ai_services.dart}"
---

# Apexo AI Services

One Worker (`https://dataextraction.apexo.app`) behind one base class, `AIService` in `lib/services/ai_services.dart`:

```
AIService
├── DentalHistory  — audio → teeth states + notes
├── ReceiptScanner — receipt image → line items
└── PostOpNotes    — dictation → post-op notes, prescriptions, price
```

## Base class

- `getToken()`: authenticates against `/auth` with headers `x-server` (clinic URL) and `x-worker-key` (`PushRelay.ensureKey()`), returns a bearer token cached 24 h in `localSettings.aiToken*` and scoped to the server. Concurrent callers share one in-flight request, and a session change mid-flight throws.
- `createMultipartRequest(endpoint)`: async `http.MultipartRequest` with the bearer header — always `await` it.
- `parseResponse(response, fromJson)`: decodes JSON on 200, otherwise throws with the Worker's `error` when it is JSON.

`lang` is not a caller parameter: every service sends `localSettings.transcriptionOutputLocale`.

## Services

| Service | Entry points | Returns |
|---|---|---|
| `DentalHistory` (`dental_history.dart`) | `processAudioBytes(bytes, filename)`, `processAudioFile(path)` | `DentalHistoryData`: `teeth` (ISO → state) and `teethExtraNotes` |
| `ReceiptScanner` (`receipt_scanner.dart`) | `readReceiptFromXFile(xFile)`, `extractItemsFromUrl(url)` | `ReceiptData`: `supplierName`, `orderDate`, `orderItems`, `totalPrice` |
| `PostOpNotes` (`post_op_notes.dart`) | `processAudioBytes(bytes, filename, {existingFields})`, `processAudioFile(path)` | `PostOpData`: notes, prescriptions, `price`, `paid`, `teeth`, labwork fields |

| Endpoint | Content |
|---|---|
| `/auth` | JSON + `x-server` / `x-worker-key` |
| `/dental-history`, `/receipt-scanner`, `/post-op-notes` | `multipart/form-data`, fields `lang` (+ `existingFields` for post-op) |

Used in: patient panel → dental chart → recorder; expenses panel → scan receipt; visit → post-op.

## Adding a service

1. New file in `lib/services/ai_services/`, models for request and response.
2. `extends AIService`, static methods that `await createMultipartRequest(endpoint)`, add `lang` and files, then `parseResponse`.

```dart
class TreatmentPlanner extends AIService {
  static Future<TreatmentPlanData> generate(XFile image) async {
    final r = await AIService.createMultipartRequest('treatment-plan');
    r.fields['lang'] = localSettings.transcriptionOutputLocale;
    r.files.add(await http.MultipartFile.fromPath('image', image.path));
    final res = await http.Response.fromStream(await r.send());
    return AIService.parseResponse(res, TreatmentPlanData.fromJson);
  }
}
```

3. Export it from `lib/services/ai_services.dart` if callers outside the folder need it.

## Gating

Every AI surface checks `globalSettings.aiServicesEnabled` (stored as `ai_services_ena`) and hides or disables itself when off.

## Common mistakes

| Mistake | Fix |
|---|---|
| Not checking `aiServicesEnabled` | AI buttons must not appear when the setting is off |
| Managing tokens by hand | `getToken()` caches for 24 h |
| Forgetting `await createMultipartRequest(...)` | It fetches the token |
| Assuming `lang` is a caller parameter | Every service sends `localSettings.transcriptionOutputLocale` |
| Calling `processAudioFile` on web | It reads through `dart:io`; use the bytes entry point |
| Skipping a web-CORS check | The Worker allows CORS, but still exercise the web path |
