# Apexo HIPAA & GDPR Compliance Plan

---

## Preface: About Apexo

### What is Apexo?

Apexo is an **open-source dental clinic management system** (GPLv3). It handles patient records, appointment scheduling, dental charts, X-ray/DICOM imaging, lab work tracking, expense management, clinic notes, and multi-user collaboration — all from a single application.

### Architecture Overview

| Layer | Technology | Details |
|-------|-----------|---------|
| **Client** | Flutter / Dart | Single codebase targeting Android, iOS, Web, Windows, and macOS |
| **UI Framework** | `fluent_ui` (Microsoft FluentUI) | Consistent design language across all platforms |
| **State Management** | Custom `Observable` system | Lightweight reactive system — no Riverpod/Bloc/Redux |
| **Local Storage** | Hive (via `hive_flutter`) | Key-value store; each feature store gets two Hive boxes (`{name}-main` for documents, `{name}-meta` for versioning & deferred sync timestamps) |
| **Remote Storage** | PocketBase (self-hosted) | Single `data` collection with a `store` column for namespacing; version-based incremental sync |
| **Backend Auth** | PocketBase built-in | Email/password auth against `_superusers` (admins) or `users` collections; JWT token-based sessions |
| **Push Notifications** | Firebase Cloud Messaging (FCM) + Cloudflare Worker relay | Store changes trigger push data → relay Worker → FCM → device |
| **AI Services** | External Cloudflare Worker (`dataextraction.apexo.app`) | Dental history transcription, receipt scanning, post-op notes generation |
| **File Storage** | PocketBase file fields + optional S3 | Photos, DICOM X-rays, note attachments; S3 can offload from PocketBase |
| **Localization** | Custom dictionary-based | English (reference), Arabic, Spanish, Greek; RTL support |

### Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                        Apexo Client                          │
│  ┌──────────┐   ┌──────────┐   ┌────────────┐               │
│  │  Store   │──▶│  Hive    │──▶│ Local Disk │ (all devices) │
│  │ (memory) │   │ (local)  │   │            │               │
│  └──────────┘   └──────────┘   └────────────┘               │
│       │                                                      │
│       │ debounced (100ms)                                    │
│       ▼                                                      │
│  ┌──────────┐   ┌──────────────┐                             │
│  │ PocketBase│──▶│ PocketBase   │ (self-hosted server)       │
│  │  Client  │   │  SQLite DB   │                             │
│  └──────────┘   └──────────────┘                             │
└─────────────────────────────────────────────────────────────┘
```

### Sensitive Data Inventory (PHI/PII)

**Patient Model** (`Patient` → `lib/features/patients/patient_model.dart`):
- Full name (`title`)
- Birth year → age (`birth`)
- Gender (`gender`)
- Phone numbers in E.164 format (`phone`)
- Email address (`email`)
- Physical address (`address`)
- Medical notes (`notes`)
- Dental chart per tooth ISO 3950 (`teeth`, `teethExtraNotes`)
- Patient tags (`tags`)
- Patient portal link (`link`)

**Appointment Model** (`Appointment` → `lib/features/appointments/appointment_model.dart`):
- Patient association (`patientID`)
- Pre-operative notes (`preOpNotes`)
- Post-operative notes (`postOpNotes`)
- Prescriptions (`prescriptions`)
- Dental work per tooth (`teeth`, `teethExtraNotes`)
- Treatment photos (`imgs`)
- DICOM X-ray images (`dcmImgs`)
- Operator/doctor assignments (`operatorsIDs`)
- Price & payment data (`price`, `paid`)
- Lab work details (`labName`, `labworkNotes`)

**DICOM Metadata** (embedded in `.dcm` files):
- Patient name, patient ID, birth date, study date
- Institution name, referring physician

**AI Processing Data**:
- Audio recordings of dental examinations → `dataextraction.apexo.app`
- Receipt/invoice images → `dataextraction.apexo.app`
- Appointment data → `dataextraction.apexo.app`

**Account Data**:
- Staff names, emails, permission levels
- SMTP credentials (email password)
- S3 credentials (access key, secret key)

---

## Regulatory Context

### HIPAA (United States)

The **Health Insurance Portability and Accountability Act** sets standards for protecting sensitive patient health information (ePHI). Key requirements:

| HIPAA Rule | Requirement |
|------------|-------------|
| **Privacy Rule** | Patients have rights over their health information; limits on uses/disclosures |
| **Security Rule** | Administrative, physical, and technical safeguards for ePHI |
| **Breach Notification Rule** | Notification requirements if ePHI is compromised |
| **Enforcement Rule** | Penalties for non-compliance |

**Technical Safeguards Required:**
- Access Control (§164.312(a)(1))
- Audit Controls (§164.312(b))
- Integrity Controls (§164.312(c)(1))
- Person or Entity Authentication (§164.312(d))
- Transmission Security (§164.312(e)(1))

### GDPR (European Union)

The **General Data Protection Regulation** applies to **any organization processing personal data of EU residents** — including a US clinic with a single EU patient, and Apexo itself where it processes data on behalf of clinics. GDPR is therefore a **parallel compliance track, not an add-on to HIPAA**: every safeguard below is evaluated against both regimes.

**Key scope fact for Apexo:** health data is a **special category** under **Art. 9** (data concerning health), which is *more* restricted than ordinary personal data — it requires a lawful basis from Art. 9(2) (most commonly **explicit consent** or **provision of health care**, Art. 9(2)(h)) plus strict security under **Art. 32**.

**Principles (Art. 5):**

| Principle | Requirement | Apexo Application |
|-----------|-------------|-------------------|
| **Lawfulness, Fairness, Transparency** | A lawful basis (Art. 6) for each processing activity; privacy notices | Consent tracking for photos, AI, portal, marketing (Phase 4.2) |
| **Purpose Limitation** | Data collected for specified, explicit purposes | AI/portal processing purposes must be documented and limited |
| **Data Minimization** | Only collect what's necessary | Selective/field-level sync (Phase 4.1); minimize push payloads (Phase 5.2) |
| **Accuracy** | Keep data accurate and up to date | Right to Rectification (Art. 16) via portal |
| **Storage Limitation** | Don't keep data longer than needed | Retention policies (Phase 4.3) |
| **Integrity & Confidentiality** | Appropriate technical measures (Art. 32) | Encryption at rest/in transit (Phase 1) |
| **Accountability** | Demonstrate compliance (Art. 5(2)) | Audit logging (Phase 2), RoPA (Art. 30), DPIA (Art. 35) |

**Lawful Bases (Art. 6) — preliminary mapping for Apexo processing activities:**

| Processing Activity | Primary Lawful Basis | Notes |
|---------------------|---------------------|-------|
| Core clinical records & scheduling | **Contract / health care provision (Art. 6(1)(b) + Art. 9(2)(h))** | Treatment relationship |
| Photo storage & AI processing | **Explicit consent (Art. 9(2)(a))** | Consent tracking required (Phase 4.2) |
| Patient web portal | **Explicit consent** | Portal access must be consent-gated and revocable |
| Staff accounts & permissions | **Contract / legitimate interest (Art. 6(1)(f))** | Document in RoPA |
| Marketing communications | **Consent** (ePrivacy) | Opt-in, revocable |
| Error monitoring (Sentry) | **Legitimate interest** | Redact PHI; document in RoPA |

**Key Data Subject Rights:**
- Right to Access (Art. 15) — including a copy of the data and processing info
- Right to Rectification (Art. 16)
- Right to Erasure / "Right to be Forgotten" (Art. 17)
- Right to Data Portability (Art. 20) — structured, machine-readable
- Right to Object (Art. 21)
- Right not to be subject to automated decision-making (Art. 22) — relevant to AI features

**Operational Obligations:**
- **Records of Processing Activities (RoPA, Art. 30):** document what Apexo processes, why, and with whom
- **DPIA (Art. 35):** required for high-risk processing — health data processing almost always triggers one, especially AI and the patient portal
- **Data Protection Officer (Art. 37):** may be required for clinics processing health data at scale; Apexo should provide the documentation to support it
- **Breach notification (Art. 33/34):** notify the supervisory authority within **72 hours**; inform data subjects without undue delay
- **International transfers (Art. 44–49):** any transfer of EU personal data outside the EEA requires adequacy or **Standard Contractual Clauses (SCCs)** — see Gap §14

---

## Current State Assessment: Gap Analysis

### 1. 🔴 Encryption at Rest — CRITICAL

| Asset | Current State | Risk |
|-------|--------------|------|
| Hive local databases | **Unencrypted**. Patient names, birth years, phones, emails, addresses, medical notes, dental charts, appointment notes, prescriptions — all stored as plain JSON in Hive boxes on device disk. | **HIGH** — Any device theft/loss exposes all patient data. |
| PocketBase server (SQLite) | **Unencrypted**. PocketBase stores all data in a plain SQLite file on the server. The `data` collection's `data` column holds full JSON documents including all PHI fields. | **HIGH** — Server compromise = full data exposure. |
| DICOM `.dcm` files | **Unencrypted on disk**. X-ray files cached locally in `filesDir()` with no encryption. | **HIGH** — DICOM files contain embedded patient metadata. |
| Photos/images | **Unencrypted**. Patient photos (before/after treatment) stored in PocketBase file storage or S3 with no encryption. | **MEDIUM** — Facial photos are PHI. |
| Login token | **Stored in Hive unencrypted**. The JWT token is persisted in `_LoginService` which extends `ObservablePersistingObject` → saved to Hive box `main-state` as plain JSON. | **HIGH** — Token theft = full account access. |

**Hive encryption status**: The `pubspec.yaml` has no `hive_flutter` encryption dependencies. `safeHiveInit()` in `lib/utils/safe_hive_init.dart` does not pass an encryption key. All Hive boxes are plaintext.

### 2. 🔴 Encryption in Transit — CRITICAL

| Channel | Current State | Risk |
|---------|--------------|------|
| Client ↔ PocketBase | HTTPS (assumed — depends on user's server setup). No certificate pinning. | **MEDIUM** — Subject to MITM if server HTTPS is misconfigured. |
| Client ↔ AI Worker (`dataextraction.apexo.app`) | HTTPS. Audio files, receipt images, and appointment data sent to external Worker. | **HIGH** — PHI sent to third-party service with no BAA. |
| Client ↔ Push Relay (`apexo-notifications-relay.alisaleem.workers.dev`) | HTTPS. Push payloads contain patient-readable identifiers and appointment data. | **HIGH** — PHI flows through Cloudflare Worker. |
| Client ↔ FCM (Firebase) | Google's FCM infrastructure. Push payload includes patient identifiers. | **MEDIUM** — Google processes push data containing PHI. |
| Client ↔ S3 (if configured) | Depends on user configuration (HTTPS or HTTP). | **MEDIUM** — Could be unencrypted if user misconfigures. |
| Patient Web Portal (`web.apexo.app`) | HTTPS. Patient data including appointments, payments, and photos accessible via base64-encoded URL parameter (no authentication). | **HIGH** — Anyone with the link can view full patient data. |

### 3. 🔴 Audit Logging — CRITICAL

**Current state: No audit logging exists.**

- No record of who accessed which patient record
- No record of who created/modified/deleted data
- No record of who viewed images or DICOM X-rays
- No record of who exported data
- No record of login attempts (successful or failed)
- No record of permission changes

The `logger()` function in `lib/utils/logger.dart` only sends exceptions to Sentry — it is not an audit log. Sentry itself may capture PHI in error messages.

### 4. 🟡 Access Control — HIGH

| Area | Current State | Gap |
|------|--------------|-----|
| **Authentication** | Email/password via PocketBase. JWT tokens. | No MFA support. No session timeout. No failed-login lockout. |
| **Authorization** | `Perm` class with 9 slots (patients, appointments, postOp, stats, expenses, setting, photos, notes, revenue). Levels: 0=none, 1=personal, 2=full. | Coarse-grained — "personal" access for patients means "has appointments where user is operator". No per-field permissions. |
| **PocketBase rules** | `data` collection: `listRule`/`viewRule` = any authenticated user OR settings_global store; `createRule`/`updateRule`/`deleteRule` = any authenticated user except settings_global. `public` collection has **no rules at all** (open access). | **CRITICAL** — The `public` collection used for patient-side portal has empty rules, meaning **anyone can read appointment data without authentication**. |
| **Patient portal** | URL format: `https://web.apexo.app/{base64(patientID|name|server|relayKey)}`. No authentication. | Anyone with the URL has full access. No expiration. No access revocation. |
| **Server admin** | PocketBase `_superusers` have full access. Admin panel at `https://SERVER/_/`. | No MFA for admin panel. No audit of admin actions. |

