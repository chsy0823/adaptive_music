import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'audio_backend.dart';
import 'envelope.dart';
import 'models.dart';
import 'soloud_backend.dart';

/// Domain-independent music playback with persistent DSP and smooth controls.
///
/// Commands return once accepted. Pause completion is observable in [state].
/// Load completes only when every track has been decoded. Listen to [states]
/// for runtime errors. Call [dispose] when finished.
class AdaptiveMusicPlayer {
  AdaptiveMusicPlayer({
    TransitionDefaults transitions = const TransitionDefaults.smooth(),
  }) : this.withBackend(SoloudBackend(), transitions: transitions);

  @visibleForTesting
  AdaptiveMusicPlayer.withBackend(
    this._backend, {
    this.transitions = const TransitionDefaults.smooth(),
    bool automaticTick = true,
  }) {
    for (final d in [
      transitions.volume,
      transitions.play,
      transitions.pause,
      transitions.filter,
    ]) {
      _validateDuration(d);
    }
    if (automaticTick) {
      _timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        try {
          tick();
        } catch (error) {
          _fail(error);
        }
      });
    }
  }

  final AudioBackend _backend;
  final TransitionDefaults transitions;
  final _events = StreamController<MusicState>.broadcast();
  final _volume = Envelope(1);
  final _transport = Envelope(0);
  final _clips = <_Clip>[];
  List<MusicTrack> _tracks = [];
  List<int> _lengths = [];
  MusicRepeatMode _repeat = MusicRepeatMode.none;
  TrackTransition _transition = const TrackTransition.gapless();
  PlaybackStatus _status = PlaybackStatus.empty;
  MusicState _state = const MusicState(status: PlaybackStatus.empty);
  Timer? _timer;
  int _origin = 0;
  int _held = 0;
  int? _pauseAt;
  int _index = 0;
  Future<void>? _loading;
  Future<void>? _disposing;
  bool _disposed = false;
  Object? _error;

  MusicState get state => _state;
  Stream<MusicState> get states => _events.stream;
  List<MusicTrack> get tracks => List.unmodifiable(_tracks);
  bool get _running =>
      _status == PlaybackStatus.playing || _status == PlaybackStatus.pausing;
  int get _time => _running ? math.max(0, _backend.now - _origin) : _held;

  /// Replaces the playlist. All tracks must be finite and at least 100 ms long.
  /// Loading stops current playback. If any source fails, the whole load fails.
  Future<void> load({
    required List<MusicTrack> tracks,
    MusicRepeatMode repeat = MusicRepeatMode.none,
    TrackTransition transition = const TrackTransition.crossfade(),
  }) {
    _checkAlive();
    if (_status == PlaybackStatus.loading) {
      throw StateError('A load is already in progress.');
    }
    if (tracks.isEmpty || tracks.any((t) => t.location.isEmpty)) {
      throw ArgumentError('Provide at least one non-empty track.');
    }
    _validateDuration(transition.duration);
    final copy = List<MusicTrack>.of(tracks);
    _status = PlaybackStatus.loading;
    _error = null;
    _clips.clear();
    _tracks = [];
    _lengths = [];
    _index = 0;
    _held = 0;
    _emit();
    return _loading = _load(copy, repeat, transition);
  }

  Future<void> _load(
    List<MusicTrack> tracks,
    MusicRepeatMode repeat,
    TrackTransition transition,
  ) async {
    try {
      await _backend.initialize();
      await _backend.clear();
      final lengths = <int>[];
      for (var i = 0; i < tracks.length && !_disposed; i++) {
        final length = await _backend.load(tracks[i], i);
        if (length < const Duration(milliseconds: 100)) {
          throw ArgumentError('Tracks must be at least 100 ms long.');
        }
        lengths.add(length.inMicroseconds);
      }
      if (_disposed) return;
      _tracks = tracks;
      _lengths = lengths;
      _repeat = repeat;
      _transition = transition;
      _status = PlaybackStatus.ready;
      _pauseAt = null;
      _emit();
    } catch (error) {
      await _backend.clear();
      if (!_disposed) {
        _status = PlaybackStatus.failed;
        _error = error;
        _emit();
      }
      rethrow;
    }
  }

  /// Resumes by default. Restart selects the beginning of the current track.
  void play({
    PlaybackStart start = PlaybackStart.resume,
    Duration? transition,
  }) {
    _checkReady();
    final fade = transition ?? transitions.play;
    _validateDuration(fade);
    final now = _backend.now;
    if (start == PlaybackStart.restartTrack ||
        _status == PlaybackStatus.completed) {
      _resetAt(_status == PlaybackStatus.completed ? 0 : _index);
    }
    if (_clips.isEmpty) {
      _origin = now + 40000; // Reserve one small scheduling lead-in.
      _held = 0;
      _clips.add(_Clip(_index, 0, _lengths[_index]));
      _transport.moveTo(0, now, 0);
    } else if (!_running) {
      _origin = now - _held;
      for (final clip in _clips) {
        if (clip.voice != null) _backend.pause(clip.voice!, false);
      }
    }
    _status = PlaybackStatus.playing;
    _pauseAt = null;
    _transport.moveTo(1, now, fade.inMicroseconds);
    tick();
  }

  /// Fades out while playback advances, then freezes both overlapping tracks.
  void pause({Duration? transition}) {
    _checkReady();
    final fade = transition ?? transitions.pause;
    _validateDuration(fade);
    if (!_running) return;
    _transport.moveTo(0, _backend.now, fade.inMicroseconds);
    _pauseAt = _backend.now + fade.inMicroseconds;
    _status = PlaybackStatus.pausing;
    tick();
  }

  /// Immediate stop and rewind to the beginning of the playlist.
  void stop() {
    _checkReady();
    _resetAt(0);
    _emit();
  }

  /// Changes the user's target gain without changing pause/crossfade gains.
  void setVolume(double value, {Duration? transition}) {
    _checkAlive();
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, 'volume', 'Expected 0..1');
    }
    final fade = transition ?? transitions.volume;
    _validateDuration(fade);
    _volume.moveTo(value, _backend.now, fade.inMicroseconds);
    _emit();
  }

  /// Applies or retargets the player's filter, including future tracks.
  void setFilter(MusicFilter filter, {Duration? transition}) {
    _checkReady();
    if (filter is LowPassFilter &&
        (!filter.cutoffHz.isFinite ||
            filter.cutoffHz < 10 ||
            filter.cutoffHz > 16000 ||
            !filter.resonance.isFinite ||
            filter.resonance < 0.1 ||
            filter.resonance > 20)) {
      throw ArgumentError('Cutoff must be 10..16000 Hz and resonance 0.1..20.');
    }
    if (filter is HighShelfFilter &&
        (!filter.frequencyHz.isFinite ||
            filter.frequencyHz < 100 ||
            filter.frequencyHz > 8000 ||
            !filter.gainDb.isFinite ||
            filter.gainDb < -24 ||
            filter.gainDb > 12)) {
      throw ArgumentError(
        'Shelf frequency must be 100..8000 Hz and gain -24..12 dB.',
      );
    }
    final fade = transition ?? transitions.filter;
    _validateDuration(fade);
    _backend.setFilter(filter, fade);
  }

  void clearFilter({Duration? transition}) {
    _checkReady();
    final fade = transition ?? transitions.filter;
    _validateDuration(fade);
    _backend.setFilter(null, fade);
  }

  /// Manually transitions to another track using the playlist's transition.
  void skipTo(int index) {
    _checkReady();
    RangeError.checkValidIndex(index, _tracks);
    if (!_running) {
      _resetAt(index);
      _emit();
      return;
    }
    final time = _time;
    final audible = _clips
        .where((c) => c.start <= time && c.end > time)
        .toList();
    for (final clip in _clips.where((c) => !audible.contains(c))) {
      _stopVoice(clip);
    }
    _clips.clear();
    var overlap = _transition.duration.inMicroseconds;
    overlap = math.min(overlap, _lengths[index] ~/ 2);
    for (final clip in audible) {
      overlap = math.min(overlap, clip.end - time);
    }
    for (final clip in audible) {
      if (overlap > 0) {
        // Retarget every audible voice; do not cut an existing overlap short.
        clip.fixedGain = clip.gain(time, _transition.curve);
        clip.fadeIn = 0;
        clip.end = time + overlap;
        clip.fadeOut = overlap;
        _clips.add(clip);
      } else {
        _stopVoice(clip);
      }
    }
    _clips.add(
      _Clip(
        index,
        time,
        time + _lengths[index],
        fadeIn: audible.isEmpty ? 0 : overlap,
      ),
    );
    _index = index;
    tick();
  }

  void next() {
    _checkReady();
    if (_index + 1 < _tracks.length) {
      skipTo(_index + 1);
    } else if (_repeat != MusicRepeatMode.none) {
      skipTo(0);
    }
  }

  @visibleForTesting
  void tick() {
    if (!_running || _disposed) return;
    final time = _time;
    for (final clip in _clips.where((c) => c.end <= time).toList()) {
      _stopVoice(clip);
      _clips.remove(clip);
    }
    if (_clips.isEmpty) {
      _status = PlaybackStatus.completed;
      _held = time;
      _emit();
      return;
    }
    // Keep three successors scheduled so Dart/UI stalls do not open a gap.
    while (_clips.length < 4) {
      final last = _clips.last;
      final next = _successor(last.index);
      if (next == null) break;
      final overlap = _overlap(last.index, next);
      last.fadeOut = overlap;
      final start = last.end - overlap;
      _clips.add(_Clip(next, start, start + _lengths[next], fadeIn: overlap));
    }
    for (final clip in _clips) {
      clip.voice ??= _backend.schedule(clip.index, _origin + clip.start);
      // Future gapless voices must start at their audible gain without waiting
      // for a Dart tick. Crossfades begin at zero and are smoothed natively.
      final sampleTime = math.max(time, clip.start);
      final gain =
          clip.gain(sampleTime, _transition.curve) *
          _volume.at(_backend.now) *
          _transport.at(_backend.now);
      _backend.gain(
        clip.voice!,
        gain,
        time < clip.start ? Duration.zero : const Duration(milliseconds: 10),
      );
    }
    final audible = _clips
        .where((c) => c.start <= time && c.end > time)
        .toList();
    if (audible.isNotEmpty) _index = audible.last.index;
    if (_pauseAt != null && _backend.now >= _pauseAt!) {
      _held = time;
      for (final clip in _clips) {
        if (_origin + clip.start > _backend.now) {
          _stopVoice(clip);
        } else if (clip.voice != null) {
          _backend.gain(clip.voice!, 0, Duration.zero);
          _backend.pause(clip.voice!, true);
        }
      }
      _status = PlaybackStatus.paused;
      _pauseAt = null;
    }
    _emit();
  }

  int? _successor(int index) => switch (_repeat) {
    MusicRepeatMode.one => index,
    MusicRepeatMode.all => (index + 1) % _tracks.length,
    MusicRepeatMode.none => index + 1 < _tracks.length ? index + 1 : null,
  };
  int _overlap(int a, int b) => math.min(
    _transition.duration.inMicroseconds,
    math.min(_lengths[a] ~/ 2, _lengths[b] ~/ 2),
  );
  void _resetAt(int index) {
    for (final clip in _clips) {
      _stopVoice(clip);
    }
    _clips.clear();
    _held = 0;
    _index = index;
    _pauseAt = null;
    _status = PlaybackStatus.ready;
  }

  void _stopVoice(_Clip clip) {
    final voice = clip.voice;
    clip.voice = null;
    if (voice != null) {
      unawaited(
        _backend.stop(voice).catchError((Object error) {
          _fail(error);
        }),
      );
    }
  }

  void _fail(Object error) {
    if (_disposed || _status == PlaybackStatus.failed) return;
    _error = error;
    _status = PlaybackStatus.failed;
    for (final clip in _clips) {
      _stopVoice(clip);
    }
    _clips.clear();
    _emit();
  }

  void _emit() {
    if (_disposed) return;
    final time = _time;
    final audible = _clips
        .where((c) => c.start <= time && c.end > time)
        .toList();
    final length = _lengths.isEmpty ? 0 : _lengths[_index];
    final position = _status == PlaybackStatus.completed
        ? length
        : audible.isEmpty
        ? 0
        : time - audible.last.start;
    _state = MusicState(
      status: _status,
      index: _index,
      position: Duration(microseconds: position),
      duration: Duration(microseconds: length),
      overlapping: audible.length > 1,
      volume: _volume.target,
      error: _error,
    );
    _events.add(_state);
  }

  void _checkAlive() {
    if (_disposed) throw StateError('Player is disposed.');
  }

  void _checkReady() {
    _checkAlive();
    if (_tracks.isEmpty ||
        _status == PlaybackStatus.loading ||
        _status == PlaybackStatus.failed) {
      throw StateError('Load a playlist before issuing playback commands.');
    }
  }

  static void _validateDuration(Duration value) {
    if (value.isNegative) {
      throw ArgumentError.value(value, 'transition', 'Must not be negative');
    }
  }

  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    _timer?.cancel();
    try {
      await _loading;
    } catch (_) {
      /* load reports its own error */
    }
    await _backend.dispose();
    _clips.clear();
    _status = PlaybackStatus.disposed;
    _state = const MusicState(status: PlaybackStatus.disposed);
    await _events.close();
  }
}

class _Clip {
  _Clip(this.index, this.start, this.end, {this.fadeIn = 0});
  final int index;
  final int start;
  int end;
  int fadeIn;
  int fadeOut = 0;
  int? voice;
  double fixedGain = 1;
  double gain(int time, FadeCurve curve) {
    var value = 1.0;
    if (fadeIn > 0 && time < start + fadeIn) {
      value = ((time - start) / fadeIn).clamp(0.0, 1.0);
    }
    if (fadeOut > 0 && time > end - fadeOut) {
      value = ((end - time) / fadeOut).clamp(0.0, 1.0);
    }
    return fixedGain *
        (curve == FadeCurve.equalPower ? math.sin(value * math.pi / 2) : value);
  }
}
