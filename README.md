# Adaptive Music

A Flutter music player for games and interactive apps. Keep music moving while
changing its volume and tone: playlists, gapless scheduling, crossfades, smooth
pause/resume, and real-time low-pass filtering.

Built on [flutter_soloud](https://pub.dev/packages/flutter_soloud). The package
contains no exercise, scene, or game-state concepts.

**Status:** initial 0.1 implementation. macOS playback and DSP have an automated
native output test. macOS, Android debug APK, and iOS simulator builds have been verified.
Physical-device listening and interruption testing remain necessary. Web is not supported in this
version (the file backend uses `dart:io`).

## Try the listening lab

```sh
git clone https://github.com/chsy0823/adaptive_music.git
cd adaptive_music/example
flutter pub get
flutter run -d macos
```

Select an Android/iOS device instead of `macos` to run there. Configure your own
iOS signing team. The example includes three original 120 BPM synthesized loops,
plus an **Open audio** button for your own files. Use **Apply playlist setup** after
changing repeat/crossfade settings; this prepares the playlist again and stops
playback. Volume, filter, and control fades change live.

## Install from Git

```yaml
dependencies:
  adaptive_music:
    git:
      url: https://github.com/chsy0823/adaptive_music.git
```

Requires Dart 3.11 or later and a compatible Flutter SDK. This repository is not
yet published to pub.dev. The current backend targets `flutter_soloud` 4.x.

## Use

```dart
import 'package:adaptive_music/adaptive_music.dart';

final music = AdaptiveMusicPlayer(
  transitions: const TransitionDefaults.smooth(
    volume: Duration(milliseconds: 400),
    play: Duration(milliseconds: 500),
    pause: Duration(milliseconds: 500),
    filter: Duration(milliseconds: 700),
  ),
);

await music.load(
  tracks: const [
    MusicTrack.asset('assets/music/a.wav', title: 'First track'),
    MusicTrack.asset('assets/music/b.wav', title: 'Second track'),
  ],
  repeat: MusicRepeatMode.all,
  transition: const TrackTransition.crossfade(
    duration: Duration(seconds: 3),
    curve: FadeCurve.equalPower,
  ),
);

music.play(); // Resume; initially starts the first track.
music.setVolume(0.4); // Retarget from the current audible level.
music.setFilter(const LowPassFilter(cutoffHz: 1200));
music.clearFilter(); // Smooth wet/dry transition back to the original audio.
music.pause(); // Fade out, then freeze the overlapping voices and timeline.
music.play(); // Resume the same overlap and fade back to the user's volume.
music.play(start: PlaybackStart.restartTrack);
music.next();
music.skipTo(0);
music.stop(); // Immediately stop and rewind the playlist.

await music.dispose();
```

Declare asset paths in the host app's `pubspec.yaml`. `MusicTrack.file` and
`MusicTrack.url` are also available. URLs are downloaded completely before
playback; they are not live streams.

## Playback contract

| Setting | Behavior |
| --- | --- |
| `MusicRepeatMode.none` | Play the list once, then report `completed` |
| `MusicRepeatMode.one` | Repeat the selected track |
| `MusicRepeatMode.all` | Repeat the entire list |
| `TrackTransition.gapless()` | Schedule the next track at the previous track's end |
| `TrackTransition.crossfade(...)` | Overlap adjacent tracks; also applies when repeating one track |
| `PlaybackStart.resume` | Resume where playback paused; after completion, start the list again |
| `PlaybackStart.restartTrack` | Start the current track from the beginning |

Crossfade duration is capped at half the duration of each neighboring track.
Manual skips fade all currently audible voices into the selected track. A skip
while paused selects the new track without starting playback. `next()` at the
end of a non-repeating playlist is a no-op; in a repeating playlist it wraps.

`TransitionDefaults.immediate()` disables default command smoothing. Individual
calls accept a `transition` override, including `Duration.zero`. These defaults
are independent of the playlist's crossfade/gapless setting. `stop()` is always
immediate. Commands return when accepted, not when a fade finishes.

Pause playback continues during its fade-out. Its final paused position is the
position at fade completion. A new `play()` during that fade cancels the pending
pause and fades upward from the current gain. User volume is preserved separately
from pause and crossfade envelopes.

```dart
final subscription = music.states.listen((state) {
  // status, index, position, duration, overlapping, volume, error
  // During a crossfade, index/position describe the incoming track.
});

music.pause(transition: Duration.zero);
// Later:
await subscription.cancel();
```

Read `music.state` for the current snapshot. Invalid arguments/state throw
synchronously. Load failures complete the load future with an error; runtime
failures appear as `PlaybackStatus.failed` with `state.error`. Reload to recover.
Calling playback methods during a load is rejected. Disposal waits for an ongoing
load and is idempotent.

## DSP and continuity

Each player has its own mixing bus. Low-pass settings affect its overlapping and
future tracks, without filtering other players. Cutoff accepts 10–16000 Hz and
resonance 0.1–20. Filter removal smoothly reduces the wet contribution to zero;
the bypassed filter stays allocated until player disposal so rapid toggles are
safe. Low-pass is the only exposed filter in this first version.

Sources are fully decoded into memory during `load` to avoid network or decoder
work at a transition. Budget memory accordingly: stereo float PCM uses roughly
21 MB per minute at 44.1 kHz, per track, beyond compressed download buffers.
For large music catalogs, load a bounded playlist.

Track starts use the native engine's sample-accurate scheduler. The player keeps
up to three successors queued ahead. Crossfade and control envelopes are updated
on a 10 ms Dart control tick with native gain smoothing; filter interpolation runs
in the native DSP engine. This is not a hard real-time scheduler: a blocked or
suspended Dart isolate can delay fades, pause completion, and queue replenishment.
The initial play reserves approximately 40 ms of scheduling lead-in.

Gapless describes the engine boundary, not silence embedded in a recording.
Crossfade does not align beats, normalize loudness, or perform tempo matching.
Equal-power overlap can increase peaks, especially on correlated material; use
tracks with headroom and conservative gain. Linear crossfade is also available.

The host owns OS audio-session policy, interruptions, background execution, and
headphone routing. The example pauses when backgrounded. The library does not
shut down the shared SoLoud engine when a player is disposed.

## Repository

```text
lib/                         Public API and native backend
test/                        Deterministic transport and envelope tests
example/lib/                 Listening lab
example/assets/audio/        Original generated demo loops
example/integration_test/    Native mixer-output verification
tool/generate_demo_audio.py   Reproducible demo asset generator
```

## Verify

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test example/lib example/test example/integration_test
flutter analyze
flutter test
cd example
flutter test
flutter test integration_test/audio_test.dart -d macos
flutter build macos --debug
```

The native test plays low-volume synthetic tones. It checks non-silent windows
across crossfade and gapless boundaries, pause/resume, and attenuation/restoration
of a 6 kHz tone with a 500 Hz low-pass filter. It is a signal-level regression
test, not a substitute for listening on supported physical devices.

## License

MIT, including the original generated demo audio. Dependencies retain their own
licenses; see [THIRD_PARTY.md](THIRD_PARTY.md).
