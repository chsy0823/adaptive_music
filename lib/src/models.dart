/// Where a finite, seekable music track is loaded from.
enum TrackSource { asset, file, url }

/// One music file. URLs are fully downloaded during load, before playback.
class MusicTrack {
  const MusicTrack.asset(
    this.location, {
    this.title,
    this.cueIn = Duration.zero,
    this.cueOut,
  }) : source = TrackSource.asset;
  const MusicTrack.file(
    this.location, {
    this.title,
    this.cueIn = Duration.zero,
    this.cueOut,
  }) : source = TrackSource.file;
  const MusicTrack.url(
    this.location, {
    this.title,
    this.cueIn = Duration.zero,
    this.cueOut,
  }) : source = TrackSource.url;
  final String location;
  final String? title;
  final TrackSource source;

  /// Inclusive start and exclusive end in the source file. Null end uses EOF.
  /// The selected window must fit the decoded file and be at least 100 ms.
  final Duration cueIn;
  final Duration? cueOut;
}

enum MusicRepeatMode { none, one, all }

enum PlaybackStart { resume, restartTrack }

enum PlaybackStatus {
  empty,
  loading,
  ready,
  playing,
  pausing,
  paused,
  completed,
  failed,
  disposed,
}

enum FadeCurve { linear, equalPower }

/// Crossfade overlaps the end of a track with the beginning of its successor.
/// A zero duration selects gapless scheduling. Overlap is capped to half of
/// each adjacent track's duration, so automatic transitions have at most two audible tracks.
class TrackTransition {
  const TrackTransition.gapless()
    : duration = Duration.zero,
      curve = FadeCurve.linear;
  const TrackTransition.crossfade({
    this.duration = const Duration(seconds: 3),
    this.curve = FadeCurve.equalPower,
  });
  final Duration duration;
  final FadeCurve curve;
}

/// Default smoothing for commands. A command can override its own duration.
class TransitionDefaults {
  const TransitionDefaults.smooth({
    this.volume = const Duration(milliseconds: 400),
    this.play = const Duration(milliseconds: 500),
    this.pause = const Duration(milliseconds: 500),
    this.filter = const Duration(milliseconds: 700),
  });
  const TransitionDefaults.immediate()
    : volume = Duration.zero,
      play = Duration.zero,
      pause = Duration.zero,
      filter = Duration.zero;
  final Duration volume;
  final Duration play;
  final Duration pause;
  final Duration filter;
}

/// Tone processing selected for a player and all its tracks.
sealed class MusicFilter {
  const MusicFilter();
}

/// A resonant low-pass filter. Cutoff is in Hz; resonance is the engine's Q.
class LowPassFilter extends MusicFilter {
  const LowPassFilter({this.cutoffHz = 1200, this.resonance = 0.707});
  final double cutoffHz;
  final double resonance;
}

/// A spectral high shelf with a one-octave transition around [frequencyHz].
/// Positive gain boosts treble; negative gain softens it without removing it.
class HighShelfFilter extends MusicFilter {
  const HighShelfFilter({this.frequencyHz = 2000, this.gainDb = -6});
  final double frequencyHz;
  final double gainDb;
}

/// Immutable playback state. During overlap [index] is the incoming track.
class MusicState {
  const MusicState({
    required this.status,
    this.index = 0,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.overlapping = false,
    this.volume = 1,
    this.error,
  });
  final PlaybackStatus status;
  final int index;
  final Duration position;
  final Duration duration;
  final bool overlapping;

  /// User's target volume, independent of pause and crossfade envelopes.
  final double volume;
  final Object? error;
}
