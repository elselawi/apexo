---
description: AI Services for Apexo — the AIService base class, token management, dental history transcription, receipt scanning, and post-op notes generation. Applies when working with AI-powered features, the dataextraction Worker, or adding new AI capabilities.
applyTo: "lib/services/ai_services/**"
---

# Apexo AI Services

## Architecture

All AI features share a common base class `AIService` in `lib/services/ai_services.dart`. Each specialized service extends it for a specific domain.

```
AIService (base)
├── DentalHistory   — audio recording → dental chart + notes
├── ReceiptScanner  — receipt image → structured line items
└── PostOpAssistant — appointment data → post-op notes, prescriptions, pricing
```

## AIService Base Class (`lib/services/ai_services.dart`)

### Token Management

- Authenticates with the AI Worker at `https://dataextraction.apexo.app`
- Uses `PushRelay.ensureKey()` to get the clinic's relay key for auth
- **24-hour token caching**: stored in `localSettings.aiToken` / `localSettings.aiTokenExpiry`
- Concurrent requests are deduplicated — if token refresh is in-flight, subsequent callers wait for it

### Key Methods

| Method | Purpose |
|--------|---------|
| `getToken()` | Returns a valid bearer token, refreshing if expired |
| `createMultipartRequest(endpoint)` | Creates a `http.MultipartRequest` with auth header |
| `parseResponse(response, fromJson)` | Parses JSON response, throws on non-200 |

## Individual Services

### DentalHistory (`ai_services/dental_history.dart`)

Converts audio recordings of dental examinations into structured chart data.

**Input**: Audio file (bytes or file path) + optional `lang` parameter
**Output**: `DentalHistoryData` with `teeth` (ISO→state map) and `teethExtraNotes` (ISO→notes map)

```dart
final result = await DentalHistory.processAudioBytes(
  audioBytes,
  'recording.m4a',
  lang: localSettings.transcriptionLocale,
);
// result.teeth = {"11": "caries", "21": "missing", ...}
// result.teethExtraNotes = {"11": "Deep caries, needs RCT"}
```

**Used in**: Patient panel → Dental Notes tab → Audio recorder button

### ReceiptScanner (`ai_services/receipt_scanner.dart`)

Extracts structured data from receipt/invoice images.

**Input**: Image file (path or `XFile`) + optional `lang`
**Output**: `ReceiptData` with `supplierName`, `orderDate`, `orderItems` (list of `ReceiptItem`), `totalPrice`

**Used in**: Expenses panel → Scan receipt button

### PostOpAssistant (`ai_services/post_op_notes.dart`)

Generates post-operative notes from appointment data.

**Input**: JSON body with `appointmentDetails`, `patientHistory`, optional `lang`
**Output**: `PostOpData` with `postOpNotes`, `prescriptions`, `price`, `paid`, `teeth`, `hasLabwork`, `labName`, `labworkNotes`

## Worker Endpoint Convention

All AI services hit the same Worker at `https://dataextraction.apexo.app` with different endpoints:

| Service | Endpoint | Method | Content-Type |
|---------|----------|--------|-------------|
| Auth | `/auth` | POST | JSON (headers: `x-server`, `x-worker-key`) |
| DentalHistory | `/dental-history` | POST | `multipart/form-data` |
| ReceiptScanner | `/receipt-scanner` | POST | `multipart/form-data` |
| PostOpAssistant | `/post-op-notes` | POST | `application/json` |

## Adding a New AI Service

1. Create a new file in `lib/services/ai_services/` (e.g., `treatment_planner.dart`)
2. Define your request/response model classes
3. Extend `AIService` and create static methods:

```dart
class TreatmentPlanner extends AIService {
  static Future<TreatmentPlanData> generate(XFile image, {String? lang}) async {
    final r = await AIService.createMultipartRequest('treatment-plan');
    if (lang != null) r.fields['lang'] = lang;
    r.files.add(await http.MultipartFile.fromPath('image', image.path));
    final res = await http.Response.fromStream(await r.send());
    return AIService.parseResponse(res, TreatmentPlanData.fromJson);
  }
}
```

4. Export from `lib/services/ai_services.dart` if it should be publicly accessible

## Settings Dependency

AI services are gated behind `globalSettings.aiServicesEnabled` — check this before offering AI features in the UI. The setting is stored as `"1"` or `"0"` in the `ai_services_ena` global setting.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Not checking `globalSettings.aiServicesEnabled` | AI features should be hidden/disabled when the setting is off |
| Calling `getToken()` for every small request | It's cached for 24h — no need to manually manage tokens |
| Forgetting to await `createMultipartRequest` | It's async (fetches token) — always `await` it |
| Using AI services on web without CORS | The Worker handles CORS, but test on web explicitly |
