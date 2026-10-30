# RecordingCore / MeetRecKit

Design for a shared local recording module used by:

- **MeetRec.app** — thin audio-only client (today’s product; stays WAV-first, no video UI).
- **MeetSecretary Local** — session-dir product: compact audio default, optional HQ, optional screen-region video for CV speaker rings.

Extracted from MeetRec `Sources/main.swift` (AppKit UI + `Recorder` + RNNoise).  
Out of scope: TrueConf bot / contour, cloud upload, transcription engines themselves.

---

## Goals

1. One capture/mix/write core; two (or more) thin app shells.
2. Stable **session directory contract** for MeetSecretary Local v1.
3. Audio profiles: compact (default for MS), compromise, HQ (current MeetRec default).
4. Optional **panel region** → `video.mp4` without forcing MeetRec to ship video.
5. Preserve Screen Recording permission stickiness via **per-app bundle id + local codesign identity** (same pattern as «MeetRec Local»).

Non-goals for v1 of the module: live waveform UI, multi-display picker polish, AAC as the only container, rewriting RNNoise.

---

## Current MeetRec baseline (facts)

| Piece | Today |
| --- | --- |
| Output | Single `встреча-YYYY-MM-DD_HH-mm-ss.wav` under `~/Recordings/MeetRec/` |
| Format | 48 kHz, stereo, 16-bit PCM WAV |
| System audio | ScreenCaptureKit, 2×2 video discarded, audio kept |
| Mic | `AVAudioEngine` tap → convert → optional RNNoise → `.caf` |
| Mix | Float32 sum clamp → WAV |
| Bundle id | `local.leogo.MeetRec` |
| Signing | Local cert «MeetRec Local» (`scripts/ensure-sign-identity.sh`) |

MeetSecretary Local needs a **directory**, not a lone WAV, and different default sample geometry.

---

## Proposed package layout

Prefer SwiftPM library + Makefile (or Xcode) apps that depend on it. Do **not** big-bang rewrite `main.swift` until types below compile in isolation.

```
Packages/RecordingCore/          # or top-level Package.swift product «RecordingCore»
  Package.swift
  Sources/RecordingCore/
    AudioProfile.swift
    CaptureMode.swift
    MicDenoise.swift
    RecordingConfiguration.swift
    SessionDirectory.swift       # layout + meta.json writer
    AudioCapture/
      MicrophoneCapture.swift    # AVAudioEngine + converter + RNNoise
      SystemAudioCapture.swift   # SCStream audio-only (2×2 discard)
      AudioMixer.swift           # mix / downsample / encode
    VideoCapture/
      PanelRegionCapture.swift   # optional SCStream crop → AVAssetWriter mp4
    RecordingSession.swift       # public façade: start/stop
    RNNoise/                     # bridge + vendor link (keep MeetRec names or rename once)
  Tests/RecordingCoreTests/
Apps/
  MeetRec/                       # AppKit shell → RecordingSession(audio-only config)
  MeetSecretaryLocal/            # own bundle id; session-dir UI
```

**Near-term (this repo):** keep Makefile + `Sources/main.swift`; land this doc; extract types incrementally into `Sources/RecordingCore/` compiled by both `swiftc` and a future `Package.swift`. Full Package.swift split is **not** started here — ObjC bridge header + static RNNoise `.o` + AppKit `@main` make a naïve SPM move unsafe without a working dual build.

Suggested product name in code: **`RecordingCore`**. Marketing/kit name **`MeetRecKit`** can be a thin re-export module later if a second repo needs a branded import.

---

## Public types

### AudioProfile

```swift
public enum AudioProfile: String, Codable, Sendable {
    /// MeetSecretary Local default — Whisper-friendly, small on disk.
    case compact      // mono, 16 kHz, 16-bit WAV (or AAC — see Risks)
    /// Balanced size / quality for archival listening.
    case compromise   // mono or stereo, 24 kHz, 16-bit WAV
    /// Current MeetRec default.
    case hq           // stereo, 48 kHz, 16-bit WAV
}
```

Internal capture may still run at 48 kHz float for mix stability; **export** applies profile (resample / downmix / encode).

### CaptureMode

Same semantics as today:

```swift
public enum CaptureMode: String, Codable, Sendable {
    case microphone
    case system
    case both
}
```

### MicDenoise

Keep `off` / `light` / `strong` with the same mix factors (0 / 0.65 / 1). Apply **only** to mic path.

### CaptureMedia / PanelRegion

```swift
public enum CaptureMedia: String, Codable, Sendable {
    case audioOnly
    case audioAndPanelVideo   // MeetSecretary Local option
}

public struct PanelRegion: Codable, Sendable, Equatable {
    /// Display that owns the region (SCDisplay displayID).
    public var displayID: UInt32
    /// Global or display-local points; document coordinate space in API comments.
    public var rect: CGRect
    /// Target encode size (e.g. 960×540); nil = capture pixel size.
    public var outputSize: CGSize?
    public var framesPerSecond: Int  // e.g. 5–15 for CV rings, not 60
}
```