**GDPR overlay:** dental health records are **special-category data (Art. 9)**. The open `public` collection therefore violates not just HIPAA but GDPR Art. 5 (lawfulness), Art. 25 (data protection by design), and Art. 32 (security of processing). The `Perm` system must also enforce **purpose limitation** — e.g., a receptionist must never be able to read clinical notes for which there is no clinical need.

**PocketBase rules detail** (`lib/utils/constants.dart` lines 217-219):
```dart
const ruleLoggedUsersExceptForSettings =
    "@request.auth.id != \"\" && store != \"settings_global\"";
const ruleEitherLoggedOrSettings =
    "@request.auth.id != \"\" || store = \"settings_global\"";
```

These rules are **store-level only** — they don't check *which* patient/appointment data a user can access. A user with `patients` permission can read ALL patient records.

### 5. 🟡 PHI in Push Notifications — HIGH

The push notification system sends patient-identifiable data through:
1. The Cloudflare Worker relay (`apexo-notifications-relay.alisaleem.workers.dev`)
2. Firebase Cloud Messaging (Google infrastructure)

The `PushData` class (`lib/services/notifications/model_push_data.dart`) includes `readableIdentifier` (patient/appointment title), `updatedFields`, `oldVals`, and `newVals`. These are plain JSON — not encrypted, not minimized.

The push relay server (`push_relay.dart`) sends the full `PushData.toJson()` payload.

**GDPR overlay:** transmitting full identifiers over push violates **data minimization (Art. 5(1)(c))** and exposes data to sub-processors (Cloudflare, Google) without documented safeguards — see Gap §14 on transfers.

### 6. 🟡 AI Services & Third-Party Processing — HIGH

Three AI services send PHI to `https://dataextraction.apexo.app`:

| Service | Data Sent | PHI Content |
|---------|-----------|-------------|
| `DentalHistory` | Audio file (`.m4a`) | Voice recording of dental examination — contains patient identifiers, conditions, treatment plans |
| `ReceiptScanner` | Receipt image | May contain patient names if receipts are patient-specific |
| `PostOpAssistant` | Appointment JSON + patient history | Full pre-op notes, post-op notes, prescriptions, dental chart, pricing |

**Critical issues:**
- No **Business Associate Agreement (BAA)** exists with the AI Worker operator
- No **Data Processing Agreement (DPA)** under GDPR
- Audio files may be stored/processed on the Worker temporarily
- No data retention policy for AI-processed data
- The `aiServicesEnabled` setting (gating mechanism) defaults to `"0"` (off), which is good — but when enabled, there's no warning about PHI transmission

### 7. 🟡 Backup Security — HIGH

| Issue | Detail |
|-------|--------|
| Backup files unencrypted | PocketBase backup `.zip` files contain the full SQLite database — all PHI in plaintext. |
| Backup download URL | Uses PocketBase file token — but the token provides direct access to the backup file. |
| S3 backup storage | Optional S3 backup storage — encryption depends on user's S3 configuration. No enforcement of server-side encryption. |
| No backup encryption key | No option to encrypt backups with a password before download. |

### 8. 🟡 Credential & Secret Storage — HIGH

| Secret | Storage Location | Security |
|--------|-----------------|----------|
| SMTP password | PocketBase `settings_global` store → plaintext JSON in `data` collection | **Plaintext** — any admin can read |
| S3 secret key | PocketBase `settings_global` store → plaintext JSON | **Plaintext** — any admin can read |
| JWT auth token | Hive `main-state` box on device → plaintext JSON | **Plaintext on disk** |
| Push relay key | PocketBase `data` collection with ID `notifications_k` | Deterministic hash of `url + token + email + timestamp` |
| AI Worker token | Cached in `localSettings.aiToken` (Hive) for 24h | **Plaintext on disk** |

### 9. 🟡 Data Export & Portability — MEDIUM

- CSV export includes ALL PHI fields without any protection
- No option to export in encrypted format
- No audit of who exported what data
- No structured machine-readable format (only CSV)
- No bulk deletion capability (GDPR Right to Erasure)
- No mechanism for patients to request their data (GDPR Right to Access)

### 10. 🟡 Data Minimization — MEDIUM

- Full model JSON synced to ALL authenticated devices — a receptionist's device gets all dental charts, X-rays, and photos
- No field-level filtering based on user role
- The `ObservableDict` keeps all data in memory
- No data retention/archiving policy — data stays forever unless manually archived

### 11. 🟡 Session Management — MEDIUM

| Issue | Detail |
|-------|--------|
| No session timeout | App stays logged in indefinitely |
| No auto-lock | No PIN/biometric re-authentication after inactivity |
| Token persisted indefinitely | JWT token saved in Hive, restored on app restart |
| No remote logout | No way to invalidate all sessions for a user |
| No device management | Can't see or revoke device-specific sessions |

### 12. 🟢 Existing Security Controls (Positive Findings)

The following security measures are already in place:

| Control | Detail |
|---------|--------|
| Permission system | Granular 9-slot permission model with admin/user roles |
| AI services toggle | `aiServicesEnabled` defaults to OFF — opt-in for AI features |
| HTTPS for all services | All external endpoints use HTTPS |
| Sentry error monitoring | Production error tracking with `sentry_flutter` |
| Authentication via PocketBase | Industry-standard JWT-based auth |
| Soft-delete (archive) | Models support `archived` flag instead of hard delete |
| Offline-first resilience | Data accessible offline; syncs when connectivity returns |
| Self-hosted backend | Clinics own their data — no vendor lock-in |

### 13. 🟡 GDPR Lawful Basis & Consent — HIGH

