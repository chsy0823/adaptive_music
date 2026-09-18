import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_music/src/audio_backend.dart';
import 'package:adaptive_music/src/models.dart';
import 'package:adaptive_music/src/player.dart';

class FakeBackend implements AudioBackend {
  @override
  int now = 0;
  final starts = <int, (int, int)>{};
  final windows = <int, (Duration, Duration)>{};
  final gains = <int, double>{};
  final paused = <int>{};
  int counter = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<Duration> load(MusicTrack track, int index) async =>
      const Duration(seconds: 10);
  @override
  int schedule(
    int index,
    int engineTime, {
    Duration offset = Duration.zero,
    Duration duration = Duration.zero,
  }) {
    starts[++counter] = (index, engineTime);
    windows[counter] = (offset, duration);
    return counter;
  }

  @override
  void gain(int voice, double value, Duration smoothing) {
    gains[voice] = value;
  }

  @override
  void pause(int voice, bool value) {
    value ? paused.add(voice) : paused.remove(voice);
  }

  @override
  Future<void> stop(int voice) async {
    starts.remove(voice);
    gains.remove(voice);
    paused.remove(voice);
  }

  @override
  void setFilter(MusicFilter? filter, Duration transition) {
    lastFilter = filter;
    filterTransition = transition;
  }

  MusicFilter? lastFilter;
  Duration? filterTransition;
  @override
  Future<void> clear() async {
    starts.clear();
    gains.clear();
    paused.clear();
  }

  @override
  Future<void> dispose() async {
    await clear();
  }
}

