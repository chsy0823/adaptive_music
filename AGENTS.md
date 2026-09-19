# AI contributor guide

This guide applies to the whole repository. Read [CONTRIBUTING.md](CONTRIBUTING.md)
for contribution, verification, review and licensing requirements, and
[README.md](README.md) for the public playback contract before changing behavior.

## Scope and structure

Adaptive Music is a general-purpose Flutter audio library. Exercise scenes,
game states, speech classification and other application policy belong in host
apps, not in the library. The example is a standalone listening lab using the
package through a local path dependency.

| Path | Responsibility |
| --- | --- |
| `lib/adaptive_music.dart` | Public exports |
| `lib/src/models.dart` | Public configuration and playback state |
| `lib/src/player.dart` | Playlist, transport, cue windows and ducking policy |
| `lib/src/envelope.dart` | Gain calculations shared with audio control |
| `lib/src/audio_backend.dart` | Internal backend seam for deterministic tests |
| `lib/src/soloud_backend.dart` | Native voices, source loading, per-player bus and DSP |
| `lib/src/gain_worker.dart` | Gain automation independent of the host UI isolate |
| `test/` | Deterministic transport and envelope regressions |
| `example/lib/` and `example/test/` | Listening lab and widget tests |
| `example/integration_test/` | Native mixer-output tests using synthetic tones |

## Before and during a change

1. Inspect the current branch, worktree and diff. Preserve unrelated work. Use a
   topic branch for contributions; do not make changes directly on `main`.
2. Read the affected implementation and nearby tests. State the expected behavior
   and verification approach before editing. Surface ambiguity in public behavior
   rather than silently changing the playback contract.
3. For a bug fix, reproduce it with a failing regression test, then implement the
   smallest correction. Keep unrelated refactors and dependency changes out.
4. Update public API documentation and the listening lab when their behavior or
   usage changes. Keep this path map current when moving the listed modules.

## Audio boundaries to preserve

- Keep user volume, ducking and transport/crossfade gains independent; releasing
  one ducking request must not erase another active request or the user's volume.
- Preserve overlapping voices and their positions across pause/resume. Evaluate
  continuity at cue and repeat boundaries, not just at the decoded file's end.
- Keep queued gain automation independent of host UI ticks. The bounded scheduling
  horizon and suspension limits are documented in README; do not claim unlimited
  gapless playback or hard real-time guarantees.
- Each player owns its sources and mixing bus. Filters must not affect other
  players, and disposing a player must not shut down the shared SoLoud engine.
- Keep native loading and playback registration on the host isolate. The gain
  worker uses SoLoud's public experimental isolate bindings only for mixer control;
  check that boundary when updating the dependency.
- Guard asynchronous completion against replaced playback state. Verify that
  genuine errors in the current playback still reach the caller or state stream.

## Verification and handoff

Run the relevant commands in [CONTRIBUTING.md — Verify locally](CONTRIBUTING.md#verify-locally).
For transport or DSP changes, run both native output suites in addition to unit
and example tests. CI currently runs Dart checks and a macOS build; it does not
run the native mixer-output tests. Report unavailable platform checks explicitly,
and distinguish signal-level test results from listening on physical devices.
For documentation-only changes, verify referenced paths, commands and diff hygiene;
there is no need to replay audio tests unless behavior also changed.

Open or update the contribution PR against `main`. Summarize the resulting
behavior, tests actually run, and remaining limitations so a human can review it.
Do not merge, enable auto-merge, bypass branch protection, publish a release or
change repository permissions unless the maintainer explicitly requests that
specific action. A request to implement, commit or push is not permission to merge.
