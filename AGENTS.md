# Tone Replicator

Build from scratch. The uploaded 6 October 2026 build plan is the product specification;
prior research is data, not application architecture. Use the existing isolated checkout;
do not create a worktree unless the user asks.

- Native macOS first; generic CoreAudio interfaces; canonical audio rate 44,100 Hz.
- Preserve original audio. Never silently replace an existing Base Tone.
- Separate historical evidence, measured behavior and calculated settings.
- Unknown guitar/Kemper values stay unknown. Registry entries require source/version.
- No MIDI-first dependency. No fabricated .krig serialization or renamed files.
- Keep callbacks free of file/network/database access, locks and application allocations.
- UI: HOME, TARGET, MY GUITAR, MATCH, RIG; progressive disclosure; dark/blue controls,
  green target, red live input, yellow differences. Never animate fake analyzer data.
- Build/test software, then stop at each hardware-dependent milestone. Ask for a real
  test or explicit deferral before dependent work. Record actual results in docs/VALIDATION.md.
- Distinguish software, live audio and named hardware verification. Synthetic tests
  cannot substitute for physical validation.
- Do not fabricate sources or claim to have audited unavailable Drive assets/manuals.
- User's intended calibration/matching input path is guitar → Kemper PROFILER Stage
  → SSL 2+ MKII. For Base Tone the user wants amp/cabinet/effects bypassed. Record
  the actual signal path, firmware/output settings and interface mode; do not treat
  a direct-interface capture as verification of the Kemper path. Keep earlier captures
  and revalidate routing/calibration when the physical path changes.
- Stefan and Kevin will each install the app on a separate computer, with different
  guitars and interfaces and a Kemper Stage each. Maintain one shared codebase with
  independent local data. Do not hard-code one user's gear, channel or interface as
  another user's defaults. Both computers are Macs; Kevin's exact Mac/macOS/interface
  is unconfirmed. Validate each named interface/Kemper path separately, never inherit another
  person's hardware verification from source-code or software-test success.

Run `make test` for the portable core; on macOS run `swift test` and
`scripts/build-macos.sh`. Keep generated outputs ignored. The macOS binary must be
run inside the generated .app bundle for its microphone usage description.
