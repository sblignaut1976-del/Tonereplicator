# Validation log

Dates use the user's Africa/Johannesburg timezone. No synthetic test is a hardware test.

## 6 October 2026 — M1 foundation candidate / app 0.1.0

- Build identity: M1 foundation candidate, app 0.1.0. Use `git rev-parse HEAD`
  from the tested checkout to identify the exact source revision; no release assigned.
- Host: Linux Debian 13, GCC 14.2.0, C++17.
- Portable software: `make test` **PASS**, 11 executed checks. Known 1 kHz/44.1 kHz
  synthetic sine validates peak/RMS; invalid inputs and out-of-range channels tested;
  bounded SPSC overflow/wrap tested; 200,000 concurrent frames preserve order.
- AddressSanitizer + UndefinedBehaviorSanitizer: **PASS**, same 11 checks;
  no sanitizer findings. Build script shell syntax and bundle plist: **PASS**.
- `swift test`: **UNRUN** — Swift and Apple frameworks unavailable on this host.
- Native executable/.app compilation: **UNRUN**, requires macOS/Xcode.
- Live audio: **PENDING**, no real recording or interface attached.
- Hardware: **PENDING**, Kemper Stage and firmware reported below; Mac/interface unconfirmed.
- M1 overall: **NOT COMPLETE**, awaiting the README live gate or explicit user deferral.

## 6 October 2026 — User-reported Kemper information

- Firmware: **14.2.2.68644**.
- Firmware date reported by user: **22 September 2026**.
- Device identifier supplied in chat; not used to infer model or stored in the source log.
- Kemper model: **PROFILER Stage**, confirmed by user in chat.
- Evidence class: **USER REPORTED**, not a hardware compatibility test.
- Uploaded manuals cover 14.2; exact model applicability and patch-version differences
  still require source review and real-device validation.
- Live input/output and Rig Manager compatibility remain **UNRUN**.

## Live result template

- Date, build version/commit:
- Mac model, macOS, Xcode/Swift:
- Interface model/driver, input/output channels:
- Sample rate (must be 44,100 Hz):
- Kemper model/firmware (when relevant):
- Test steps and expected behavior:
- Actual result, screenshot/capture references:
- Latency/noise/clipping observation (subjective vs measured):
- SOFTWARE / LIVE AUDIO / HARDWARE result: PASS / FAIL / UNRUN:
- Fix and identical retest result:

Never fill actual results from assumptions, generated audio or unit tests.
