import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:http/http.dart' as http;
import 'audio_backend.dart';
import 'models.dart';
import 'envelope.dart';
import 'gain_worker.dart';

/// Each player owns a bus and uniquely named sources, never global filters.
class SoloudBackend implements AudioBackend {
  static int _serial = 0;
  static Future<void>? _initializing;
  late final _engine = SoLoud.instance;
  final _sources = <int, AudioSource>{};
  final _voices = <int, SoundHandle>{};
  Bus? _bus;
  GainWorker? _gains;
  bool _filterActive = false;
  @override
  int get now => _bus != null ? _engine.getEngineTime().inMicroseconds : 0;
  @override
  Future<void> initialize() async {
    if (!_engine.isInitialized) {
      try {
        await (_initializing ??= _engine.init());
      } finally {
        _initializing = null;
      }
    }
    _gains ??= await GainWorker.start();
    if (_bus == null) {
      _bus = _engine.createMixingBus(name: 'adaptive_music_${_serial++}');
      _bus!.playOnEngine();
      // Keep the STFT path present from startup to avoid a latency jump when
      // changing filter type. Unity gains leave the spectrum unchanged.
      final shelf = _bus!.filters.parametricEqFilter;
      shelf.activate();
      shelf.numBands().value = 64;
      for (var i = 0; i < 64; i++) {
        shelf.bandGain(i).value = 1;
      }
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
  int schedule(
    int index,
    int engineTime, {
    Duration offset = Duration.zero,
    Duration duration = Duration.zero,
  }) {
    final voice = _engine.playScheduled(
      _sources[index]!,
      Duration(microseconds: engineTime),
      duration: duration,
      busId: _bus!.busId,
      volume: 0,
    );
    if (voice.id == 0) {
      throw StateError('Audio engine could not start a voice.');
    }
    if (offset > Duration.zero) _engine.seek(voice, offset);
    _engine.setInaudibleBehavior(voice, true, false);
    _engine.setProtectVoice(voice, true);
    _voices[voice.id] = voice;
    return voice.id;
  }

  @override
  void automate(int voice, GainAutomation automation) {
    _gains!.automate(voice, automation);
  }

  @override
  void gain(int voice, double value, Duration smoothing) {
    _gains!.gain(voice, value, smoothing);
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
    if (handle != null) {
      await _gains!.remove(voice);
      await _engine.stop(handle);
    }
  }

  @override
  void setFilter(MusicFilter? settings, Duration transition) {
    _lowPass(settings is LowPassFilter ? settings : null, transition);
    final shelf = _bus!.filters.parametricEqFilter;
    for (var i = 0; i < 64; i++) {
      var gain = 1.0;
      if (settings is HighShelfFilter) {
        final frequency = shelf.bandFrequency(i);
        final x = (math.log(frequency / settings.frequencyHz) / math.ln2 + 0.5)
            .clamp(0.0, 1.0);
        final blend = x * x * (3 - 2 * x);
        gain = math.pow(10, settings.gainDb * blend / 20).toDouble();
      }
      if (transition == Duration.zero) {
        shelf.bandGain(i).value = gain;
      } else {
        shelf.bandGain(i).fadeFilterParameter(to: gain, time: transition);
      }
    }
  }

  void _lowPass(LowPassFilter? settings, Duration transition) {
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
    await _gains?.dispose();
    _gains = null;
    _bus?.dispose();
    _bus = null;
    // SoLoud is shared with other app audio; never deinitialize it here.
  }
}
