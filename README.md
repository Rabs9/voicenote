# VoiceNote — offline voice assistant for Ubuntu Touch

Push-to-talk speech-to-text running **entirely on-device** via
[whisper.cpp](https://github.com/ggml-org/whisper.cpp). Nothing you say ever
leaves the phone — the only network use is a one-time model download.

Developed and tested on a Xiaomi Poco X3 NFC ("surya") running
Ubuntu Touch 24.04-1.x.

## Features

- **Voice notes** — hold to talk, release, edit, save. Notes are plain text
  files (`~/.local/share/voicenote.falcon/voicenote.falcon/notes/`) —
  greppable, syncable, no lock-in.
- **Notes browser & editor** — browse, edit (keyboard or dictation), delete.
- **Voice commands** — "open camera", "search for ubuntu touch news".
- **Alarms** — "set alarm for tomorrow at 6 AM", "set alarm for February
  14th for Valentine's day at 9 AM". Creates real Clock-app alarms via the
  Lomiri Alarm API.
- **Calendar events** — "add event dentist appointment on Friday at 2 PM".
  Creates real Calendar-app events via QtOrganizer/EDS.
- **Model choice** — whisper tiny.en (fast) or base.en (accurate), selected
  in Settings, downloaded once, persisted.

## Permissions

`audio`, `microphone`, `networking` (model download only), and `calendar`.

**Why `calendar` (reserved policy group):** alarms and calendar events are
created through the system EDS store — the same mechanism the Clock and
Calendar apps use. Alarm/event creation happens only on explicit voice
command from the user. The app never reads existing calendar data and never
transmits anything; all speech processing is offline.

## Building

Prerequisites: [clickable](https://clickable-ut.dev/) ≥ 8.4.0 with
container support (podman/docker).

```bash
git clone --recurse-submodules <this-repo> voicenote
cd voicenote
clickable build --arch arm64     # or --arch armhf
```

The whisper.cpp submodule is pinned to release **v1.9.1**.

Install on a device over adb:

```bash
adb push build/aarch64-linux-gnu/app/voicenote.falcon_*.click /tmp/
adb shell 'gdbus call --system --dest com.lomiri.click \
  --object-path /com/lomiri/click \
  --method com.lomiri.click.Install /tmp/voicenote.falcon_<version>_arm64.click'
```

(`clickable install` also works on most setups.)

Note: the click review will flag the reserved `calendar` policy group —
expected; see Permissions above.

### Cross-compilation notes

The clickable containers don't set `CMAKE_SYSTEM_PROCESSOR`, which makes
ggml mis-detect the target as x86 and inject SSE/AVX flags. `CMakeLists.txt`
forces the correct value based on the cross-compiler triplet, and sets
`GGML_NATIVE=OFF`. This is required for both arm64 and armhf builds.

## Performance (Snapdragon 732G)

- First transcription includes ~1 s of model load; the whisper context is
  cached afterwards.
- tiny.en transcribes a 5–10 s utterance in a few seconds with
  `n_threads = 4`.
- Recordings shorter than ~0.4 s are ignored (whisper hallucinates on
  silence).

## License

MIT — see [LICENSE](LICENSE). whisper.cpp is MIT-licensed.
