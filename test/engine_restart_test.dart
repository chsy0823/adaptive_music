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

class GatedDisposeBackend extends FakeBackend {
  Completer<void>? gate;
  @override
  Future<void> dispose() async {
    await gate?.future;
    await super.dispose();
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

class FailingReleaseBackend extends FakeBackend {
  @override
  Future<void> dispose() async {
    await super.dispose();
    if (disposals == 1) throw StateError('bus already gone');
  }
}

class BrokenClockBackend extends FakeBackend {
  bool dead = false;
  @override
  int get now => dead ? throw StateError('engine gone') : super.now;
}

/// Fakes the engine restart: SoLoud's clock begins again from zero.
Future<void> Function() rebooting(List<FakeBackend> backends, List<int> log) =>
    () async {
      for (final backend in backends) {
        backend.now = 0;
      }
      log.add(backends.first.now);
    };

AdaptiveMusicPlayer player(
  FakeBackend backend, {
  TransitionDefaults transitions = const TransitionDefaults.smooth(),
}) {
  final player = AdaptiveMusicPlayer.withBackend(
    backend,
    transitions: transitions,
    automaticTick: false,
  );
  addTearDown(player.dispose);
  return player;
}

void main() {
  const tracks = [
    MusicTrack.asset('a', cueIn: Duration(seconds: 1)),
    MusicTrack.asset('b'),
  ];
  const immediate = TransitionDefaults.immediate();

  test(
    'a playing player resumes its track, position, gains and filter',
    () async {
      final backend = FakeBackend();
      final music = player(backend, transitions: immediate);
      final statuses = <PlaybackStatus>[];
      final subscription = music.states.listen((s) => statuses.add(s.status));
      addTearDown(subscription.cancel);
      await music.load(
        tracks: tracks,
        repeat: MusicRepeatMode.all,
        transition: const TrackTransition.gapless(),
      );
      music.setVolume(0.5);
      music.setFilter(const LowPassFilter(cutoffHz: 800));
      music.requestDucking(gain: 0.3);
      music.play();
      backend.now = backend.starts.values.first.$2 + 3000000;
      music.tick();
      expect(music.state.position, const Duration(seconds: 3));
      final restarts = <int>[];

      await AdaptiveMusicPlayer.restartEngineWith(
        rebooting([backend], restarts),
      );

      expect(restarts, [0]);
      expect(statuses, contains(PlaybackStatus.loading));
      expect(backend.disposals, 1);
      expect(backend.initializations, 2);
      expect(backend.loads, 4);
      expect(music.state.status, PlaybackStatus.playing);
      expect(music.state.index, 0);
      expect(music.state.position, const Duration(seconds: 3));
      expect(music.state.duration, const Duration(seconds: 9));
      expect(music.state.volume, 0.5);
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
      music.tick();
      expect(music.state.index, 1);
      expect(music.state.position, Duration.zero);
    },
  );

  test('a paused player stays paused and resumes from its position', () async {
    final backend = FakeBackend();
    final music = player(backend, transitions: immediate);
    await music.load(tracks: tracks);
    music.play();
    backend.now = backend.starts.values.first.$2 + 2000000;
    music.tick();
    music.pause();
    music.tick();
    expect(music.state.status, PlaybackStatus.paused);

    await AdaptiveMusicPlayer.restartEngineWith(rebooting([backend], []));

    expect(music.state.status, PlaybackStatus.paused);
    expect(music.state.position, const Duration(seconds: 2));
    expect(backend.starts, isEmpty);
    backend.now = 500000;
    music.play();
    expect(music.state.status, PlaybackStatus.playing);
    expect(music.state.position, const Duration(seconds: 2));
    // The restored voice gets the same lead-in as a fresh start.
    final voice = backend.starts.entries.first;
    expect(voice.value, (0, 540000));
    expect(backend.windows[voice.key], (
      const Duration(seconds: 3),
      const Duration(seconds: 7),
    ));
  });

  test('a pause still fading completes as paused', () async {
    final backend = FakeBackend();
    final music = player(backend);
    await music.load(tracks: tracks);
    music.play(transition: Duration.zero);
    backend.now = backend.starts.values.first.$2 + 1000000;
    music.tick();
    music.pause(transition: const Duration(seconds: 1));
    expect(music.state.status, PlaybackStatus.pausing);

    await AdaptiveMusicPlayer.restartEngineWith(rebooting([backend], []));

    expect(music.state.status, PlaybackStatus.paused);
    expect(music.state.position, const Duration(seconds: 1));
  });

  test('ready, completed and empty players keep their status', () async {
    final ready = FakeBackend();
    final completed = FakeBackend();
    final empty = FakeBackend();
    final players = [player(ready), player(completed), player(empty)];
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
  });

  test('commands and loads are rejected while the engine restarts', () async {
    final backend = FakeBackend();
    final music = player(backend);
    await music.load(tracks: tracks);
    music.play(transition: Duration.zero);
    final engine = Completer<void>();
    final restart = AdaptiveMusicPlayer.restartEngineWith(() => engine.future);
    expect(music.state.status, PlaybackStatus.loading);
    expect(music.play, throwsStateError);
    expect(music.pause, throwsStateError);
    expect(() => music.skipTo(1), throwsStateError);
    expect(
      () => music.load(tracks: tracks),
      throwsA(
        isStateError.having(
          (e) => e.message,
          'message',
          contains('restartEngine'),
        ),
      ),
    );
    music.setVolume(0.2, transition: Duration.zero);
    engine.complete();
    await restart;
    expect(music.state.status, PlaybackStatus.playing);
    expect(music.state.volume, 0.2);
    // The default play fade brings the resumed voice up over 500 ms.
    expect(backend.gains.values.first, 0);
    backend.now = 500000;
    music.tick();
    expect(backend.gains.values.first, closeTo(0.2, 1e-9));
  });

  test('concurrent restarts share one engine restart', () async {
    final backend = FakeBackend();
    final music = player(backend);
    await music.load(tracks: tracks);
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
  });

  test('a reset reported during the rebuild runs one more pass', () async {
    final backend = GatedLoadBackend();
    final music = player(backend, transitions: immediate);
    await music.load(tracks: tracks);
    music.play();
    backend.now = backend.starts.values.first.$2 + 2000000;
    music.tick();
    var restarts = 0;
    Future<void> restart() async {
      backend.now = 0;
      restarts++;
    }

    backend.gate = Completer<void>();
    final first = AdaptiveMusicPlayer.restartEngineWith(restart);
    await Future<void>.delayed(Duration.zero);
    expect(restarts, 1);
    expect(music.state.status, PlaybackStatus.loading);
    final second = AdaptiveMusicPlayer.restartEngineWith(restart);
    backend.gate!.complete();
    backend.gate = null;
    await first;
    await second;
    expect(restarts, 2);
    expect(backend.initializations, 3);
    expect(music.state.status, PlaybackStatus.playing);
    expect(music.state.position, const Duration(seconds: 2));
  });

  test('a load in flight finishes and its playlist is rebuilt', () async {
    final backend = GatedLoadBackend()..gate = Completer<void>();
    final music = player(backend);
    final load = music.load(tracks: tracks);
    final restart = AdaptiveMusicPlayer.restartEngineWith(() async {});
    await Future<void>.delayed(Duration.zero);
    expect(backend.disposals, 0);
    backend.gate!.complete();
    backend.gate = null;
    await load;
    await restart;
    expect(music.state.status, PlaybackStatus.ready);
    expect(music.tracks, hasLength(2));
    expect(backend.disposals, 1);
    expect(backend.loads, 4);
  });

  test('disposal during a restart completes without rebuilding', () async {
    final backend = FakeBackend();
    final music = player(backend);
    await music.load(tracks: tracks);
    music.play(transition: Duration.zero);
    final engine = Completer<void>();
    final restart = AdaptiveMusicPlayer.restartEngineWith(() => engine.future);
    final disposal = music.dispose();
    engine.complete();
    await restart;
    await disposal;
    expect(music.state.status, PlaybackStatus.disposed);
    expect(backend.initializations, 1);
    expect(backend.loads, 2);
  });

  test('a player disposed as the restart begins releases first', () async {
    final backend = FakeBackend();
    final music = player(backend);
    await music.load(tracks: tracks);
    music.play(transition: Duration.zero);
    var releasedBeforeEngine = -1;
    final restart = AdaptiveMusicPlayer.restartEngineWith(() async {
      releasedBeforeEngine = backend.disposals;
    });
    final disposal = music.dispose();
    await restart;
    await disposal;
    expect(releasedBeforeEngine, 1);
    expect(music.state.status, PlaybackStatus.disposed);
    expect(backend.initializations, 1);
  });

  test('a disposal already in flight finishes before the engine', () async {
    final backend = GatedDisposeBackend()..gate = Completer<void>();
    final music = player(backend);
    await music.load(tracks: tracks);
    final disposal = music.dispose();
    var releasedBeforeEngine = -1;
    final restart = AdaptiveMusicPlayer.restartEngineWith(() async {
      releasedBeforeEngine = backend.disposals;
    });
    await Future<void>.delayed(Duration.zero);
    expect(releasedBeforeEngine, -1);
    backend.gate!.complete();
    await disposal;
    await restart;
    expect(releasedBeforeEngine, 1);
  });

  test('a failed reload reports failure and leaves others playing', () async {
    final failing = FailingReloadBackend();
    final healthy = FakeBackend();
    final broken = player(failing);
    final fine = player(healthy);
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
  });

  test('an engine restart error fails the rebuilt players', () async {
    final backend = FakeBackend();
    final music = player(backend);
    await music.load(tracks: tracks);
    music.play(transition: Duration.zero);
    await expectLater(
      AdaptiveMusicPlayer.restartEngineWith(
        () async => throw StateError('engine stuck'),
      ),
      throwsStateError,
    );
    expect(music.state.status, PlaybackStatus.failed);
    expect(music.state.error, isStateError);
    expect(backend.initializations, 1);
  });

  test('a backend that fails to release is still rebuilt', () async {
    final backend = FailingReleaseBackend();
    final music = player(backend, transitions: immediate);
    await music.load(tracks: tracks);
    music.play();
    backend.now = backend.starts.values.first.$2 + 1000000;
    music.tick();

    await AdaptiveMusicPlayer.restartEngineWith(rebooting([backend], []));

    expect(music.state.status, PlaybackStatus.playing);
    expect(music.state.position, const Duration(seconds: 1));
    expect(backend.initializations, 2);
  });

  test(
    'a clock the dead engine cannot report loses only the position',
    () async {
      final backend = BrokenClockBackend();
      final music = player(backend, transitions: immediate);
      await music.load(tracks: tracks);
      music.play();
      backend.now = backend.starts.values.first.$2 + 2000000;
      music.tick();
      backend.dead = true;

      await AdaptiveMusicPlayer.restartEngineWith(() async {
        backend.dead = false;
        backend.now = 0;
      });

      expect(music.state.status, PlaybackStatus.playing);
      expect(music.state.index, 0);
      expect(music.state.position, Duration.zero);
      expect(backend.initializations, 2);
    },
  );

  test('a crossfade in progress resumes with the incoming track', () async {
    final backend = FakeBackend();
    final music = player(backend, transitions: immediate);
    await music.load(
      tracks: tracks,
      repeat: MusicRepeatMode.all,
      transition: const TrackTransition.crossfade(
        duration: Duration(seconds: 2),
      ),
    );
    music.play();
    // Track a's window lasts 9 s; its successor starts 2 s before that end.
    backend.now = backend.starts.values.first.$2 + 8000000;
    music.tick();
    expect(music.state.overlapping, isTrue);
    expect(music.state.index, 1);
    expect(music.state.position, const Duration(seconds: 1));

    await AdaptiveMusicPlayer.restartEngineWith(rebooting([backend], []));

    expect(music.state.status, PlaybackStatus.playing);
    expect(music.state.overlapping, isFalse);
    expect(music.state.index, 1);
    expect(music.state.position, const Duration(seconds: 1));
    final voice = backend.starts.entries.first;
    expect(voice.value, (1, 40000));
    expect(backend.windows[voice.key], (
      const Duration(seconds: 1),
      const Duration(seconds: 9),
    ));
  });
}
