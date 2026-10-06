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

Run `make test` for the portable core; on macOS run `swift test` and
`scripts/build-macos.sh`. Keep generated outputs ignored. The macOS binary must be
run inside the generated .app bundle for its microphone usage description.
