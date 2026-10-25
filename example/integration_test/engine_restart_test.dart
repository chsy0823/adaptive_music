// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:adaptive_music/adaptive_music.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'audio_test.dart' show tone, rms;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('engine restart resumes position, tone and pause state', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('music_restart_');
    final high = await tone(dir, 'high', 6000, 12);
    final low = await tone(dir, 'low', 600, 2);
    final music = AdaptiveMusicPlayer(
      transitions: const TransitionDefaults.immediate(),
    );
    final paused = AdaptiveMusicPlayer(
      transitions: const TransitionDefaults.immediate(),
    );
    final samples = <double>[];
    StreamSubscription<Uint8List>? capture;
    void startCapture() {
      capture = SoLoud.instance.startMixerOutputStream().listen((chunk) {
        final data = ByteData.sublistView(chunk);
        for (var i = 0; i + 4 <= data.lengthInBytes; i += 4) {
          samples.add(data.getFloat32(i, Endian.little));
        }
      });
    }

    Future<void> stopCapture() async {
      SoLoud.instance.stopMixerOutputStream();
      await capture?.cancel();
      capture = null;
    }

    Future<double> measure() async {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      samples.clear();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(samples, isNotEmpty);
      return rms(samples);
    }

    try {
      await music.load(
        tracks: [MusicTrack.file(high.path)],
        repeat: MusicRepeatMode.one,
      );
      await paused.load(
        tracks: [MusicTrack.file(low.path)],
        repeat: MusicRepeatMode.one,
      );
      startCapture();
      paused.play();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      paused.pause();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(paused.state.status, PlaybackStatus.paused);
      final pausedPosition = paused.state.position;
      music.setVolume(0.3, transition: Duration.zero);
      music.play();
      final dry = await measure();
      music.setFilter(
        const LowPassFilter(cutoffHz: 500),
        transition: Duration.zero,
      );
      final wet = await measure();
      expect(wet, lessThan(dry * 0.2));
      final before = music.state.position;

      // The capture stream belongs to the engine being shut down.
      await stopCapture();
      await AdaptiveMusicPlayer.restartEngine();

      expect(music.state.status, PlaybackStatus.playing);
      expect(music.state.position, greaterThanOrEqualTo(before));
      expect(
        music.state.position,
        lessThan(before + const Duration(seconds: 1)),
      );
      expect(paused.state.status, PlaybackStatus.paused);
      expect(paused.state.position, pausedPosition);
      startCapture();
      final restoredWet = await measure();
      expect(
        restoredWet,
        lessThan(dry * 0.2),
        reason: 'The low-pass filter must survive the restart',
      );
      music.clearFilter(transition: Duration.zero);
      final restoredDry = await measure();
      expect(
        restoredDry,
        greaterThan(dry * 0.8),
        reason: 'Audio must flow again at the previous level',
      );
      paused.play();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(paused.state.status, PlaybackStatus.playing);
      expect(paused.state.position, greaterThan(pausedPosition));
    } finally {
      await stopCapture();
      await music.dispose();
      await paused.dispose();
      await dir.delete(recursive: true);
    }
  });
}
