# Contributing

Adaptive Music is a general-purpose Flutter music/DSP library. Keep exercise,
game-state and other application policy in host apps.

For AI-assisted contributions, start with [AGENTS.md](AGENTS.md).
`CLAUDE.md` imports the same guide so the instructions have one source.

## Propose a change

Open an issue for substantial API or architecture changes. For a focused fix,
fork this repository, create a topic branch and open a pull request against
`main`. Describe the problem, resulting behavior, and how you verified it.
Keep changes focused; include a regression test for behavior changes and update
API documentation and the listening lab when relevant.

Public visibility permits reading, cloning and forking; it does not grant push
access to this repository. External contributions arrive through fork PRs.

## Verify locally

Use a stable Flutter SDK supporting Dart 3.11 or later.

```sh
flutter pub get
cd example
flutter pub get
cd ..
dart format --output=none --set-exit-if-changed lib test example/lib example/test example/integration_test
flutter analyze
flutter test
cd example
flutter test
flutter build macos --debug
flutter test integration_test/audio_test.dart -d macos
flutter test integration_test/stalled_ui_test.dart -d macos
```

Native output tests require macOS and play quiet synthetic tones. Run them for
DSP or transport changes. Also listen using the example on affected platforms;
unit tests and a successful build cannot establish perceived audio quality.

## Review and protected main

`@chsy0823` owns all paths, including workflows and CODEOWNERS. Contributors need
a PR, one approving code-owner review, resolved review conversations, and passing
`dart` and `macos-build` checks against the latest main. New reviewable commits
invalidate previous approvals.

Only `@chsy0823` has an explicit PR-rule bypass. CODEOWNERS does not itself grant
push or bypass permission; adding another owner does not add that exception.
The separate integrity rule has no bypass: everyone must pass CI, and nobody
may force-push or delete main. The owner can fast-forward main to a commit that
already passed checks on a topic branch. Ordinary PRs are preferred.

GitHub rulesets enforce these rules; this document alone does not. Changing
repository settings requires administrator permission. External fork workflow
runs may require maintainer approval before CI starts.

## Audio and licensing

Contributions are under this repository's MIT license. Only commit audio you
have the rights to distribute under that license. Do not commit personal music,
credentials, signing files or generated builds. The included demo loops can be
regenerated with `python3 tool/generate_demo_audio.py`.
