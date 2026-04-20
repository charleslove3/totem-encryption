# Digital Totem — Project Specification

## System Overview
A native iOS application that derives a deterministic 256-bit AES key from a multi-modal
physical root of trust. The key is **never stored** — it is reconstructed on-the-fly from
physical sensors.

---

## Core Pillars

| Pillar | Sensor / API | Role |
|---|---|---|
| **The Totem** (Physical) | LiDAR / ARKit `ARMeshAnchor` | 3D point cloud hash of a specific object |
| **The Anchor** (Geographic) | CoreMotion `CMMagnetometerData` | Magnetic anomaly fingerprint at a specific location |
| **The Vault** (Crypto) | CryptoKit + Keychain / Secure Enclave | Fuzzy extractor, helper string storage, biometric gate |

---

## Technical Stack
- **Language:** Swift 6.0+
- **Frameworks:** ARKit, CoreMotion, CryptoKit, LocalAuthentication, Accelerate
- **Target:** iOS 17+ (LiDAR device required for full functionality)

---

## Folder Structure

```
totem-encryption/
├── Models/
│   ├── PointCloud.swift          # SIMD vertex array + radial sort
│   └── MagneticSignature.swift   # 3-axis vector + baseline comparison
├── Services/
│   ├── LiDARService.swift        # ARKit point cloud capture
│   ├── MagneticService.swift     # CoreMotion magnetometer manager
│   └── VaultService.swift        # Keychain / Secure Enclave helper
├── Crypto/
│   └── FuzzyExtractor.swift      # BCH-style sketch + CryptoKit SHA-256
├── Views/
│   ├── HomeView.swift            # Tab navigation root
│   ├── TotemView.swift           # LiDAR AR scanning UI
│   ├── AnchorView.swift          # Magnetic fingerprint UI
│   └── VaultView.swift           # Encrypt / Decrypt payload UI
└── ContentView.swift             # App entry → HomeView
```

---

## Phase 1 — LiDAR Geometry Engine
- `ARWorldTrackingConfiguration` with `.sceneReconstruction = .meshWithClassification`
- Extract `ARMeshAnchor` vertices in a 10 cm³ bounding box
- Normalize to centroid; sort by **radial distance** (rotation-invariant)
- Hash sorted distances with SHA-256

## Phase 2 — Magnetic Fingerprinting
- `CMMagnetometerData` — 3-axis (x, y, z) µT readings
- Store baseline; compare live reading within ±5 % tolerance
- Produce a normalised 64-byte vector for key mixing

## Phase 3 — Fuzzy Extractor / Crypto Engine
- Input: noisy point-cloud hash + magnetic vector bytes
- BCH-style "secure sketch": XOR with stored syndrome to correct bit errors
- Final key = `SHA-256(corrected_seed)` via `CryptoKit.SHA256`

## Phase 4 — Secure Enclave & Vault
- Store "helper string" (syndrome) in Keychain
  - `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`
  - Biometric (`LAContext`) gate before retrieval
- Encrypt/decrypt an arbitrary payload with the derived AES-256 key

---

## Testing Strategy
| Test | Goal |
|---|---|
| Two watches same model | Different hashes (unique LiDAR geometry) |
| Same watch, low vs bright light | Same hash (lighting-invariant) |
| Different room, same watch | Key fails (magnetic anchor mismatch) |
