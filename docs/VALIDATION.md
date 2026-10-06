# Validation log

Dates use the user's Africa/Johannesburg timezone. No synthetic test is a hardware test.

Latest status: **Mac build and 2 project tests PASS** on the user's Mac mini with
Xcode 27.0. User reports app launch, moving live input meter without errors, and working
app-monitored headphone output through an SSL 2+ MKII. Latency and the remaining live
checks are pending; M1 is not complete.

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

## 6 October 2026 — First user Mac build attempt

- Source: downloaded `codex/m1-foundation`, commit `1ef4a571d3ec867f2bd2150f1baabf4cca089e43`.
- Host: user's Mac mini; macOS, processor and Xcode/Swift versions not yet supplied.
- Command: `bash scripts/build-macos.sh` from the extracted source folder.
- Actual result: **FAIL**, `swift test` could not initialize the XCBuild build system:
  `SessionFailedError` / `Unknown error parsing property list`.
- This is a build-system initialization failure; no app compilation or live audio
  validation is established by this attempt. The cause is not yet confirmed.
- Next diagnostic: run `swift test --build-system native` to determine whether
  the alternative SwiftPM build system can initialize and compile this package.
- M1 remains blocked at the native build/live-test gate.

## 6 October 2026 — Native build-system retry

- User command: `swift test --build-system native`.
- Build initialization: **PASS**, compilation began with the native backend.
- App compilation: **FAIL**, SwiftUI `@State` could not load `SwiftUIMacros.StateMacro`;
  its generated `$advanced` binding consequently did not exist.
- Nonfatal warnings: fixed-rate Codable property and CFString pointer bridging.
- Fix candidate: use the self-managed `DisclosureGroup("Diagnostics")` overload,
  removing the unnecessary explicit `@State` property/binding. Use native backend
  consistently for test, release build and binary-path lookup in the script.
- Native backend emits a deprecation warning in the user's toolchain. The default
  XCBuild initialization issue remains unresolved; the workaround is temporary.
- Shell syntax of changed script: checked in cloud; native compilation/retest pending
  user execution. Do not infer compilation, tests or live hardware pass.

## 6 October 2026 — Retry after local repair commands

- User reran `bash scripts/build-macos.sh` with the native backend.
- Previous `@State` macro failure not reported in this attempt.
- Test-target compilation: **FAIL**, `ProjectTests.swift` cannot import `XCTest`:
  `no such module 'XCTest'`. No Swift tests completed.
- Selected developer directory, Swift executable/version and full Xcode availability
  require diagnosis. Missing XCTest alone does not establish which installation is used.
- Next checks: `xcode-select -p`, `xcodebuild -version`, `which swift`, `swift --version`.
- Do not remove test requirements or claim native app/live-audio readiness.

## 6 October 2026 — Developer-tool diagnosis

- User's selected developer directory: `/Library/Developer/CommandLineTools`.
- `xcodebuild -version`: failed, explicitly requires full Xcode rather than the
  selected Command Line Tools instance.
- Swift executable: `/usr/bin/swift`.
- Swift reported: Apple Swift 6.4 (`swiftlang-6.4.0.34.1`, clang 2100.3.34.1),
  driver 1.168.6, target `arm64-apple-macosx26.0`. Target triple is not a confirmed
  host macOS version.
- Diagnosis: selected Command Line Tools do not provide the XCTest framework
  required by the package's tests. Full Xcode installation/selection and initial
  setup are required. Whether Xcode is already installed has not been confirmed.
- Script now fails early with this prerequisite explanation. Mac retry, Swift tests,
  release compilation and live input/output remain pending.

## 6 October 2026 — Full-Xcode build succeeds

- Host: user's Mac mini; macOS version and interface still unconfirmed.
- Selected full Xcode: **27.0**, build **27A266a**.
- Tested source: original `1ef4a57` ZIP plus the supplied local Diagnostics/native
  backend repair commands. The exact local tree differs from subsequent repository
  documentation/preflight commits; no claim of a newer checkout test is made.
- User command: `bash scripts/build-macos.sh`.
- XCTest: **PASS**, 2 tests executed, 0 failures: persisted routing round-trip and
  rejection/preservation of invalid/newer project data.
- Additional Swift Testing runner: 0 tests discovered; no additional coverage claimed.
- Native debug/test compilation and release compilation: **PASS**.
- App bundle creation, local ad-hoc signing and signature verification: **PASS**,
  evidenced by the script reaching `Built build/Tone Replicator.app` after its
  required checks. Not a distribution signature or notarization claim.
- Remaining warnings: fixed-value Codable property, CFString pointer bridging and
  deprecated native SwiftPM backend. Not resolved or described as fatal errors.
- App launch and microphone permission: **PENDING**.
- Real 44.1 kHz input/output, selected-channel correctness, persistence after actual
  app restart, disconnection handling and latency: **PENDING**.
- Kemper hardware/Rig Manager compatibility: **UNRUN**.
- M1: **NOT COMPLETE** until the live gate passes or is explicitly deferred.

