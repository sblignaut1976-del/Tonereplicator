# Target import candidate 0.3.0

TARGET supports local audio that AVAudioFile can decode into mono/stereo Float32
at 8–192 kHz. WAV/AIFF are the primary validation formats; compressed formats depend
on the Mac's decoder and still need real-file validation. No uploads or network
services are involved. Imports do not change interface rate or saved calibrations.

Choose a section by start time and duration (1–30 seconds, default 10). The entire
original is copied into a new UUID directory under the user's Application Support
ToneReplicator/Targets directory. Source name, rate, channel count and SHA-256 are
retained. Decode the preserved copy, select rounded source frames, convert using
AVAudioConverter with max quality and no priming, then trim to the floored 44.1 kHz
frame count. Keep interleaved mono/stereo Float32 analysis.wav with its own hash.
Never normalize levels, discard stereo polarity or overwrite the source. Invalid
sections and silent/nonfinite audio are rejected; clipping is reported without
discarding mastered references. Failed conversion removes only its new asset folder.
If saving library metadata fails after a completed conversion, files remain retained
but are not listed; existing selected targets remain unchanged.

Repeatability is tested within the same OS/converter version; identical bytes across
all Apple versions are not claimed. Conversion policy and OS version are stored.
Analysis is the existing Hann FFT 2048/hop1024/24 log-band measurement. Stereo bands
and RMS average channel energy, avoiding cancellation. Measurements include all
instruments in the selected recording, and cannot identify historical gear uniquely.

targets.json is a separate schema-1 library beside project.json. It retains all
imports and the selected ID, independent of calibration schema compatibility.
Atomic saves validate both existing and new data; unreadable/newer data is preserved.
Stefan and Kevin retain independent libraries on their respective Macs.

Evidence is added manually per claim: topic, statement, status, source, optional
version/page and assessment date. Every non-UNKNOWN claim requires a source string.
VERIFIED/CORROBORATED labels reflect explicit user assessment, not an automated audit.
Audio measurements do not promote claims. Automatic complete-chain song research,
audio playback, live reference spectra and matching remain subsequent work.

## Mac live check

1. Quit the app, pull codex/m1-foundation, run scripts/build-macos.sh and launch the
   built app. Candidate has 20 XCTest tests; report the first build/test error if any.
2. TARGET: use start 0 and length 10; import a real WAV/AIFF at least ten seconds long.
   Expect a green measured reference label at 44.1 kHz, with mono/stereo as appropriate.
3. Open Source and analysis details: source rate should match the original (including
   48 kHz if applicable); Show preserved audio files reveals original and analysis.wav.
4. Add a title/artist/version and Save details. Add an UNKNOWN gear claim, then a
   sourced UNVERIFIED claim; neither should be labelled verified automatically.
5. Quit/reopen: selected target, metadata and both evidence statuses must persist.
6. Try importing a section beyond the end; expect an error, with the previous target
   and original files preserved. Report file format/rate and actual results.

Do not advance to M4 real-time comparison until the native conversion suite and
real reference import gate pass or the user explicitly defers the gate.
