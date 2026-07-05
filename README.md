# VoiceNote — offline speech-to-text for Ubuntu Touch 24.04

Push-to-talk voice notes and (eventually) voice actions, running whisper.cpp
entirely on-device. Target device: Xiaomi Poco X3 NFC ("surya"), UT 24.04-1.x.

## Prerequisites (on your Fedora dev machine)

- Docker (Clickable uses it for cross-compiling)
- Clickable **8.4.0 or later** (needed for the 24.04-1.x framework):
  `pipx install clickable-ut` then `clickable update-images`
- Developer mode enabled on the phone, connected via USB (adb) or same
  network (ssh)

## Setup

```bash
cd voicenote
git init
git submodule add https://github.com/ggml-org/whisper.cpp libs/whisper.cpp
# Pin to a release tag for reproducible builds, e.g.:
# cd libs/whisper.cpp && git checkout v1.7.4 && cd ../..
```

Rename the app id: replace `voicenote.yourname` with your own
`appname.developername` in `manifest.json.in`, `qml/Main.qml`, and
`src/main.cpp`, and set the maintainer field in the manifest.

## Build & run

```bash
clickable build --arch arm64      # cross-compile + package the click
clickable install                 # push to the phone
clickable launch                  # start it
clickable logs                    # tail app output (very useful)
clickable desktop                 # run on your PC for fast UI iteration
```

Note: `clickable desktop` runs on x86_64 so whisper.cpp gets rebuilt for your
PC — handy, since you can test transcription locally too.

## First run

Tap "Download model" — it fetches `ggml-tiny.en.bin` (~75 MB) from Hugging
Face into the app's data directory. After that the app never needs the
network. To try the more accurate `base.en` (~142 MB), change `modelName`
(exposed as a property on the Transcriber; wire a settings toggle or edit
the default in `transcriber.h`).

You can also push a model manually instead of downloading:

```bash
scp ggml-tiny.en.bin phablet@<phone-ip>:.local/share/voicenote.yourname/models/
```

Notes are saved as plain text files in
`~/.local/share/voicenote.yourname/notes/` — greppable, syncable, no lock-in.

## Performance notes (Snapdragon 732G)

- First transcription includes ~1 s of model load; the context is cached
  after that.
- tiny.en handles a 5–10 s utterance in roughly the same few seconds.
  base.en is noticeably better on names/punctuation but slower.
- `n_threads = 4` in `transcriber.cpp` is a starting point (2×A76 + 6×A55);
  experiment with 2–6.
- Keep utterances short (< 15 s) for a snappy feel.

## Roadmap

**Phase 1 (this scaffold):** record → transcribe → save/copy notes.
Only needs `microphone`, `audio`, `networking` policy groups — no manual
OpenStore review hurdles.

**Phase 2 — intent parsing:** a small grammar over the transcript:
`call <name>`, `text <name> <message>`, `note <text>`,
`remind me <when> <what>` / `add event <...>`. Pure string logic, no new
permissions. For dates ("next Tuesday at 3"), a compact rule-based parser
is enough — no need for an LLM.

**Phase 3 — system integration:**
- Contacts: add the `contacts` policy group and use the QtContacts QML/C++
  API to fuzzy-match the spoken name, then
  `Qt.openUrlExternally("tel:+15551234567")` to pop the dialer, or
  `sms:`/`message:` URIs for the messaging app.
- Calendar: add the `calendar` policy group and insert events directly via
  QtOrganizer (cleaner than trying to drive the calendar app's UI).
- **OpenStore caveat:** `contacts` and `calendar` are *reserved* policy
  groups — submissions using them get flagged for manual human review.
  Plan to ship Phase 1/2 first, then add these with a justification in the
  submission notes.

**Ideas later:** a VAD (voice activity detection) auto-stop so you don't
have to hold the button; per-note tags ("note to wine: ..."); export via
Content Hub.

## Prior art worth reading

- **Speech Note (dsnote)** — open-source Qt/QML offline STT for Linux
  mobile; solves many of the same problems.
- whisper.cpp `examples/` — especially `stream` and `command` for
  low-latency tricks.

## Known rough edges in this scaffold

This scaffold was written blind (not compiled against the UT 24.04 SDK), so
expect small fixes: whisper.cpp API drift between releases
(`whisper_init_from_file_with_params` is current as of v1.5+), Lomiri
component property names, and the QAudioInput format negotiation. If the mic
delivers 48 kHz despite the requested format (check `clickable logs`),
downsample before handing PCM to whisper — PulseAudio normally resamples for
you, so this is unlikely but worth knowing.
