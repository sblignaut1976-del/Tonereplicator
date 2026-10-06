# Tone Replicator

Greenfield native macOS guitar-tone matching app. This checkout implements the **M2
calibration candidate**, not the complete product. Local operation has no GitHub login
or network dependency. Future online song research will require internet access.

Current scope: CoreAudio interface discovery, saved per-interface routing, explicit
44.1 kHz validation, native Home screen, real input peak/RMS meter, optional local
monitoring, a multi-guitar Gear Vault and ten-second measured calibration. One duplex
interface is required. Output goes to that interface's
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
M1 was built and live-tested by the user with a Mac mini, Xcode 27.0 and SSL 2+ MKII.
M2 native compilation and real calibration remain pending. Linux cannot compile or
run the Apple framework layer. Its portable checks are:

```sh
make test
```

Settings live at `~/Library/Application Support/ToneReplicator/project.json`, using
stable device UIDs and atomic writes. Invalid/newer project files are preserved and
block startup until resolved; no automatic reset. A future project migration must
preserve the original. Monitoring is always off when a session starts.

M2 uses project schema 2. The first save after loading M1's schema 1 preserves a
uniquely named `project-schema1-*.json` backup beside the project. Older M1 builds
will refuse schema 2. Never delete or reset the project to resolve a loading error.

## M2 live calibration gate

Start with **the Fender bridge pickup only**. All positions do not need to be tested
before this gate passes. Other guitars/positions/modes can get separate captures later.

1. Build with the script above. It must finish all **12 XCTest tests**, release build
   and signing. If any fail, stop and return the first error.
2. On HOME, start your working SSL route at 44.1 kHz. In MY GUITAR, use the Fender
   **Fender SH template**, confirm Player II Modified Telecaster SH / bridge Player II Noiseless
   Tele and correct any details before saving the configuration. These identities
   carry the user's source/verification attribution, not an independent source audit.
3. Choose the actual **Calibration signal path** before recording. The intended user
   path is guitar → Kemper Stage, amp/cabinet/all effects bypassed → Monitor Output →
   SSL rear line input. Record device/firmware, output source/level/processing and
   gain notes. Verify this new physical route before capture. Then play single notes across the strings
   and a few chords throughout ten seconds, without changing pickup/control/gain.
   Enter optional control/gain notes before recording. Clipping, silence, invalid
   samples or lost frames must produce an unsaved error, not an accepted Base Tone.
4. When the candidate is ready, choose **Save Base Tone**. Check the MEASURED badge,
   date and 44.1 kHz/10-second fingerprint. Capture ID is under Identity and sources.
5. Stop, quit and reopen. Select MY GUITAR: the exact configuration, My Calibration
   source, date and capture ID must persist. The original interface route must survive.
6. Record a second candidate. The existing Base Tone/capture ID must remain active.
   Cancel the Replace confirmation and discard the candidate: the original must remain.
7. A deliberate Replace confirmation may activate a new capture ID; the previous
   calibration stays in retained history. A separate guitar/pickup configuration must
   have its own Base Tone. Use the Ibanez AZ224F template and explicitly enter its position
   and switching/Alter mode, which have not been supplied.

Record actual outcomes in [the validation log](docs/VALIDATION.md). No calibration
or persistence milestone is complete solely because a synthetic test passed. Capture
WAVs stay local under the project's `Calibrations/` directory with unique filenames.
The fingerprint is measured level and spectral power, not a tone-match percentage.
Factory Data selection currently shows UNKNOWN: textual pickup specs alone do not
provide a verified factory audio baseline. Source selection preserves calibration.

Earlier successful captures were direct guitar-to-SSL; retain them as separate history.
The new Kemper path needs its own measured capture. Legacy captures with no path field
display UNSPECIFIED; loading never invents a path or loses volume/tone/gain notes.

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

HOME and MY GUITAR are active navigation. TARGET, MATCH and RIG remain roadmap labels.
No simultaneous live/reference spectra, matching percentage, reference import, online
research engine, Kemper controls, optimization or rig exports are implemented yet.
No Kemper audio path or generic hardware certification is established by M1 testing.

See [stack decision](docs/STACK_DECISION.md), [roadmap](docs/ROADMAP.md) and
[source inventory](docs/SOURCES.md).