| Issue | Detail |
|-------|--------|
| No lawful-basis mapping | No documented Art. 6 basis for each processing activity (clinical, photos, AI, portal, marketing, monitoring) |
| No consent management | No record of *when* or *for what* a patient consented; no withdrawal mechanism |
| No consent proof | No timestamped, immutable record of consent — required for the Art. 9(2)(a) explicit-consent basis |
| ePrivacy | No consent for non-essential cookies/storage on the web portal |
| Portal = no basis | The unauthenticated patient portal (see Gap §4) processes PHI with **no lawful basis at all** |

### 14. 🟡 GDPR International Data Transfers — HIGH

| Issue | Detail |
|-------|--------|
| No transfer analysis | PHI of EU residents flows to PocketBase (server location = clinic's choice), Cloudflare Workers (US), Firebase/Google (US), Sentry (US) |
| No SCCs | No Standard Contractual Clauses or adequacy assessment documented for US-based sub-processors |
| No data-subprocessor register | No per-subprocessor record of purpose, location, and safeguards (feeds the RoPA) |
| Self-hosted ambiguity | Apexo can't control where clinics host — but must ship SCC/adequacy **guidance and templates** for clinic admins |

### 15. 🟡 GDPR Operational Compliance (DPIA, DPO, RoPA) — MEDIUM

| Issue | Detail |
|-------|--------|
| No RoPA | No Art. 30 Record of Processing Activities — the foundational accountability artifact |
| No DPIA screening | Health data (Art. 9) + AI + portal = high-risk processing; no DPIA exists or is planned in the current plan |
| No DPO guidance | No guidance on when a clinic needs an Art. 37 DPO and what documentation to prepare |
| No Art. 22 analysis | AI features may constitute automated decision-making — no assessment of whether they produce legal/significant effects |
| No sub-processor register | No consolidated list mapping each sub-processor to purpose, location, and safeguard |

---

## Implementation Plan

The plan is organized into **phases** prioritized by risk severity and implementation dependency.

### Phase 0: Pre-Requisites & Foundation (Week 1–2)

Before implementing any security features, establish the foundation.

#### 0.1 Security Documentation & Policies

- [ ] Create a **Privacy Policy** document for the application
- [ ] Create a **Data Processing Agreement (DPA)** template for clinics to use
- [ ] Create a **Security Incident Response Plan**
- [ ] Document the **data retention policy**
- [ ] Create a **Business Associate Agreement (BAA)** for the AI Worker service
- [ ] Publish a **list of sub-processors** (PocketBase, Firebase/Google, Cloudflare, Sentry)
- [ ] Create the **GDPR Record of Processing Activities (RoPA, Art. 30)** — one entry per processing activity: purpose, lawful basis, data categories, recipients, retention, safeguards
- [ ] Perform a **GDPR lawful-basis mapping (Art. 6)** for every processing activity (see Regulatory Context)
- [ ] Run **DPIA screening (Art. 35)** for high-risk processing: health records, AI, patient portal, transfers — write full DPIAs where triggered
- [ ] Draft **Standard Contractual Clauses (SCCs)** and adequacy guidance for US-based sub-processors (Cloudflare, Google, Sentry)
- [ ] Add **DPO guidance** for clinics (when Art. 37 applies, and what Apexo documentation supports it)
- [ ] Add **Art. 22 automated-decision-making assessment** for AI features

#### 0.2 Technical Foundation

- [ ] Add `hive_flutter` encryption support:
  - Add dependency: `flutter_secure_storage` (for storing encryption keys)
  - Generate a cryptographically secure encryption key per device
  - Store key in platform keystore (iOS Keychain, Android Keystore, Windows Credential Manager)
- [ ] Add dependency audit for security vulnerabilities
- [ ] Set up a security-focused code review process

### Phase 1: Critical Fixes — Data Protection (Week 2–4)

These are the highest-risk items that must be addressed first.

#### 1.1 Encrypt Hive Local Storage 🔴

**Files to modify:**
- `lib/core/save_local.dart`
- `lib/utils/safe_hive_init.dart`
- `lib/services/login.dart` (for `ObservablePersistingObject` encryption)

**Implementation:**
1. Generate a 256-bit AES encryption key using `dart:crypto` + platform randomness
2. Store encryption key in platform secure storage (iOS Keychain / Android Keystore)
3. Pass encryption key to `Hive.openBox()` via `HiveCipher`
4. Encrypt all Hive boxes:
   - `{store}-main` (document data)
   - `{store}-meta` (version & deferred sync data)
   - `main-state` (login credentials & token)
   - `settings_local` (local preferences)
   - DICOM persistence boxes
   - Push deferring box
5. Add migration path for existing unencrypted Hive boxes

**Dependencies to add:** `flutter_secure_storage`, ensure `crypto` is available

#### 1.2 Fix PocketBase Collection Rules 🔴

**Files to modify:**
- `lib/utils/constants.dart`

**Implementation:**
1. **IMMEDIATE FIX**: Add authentication requirement to `publicCollectionImport`:
   ```dart
   listRule: "@request.auth.id != ''",
   viewRule: "@request.auth.id != ''",
   ```
2. Implement row-level access control using PocketBase's `@request.data` filters
3. Patient data: only allow access if user has `patients` permission
4. Add API rule to prevent users from modifying records they shouldn't access
5. Consider creating a PocketBase hook/extension for more granular access control

#### 1.3 Encrypt PocketBase Data at Rest 🔴

**Implementation options:**

**Option A (Recommended):** Use PocketBase's built-in encryption (if available in the version used)

**Option B:** Implement application-level field encryption:
1. Create an `EncryptedField` wrapper that encrypts/decrypts specific PHI fields
2. Encrypt before `toJson()` serialization, decrypt after `fromJson()` deserialization
3. Fields to encrypt:
   - Patient: `title` (name), `phone`, `email`, `address`, `notes`, `teeth`, `teethExtraNotes`
   - Appointment: `preOpNotes`, `postOpNotes`, `prescriptions`
4. Encryption key derived from clinic-specific secret + server ID
5. Store encrypted blobs in the existing `data` JSON column

#### 1.4 Secure Patient Web Portal 🔴

**Files to modify:**
- `lib/features/patient_side/`
- `lib/services/patient_side.dart`
- `lib/features/patients/patient_model.dart` (`generatePatientLink()`)
- `web/` (service worker, HTML)

**Implementation:**
1. Replace base64-encoded URL with a **cryptographically random token** stored on the server
2. Add token expiration (e.g., 30 days, configurable)
3. Add optional PIN/passcode protection for patient portal access
4. Add access logging for patient portal (who viewed, when)
5. Allow patient to revoke portal access
6. Rate-limit portal access attempts
7. Add a privacy notice on the portal page
8. **GDPR**: gate portal activation on **explicit consent** (Art. 9(2)(a)); add a consent-withdrawal action that immediately revokes the token; log the consent event (Phase 2.1)

### Phase 2: Audit & Accountability (Week 4–6)

#### 2.1 Implement Audit Logging System 🔴

**New files to create:**
- `lib/services/audit/audit_log.dart`
- `lib/services/audit/audit_store.dart`
- `lib/services/audit/audit_model.dart`

**Implementation:**
1. Create an `AuditEntry` model with fields:
   - `timestamp` (DateTime)
   - `actorId` (who performed the action)
   - `actorName` (for display)
   - `action` (enum: CREATE, READ, UPDATE, DELETE, EXPORT, LOGIN, LOGOUT, VIEW_PHOTO, etc.)
   - `resourceType` (patient, appointment, photo, setting, etc.)
   - `resourceId` (which record was affected)
   - `resourceTitle` (human-readable identifier)
   - `details` (what changed — old/new values for updates)
   - `ipAddress` (if available)
   - `deviceInfo` (platform, app version)

2. Integrate audit logging into the `Store` base class:
   - Hook into `_processChanges()` to log all data mutations
   - Add read-access logging in panel open functions
   - Log photo/DICOM views
   - Log exports

3. Store audit log in a dedicated PocketBase collection (or separate SQLite DB)
4. Make audit logs **immutable** and **append-only**
5. Add audit log viewer in Settings (admin-only)
6. Add audit log export functionality

**GDPR overlay (accountability, Art. 5(2) / Art. 30):**
7. Log **consent events** — grant, scope, withdrawal, timestamped and immutable (needed for the Art. 9(2)(a) explicit-consent basis)
8. Log **data-subject requests** — access, rectification, erasure, portability, objection — with status and resolution (Art. 12–21)
9. Log **erasure propagation** — which stores/devices/backups were purged and when
10. Log **AI processing events** — what was sent, for which lawful basis, and the retention window

#### 2.2 PHI-Safe Logging 🔴

**Files to modify:**
- `lib/utils/logger.dart`

**Implementation:**
1. Review ALL `logger()` calls for potential PHI leakage
2. Create a `safeLogger()` that strips PHI before sending to Sentry
3. Add PHI pattern detection and redaction (names, phone numbers, emails)
4. Separate error logging (Sentry) from audit logging (local)
5. Add a debug flag that prevents PHI logging even in development

#### 2.3 Login & Authentication Audit

**Implementation:**
- Log all login attempts (successful + failed) with IP and timestamp
- Implement failed-login rate limiting (5 attempts → 15 min lockout)
- Log all permission changes
- Log all account creation/deletion
- Log all password changes
- Record **session/device metadata** (Art. 15 access): store enough to tell a data subject *which devices* hold their data and *when sessions were active*, and to revoke/erase a specific device on request

### Phase 3: Access Control Hardening (Week 6–8)

#### 3.1 Session Management 🟡

**Files to modify:**
- `lib/services/login.dart`
- `lib/app/app.dart`

**Implementation:**
1. Add **session timeout**: Auto-logout after configurable inactivity period (default: 30 minutes)
2. Add **app-level lock screen**: Require PIN/biometric to unlock after timeout
3. Implement **token refresh** with shorter-lived access tokens
4. Add **remote session revocation**: Admin can force-logout specific users
5. Add **device session tracking**: Show active sessions in Settings
6. Add **concurrent session limit**: Prevent same account from too many simultaneous devices

#### 3.2 Role-Based Field-Level Access 🟡

**Implementation:**
1. Extend the `Perm` class to support field-level permissions
2. Define which fields each permission level can read/write:
   - **Level 0 (none):** Cannot access patient data at all
   - **Level 1 (personal):** Can read patient name, phone; can only see appointments where they are operator
   - **Level 2 (full):** Can read/write all fields
3. Implement field masking in `Model.toJson()` based on viewer permissions
4. Implement data filtering in Store queries
5. **GDPR purpose limitation**: encode role → purpose → fields so access is tied to a documented purpose (e.g., a receptionist can't read clinical notes with no clinical need)

#### 3.3 PocketBase Server Hardening 🟡

**Documentation for users:**
1. Guide for enabling HTTPS on PocketBase server (Caddy configuration)
2. Guide for firewall configuration (restrict PocketBase port to application only)
3. Guide for regular PocketBase updates
4. Guide for server-side encryption (disk encryption, file system encryption)
5. Add PocketBase server health check that verifies HTTPS, firewall, and version

#### 3.4 Multi-Factor Authentication 🟡

**Implementation (future phase):**
1. Add TOTP-based MFA (Time-based One-Time Password)
2. Integrate with PocketBase's auth hooks if available
3. Alternatively, implement at the application level before PocketBase auth
4. Require MFA for admin accounts

### Phase 4: Data Lifecycle Management (Week 8–10)

#### 4.1 Data Minimization 🟡

**Implementation:**
1. **Selective sync**: Only sync data relevant to the user's role
   - Receptionist: patient list + appointments (no dental charts, no photos)
   - Doctor: full access to assigned patients
   - Admin: everything
2. **On-demand loading**: Load dental charts and photos only when viewing a patient
3. Implement **pagination** improvements for large datasets

#### 4.2 GDPR Data Subject Rights & Operational Compliance 🟡

**Implementation:**
1. **Right to Access (Art. 15)**: Create a "Download My Data" feature that exports all patient data in structured JSON format, plus a human-readable summary of *what* is processed, *why* (lawful basis), *by whom* (recipients), and *for how long* (retention)
2. **Right to Erasure (Art. 17)**: Create a "Delete Patient Data" feature with:
   - Anonymization option (replace name with ID, clear contact info)
   - Full deletion option (hard delete from server and all devices)
   - Cascade deletion of appointments, photos, X-rays
   - **Erasure propagation**: purge from Hive boxes on all synced devices, PocketBase, *and* backups within the retention window — audit each purge (see Phase 2.1)
   - Time-boxed erasure SLA (e.g., ≤ 30 days) with a status tracker for data-subject requests
3. **Right to Portability (Art. 20)**: Export in FHIR or openEHR-compatible format
4. **Right to Rectification (Art. 16)**: Allow patients to request corrections (via patient portal)
5. **Consent Management (Art. 7)**: Add consent tracking for:
   - Photo storage
   - AI processing
   - Patient portal access
   - Marketing communications
   - Store consent as **timestamped, immutable audit entries** with scope, version of the notice, and withdrawal — never silently inferred
6. **Lawful-basis enforcement**: gate each processing activity on its mapped Art. 6 basis (see Regulatory Context); block AI/photo/portal use when consent is absent or withdrawn
7. **DPIA output (Art. 35)**: attach the completed DPIAs for AI, portal, and data transfers to the Settings → Compliance area for clinic admins
8. **RoPA export (Art. 30)**: generate the clinic's record of processing activities from the actual configured integrations (sub-processors, purposes, retention) — kept current automatically
9. **Automated decision-making (Art. 22)**: document that AI output is clinician-reviewed and not autonomous, with human-in-the-loop confirmation

#### 4.3 Data Retention 🟡

**Implementation:**
1. Add configurable data retention policies:
   - Auto-archive patients with no appointments in X years
   - Auto-delete archived patients after Y years
   - Auto-delete sent messages/notifications after Z days
2. Add retention policy configuration in Settings
3. Implement scheduled cleanup tasks
4. **GDPR storage limitation (Art. 5(1)(e))**: retention defaults must reflect the clinic's stated lawful basis (e.g., clinical/legal minimums), be configurable per category, and support erasure-on-request that overrides scheduled retention

#### 4.4 Backup Encryption 🟡

**Files to modify:**
- `lib/services/backups.dart`

**Implementation:**
1. Add option to **encrypt backups** with a user-provided password before download
2. Implement AES-256-GCM encryption for backup files
3. Add backup integrity verification (checksums)
4. Enforce S3 server-side encryption by default when S3 backup is configured
5. Add warning if S3 is configured without encryption

### Phase 5: Transmission Security (Week 10–12)

#### 5.1 Certificate Pinning 🟡

**Implementation:**
1. Implement certificate pinning for:
   - The clinic's PocketBase server
   - `dataextraction.apexo.app` (AI Worker)
   - `apexo-notifications-relay.alisaleem.workers.dev` (Push Relay)
2. Use `dart:io` `HttpClient` with custom `SecurityContext` on native platforms
3. Use appropriate web mechanisms for certificate validation

#### 5.2 Push Notification PHI Minimization 🟡

**Files to modify:**
- `lib/services/notifications/model_push_data.dart`
- `lib/services/notifications/push_relay.dart`
- `lib/core/store.dart` (`_processChanges()` push generation)

**Implementation:**
1. **Remove PHI from push payloads**: Instead of sending `readableIdentifier` (patient name), send opaque IDs only
2. Use notification categories/types instead of free-text descriptions
3. On device: resolve the opaque ID to a display name from local data
4. Encrypt the push payload with a per-device key
5. Add a setting for "Show patient names in notifications" (default: OFF)

#### 5.3 AI Worker Data Processing Agreement 🟡

**Implementation:**
1. Create a **Data Processing Agreement (DPA)** for the AI Worker
2. Add data retention commitments: processed data deleted within 24 hours
3. Add a "Delete my AI data" API endpoint on the Worker
4. Implement **client-side data minimization** before sending to AI:
   - Strip patient names from audio transcriptions before sending
   - Replace patient IDs with session tokens
   - Don't send full appointment JSON — only relevant fields
5. Add clear **privacy notice** in-app when enabling AI services — including the lawful basis (explicit consent), sub-processor identity, and retention
6. Log all AI service usage for audit
7. **GDPR transfer safeguards**: document SCCs/adequacy for the AI Worker and each sub-processor; surface them in the RoPA (Phase 4.2)
8. **DPIA for AI (Art. 35)**: complete the DPIA covering transcription/scanning/assistant processing, including the Art. 22 human-in-the-loop analysis

### Phase 6: Monitoring & Incident Response (Week 12–14)

#### 6.1 Breach Detection 🔴

**Implementation:**
1. Implement anomaly detection:
   - Unusual data access patterns (e.g., bulk downloads)
   - Login attempts from new locations/IPs
   - Multiple failed login attempts
   - Access outside of business hours
2. Add alerting for suspicious activities (in-app + email)
3. Create an incident response dashboard in Settings (admin-only)

#### 6.2 Security Monitoring

**Implementation:**
1. Monitor PocketBase server health and security
2. Add automated security scans in CI/CD pipeline
3. Regular dependency vulnerability scanning
4. Add security.txt and vulnerability disclosure policy

#### 6.3 Breach Notification

**Implementation:**
1. Create notification templates for data breaches
2. Implement user notification mechanism (in-app + email)
3. Document regulatory reporting timelines (HIPAA: 60 days; GDPR: 72 hours to the supervisory authority under Art. 33, plus data-subject notification under Art. 34 when risk is high)

### Phase 7: Platform-Specific Security (Ongoing)

#### 7.1 Mobile Security (Android/iOS)

- [ ] Enable Android Network Security Config with certificate pinning
- [ ] Enable iOS App Transport Security (ATS) with no exceptions
- [ ] Implement biometric authentication for app unlock
- [ ] Enable Android auto-backup exclusion for app data
- [ ] Mark relevant files as "do not back up" on iOS
- [ ] Add jailbreak/root detection (optional)
- [ ] Implement screen capture prevention for sensitive screens

#### 7.2 Desktop Security (Windows/macOS)

- [ ] Use platform secure credential storage (Windows Credential Manager, macOS Keychain)
- [ ] Enable file system permissions with least privilege
- [ ] Implement screen lock on system sleep/lock
- [ ] Add disk encryption check (warn if BitLocker/FileVault not enabled)

#### 7.3 Web Security

- [ ] Add Content Security Policy (CSP) headers
- [ ] Add security headers (HSTS, X-Content-Type-Options, X-Frame-Options)
- [ ] Implement service worker with cache encryption
- [ ] Add Subresource Integrity (SRI) for external scripts
- [ ] Implement CSRF protection for PocketBase API calls

### Phase 8: Documentation & Compliance Evidence

#### 8.1 Technical Documentation

- [ ] System architecture and data flow diagrams
- [ ] Encryption implementation details
- [ ] Access control matrix
- [ ] Audit log schema and retention
- [ ] Incident response procedures
- [ ] Disaster recovery plan

#### 8.2 User-Facing Documentation

- [ ] Privacy policy
- [ ] Terms of service
- [ ] Data processing agreement
- [ ] Security configuration guide for clinic admins
- [ ] HIPAA compliance checklist for clinics
- [ ] GDPR compliance guide for EU clinics
- [ ] GDPR lawful-basis & consent notice templates (Art. 6/7)
- [ ] DPIA template + completed examples (Art. 35)
- [ ] RoPA template and maintenance guide (Art. 30)
- [ ] SCC/adequacy guidance for US sub-processors (Art. 44–49)
- [ ] Data-subject rights request handling guide (Art. 12–21)

#### 8.3 Developer Documentation

- [ ] Security coding guidelines
- [ ] PHI handling rules for contributors
- [ ] Security review checklist for PRs
- [ ] Vulnerability disclosure policy

---

## Dependency & Tooling Requirements

### New Dependencies to Add

| Package | Purpose |
|---------|---------|
| `flutter_secure_storage` | Platform secure credential/key storage |
| `encrypt` or `pointycastle` | AES encryption primitives |
| `crypto` (already transitive) | Hashing and key derivation |
| `local_auth` | Biometric authentication (fingerprint, face) |
| `package_info_plus` (already present) | App version for audit logs |
| `device_info_plus` | Device identification for audit |

### Infrastructure Changes

| Component | Change |
|-----------|--------|
| AI Worker (`dataextraction.apexo.app`) | Add DPA compliance, data retention limits, delete endpoint, audit logging |
| Push Relay Worker | Add payload encryption, minimize PHI in transit |
| PocketBase Server | Add collection rules hardening, potential hooks for row-level security |
| Cloudflare Pages (web.apexo.app) | Add security headers, CSP |

---

## Risk Matrix Summary

| # | Risk | Likelihood | Impact | Priority | Phase |
|---|------|-----------|--------|----------|-------|
| 1 | Unencrypted local storage (Hive) | HIGH | CRITICAL | 🔴 P0 | Phase 1 |
| 2 | Public collection open access | HIGH | CRITICAL | 🔴 P0 | Phase 1 |
| 3 | No audit logging | HIGH | HIGH | 🔴 P0 | Phase 2 |
| 4 | PHI in error logs (Sentry) | MEDIUM | HIGH | 🔴 P0 | Phase 2 |
| 5 | Patient portal unauthenticated | HIGH | HIGH | 🔴 P0 | Phase 1 |
| 6 | PHI in push notifications | MEDIUM | HIGH | 🟡 P1 | Phase 5 |
| 7 | AI Worker — no BAA/DPA | MEDIUM | HIGH | 🟡 P1 | Phase 5 |
| 8 | Credentials stored in plaintext | MEDIUM | HIGH | 🟡 P1 | Phase 1 |
| 9 | No session timeout | MEDIUM | MEDIUM | 🟡 P2 | Phase 3 |
| 10 | No MFA | LOW | MEDIUM | 🟡 P2 | Phase 3 |
| 11 | No data retention policy | LOW | MEDIUM | 🟡 P2 | Phase 4 |
| 12 | Backup files unencrypted | LOW | MEDIUM | 🟡 P2 | Phase 4 |
| 13 | No certificate pinning | LOW | MEDIUM | 🟢 P3 | Phase 5 |
| 14 | No GDPR data subject rights | MEDIUM | MEDIUM | 🟡 P2 | Phase 4 |
| 15 | No GDPR lawful basis / consent records | HIGH | HIGH | 🔴 P0 | Phase 4 |
| 16 | No GDPR international transfer safeguards (SCCs) | MEDIUM | HIGH | 🟡 P1 | Phase 5 |
| 17 | No DPIA / RoPA / DPO guidance (Art. 30/35/37) | MEDIUM | MEDIUM | 🟡 P2 | Phase 4 |

---

## Estimated Timeline

| Phase | Duration | Cumulative |
|-------|----------|------------|
| Phase 0: Foundation | 2 weeks | Week 2 |
| Phase 1: Critical Data Protection | 2 weeks | Week 4 |
| Phase 2: Audit & Accountability | 2 weeks | Week 6 |
| Phase 3: Access Control Hardening | 2 weeks | Week 8 |
| Phase 4: Data Lifecycle | 2 weeks | Week 10 |
| Phase 5: Transmission Security | 2 weeks | Week 12 |
| Phase 6: Monitoring & Response | 2 weeks | Week 14 |
| Phase 7: Platform Security | Ongoing | — |
| Phase 8: Documentation | Ongoing | — |

**Total estimated effort: 14 weeks for core compliance + ongoing platform & documentation work.**

> **GDPR note:** the GDPR operational track (RoPA, lawful-basis mapping, DPIA, SCCs — Phase 0.1) runs **in parallel** from day one and costs mostly documentation effort, not code. The GDPR code work is folded into Phases 1, 2, 4, and 5 above; it does **not** add a separate phase.

---

## Appendix A: PHI Field Inventory

### Patient Model (`patient_model.dart`)

| Field | PHI Category | Encryption Priority |
|-------|-------------|-------------------|
| `title` (name) | Direct identifier | HIGH |
| `birth` (birth year) | Demographic | HIGH |
| `gender` | Demographic | MEDIUM |
| `phone` (E.164) | Direct identifier | HIGH |
| `email` | Direct identifier | HIGH |
| `address` | Direct identifier | HIGH |
| `notes` (medical) | Clinical data | HIGH |
| `teeth` (dental chart) | Clinical data | HIGH |
| `teethExtraNotes` | Clinical data | HIGH |
| `tags` | Metadata | LOW |
| `link` | System data | MEDIUM |

### Appointment Model (`appointment_model.dart`)

| Field | PHI Category | Encryption Priority |
|-------|-------------|-------------------|
| `patientID` | Association (link to PHI) | MEDIUM |
| `preOpNotes` | Clinical data | HIGH |
| `postOpNotes` | Clinical data | HIGH |
| `prescriptions` | Clinical data | HIGH |
| `teeth` (dental work) | Clinical data | HIGH |
| `teethExtraNotes` | Clinical data | HIGH |
| `imgs` (photos) | Biometric (facial) | HIGH |
| `dcmImgs` (X-rays) | Diagnostic imaging | HIGH |
| `operatorsIDs` | Operational | LOW |
| `price` / `paid` | Financial | MEDIUM |
| `labName` / `labworkNotes` | Operational | MEDIUM |

---

## Appendix B: Third-Party Services & Compliance Status

| Service | Purpose | PHI Exposure | BAA/DPA/SCC | Mitigation |
|---------|---------|-------------|---------|------------|
| **PocketBase** (self-hosted) | Backend database | ALL PHI stored | N/A (self-hosted) | Clinic's responsibility |
| **Firebase Cloud Messaging** | Push notifications | Patient identifiers, appointment data | Google's BAA covers FCM | Minimize payload, encrypt |
| **Cloudflare Workers** (Push Relay) | Push notification relay | Patient identifiers | No BAA | Encrypt payload end-to-end |
| **Cloudflare Workers** (AI) | AI transcription, scanning | Voice recordings, images, patient data | No BAA | Client-side minimization, DPA needed |
| **Sentry** | Error monitoring | Exception messages (may contain PHI) | BAA available (Enterprise) | Redact PHI before sending |
| **S3 providers** (various) | File storage (photos, X-rays) | Photos, DICOM files | Depends on provider | Enforce server-side encryption |
| **SMTP providers** | Email sending | Email content | Depends on provider | Minimize PHI in emails |

**GDPR transfer note:** for EU residents' data, every row above is a *data transfer* that must be covered by adequacy or **SCCs (Art. 44–49)** and recorded in the RoPA (Phase 4.2). Cloudflare, Google, and Sentry are US-based; the clinic must hold the SCC addenda and the app must surface them to admins in Settings → Compliance.

---

## Appendix C: PocketBase Collection Security Rules (Recommended)

Current rules in `lib/utils/constants.dart` should be updated to:

```
// data collection — main application data
listRule:   "@request.auth.id != ''"
viewRule:   "@request.auth.id != ''"
createRule: "@request.auth.id != '' && @request.data.store != 'settings_global'"
updateRule: "@request.auth.id != '' && @request.data.store != 'settings_global'"
deleteRule: "@request.auth.id != '' && store != 'settings_global'"

// public collection — patient portal data (CRITICAL FIX)
listRule:   "@request.auth.id != ''"  // WAS: "" (open access!)
viewRule:   "@request.auth.id != ''"  // WAS: "" (open access!)
createRule: null  // no public creation
updateRule: null  // no public updates
deleteRule: null  // no public deletion

// profiles collection — staff profiles
listRule:   "@request.auth.id != ''"
viewRule:   "@request.auth.id != ''"
createRule: "@request.auth.collectionName = '_superusers'"
updateRule: "@request.auth.collectionName = '_superusers'"
deleteRule: "@request.auth.collectionName = '_superusers'"

// profiles_view collection — read-only staff view
listRule:   "@request.auth.id != ''"
viewRule:   "@request.auth.id != ''"
createRule: null
updateRule: null
deleteRule: null

// users collection — PocketBase built-in
createRule: "@request.auth.collectionName = '_superusers'"
// (update existing rule from init_pocketbase.dart)
```

---

## Appendix D: Key Implementation References

| Feature | File(s) | Lines of Interest |
|---------|---------|-------------------|
| Hive initialization | `lib/utils/safe_hive_init.dart` | `Hive.initFlutter()` — add encryption key |
| Hive box creation | `lib/core/save_local.dart` | `Hive.openBox<String>(...)` — add `HiveCipher` |
| Login persistence | `lib/services/login.dart` | `_LoginService extends ObservablePersistingObject` — encrypt token |
| PocketBase rules | `lib/utils/constants.dart` | Lines 89–93, 99–103, 111–115, 123–127, 217–219 |
| Store sync | `lib/core/store.dart` | `_processChanges()`, `_syncTry()` — add audit hooks |
| Push data model | `lib/services/notifications/model_push_data.dart` | Full file — remove PHI from payloads |
| Push relay client | `lib/services/notifications/push_relay.dart` | Full file — add payload encryption |
| AI service base | `lib/services/ai_services.dart` | Full file — add PHI minimization |
| Patient portal | `lib/services/patient_side.dart` | Full file — replace base64 with secure tokens |
| Patient portal link generation | `lib/features/patients/patient_model.dart` | `generatePatientLink()` — replace URL format |
| Logger / Sentry | `lib/utils/logger.dart` | Full file — add PHI redaction |
| Backups | `lib/services/backups.dart` | Full file — add encryption option |
| Permissions | `lib/services/perm.dart` | Full file — extend for field-level access |
| Settings (SMTP/S3 creds) | `lib/features/settings/settings_stores.dart` | `GlobalSettings` — encrypt sensitive values |
| DICOM importer | `lib/services/dicom/dicom_importer.dart` | Full file — encrypt DCM file cache |
| Main entry | `lib/main.dart` | Lines 14–55 — add security initializations |

---

*This compliance plan was prepared on 2026-07-31 based on a thorough review of the Apexo codebase at version 0.13.0. It should be reviewed and updated as the codebase evolves and as regulatory requirements change.*
