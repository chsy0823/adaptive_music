import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_music/adaptive_music.dart';
import 'player_test.dart' show FakeBackend;

class DelayedStopBackend extends FakeBackend {
  final failedStop = Completer<void>();
  bool hold = true;
  @override
  Future<void> stop(int voice) {
    if (hold) {
      hold = false;
      return failedStop.future;
    }
    return super.stop(voice);
  }
}

void main() {
  test(
    'repeat stays playing after the scheduling horizon is exhausted',
    () async {
      final backend = FakeBackend();
      final player = AdaptiveMusicPlayer.withBackend(
        backend,
        automaticTick: false,
      );
      await player.load(
        tracks: const [MusicTrack.asset('a')],
        repeat: MusicRepeatMode.all,
      );
      player.play();
      backend.now = 60000000;
      player.tick();
      final status = player.state.status;
      await player.dispose();
      expect(status, PlaybackStatus.playing);
    },
  );
  for (final repeat in MusicRepeatMode.values) {
    test('stalled $repeat timeline matches uninterrupted playback', () async {
      final fast = FakeBackend();
      final stalled = FakeBackend();
      final reference = AdaptiveMusicPlayer.withBackend(
        fast,
        automaticTick: false,
      );
      final recovering = AdaptiveMusicPlayer.withBackend(
        stalled,
        automaticTick: false,
      );
      addTearDown(reference.dispose);
      addTearDown(recovering.dispose);
      for (final player in [reference, recovering]) {
        await player.load(
          tracks: const [
            MusicTrack.asset(
              'a',
              cueIn: Duration(seconds: 1),
              cueOut: Duration(seconds: 3),
            ),
            MusicTrack.asset('b', cueOut: Duration(seconds: 5)),
            MusicTrack.asset(
              'c',
              cueIn: Duration(seconds: 2),
              cueOut: Duration(seconds: 9),
            ),
          ],
          repeat: repeat,
          transition: const TrackTransition.crossfade(
            duration: Duration(milliseconds: 700),
          ),
        );
        player.play(transition: Duration.zero);
      }
      for (final elapsed in [40300000, 43700000, 80900000]) {
        while (fast.now < elapsed) {
          fast.now += 100000;
          reference.tick();
        }
        stalled.now = elapsed;
        recovering.tick();
        expect(recovering.state.status, reference.state.status);
        expect(recovering.state.index, reference.state.index);
        expect(recovering.state.position, reference.state.position);
        expect(recovering.state.overlapping, reference.state.overlapping);
        if (repeat != MusicRepeatMode.none) {
          final voices = stalled.starts.entries.where(
            (v) => v.value.$2 <= elapsed,
          );
          expect(voices, isNotEmpty);
          for (final voice in voices) {
            expect(stalled.windows[voice.key]!.$2, greaterThan(Duration.zero));
          }
        }
      }
    });
  }
  test('current playlist stop errors still report failure', () async {
    final backend = DelayedStopBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
    );
    addTearDown(player.dispose);
    await player.load(
      tracks: const [MusicTrack.asset('a'), MusicTrack.asset('b')],
    );
    player.play();
    backend.now = 11000000;
    player.tick();
    backend.failedStop.completeError(StateError('current voice stop failed'));
    await Future<void>.delayed(Duration.zero);
    expect(player.state.status, PlaybackStatus.failed);
  });
  test(
    'an old asynchronous stop failure cannot fail a replacement playlist',
    () async {
      final backend = DelayedStopBackend();
      final player = AdaptiveMusicPlayer.withBackend(
        backend,
        automaticTick: false,
      );
      await player.load(tracks: const [MusicTrack.asset('a')]);
      player.play();
      player.stop();
      await player.load(tracks: const [MusicTrack.asset('b')]);
      player.play();
      backend.failedStop.completeError(StateError('old voice stop failed'));
      await Future<void>.delayed(Duration.zero);
      final status = player.state.status;
      await player.dispose();
      expect(status, PlaybackStatus.playing);
    },
  );
}
