// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:adaptive_music/adaptive_music.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:integration_test/integration_test.dart';
import 'audio_test.dart' show tone, rms;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('crossfade remains audible while the Dart isolate stalls', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp('music_review_');
    final a = await tone(dir, 'a', 600, 2);
    final b = await tone(dir, 'b', 900, 2);
    final player = AdaptiveMusicPlayer(
      transitions: const TransitionDefaults.immediate(),
    );
    final samples = <double>[];
    StreamSubscription<Uint8List>? capture;
    try {
      await player.load(
        tracks: [MusicTrack.file(a.path), MusicTrack.file(b.path)],
        repeat: MusicRepeatMode.all,
        transition: const TrackTransition.crossfade(
          duration: Duration(milliseconds: 500),
        ),
      );
      capture = SoLoud.instance.startMixerOutputStream().listen((chunk) {
        final data = ByteData.sublistView(chunk);
        for (var i = 0; i + 4 <= data.lengthInBytes; i += 4) {
          samples.add(data.getFloat32(i, Endian.little));
        }
      });
      player.setVolume(0.2, transition: Duration.zero);
      player.play();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      sleep(const Duration(milliseconds: 1900));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(samples.length, greaterThan(44100 * 5));
      var minimum = double.infinity;
      var silentWindows = 0;
      for (var i = 22050; i + 4410 < samples.length; i += 4410) {
        final power = rms(samples.sublist(i, i + 4410));
        minimum = math.min(minimum, power);
        if (power < 0.002) silentWindows++;
      }
      expect(
        minimum,
        greaterThan(0.002),
        reason: '$silentWindows silent 50ms windows captured during Dart stall',
      );
    } finally {
      SoLoud.instance.stopMixerOutputStream();
      await capture?.cancel();
      await player.dispose();
      await dir.delete(recursive: true);
    }
  });
}
