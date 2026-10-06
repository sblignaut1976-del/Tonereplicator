# Tone Replicator

Greenfield native macOS guitar-tone matching app. This checkout implements the **M1
foundation candidate**, not the complete product. Local operation has no GitHub login
or network dependency. Future online song research will require internet access.

Current scope: CoreAudio interface discovery, saved per-interface routing, explicit
44.1 kHz validation, native Home screen, real input peak/RMS meter and optional local
monitoring. One duplex interface is required in M1. Output goes to that interface's
default output pair; separate clock domains and arbitrary output maps are deferred.

## Build and run on a Mac

Requires macOS 14+ and Xcode 16+ with its command-line tools selected.

```sh
cd Tonereplicator
bash scripts/build-macos.sh
open "build/Tone Replicator.app"
```

This builds a locally ad-hoc-signed `.app`, not a notarized release. It does not need
GitHub or any package downloads: the Swift package has no external dependencies.
Linux cannot compile or run the Apple framework layer. Its portable checks are:

```sh
make test
```

Settings live at `~/Library/Application Support/ToneReplicator/project.json`, using
stable device UIDs and atomic writes. Invalid/newer project files are preserved and
block startup until resolved; no automatic reset. A future project migration must
preserve the original. Monitoring is always off when a session starts.

## First live test

1. Connect guitar → interface input, and headphones → the same interface. Lower the
   headphone volume; turn off hardware direct monitoring for this test.
2. Set the interface to **44,100 Hz** in macOS Audio MIDI Setup.
3. Open the built app, select the interface/input and the same output interface.
4. Click **Start audio**, allow microphone access, and play. The red meter should
   follow playing and the Diagnostics received-frame count should increase.
5. Enable **Listen through the app** and confirm the selected guitar input reaches
   headphones. Report delay, noise, clipping, wrong channels or missing output.
6. Stop, quit, reopen: interface/channel settings should persist and monitoring should
   remain off. Test input 2 if available, then disconnect/reconnect and refresh.
7. Set 48 kHz with audio stopped and try starting: the app must refuse it. Restore
   44.1 kHz afterward. This tests rejection, not sample-rate conversion.

Return Mac model/macOS, interface/driver, input number, app build version, screenshot
of Diagnostics and observed input/output/persistence results. If build fails, return
the first compiler error and nearby lines. Do not send credentials. Record evidence
in [the validation log](docs/VALIDATION.md). Live milestones require real results.

TARGET, MY GUITAR, MATCH and RIG are roadmap labels, not working navigation. No
calibration, spectra, matching percentage, reference import, research, Kemper controls,
optimization or exports are implemented yet. No hardware or native Mac build has
been verified in this Linux cloud session.

See [stack decision](docs/STACK_DECISION.md), [roadmap](docs/ROADMAP.md) and
[source inventory](docs/SOURCES.md).
