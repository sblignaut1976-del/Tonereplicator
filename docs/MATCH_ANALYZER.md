# MATCH candidate 0.4.0

Load the selected TARGET analysis WAV, validate its stored SHA-256, decode its bounded
1–30 second mono/stereo audio at 44.1 kHz and prepare a stereo playback buffer. Mono
is duplicated to left/right only for listening. Precompute 8192-frame analysis
windows at 4410-frame steps and a maximum-240-bin peak envelope, from actual source
samples. Silence yields no reference spectrum. Stored analysis/original files and
calibration selections are unchanged by listening or comparison.

One AVAudioEngine drives the selected duplex interface at 44.1 kHz. Guitar input
passes through a separate live mixer into main-mixer bus 0; a stereo AVAudioPlayerNode
feeds bus 1. Main mixer feeds the configured listening output pair. The input tap
remains upstream of both playback gains and publishes to the existing fixed SPSC
queue without allocation, filesystem/network access or locks. Timer drains samples
at 10 Hz for calibration and a bounded 8192-frame live analysis window. FFT runs in a
detached task, with at most one current analysis job; stop/drop generations reject
stale results. Queue overflow resets the analysis window and reports dropped samples.

Reference loops from the start. Player render sample time chooses the green window
and waveform cursor; the red window measures recent input. No generated animation,
static whole-clip fingerprint substituted for playback, automatic performance
alignment or hardware latency compensation is claimed. The last window can cover
the end of the clip while the loop returns to its beginning; a boundary discontinuity
may be audible. Windows span about 186 ms and UI refresh is up to 10 Hz; actual
latency/CPU must be checked on the user's hardware.

Spectrum y values are band energy relative to the total measured 40–20,000 Hz energy,
floored at −60 dB. Stereo averages channel energy, preserving opposite polarity.
Score uses weighted RMS difference of relative band dB values: weights are square
roots of the larger normalized energy of each band; score = 100 × exp(−error/12).
It intentionally ignores absolute gain, while reporting live-minus-reference RMS
level difference. Score is unavailable for missing data, RMS below 0.001 (−60 dBFS),
nonfinite bands or clipping (peak ≥1). It measures spectrum shape, not a complete
perceptual tone match. It does not assess dynamics, performance, modulation, stereo
image, confidence or historical identity. Selected calibration is displayed/retained
but does not yet drive a calculated tone recipe.

Listening uses Reference/Guitar/Both controls. Guitar monitoring defaults off;
choosing Guitar/Both enables it with −6 dB playback gain. Reference defaults to 25%
volume (about −12 dB). Reference continues advancing when muted for A/B. App controls
do not mute interface direct monitoring: turn that off to hear the chosen A/B source.
HOME's Listen through the app also enables the live mixer. Stop audio silences both
branches before engine teardown; leaving MATCH stops reference playback. Re-starting
audio defaults to monitoring off. Reference cannot start while calibration is being
recorded/analyzed or an unsaved candidate is awaiting review; recording stops it.

## Checks completed here

- Existing 19 portable core checks pass.
- Numerical smoke using the compiled portable FFT and score formula: 1000 Hz tone
  versus −20 dB gain copy scores 99.999998%; 1000 versus 4000 Hz scores 0.69%, with
  59.66 dB weighted shape error. This does not execute Swift or Apple playback APIs.
- Four new XCTest cases cover level invariance/frequency difference, silence/clipping
  rejection, time-varying/opposite-polarity timeline, mono playback duplication and
  changed-file hash rejection. Total 24 XCTest cases, UNRUN in this Linux environment.

## Mac build and live gate

1. Quit the app, pull codex/m1-foundation, run scripts/build-macos.sh. Expect 24 tests
   with zero failures, a release build and app bundle; return any first error.
2. HOME: select the actual incoming channels (Stefan: SSL Inputs 1/2 in LINE mode),
   the same input/output interface at 44.1 kHz and the actual speaker/headphone
   output pair. Keep volume low; for A/B put SSL MIX toward USB. Start audio.
3. MATCH: confirm the intended saved target, Load selected reference, Play reference.
   Expect audible reference, moving measured green curve and waveform cursor.
4. Play guitar while reference runs. Expect a separate red curve following playing,
   green curve continuing and a spectral similarity value when both contain signal.
   Do not judge quality with unrelated phrases; score is spectral shape only.
5. Select Guitar, Reference, Both: expect the corresponding audio. Report wrong
   channels, duplicate/direct sound, delay, noise or distortion. Stop audio: both
   app branches stop. Quit/reopen: calibration and target selections must remain.
6. Stop reference but continue playing: green curve/score disappears; red remains.
   Verify silence does not retain a meaningful score. Return real results and the
   complete test summary. Neither test fixtures nor compilation certify hardware.

Pause dependent optimization/device work until the user reports this live gate
PASS or explicitly defers it. Automatic song research remains a separate open item.
