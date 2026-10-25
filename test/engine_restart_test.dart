import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_music/adaptive_music.dart';
import 'player_test.dart' show FakeBackend;

class GatedLoadBackend extends FakeBackend {
  Completer<void>? gate;
  @override
  Future<Duration> load(MusicTrack track, int index) async {
    await gate?.future;
    return super.load(track, index);
  }
}

class FailingReloadBackend extends FakeBackend {
  @override
  Future<Duration> load(MusicTrack track, int index) async {
    // Only the rebuild after the restart fails; a later load succeeds again.
    if (initializations == 2) throw StateError('decoder unavailable');
    return super.load(track, index);
  }
}

/// Fakes the engine restart: SoLoud's clock begins again from zero.
Future<void> Function() rebooting(List<FakeBackend> backends, List<int> log) =>
    () async {
      for (final backend in backends) {
        backend.now = 0;
      }
      log.add(backends.first.now);
    };

void main() {
  const tracks = [
    MusicTrack.asset('a', cueIn: Duration(seconds: 1)),
    MusicTrack.asset('b'),
  ];

  test(
    'a playing player resumes its track, position, gains and filter',
    () async {
      final backend = FakeBackend();
      final player = AdaptiveMusicPlayer.withBackend(
        backend,
        transitions: const TransitionDefaults.immediate(),
        automaticTick: false,
      );
      final statuses = <PlaybackStatus>[];
      final subscription = player.states.listen((s) => statuses.add(s.status));
      await player.load(
        tracks: tracks,
        repeat: MusicRepeatMode.all,
        transition: const TrackTransition.gapless(),
      );
      player.setVolume(0.5);
      player.setFilter(const LowPassFilter(cutoffHz: 800));
      player.requestDucking(gain: 0.3);
      player.play();
      backend.now = backend.starts.values.first.$2 + 3000000;
      player.tick();
      expect(player.state.position, const Duration(seconds: 3));
      final restarts = <int>[];

      await AdaptiveMusicPlayer.restartEngineWith(
        rebooting([backend], restarts),
      );

      expect(restarts, [0]);
      expect(statuses, contains(PlaybackStatus.loading));
      expect(backend.disposals, 1);
      expect(backend.initializations, 2);
      expect(backend.loads, 4);
      expect(player.state.status, PlaybackStatus.playing);
      expect(player.state.index, 0);
      expect(player.state.position, const Duration(seconds: 3));
      expect(player.state.duration, const Duration(seconds: 9));
      expect(player.state.volume, 0.5);
      expect(backend.lastFilter, isA<LowPassFilter>());
      expect((backend.lastFilter! as LowPassFilter).cutoffHz, 800);
      expect(backend.filterTransition, Duration.zero);
      // The first voice resumes 3 s into the cue window after a 40 ms lead-in.
      final first = backend.starts.entries.first;
      expect(first.value, (0, 40000));
      expect(backend.windows[first.key], (
        const Duration(seconds: 4),
        const Duration(seconds: 6),
      ));
      expect(backend.gains[first.key], closeTo(0.15, 1e-9));
      // Successors are queued relative to the resumed timeline.
      expect(backend.starts.length, 4);
      backend.now = 6000000 + 40000;
      player.tick();
      expect(player.state.index, 1);
      expect(player.state.position, Duration.zero);
      await subscription.cancel();
      await player.dispose();
    },
  );

  test('a paused player stays paused and resumes from its position', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      transitions: const TransitionDefaults.immediate(),
      automaticTick: false,
    );
    await player.load(tracks: tracks);
    player.play();
    backend.now = backend.starts.values.first.$2 + 2000000;
    player.tick();
    player.pause();
    player.tick();
    expect(player.state.status, PlaybackStatus.paused);

    await AdaptiveMusicPlayer.restartEngineWith(rebooting([backend], []));

    expect(player.state.status, PlaybackStatus.paused);
    expect(player.state.position, const Duration(seconds: 2));
    expect(backend.starts, isEmpty);
    backend.now = 500000;
    player.play();
    expect(player.state.status, PlaybackStatus.playing);
    expect(player.state.position, const Duration(seconds: 2));
    final voice = backend.starts.entries.first;
    expect(voice.value, (0, 500000));
    expect(backend.windows[voice.key], (
      const Duration(seconds: 3),
      const Duration(seconds: 7),
    ));
    await player.dispose();
  });

  test('a pause still fading completes as paused', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
    );
    await player.load(tracks: tracks);
    player.play(transition: Duration.zero);
    backend.now = backend.starts.values.first.$2 + 1000000;
    player.tick();
    player.pause(transition: const Duration(seconds: 1));
    expect(player.state.status, PlaybackStatus.pausing);

    await AdaptiveMusicPlayer.restartEngineWith(rebooting([backend], []));

    expect(player.state.status, PlaybackStatus.paused);
    expect(player.state.position, const Duration(seconds: 1));
    await player.dispose();
  });

  test('ready, completed and empty players keep their status', () async {
    final ready = FakeBackend();
    final completed = FakeBackend();
    final empty = FakeBackend();
    final players = [
      AdaptiveMusicPlayer.withBackend(ready, automaticTick: false),
      AdaptiveMusicPlayer.withBackend(completed, automaticTick: false),
      AdaptiveMusicPlayer.withBackend(empty, automaticTick: false),
    ];
    await players[0].load(tracks: tracks);
    players[0].skipTo(1);
    await players[1].load(tracks: const [MusicTrack.asset('a')]);
    players[1].play(transition: Duration.zero);
    completed.now = 11000000;
    players[1].tick();
    expect(players[1].state.status, PlaybackStatus.completed);

    await AdaptiveMusicPlayer.restartEngineWith(
      rebooting([ready, completed, empty], []),
    );

    expect(players[0].state.status, PlaybackStatus.ready);
    expect(players[0].state.index, 1);
    expect(players[1].state.status, PlaybackStatus.completed);
    expect(players[1].state.position, const Duration(seconds: 10));
    expect(players[2].state.status, PlaybackStatus.empty);
    expect(empty.initializations, 0);
    expect(ready.initializations, 2);
    expect(completed.initializations, 2);
    for (final player in players) {
      await player.dispose();
    }
  });

  test('commands and loads are rejected while the engine restarts', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
    );
    await player.load(tracks: tracks);
    player.play(transition: Duration.zero);
    final engine = Completer<void>();
    final restart = AdaptiveMusicPlayer.restartEngineWith(() => engine.future);
    expect(player.state.status, PlaybackStatus.loading);
    expect(player.play, throwsStateError);
    expect(player.pause, throwsStateError);
    expect(() => player.skipTo(1), throwsStateError);
    expect(() => player.load(tracks: tracks), throwsStateError);
    player.setVolume(0.2, transition: Duration.zero);
    engine.complete();
    await restart;
    expect(player.state.status, PlaybackStatus.playing);
    expect(player.state.volume, 0.2);
    // The default play fade brings the resumed voice up over 500 ms.
    expect(backend.gains.values.first, 0);
    backend.now = 500000;
    player.tick();
    expect(backend.gains.values.first, closeTo(0.2, 1e-9));
    await player.dispose();
  });

  test('concurrent restarts share one engine restart', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
    );
    await player.load(tracks: tracks);
    var restarts = 0;
    Future<void> restart() async => restarts++;
    await Future.wait([
      AdaptiveMusicPlayer.restartEngineWith(restart),
      AdaptiveMusicPlayer.restartEngineWith(restart),
    ]);
    expect(restarts, 1);
    expect(backend.initializations, 2);
    await AdaptiveMusicPlayer.restartEngineWith(restart);
    expect(restarts, 2);
    await player.dispose();
  });

  test('a load in flight finishes and its playlist is rebuilt', () async {
    final backend = GatedLoadBackend()..gate = Completer<void>();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
    );
    final load = player.load(tracks: tracks);
    final restart = AdaptiveMusicPlayer.restartEngineWith(() async {});
    await Future<void>.delayed(Duration.zero);
    expect(backend.disposals, 0);
    backend.gate!.complete();
    backend.gate = null;
    await load;
    await restart;
    expect(player.state.status, PlaybackStatus.ready);
    expect(player.tracks, hasLength(2));
    expect(backend.disposals, 1);
    expect(backend.loads, 4);
    await player.dispose();
  });

  test('disposal during a restart completes without rebuilding', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
    );
    await player.load(tracks: tracks);
    player.play(transition: Duration.zero);
    final engine = Completer<void>();
    final restart = AdaptiveMusicPlayer.restartEngineWith(() => engine.future);
    final disposal = player.dispose();
    engine.complete();
    await restart;
    await disposal;
    expect(player.state.status, PlaybackStatus.disposed);
    expect(backend.initializations, 1);
    expect(backend.loads, 2);
  });

  test('a failed reload reports failure and leaves others playing', () async {
    final failing = FailingReloadBackend();
    final healthy = FakeBackend();
    final broken = AdaptiveMusicPlayer.withBackend(
      failing,
      automaticTick: false,
    );
    final fine = AdaptiveMusicPlayer.withBackend(healthy, automaticTick: false);
    await broken.load(tracks: tracks);
    await fine.load(tracks: tracks);
    broken.play(transition: Duration.zero);
    fine.play(transition: Duration.zero);

    await AdaptiveMusicPlayer.restartEngineWith(
      rebooting([failing, healthy], []),
    );

    expect(broken.state.status, PlaybackStatus.failed);
    expect(broken.state.error, isStateError);
    expect(fine.state.status, PlaybackStatus.playing);
    await broken.load(tracks: const [MusicTrack.asset('c')]);
    expect(broken.state.status, PlaybackStatus.ready);
    await broken.dispose();
    await fine.dispose();
  });

  test('an engine restart error fails the rebuilt players', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
    );
    await player.load(tracks: tracks);
    player.play(transition: Duration.zero);
    await expectLater(
      AdaptiveMusicPlayer.restartEngineWith(
        () async => throw StateError('engine stuck'),
      ),
      throwsStateError,
    );
    expect(player.state.status, PlaybackStatus.failed);
    expect(player.state.error, isStateError);
    expect(backend.initializations, 1);
    await player.dispose();
  });

  test('a crossfade in progress resumes with the incoming track', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      transitions: const TransitionDefaults.immediate(),
      automaticTick: false,
    );
    await player.load(
      tracks: tracks,
      repeat: MusicRepeatMode.all,
      transition: const TrackTransition.crossfade(
        duration: Duration(seconds: 2),
      ),
    );
    player.play();
    // Track a's window lasts 9 s; its successor starts 2 s before that end.
    backend.now = backend.starts.values.first.$2 + 8000000;
    player.tick();
    expect(player.state.overlapping, isTrue);
    expect(player.state.index, 1);
    expect(player.state.position, const Duration(seconds: 1));

    await AdaptiveMusicPlayer.restartEngineWith(rebooting([backend], []));

    expect(player.state.status, PlaybackStatus.playing);
    expect(player.state.overlapping, isFalse);
    expect(player.state.index, 1);
    expect(player.state.position, const Duration(seconds: 1));
    final voice = backend.starts.entries.first;
    expect(voice.value, (1, 40000));
    expect(backend.windows[voice.key], (
      const Duration(seconds: 1),
      const Duration(seconds: 9),
    ));
    await player.dispose();
  });
}