### RecordingConfiguration

```swift
public struct RecordingConfiguration: Sendable {
    public var mode: CaptureMode
    public var profile: AudioProfile
    public var denoise: MicDenoise
    public var media: CaptureMedia
    public var panel: PanelRegion?          // required if media == .audioAndPanelVideo
    public var sessionRoot: URL             // parent of session dirs
    public var excludesCurrentProcessAudio: Bool  // default true
}
```

MeetRec always uses `media: .audioOnly`, `profile: .hq` (until UI exposes profiles).  
MeetSecretary Local defaults: `profile: .compact`, optional panel.

---

## Session directory contract (MeetSecretary Local v1)

One recording = one directory:

```
~/Recordings/MeetSecretaryLocal/sess-YYYY-MM-DD_HH-mm-ss/
  audio.wav          # required (or audio.m4a if AAC profile — see Risks)
  video.mp4          # optional; panel region only
  meta.json          # required
  transcript.*       # written by consumer (json/txt/vtt); core may leave stubs empty
  protocol.md        # written by consumer / pipeline; core does not author content
```

MeetRec may keep writing a flat `встреча-….wav` via a **compatibility writer**, or optionally adopt the same session dir with only `audio.wav` + minimal `meta.json`.

### `meta.json` sketch

```json
{
  "schemaVersion": 1,
  "product": "MeetSecretaryLocal",
  "startedAt": "2026-10-30T12:00:00Z",
  "endedAt": "2026-10-30T12:45:00Z",
  "durationSec": 2700.0,
  "captureMode": "both",
  "audioProfile": "compact",
  "audio": { "path": "audio.wav", "sampleRate": 16000, "channels": 1, "codec": "pcm_s16le" },
  "video": { "path": "video.mp4", "displayID": 1, "region": [100, 80, 1280, 720], "fps": 10 },
  "denoise": "light",
  "bundleId": "local.leogo.MeetSecretaryLocal"
}
```

`video` key omitted when audio-only.

### SessionDirectory writer API sketch

```swift
public struct SessionArtifacts: Sendable {
    public var audioURL: URL
    public var videoURL: URL?
    public var metaURL: URL
}

public final class SessionDirectory {
    public let url: URL
    public init(root: URL, stamp: Date = Date()) throws
    public func writeMeta(_ meta: SessionMeta) throws
    public func finalize() throws -> SessionArtifacts
}
```

Core owns: create dir, write `audio.*` / optional `video.mp4`, write/update `meta.json`.  
Apps own: `transcript.*`, `protocol.md`, naming of parent folder.

---

## RecordingSession façade (API sketch)

```swift
public final class RecordingSession {
    public private(set) var isRecording: Bool { get }

    public init(configuration: RecordingConfiguration)

    public func start() async throws
    public func stop() async throws -> SessionArtifacts

    /// MeetRec compatibility: mix to a single WAV URL (no session dir).
    public func stopToSingleWAV(named name: String) async throws -> URL
}
```

Internals:

1. Create session folder (or temp for MeetRec single-file path).
2. Start mic and/or system audio writers (`.caf` intermediates OK).
3. If panel video: start `PanelRegionCapture` on a **separate** SCStream (see Risks) or shared stream if proven safe.
4. On stop: stop streams, flush RNNoise, mix/resample to profile, write `audio.wav`, finish `video.mp4`, write `meta.json`, delete intermediates.

---

## Capture architecture

```
                    ┌─────────────────────┐
  Mic ──AVAudioEngine──► MicDenoiser? ──► mic.caf
                    └─────────────────────┘
                                                    ┌──────────────┐
  System ──SCStream(audio)──► system.caf ──────────►│ AudioMixer   │──► audio.wav / .m4a
                                                    │ (profile)    │
  Display/region ──SCStream(screen)──► AVAssetWriter┘──────────────┘
                                              optional video.mp4
```

- **System audio path:** keep today’s pattern (tiny frame interval, discard frames, `capturesAudio = true`).
- **Panel video path:** `SCContentFilter` + crop/`sourceRect` (or equivalent) at low FPS; **do not** mux meeting audio into the MP4 by default — audio stays in `audio.wav` for Whisper/ASR; video is for CV rings only.
- **Exclude self:** `excludesCurrentProcessAudio` + filter out own bundle id apps (today’s MeetRec behavior).

---

## Signing & permissions (both apps)

| App | Bundle id | Local signing identity | Notes |
| --- | --- | --- | --- |
| MeetRec | `local.leogo.MeetRec` | «MeetRec Local» | Unchanged |
| MeetSecretary Local | e.g. `local.leogo.MeetSecretaryLocal` | e.g. «MeetSecretary Local» | Same script pattern; **own** cert + Keychain entries so TCC Screen Recording sticks across rebuilds |

