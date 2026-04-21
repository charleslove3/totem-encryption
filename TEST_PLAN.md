# Digital Totem — Full Test Plan

> **Version:** 1.0 | **Date:** April 20, 2026
> **Tester:** Charles Love
> **Device:** iPhone (LiDAR-capable, e.g., iPhone 12 Pro+)

---

## How the app works (north star)

```
Website: "Scan on your app"
    ↓  shows QR code with a challenge token
User opens Totem app → Authenticator tab → scans QR
    ↓  app scans the physical "totem" object with LiDAR
    ↓  reconstructs 256-bit key (LiDAR hash + magnetic anchor)
    ↓  signs the challenge token with the key
    ↓  sends signed response back to website
Website verifies signature → grants access
```

The key is **never stored**. If you're in the wrong room, or scanning the wrong object, the reconstructed key will be wrong and the signature will fail.

---

## Test Objects (what you have available)

| ID | Object | Notes |
|----|--------|-------|
| **A** | Inner wrist (vein-side) | Fine surface texture, stable geometry |
| **B** | Fingernail (index or thumb) | Curved, small — good uniqueness test |
| **C** | Palm (open hand, dominant) | Larger surface area, palm lines |
| **D** | Computer keyboard (top surface) | Rigid, inanimate — best repeatability baseline |

---

## Test Suite 1 — Stability Tests (same object → same key)

**Goal:** Verify the same object produces the same hash across multiple scans.
**Pass criterion:** 3 out of 3 captures produce a hash that decrypts the same payload.

### 1A — Keyboard (baseline / easiest)
Run first. The keyboard doesn't move and has no lighting variation from position changes.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Scan keyboard → Enroll | Helper string saved to Vault |
| 2 | Encrypt a known message ("hello") | Ciphertext stored |
| 3 | Scan keyboard again (don't move phone position) | Same key reconstructed → decrypts "hello" ✓ |
| 4 | Repeat step 3 two more times | Same result each time |
| 5 | Move phone 10 cm away, re-scan | **Expected: still decrypts** (bounding box captures same geometry) |

### 1B — Inner Wrist
Hold your wrist flat under the phone. Rest your elbow on the desk so you don't wobble.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Scan wrist → Enroll | Helper string saved |
| 2 | Encrypt "wrist-test" | Ciphertext stored |
| 3 | Relax hand, wait 5 seconds, re-scan | Decrypts ✓ |
| 4 | Rotate wrist 15° and re-scan | **Expected: still decrypts** (radial sort is rotation-invariant) |
| 5 | Re-scan after 30 min (skin temp change) | Decrypts ✓ |

### 1C — Fingernail
Rest your finger flat on a dark surface so LiDAR gets a clean read.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Scan nail → Enroll | Helper string saved |
| 2 | Encrypt "nail-test" | Ciphertext stored |
| 3 | Lift and replace finger in same spot, re-scan | Decrypts ✓ |
| 4 | Re-scan after washing hands | Decrypts ✓ (geometry unchanged) |
| 5 | Re-scan with nail polish applied | **Expected: FAIL** (surface changed) — document result |

### 1D — Palm
Hold palm face-up, phone ~15–20 cm above.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Scan palm → Enroll | Helper string saved |
| 2 | Encrypt "palm-test" | Ciphertext stored |
| 3 | Close and re-open hand, re-scan | Decrypts ✓ |
| 4 | Re-scan with hand slightly tilted | **Expected: still decrypts** (rotation-invariant) |
| 5 | Scan other hand | **Expected: FAIL** (different geometry) — document result |

---

## Test Suite 2 — Uniqueness Tests (different objects → different keys)

**Goal:** Verify that two different objects produce different keys (no cross-decryption).
**Pass criterion:** Ciphertext from Object X cannot be decrypted by scanning Object Y.

| Test | Enroll with | Try to decrypt with | Expected |
|------|-------------|---------------------|----------|
| 2.1 | Keyboard | Wrist | FAIL ✗ |
| 2.2 | Keyboard | Palm | FAIL ✗ |
| 2.3 | Wrist | Fingernail | FAIL ✗ |
| 2.4 | Wrist (left) | Wrist (right) | FAIL ✗ — document how close |
| 2.5 | Palm | Keyboard | FAIL ✗ |
| 2.6 | Fingernail (index) | Fingernail (middle) | FAIL ✗ — document if they're close |

> **Note on 2.4 and 2.6:** If these pass (wrong object decrypts), that reveals the bounding box is too large or the fuzzy extractor tolerance is too loose. Document the result — we'll tighten the BCH syndrome window.

---

## Test Suite 3 — Magnetic Anchor Tests

**Goal:** Verify the key derivation fails when you're in the wrong room.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 3.1 | Save magnetic baseline at your desk | Status: "Baseline saved" |
| 3.2 | Encrypt payload at desk | Ciphertext stored |
| 3.3 | Walk to another room, re-scan same object | Anchor mismatch → decryption fails ✗ |
| 3.4 | Return to desk, re-scan | Decrypts ✓ |
| 3.5 | Open large metal object near phone (fridge?) | Magnetic anomaly → check if match breaks |

---

## Test Suite 4 — Authenticator Flow (QR Challenge)

> Run this once you connect your phone and have a second device or browser tab open.

| Step | Action | Expected Result |
|------|--------|-----------------|
| 4.1 | Open the Authenticator tab in the app | Sees "Waiting for challenge…" |
| 4.2 | Simulate a challenge (tap "Generate Test Challenge" in app) | Challenge QR appears on screen |
| 4.3 | Scan object → approve | Challenge marked "Approved ✓" |
| 4.4 | Try to approve with wrong object | Challenge marked "Denied ✗" |
| 4.5 | Challenge expires after 30 seconds | Challenge marked "Expired" |

---

## Test Suite 5 — Lighting & Environment Stability

**Goal:** The LiDAR sensor works on IR — it should be lighting-independent. Verify this.

| Test | Condition | Object | Expected |
|------|-----------|--------|----------|
| 5.1 | Normal desk lamp | Keyboard | Decrypts ✓ |
| 5.2 | Room lights off | Keyboard | Decrypts ✓ (LiDAR = IR, lighting-independent) |
| 5.3 | Direct sunlight | Keyboard | Decrypts ✓ |
| 5.4 | Normal light | Wrist | Decrypts ✓ |
| 5.5 | Room lights off | Wrist | Decrypts ✓ |

---

## Recording Results

For each test, record:

```
Test ID:
Date/Time:
Object:
Lighting:
Room:
Vertex count captured:
Result (✓ / ✗):
Notes:
```

---

## Failure Modes & Debugging

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Always fails to reconstruct | Fuzzy extractor tolerance too tight | Widen BCH syndrome |
| Cross-object decryption succeeds | Bounding box too large / not enough vertices | Shrink box to 5 cm, require min 500 vertices |
| Works in one room only | Magnetic weight too high in seed | Reduce magnetic bytes contribution or make anchor optional |
| Wrist scan varies too much | Veins shift with blood pressure | Move enroll logic to average 3 scans |
| Palm scan flaky | Hand not flat enough | Add a "Hold still" guidance overlay in TotemView |