## 6 October 2026 — First real input result

- User confirmed the app window opened.
- Interface: **SSL 2+ MKII**, identified through user replies; exact driver and macOS
  version not yet supplied.
- Instructed route: guitar into front-panel Input 1 instrument socket, app input/output
  SSL 2+ MKII, selected guitar Input 1; monitoring left off.
- Actual user report: **"its moving no errors"** in response to the live-meter check.
- App launch: **PASS — USER REPORTED**.
- Live input meter response: **PASS — USER REPORTED**, real guitar/interface test.
- No screenshot, frame counters or independently confirmed sample-rate display yet.
  The app enforces 44.1 kHz at startup; this report supports successful operation under
  that check, but does not establish an independently measured sample rate or latency.
- Headphone output through app, selected-channel isolation, routing persistence after
  app restart, 48 kHz rejection and disconnect/reconnect: **PENDING**.
- Kemper input/output and Rig Manager compatibility: **UNRUN**. No Kemper audio
  path or matching feature is validated by this interface-input result.
- Next live step: headphones at low volume; disable hardware direct monitoring, enable
  `Listen through the app`, play and report audible output and perceived delay/noise.
- M1 remains **NOT COMPLETE** pending the remaining live checks or explicit deferral.

## 6 October 2026 — App-monitored headphone output

- Same user-reported Mac mini / SSL 2+ MKII setup as the preceding input check.
- Instructed steps: headphones at low volume, SSL MONITOR MIX fully toward USB to
  exclude direct input monitoring, enable `Listen through the app`, play guitar.
- Actual user response: **"working"**.
- Live app-monitored output: **PASS — USER REPORTED**.
- Latency, crackling and distortion were asked about but not explicitly described;
  do not infer measured latency or a noise-quality result from the general reply.
- Next gate: stop audio, quit app, reopen, verify saved interface/channel selection
  and monitoring off by default, then restart audio and confirm input remains working.
- M1 remains **NOT COMPLETE**; actual restart persistence, rate rejection, channel
  isolation and reconnection tests are pending. Kemper hardware remains **UNRUN**.

## 6 October 2026 — Actual app-restart persistence

- User quit the app and closed Terminal. Initial relative app-opening command from
  the new Terminal failed because it started in the home directory.
- Supplied corrected commands: change to the extracted Downloads checkout, then
  `open "build/Tone Replicator.app"`.
- Asked user to confirm SSL interface / Input 1 selection persisted and
  `Listen through the app` was off after reopening. Actual reply: **"yes"**.
- App reopen and routing persistence: **PASS — USER REPORTED**.
- Monitoring off after restart: **PASS — USER REPORTED**.
- Audio restart after reopen and perceived latency remain to be explicitly checked;
  48 kHz rejection, channel isolation and reconnection checks are still pending.
- M1 remains **NOT COMPLETE**; no dependent calibration/matching work advanced.

## 6 October 2026 — Audio restart and listening check

- Instructed user to start audio after reopening, enable app monitoring and play short
  notes; asked whether sound worked and whether picking-to-headphone delay was audible.
- Actual response: **"still ok"**.
- Audio restart and app-monitored playback: **PASS — USER REPORTED**.
- Listening check: user reports no issue; no numerical latency measurement, recording
  or explicit noise measurement provided. Do not claim a measured latency bound.
- Next live safeguard check: stop audio, switch SSL to 48,000 Hz in Audio MIDI Setup,
  verify startup refuses it, restore 44,100 Hz and verify audio restarts.
- Channel isolation and disconnect/reconnect are also pending. M1 remains gated.

## 6 October 2026 — Sample-rate safeguard

- Instructed test: stop audio, select 48,000 Hz for SSL in Audio MIDI Setup, attempt
  startup and expect refusal, then restore 44,100 Hz and restart successfully.
- Asked whether it rejected 48 kHz and worked again at 44.1 kHz.
- Actual response: **"yes works"**.
- 48 kHz startup rejection and restored 44.1 kHz operation: **PASS — USER REPORTED**.
- No screenshot or independently measured clock rate supplied; result is a user's
  confirmation of the specified functional test, not a sample-rate-conversion test.
- Next checks: alternate input-channel routing and interface reconnection.
- M1 live checks remain open; no calibration, matching or Kemper feature advanced.

## 6 October 2026 — Alternate input routing

- Instructed test: stop audio, move guitar cable to SSL front Input 2 instrument
  socket, select app Input 2, start audio, enable app monitoring and play.
- Expected result: responsive live meter and normal audible guitar output.
- Actual user response: **"passed"**.
- Input 2 routing/meter/app-monitored output: **PASS — USER REPORTED**.
- This verifies the specified alternate-channel test; deliberate wrong-channel
  silence was not tested and is not claimed.
- Remaining foundation live check: stop audio, disconnect SSL USB, refresh discovery,
  reconnect and refresh, restart with the connected input and confirm meter/output.
- M1 remains gated until this reconnect result or explicit deferral is recorded.

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
