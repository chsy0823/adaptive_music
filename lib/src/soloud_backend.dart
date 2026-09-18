import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:http/http.dart' as http;
import 'audio_backend.dart';
import 'models.dart';

/// Each player owns a bus and uniquely named sources, never global filters.
class SoloudBackend implements AudioBackend {
  static int _serial = 0;
  static Future<void>? _initializing;
  final _engine = SoLoud.instance;
  final _sources = <int, AudioSource>{};
  final _voices = <int, SoundHandle>{};
  Bus? _bus;
  bool _filterActive = false;
  @override
  int get now =>
      _engine.isInitialized ? _engine.getEngineTime().inMicroseconds : 0;
  @override
  Future<void> initialize() async {
    if (!_engine.isInitialized) {
      try {
        await (_initializing ??= _engine.init());
      } finally {
        _initializing = null;
      }
    }
    if (_bus == null) {
      _bus = _engine.createMixingBus(name: 'adaptive_music_${_serial++}');
      _bus!.playOnEngine();
    }
  }

  @override
  Future<Duration> load(MusicTrack track, int index) async {
    final Uint8List bytes;
    switch (track.source) {
      case TrackSource.asset:
        final data = await rootBundle.load(track.location);
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      case TrackSource.file:
        bytes = await File(track.location).readAsBytes();
      case TrackSource.url:
        final response = await http
            .get(Uri.parse(track.location))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw HttpException(
            'Audio download returned HTTP ${response.statusCode}',
          );
        }
        bytes = response.bodyBytes;
    }
    final source = await _engine.loadMem('adaptive_music_${_serial++}', bytes);
    _sources[index] = source;
    return _engine.getLength(source);
  }

  @override
  int schedule(int index, int engineTime) {
    final voice = _engine.playScheduled(
      _sources[index]!,
      Duration(microseconds: engineTime),
      busId: _bus!.busId,
      volume: 0,
    );
    if (voice.id == 0) {
      throw StateError('Audio engine could not start a voice.');
    }
    _engine.setInaudibleBehavior(voice, true, false);
    _engine.setProtectVoice(voice, true);
    _voices[voice.id] = voice;
    return voice.id;
  }

  @override
  void gain(int voice, double value, Duration smoothing) {
    final handle = _voices[voice];
    if (handle == null || !_engine.getIsValidVoiceHandle(handle)) return;
    if (smoothing == Duration.zero) {
      _engine.setVolume(handle, value);
    } else {
      _engine.fadeVolume(handle, value, smoothing);
    }
  }

  @override
  void pause(int voice, bool paused) {
    final handle = _voices[voice];
    if (handle != null && _engine.getIsValidVoiceHandle(handle)) {
      _engine.setPause(handle, paused);
    }
  }

  @override
  Future<void> stop(int voice) async {
    final handle = _voices.remove(voice);
    if (handle != null) await _engine.stop(handle);
  }

  @override
  void lowPass(LowPassFilter? settings, Duration transition) {
    final filter = _bus!.filters.biquadFilter;
    if (!_filterActive) {
      if (settings == null) return;
      filter.activate();
      filter.wet().value = 0;
      filter.type().value = 0;
      filter.frequency().value = settings.cutoffHz;
      filter.resonance().value = settings.resonance;
      _filterActive = true;
    }
    if (transition == Duration.zero) {
      if (settings != null) {
        filter.frequency().value = settings.cutoffHz;
        filter.resonance().value = settings.resonance;
      }
      filter.wet().value = settings == null ? 0 : 1;
    } else {
      if (settings != null) {
        filter.frequency().fadeFilterParameter(
          to: settings.cutoffHz,
          time: transition,
        );
        filter.resonance().fadeFilterParameter(
          to: settings.resonance,
          time: transition,
        );
      }
      filter.wet().fadeFilterParameter(
        to: settings == null ? 0 : 1,
        time: transition,
      );
    }
  }

  @override
  Future<void> clear() async {
    for (final voice in _voices.keys.toList()) {
      await stop(voice);
    }
    for (final source in _sources.values) {
      await _engine.disposeSource(source);
    }
    _sources.clear();
  }

  @override
  Future<void> dispose() async {
    await clear();
    _bus?.dispose();
    _bus = null;
    // SoLoud is shared with other app audio; never deinitialize it here.
  }
}