void main() {
  test('cue windows outside the source are rejected', () async {
    for (final track in [
      const MusicTrack.asset('a', cueIn: Duration(seconds: -1)),
      const MusicTrack.asset('a', cueOut: Duration(seconds: 11)),
      const MusicTrack.asset(
        'a',
        cueIn: Duration(seconds: 5),
        cueOut: Duration(seconds: 4),
      ),
    ]) {
      final player = AdaptiveMusicPlayer.withBackend(
        FakeBackend(),
        automaticTick: false,
      );
      await expectLater(player.load(tracks: [track]), throwsArgumentError);
      await player.dispose();
    }
  });
  test(
    'duck fades retarget and tied requests restore the remaining gain',
    () async {
      final backend = FakeBackend();
      final player = AdaptiveMusicPlayer.withBackend(
        backend,
        automaticTick: false,
        transitions: const TransitionDefaults.immediate(),
      );
      await player.load(tracks: const [MusicTrack.asset('a')]);
      player.play();
      final a = player.requestDucking(
        gain: 0.4,
        transition: const Duration(seconds: 1),
      );
      backend.now = 500000;
      player.tick();
      expect(backend.gains[1], closeTo(0.7, 0.001));
      final b = player.requestDucking(gain: 0.2, transition: Duration.zero);
      player.tick();
      expect(backend.gains[1], closeTo(0.2, 0.001));
      player.releaseDucking(b, transition: Duration.zero);
      player.tick();
      expect(backend.gains[1], closeTo(0.4, 0.001));
      player.releaseDucking(a, transition: const Duration(seconds: 1));
      backend.now = 1000000;
      player.tick();
      expect(backend.gains[1], closeTo(0.7, 0.001));
      await player.dispose();
    },
  );

  test(
    'overlapping priorities duck without changing the user volume',
    () async {
      final backend = FakeBackend();
      final player = AdaptiveMusicPlayer.withBackend(
        backend,
        automaticTick: false,
        transitions: const TransitionDefaults.immediate(),
      );
      await player.load(tracks: const [MusicTrack.asset('a')]);
      player.setVolume(0.8);
      player.play();
      final first = player.requestDucking(gain: 0.5, transition: Duration.zero);
      final second = player.requestDucking(
        gain: 0.25,
        priority: 1,
        transition: Duration.zero,
      );
      player.tick();
      expect(backend.gains[1], closeTo(0.2, 0.001));
      player.releaseDucking(first, transition: Duration.zero);
      player.setVolume(0.6);
      player.tick();
      expect(backend.gains[1], closeTo(0.15, 0.001));
      player.releaseDucking(second, transition: Duration.zero);
      player.tick();
      expect(backend.gains[1], closeTo(0.6, 0.001));
      player.releaseDucking(second);
      await player.dispose();
    },
  );

  test('cue window schedules overlap before trailing silence', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
      transitions: const TransitionDefaults.immediate(),
    );
    await player.load(
      tracks: const [
        MusicTrack.asset(
          'a',
          cueIn: Duration(seconds: 1),
          cueOut: Duration(seconds: 7),
        ),
        MusicTrack.asset('b'),
      ],
      transition: const TrackTransition.crossfade(
        duration: Duration(seconds: 2),
      ),
    );
    player.play();
    final starts = backend.starts.values.toList();
    expect(starts[1].$2 - starts[0].$2, 4000000);
    expect(backend.windows[1], (
      const Duration(seconds: 1),
      const Duration(seconds: 6),
    ));
    backend.now = 5000000;
    player.tick();
    expect(backend.gains.values.where((g) => g > 0), hasLength(2));
    expect(
      backend.gains.values.fold<double>(0, (sum, g) => sum + g * g),
      closeTo(1, 0.001),
    );
    await player.dispose();
  });

  test(
    'shelf selection, retarget and clear preserve requested fades',
    () async {
      final backend = FakeBackend();
      final player = AdaptiveMusicPlayer.withBackend(
        backend,
        automaticTick: false,
      );
      await player.load(tracks: const [MusicTrack.asset('a')]);
      const shelf = HighShelfFilter(frequencyHz: 2000, gainDb: -6);
      player.setFilter(shelf);
      expect(backend.lastFilter, same(shelf));
      expect(backend.filterTransition, const Duration(milliseconds: 700));
      player.setFilter(
        const HighShelfFilter(gainDb: -12),
        transition: Duration.zero,
      );
      expect(backend.filterTransition, Duration.zero);
      for (final invalid in [
        const HighShelfFilter(frequencyHz: 0),
        const HighShelfFilter(frequencyHz: double.nan),
        const HighShelfFilter(gainDb: double.infinity),
        const HighShelfFilter(gainDb: -25),
        const HighShelfFilter(gainDb: 13),
      ]) {
        expect(() => player.setFilter(invalid), throwsArgumentError);
      }
      player.clearFilter();
      expect(backend.lastFilter, isNull);
      await player.dispose();
    },
  );
  test('pre-schedules the next track before the current track ends', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
      transitions: const TransitionDefaults.immediate(),
    );
    await player.load(
      tracks: const [MusicTrack.asset('a'), MusicTrack.asset('b')],
      transition: const TrackTransition.gapless(),
    );
    player.play();
    final starts = backend.starts.values.toList();
    expect(starts.length, 2);
    expect(starts[1].$2 - starts[0].$2, 10000000);
    await player.dispose();
  });
  test(
    'crossfade pause freezes both tracks and resume keeps the overlap',
    () async {
      final backend = FakeBackend();
      final player = AdaptiveMusicPlayer.withBackend(
        backend,
        automaticTick: false,
        transitions: const TransitionDefaults.immediate(),
      );
      await player.load(
        tracks: const [MusicTrack.asset('a'), MusicTrack.asset('b')],
        transition: const TrackTransition.crossfade(
          duration: Duration(seconds: 2),
        ),
      );
      player.play();
      backend.now = 9040000;
      player.tick();
      expect(player.state.overlapping, true);
      final voices = backend.starts.keys.toList();
      expect(backend.gains[voices[0]], closeTo(0.707106, 0.0001));
      expect(backend.gains[voices[1]], closeTo(0.707106, 0.0001));
      player.pause();
      expect(backend.paused.length, 2);
      expect(player.state.status, PlaybackStatus.paused);
      final position = player.state.position;
      backend.now += 5000000;
      player.play();
      expect(player.state.position, position);
      expect(player.state.overlapping, true);
      expect(backend.paused, isEmpty);
      await player.dispose();
    },
  );

  test(
    'play during pause fade cancels the pending pause without a gain jump',
    () async {
      final backend = FakeBackend();
      final player = AdaptiveMusicPlayer.withBackend(
        backend,
        automaticTick: false,
      );
      await player.load(tracks: const [MusicTrack.asset('a')]);
      player.play(transition: Duration.zero);
      backend.now = 1040000;
      player.tick();
      final voice = backend.starts.keys.first;
      player.pause(transition: const Duration(seconds: 1));
      backend.now += 400000;
      player.tick();
      expect(backend.gains[voice], closeTo(0.6, 0.0001));
      player.play(transition: const Duration(seconds: 1));
      expect(backend.gains[voice], closeTo(0.6, 0.0001));
      backend.now += 700000;
      player.tick();
      expect(backend.gains[voice], closeTo(0.88, 0.0001));
      expect(backend.paused, isEmpty);
      expect(player.state.status, PlaybackStatus.playing);
      await player.dispose();
    },
  );

  for (final mode in MusicRepeatMode.values) {
    test('playlist successor order for ${mode.name}', () async {
      final backend = FakeBackend();
      final player = AdaptiveMusicPlayer.withBackend(
        backend,
        automaticTick: false,
      );
      await player.load(
        tracks: const [MusicTrack.asset('a'), MusicTrack.asset('b')],
        repeat: mode,
        transition: const TrackTransition.gapless(),
      );
      player.play();
      expect(backend.starts.values.map((v) => v.$1).toList(), switch (mode) {
        MusicRepeatMode.none => [0, 1],
        MusicRepeatMode.one => [0, 0, 0, 0],
        MusicRepeatMode.all => [0, 1, 0, 1],
      });
      await player.dispose();
    });
  }
  test('single track crossfade repeat is capped and overlaps itself', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
    );
    await player.load(
      tracks: const [MusicTrack.asset('a')],
      repeat: MusicRepeatMode.one,
      transition: const TrackTransition.crossfade(
        duration: Duration(seconds: 30),
      ),
    );
    player.play();
    final starts = backend.starts.values.toList();
    expect(starts[1].$2 - starts[0].$2, 5000000);
    backend.now = 7540000;
    player.tick();
    expect(player.state.overlapping, true);
    await player.dispose();
  });

  test(
    'volume target survives pause and resumes at the requested level',
    () async {
      final backend = FakeBackend();
      final player = AdaptiveMusicPlayer.withBackend(
        backend,
        automaticTick: false,
        transitions: const TransitionDefaults.immediate(),
      );
      await player.load(tracks: const [MusicTrack.asset('a')]);
      player.play();
      backend.now = 1040000;
      player.tick();
      final voice = backend.starts.keys.first;
      player.setVolume(0.4, transition: const Duration(seconds: 1));
      backend.now += 500000;
      player.tick();
      expect(backend.gains[voice], closeTo(0.7, 0.0001));
      backend.now += 500000;
      player.pause();
      expect(player.state.volume, 0.4);
      player.play();
      expect(backend.gains[voice], closeTo(0.4, 0.0001));
      await player.dispose();
    },
  );
  test('restart rewinds current track; stop rewinds the playlist', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
      transitions: const TransitionDefaults.immediate(),
    );
    await player.load(
      tracks: const [MusicTrack.asset('a'), MusicTrack.asset('b')],
    );
    player.play();
    backend.now = 9040000;
    player.tick();
    expect(player.state.index, 1);
    player.play(start: PlaybackStart.restartTrack);
    expect(player.state.index, 1);
    expect(player.state.position, Duration.zero);
    player.stop();
    expect(player.state.index, 0);
    expect(player.state.status, PlaybackStatus.ready);
    await player.dispose();
  });
  test(
    'paused future tracks are cancelled and rescheduled relative to resume',
    () async {
      final backend = FakeBackend();
      final player = AdaptiveMusicPlayer.withBackend(
        backend,
        automaticTick: false,
        transitions: const TransitionDefaults.immediate(),
      );
      await player.load(
        tracks: const [MusicTrack.asset('a'), MusicTrack.asset('b')],
        transition: const TrackTransition.gapless(),
      );
      player.play();
      backend.now = 1040000;
      player.tick();
      player.pause();
      expect(backend.starts.length, 1);
      backend.now += 5000000;
      player.play();
      final next = backend.starts.values.singleWhere((v) => v.$1 == 1);
      expect(next.$2, 15040000);
      await player.dispose();
    },
  );
  test('finite playlist completes and play starts it again', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
    );
    await player.load(tracks: const [MusicTrack.asset('a')]);
    player.play();
    backend.now = 11000000;
    player.tick();
    expect(player.state.status, PlaybackStatus.completed);
    expect(player.state.position, const Duration(seconds: 10));
    player.play();
    expect(player.state.status, PlaybackStatus.playing);
    expect(player.state.position, Duration.zero);
    await player.dispose();
  });
  test('invalid inputs fail before mutating the transport', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
    );
    expect(() => player.play(), throwsStateError);
    expect(() => player.load(tracks: []), throwsArgumentError);
    expect(() => player.setVolume(double.nan), throwsArgumentError);
    await player.load(tracks: const [MusicTrack.asset('a')]);
    expect(
      () => player.pause(transition: const Duration(seconds: -1)),
      throwsArgumentError,
    );
    expect(
      () => player.setFilter(const LowPassFilter(cutoffHz: 0)),
      throwsArgumentError,
    );
    expect(() => player.skipTo(5), throwsRangeError);
    await player.dispose();
    await player.dispose();
    expect(() => player.play(), throwsStateError);
  });
  test('manual skip during crossfade preserves both outgoing gains', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
      transitions: const TransitionDefaults.immediate(),
    );
    await player.load(
      tracks: const [
        MusicTrack.asset('a'),
        MusicTrack.asset('b'),
        MusicTrack.asset('c'),
      ],
      transition: const TrackTransition.crossfade(
        duration: Duration(seconds: 2),
      ),
    );
    player.play();
    backend.now = 9040000;
    player.tick();
    final outgoing = backend.starts.entries
        .where((e) => e.value.$2 <= backend.now)
        .map((e) => e.key)
        .toList();
    final before = outgoing.map((id) => backend.gains[id]).toList();
    player.skipTo(2);
    for (var i = 0; i < outgoing.length; i++) {
      expect(backend.gains[outgoing[i]], before[i]);
    }
    expect(player.state.index, 2);
    await player.dispose();
  });
  test('pause before scheduled initial start cannot leak audio', () async {
    final backend = FakeBackend();
    final player = AdaptiveMusicPlayer.withBackend(
      backend,
      automaticTick: false,
      transitions: const TransitionDefaults.immediate(),
    );
    await player.load(tracks: const [MusicTrack.asset('a')]);
    player.play();
    player.pause();
    expect(backend.starts, isEmpty);
    expect(player.state.status, PlaybackStatus.paused);
    backend.now = 5000000;
    player.play();
    expect(backend.starts.values.single.$2, backend.now);
    expect(player.state.position, Duration.zero);
    await player.dispose();
  });
}
