# Production stack decision — 6 October 2026

Scope: a native macOS application, CoreAudio interfaces, deterministic 44,100 Hz
analysis and a real-time audio path independent of research/network operations.
This is an engineering comparison, not a claim that every current SDK was benchmarked.

| Candidate | Strength | Cost/risk | Decision |
| --- | --- | --- | --- |
| SwiftUI + CoreAudio + C++ | Native accessibility/settings; direct Apple device APIs; portable, bounded DSP | Swift/C boundary and two toolchains; macOS verification required | Selected |
| JUCE/C++ | Mature audio/device abstractions and cross-platform DSP | Licensing review and a less native UI; unnecessary cross-platform UI scope | Reconsider if plugin hosting becomes a requirement |
| Swift + Accelerate only | Native integrations and optimized DSP primitives | Swift ARC/collection work needs careful exclusion from callbacks; portable tests harder | Use Swift for UI/control, benchmark Accelerate later |
| Rust + CoreAudio bindings | Memory safety and strong non-real-time domain tooling | Additional FFI/deployment complexity without measured audio benefit | Not selected for the initial foundation |
| Metal/ML processing | Potential offline inference/large batch acceleration | GPU scheduling and model uncertainty; no demonstrated latency benefit | Optional offline workers after benchmarking |
| Python/web runtime | Useful offline research tooling | Runtime scheduling and UI mismatch with native real-time requirements | Excluded from the live audio path |

Use Swift Package Manager with no third-party dependencies, macOS 14 minimum,
Xcode 16 or later / Swift 6 toolchain, C++17 for the portable core. An Apple Silicon
Mac is the primary live-validation target; do not claim Intel validation until tested.
CoreAudio discovers devices, channels and nominal rates. AVAudioEngine supplies
local input/output rendering over CoreAudio, with explicit hardware device selection.
Apple's framework manages the tap delivery buffer; our C++ meter does not allocate,
block, access files or perform network operations. Framework callback scheduling and
end-to-end latency remain unverified until Mac testing. A direct AudioUnit callback
may replace the tap if measured latency requires it.

M1 measured input level. M2 adds an offline Hann FFT spectral-power fingerprint for
actual captured guitar samples; it does not implement a simultaneous live analyzer,
sample-rate conversion, tone matching, reference playback or research. Import conversion must be designed and
tested before M3; unsupported rates are rejected rather than silently analyzed at
another rate. M4 requires real spectra and benchmarked alignment/similarity metrics.

Audio-thread ownership: preallocate a telemetry object before installing the tap;
read channel buffers without copying; publish atomic telemetry; poll from the UI.
Research, persistence, device selection and graph construction stay off callbacks.
Use the SPSC queue when analysis is introduced. Overflow drops new frames and records
the loss; it never blocks the audio callback. Atomics used by callbacks must be lock-free.

No claim of CoreAudio, hardware, signing, SDK compilation, Rig Manager compatibility
or production latency is established by Linux portable-core tests. See VALIDATION.md.
