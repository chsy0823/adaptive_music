// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:adaptive_music/adaptive_music.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:integration_test/integration_test.dart';
import 'audio_test.dart' show tone;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('rapid skips preserve another player output', (tester) async {
    final dir = await Directory.systemTemp.createTemp('dsp_cycles_');
    final file = await tone(dir, 'tone', 997, 30);
    final player = AdaptiveMusicPlayer();
    final authored = AdaptiveMusicPlayer();
    final samples = <double>[];
    StreamSubscription<Uint8List>? capture;
    try {
      await player.load(
        tracks: [
          MusicTrack.file(file.path),
          MusicTrack.file(file.path),
          MusicTrack.file(file.path),
        ],
        repeat: MusicRepeatMode.one,
        transition: const TrackTransition.crossfade(
          duration: Duration(seconds: 8),
        ),
      );
      capture = SoLoud.instance.startMixerOutputStream().listen((bytes) {
        final data = ByteData.sublistView(bytes);
        for (var i = 0; i + 8 <= data.lengthInBytes; i += 8) {
          samples.add(data.getFloat32(i, Endian.little));
        }
      });
      await authored.load(
        tracks: [MusicTrack.file(file.path)],
        repeat: MusicRepeatMode.one,
      );
      authored.setVolume(0.3);
      player.setVolume(0.4);
      player.play();
      for (var cycle = 0; cycle < 8; cycle++) {
        authored.pause(transition: const Duration(milliseconds: 300));
        player.play();
        for (var skip = 0; skip < 24; skip++) {
          player.skipTo(skip % 3);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        debugPrint(
          'RAPID_SKIP cycle=$cycle voices=${SoLoud.instance.getVoiceCount()}',
        );
        expect(SoLoud.instance.getVoiceCount(), lessThanOrEqualTo(10));
        player.setFilter(
          const HighShelfFilter(frequencyHz: 2000, gainDb: -6),
          transition: const Duration(milliseconds: 300),
        );
        player.setVolume(0.22, transition: const Duration(milliseconds: 300));
        final token = player.requestDucking(gain: 0.45);
        await Future<void>.delayed(const Duration(milliseconds: 650));
        player.clearFilter(transition: const Duration(milliseconds: 300));
        player.setVolume(0.4, transition: const Duration(milliseconds: 300));
        player.releaseDucking(
          token,
          transition: const Duration(milliseconds: 300),
        );
        await Future<void>.delayed(const Duration(milliseconds: 650));
        player.pause(transition: const Duration(milliseconds: 300));
        authored.play();
        await Future<void>.delayed(const Duration(seconds: 1));
        samples.clear();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        debugPrint(
          'DSP_STATE cycle=$cycle status=${player.state.status} capture=${SoLoud.instance.isMixerOutputStreamRunning} voices=${SoLoud.instance.getVoiceCount()}',
        );
        expect(samples.length, greaterThan(4000));
        var error = 0.0, power = 0.0, peak = 0.0;
        final c = 2 * math.cos(2 * math.pi * 997 / 44100);
        for (var i = 2; i < samples.length; i++) {
          final d = samples[i] - c * samples[i - 1] + samples[i - 2];
          error += d * d;
          power += samples[i] * samples[i];
          peak = math.max(peak, samples[i].abs());
        }
        final ratio = math.sqrt(error / power);
        // Diagnostic signal residual, not a subjective audio-quality verdict.
        debugPrint(
          'DSP_PROBE cycle=$cycle residual=$ratio peak=$peak samples=${samples.length}',
        );
        expect(ratio, lessThan(0.01));
      }
    } finally {
      SoLoud.instance.stopMixerOutputStream();
      await capture?.cancel();
      await player.dispose();
      await authored.dispose();
      await dir.delete(recursive: true);
    }
  });
}
