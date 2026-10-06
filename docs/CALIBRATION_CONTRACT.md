# M2 calibration contract

Capture the selected real guitar input at 44,100 Hz for ten seconds. Allocate a
bounded SPSC queue before installing the callback. The callback only publishes
samples and meter telemetry; a main-thread consumer drains samples, with offline
fingerprint/WAV encoding away from the callback. Reject captures with lost frames,
invalid samples, clipping or insufficient signal. Capture completion alone never
replaces a saved Base Tone.

Store exact user-entered manufacturer/family/model/variant/year/pickup/position/mode
as user-provided identity, not verified manufacturer evidence. Unknown optional
fields stay empty and display UNKNOWN. A new configuration gets its own immutable
ID; editing identity creates a new configuration, rather than reassigning existing
calibrations to another pickup. Keep guitar volume/tone and interface gain notes
as user-entered capture context.

Calibration fingerprint v1: mono 44.1 kHz, peak/RMS/DC, clipping/nonfinite counts,
24 logarithmic power bands from 40–20,000 Hz, Hann-windowed 2048-point double-precision
FFT, hop 1024; window energy normalization and one-sided bin energy. This is measured
behavior, not historical settings, a pickup specification, a match score or recovered
studio equipment. Reject input at unsupported rates rather than converting it here.

Save a local Float32 WAV and its fingerprint, interface UID/channel and timestamp.
Store user-selected signal path and device/firmware/output notes. The user's intended
path is Kemper Stage bypass → Monitor Output → interface line input. Existing direct
captures remain history; a new physical path requires a new real calibration. Older
capture context lacking path metadata decodes as UNSPECIFIED without inventing facts.
Require explicit Save Base Tone. Existing calibration requires an explicit Replace
Base Tone confirmation; keep the previous capture/history. Factory and calibration
sources remain distinct; no verified factory datasets are shipped, so Factory shows
UNKNOWN and cannot supply a calculated baseline. User may select either source.

Project schema 2 adds Gear Vault. Load schema 1 without losing routing, then create
a non-overwriting backup before first schema-2 save. Refuse unsupported versions and
invalid rates. Never write over unreadable/newer project data. Failed saves must
not be reported as saved or discard a usable existing Base Tone.

Software tests: rate contract, sine/window energy and bands, silence, nonfinite/clipped
input, migration/backup, separate pickup persistence, no implicit replacement,
explicit replacement preserving history, active source changes without destructive
capture mutation. Live gate: record actual guitar, save/restart, confirm exact pickup
and Base Tone remain selected and a second recording does not silently replace them.
