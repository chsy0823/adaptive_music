## Unreleased

- High-shelf filtering with smooth frequency/gain changes and native output tests.
- Listening lab comparison of original, low-pass and high-shelf tone.
- Lazy native-engine initialization so unloaded widgets work in headless tests.
- Contributor guide and code ownership.

## [0.2.0](https://github.com/chsy0823/adaptive_music/compare/v0.1.0...v0.2.0) (2026-09-23)


### Features

* add cue windows and priority-based music ducking ([cef814e](https://github.com/chsy0823/adaptive_music/commit/cef814e4bf9a147324729611c2145e5181189192))
* add cue windows and priority-based music ducking ([b69ebb3](https://github.com/chsy0823/adaptive_music/commit/b69ebb3f1a4923bfccdfc42a847710a26d863b45))
* add high-shelf tone controls and contribution rules ([#1](https://github.com/chsy0823/adaptive_music/issues/1)) ([085261b](https://github.com/chsy0823/adaptive_music/commit/085261bc1b4b3030d46745cb977f62a4181057f6))
* allow per-command track transition overrides ([8f9ea9b](https://github.com/chsy0823/adaptive_music/commit/8f9ea9bb79b41efd8db18c0ee81d2f865aa69d23))
* configure same-track repeat crossfade duration ([63e512b](https://github.com/chsy0823/adaptive_music/commit/63e512bfdb5c836deefa468e4f8773a7c011e34c))


### Bug Fixes

* bound overlapping voices during rapid track skips ([e7a7fb0](https://github.com/chsy0823/adaptive_music/commit/e7a7fb01728d7ae61813af64b4db325389e9afb7))
* coalesce rapid track skips during crossfades ([ab6af84](https://github.com/chsy0823/adaptive_music/commit/ab6af842acb9e6a88a64642688eeb9ae2a3bfcf4))
* keep music envelopes running during UI stalls and recover transport ([e2a5b6c](https://github.com/chsy0823/adaptive_music/commit/e2a5b6c44b3e7bb6ee926b7f6575e9564127d4d0))

## 0.1.0

- Single-track and playlist playback, resume/restart, and repeat modes.
- Pre-scheduled gapless playback and linear/equal-power crossfades.
- Smooth volume, pause/resume, and low-pass filter transitions.
- Independent player buses, observable state, and deterministic transport tests.
- Flutter listening lab with original demo loops and local-file selection.
- macOS native output regression test for continuity and low-pass attenuation.