Permissions are **per bundle id**. Sharing RecordingCore source does **not** share TCC grants. MeetRec.app remains audio-only in UI; MS Local may request screen content for region video (usage strings must say so).

---

## Risks

### 1. Region + audio on SCStream

ScreenCaptureKit allows audio + screen on one stream, but MeetRec today uses a 2×2 discard stream optimized for audio. A cropped high-res region for CV may want different `minimumFrameInterval`, color, and queue priorities.

**Risk:** one stream fighting two jobs (drop audio glitches vs. drop video frames).  
**Mitigation:** prefer **two SCStreams** (audio-only 2×2 + region video-only) in v1; measure CPU and permission prompts. If two streams prove flaky, fall back to one stream with audio + region video and validate A/V sync clocks via `CMSampleBuffer` timestamps in `meta.json`.

### 2. AAC vs WAV for Whisper

Compact profile may tempt AAC/`m4a` for disk. Local Whisper / whisper.cpp pipelines typically prefer **PCM WAV 16 kHz mono**. AAC adds decode step, possible encoder delay, and worse seek/debug.

**Recommendation:** default compact = **WAV 16 kHz mono PCM**; offer AAC only as an explicit “archive small” export, not as the ASR input file. Session contract keeps `audio.wav` as the canonical ASR asset.

### 3. Clock skew mic vs system vs video

Separate engines/streams → start skew and drift. MeetRec already mixes without explicit A/V sync. For CV rings, document that `video.mp4` timeline is best-effort aligned to session `startedAt`; optional future: embed `syncOffsetMs` in `meta.json` after measuring first buffers.

### 4. RNNoise + mono compact

Denoiser currently collapses to mono then upmixes to stereo HQ. Compact mono export is a natural fit; ensure export does not stereo-upmix then downmix again (quality/CPU waste).

### 5. SPM vs Makefile

RNNoise C sources + bridging header + codesign identity script are Makefile-centric. A Package.swift without a working `swift build` / CI on macOS risks a half-migrated tree. Extract library files first; add Package.swift when `RecordingCore` compiles without AppKit `@main`.

---

## Migration plan

### Phase A — design (this PR)

- Land `docs/RECORDING_CORE.md`.
- No behavior change. No Package.swift yet.

### Phase B — extract types inside MeetRec (same repo)

- Move `CaptureMode`, `MicDenoise`, `Recorder`, `MicDenoiser` into `Sources/RecordingCore/*.swift`.
- Makefile lists those files; AppDelegate stays in `main.swift`.
- Add `AudioProfile` + export resample path; MeetRec default remains `.hq`.

### Phase C — session writer

- Implement `SessionDirectory` + `meta.json`.
- Optional MeetRec flag or MeetSecretary prototype target writing session dirs.
- Extend `.gitignore` for `*.mp4` / `*.m4a` (never commit media).

### Phase D — PanelRegionCapture

- Video-only SCStream + `AVAssetWriter`.
- Wire only behind MeetSecretary Local UI / config.

### Phase E — product split decision

See next section.

---

## Next steps: «new repo» vs «evolve MeetRec»

### Evolve MeetRec (recommended short term)

**Do this while RecordingCore is still taking shape.**

- Pros: one place for SCStream quirks, RNNoise vendor, signing scripts, real-device permission testing; MeetRec stays the smoke-test client.
- Cons: repo name/README still say “audio-only WAV”; need clear folder boundaries so MS Local UI does not leak into MeetRec.
- Action: Phases B–D in this repo; add a second app target / Makefile product `MeetSecretaryLocal.app` with its own `Info.plist` and signing identity when UI work starts.

### New repo (MeetSecretary Local + RecordingCore package)

**Do this once the session contract and dual-stream capture are proven on a Mac.**

- Pros: clean product identity, separate releases, MeetRec can stay tiny forever; RecordingCore as Swift package dependency (git submodule or published package).
- Cons: duplicate signing/docs until package is stable; two CI/macOS test surfaces; risk of forking capture bugfixes.
- Action: carve `Packages/RecordingCore` into `github.com/Leo-go/RecordingCore` (or MeetRecKit); MeetRec and MeetSecretary Local both depend on a tagged version.

### Practical recommendation

1. **Evolve MeetRec** through Phase C (session dir + profiles) with MeetRec.app still the thin audio client.  
2. Prototype panel video in-tree behind a flag.  
3. When MS Local UI + ASR pipeline need their own release cadence, **extract RecordingCore to a new repo** and leave MeetRec as a thin consumer — not before.

---

## Explicit non-touch list

- TrueConf bot / contour codepaths (not in this repo today — keep it that way).
- Do not commit `*.wav`, `*.caf`, `*.mp4`, `*.m4a`, or signing keys.
- Do not force-push; do not merge without human review.
