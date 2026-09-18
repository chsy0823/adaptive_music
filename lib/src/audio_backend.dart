import 'models.dart';

/// Internal seam for deterministic transport tests and the native engine.
abstract interface class AudioBackend {
  Future<void> initialize();
  int get now;
  Future<Duration> load(MusicTrack track, int index);
  int schedule(int index, int engineTime);
  void gain(int voice, double value, Duration smoothing);
  void pause(int voice, bool paused);
  Future<void> stop(int voice);
  void lowPass(LowPassFilter? filter, Duration transition);
  Future<void> clear();
  Future<void> dispose();
}
