// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:adaptive_music/adaptive_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<File> tone(Directory dir, String name, double hz, int seconds) async {
  const rate = 44100;
  final count = rate * seconds;
  final bytes = ByteData(44 + count * 2);
  void ascii(int at, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(at + i, value.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + count * 2, Endian.little);
  ascii(8, 'WAVEfmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, count * 2, Endian.little);
  for (var i = 0; i < count; i++) {
    bytes.setInt16(
      44 + i * 2,
      (8000 * math.sin(2 * math.pi * hz * i / rate)).round(),
      Endian.little,
    );
  }
  return File('${dir.path}/$name.wav').writeAsBytes(bytes.buffer.asUint8List());
}

double rms(List<double> samples) => math.sqrt(
  samples.fold<double>(0, (sum, s) => sum + s * s) / samples.length,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native audio remains continuous and DSP attenuates high frequencies',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Native audio verification')),
          ),
        ),
      );
      final directory = await Directory.systemTemp.createTemp(
        'adaptive_music_test_',
      );
      final a = await tone(directory, 'a', 600, 2);
      final b = await tone(directory, 'b', 900, 2);
      final high = await tone(directory, 'high', 6000, 8);
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
        player.setVolume(0.3, transition: Duration.zero);
        player.play();
        await Future<void>.delayed(const Duration(milliseconds: 1700));
        expect(samples.length, greaterThan(44100));
        // Ignore output startup and capture's final partial chunk. Each 50 ms
        // window spanning the first track change must carry non-silent audio.
        const window = 4410; // 50 ms at 44.1 kHz, stereo.
        for (
          var offset = 22050;
          offset + window < samples.length;
          offset += window
        ) {
          expect(
            rms(samples.sublist(offset, offset + window)),
            greaterThan(0.002),
            reason: 'Unexpected silence at sample $offset',
          );
        }
        player.pause(transition: const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 450));
        expect(player.state.status, PlaybackStatus.paused);
        samples.clear();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (samples.isNotEmpty) expect(rms(samples), lessThan(0.001));
        final position = player.state.position;
        player.play();
        expect(player.state.position, position);
        samples.clear();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(samples, isNotEmpty);
        expect(rms(samples), greaterThan(0.002));

        await player.load(
          tracks: [MusicTrack.file(a.path), MusicTrack.file(b.path)],
          transition: const TrackTransition.gapless(),
        );
        samples.clear();
        player.play();
        await Future<void>.delayed(const Duration(milliseconds: 2700));
        expect(samples.length, greaterThan(44100));
        for (
          var offset = 22050;
          offset + window < samples.length;
          offset += window
        ) {
          expect(
            rms(samples.sublist(offset, offset + window)),
            greaterThan(0.002),
            reason: 'Gapless boundary contains silence at sample $offset',
          );
        }

        await player.load(tracks: [MusicTrack.file(high.path)]);
        player.play();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        samples.clear();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(samples, isNotEmpty);
        final dry = rms(samples);
        player.setFilter(
          const LowPassFilter(cutoffHz: 500),
          transition: const Duration(milliseconds: 150),
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));
        samples.clear();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(samples, isNotEmpty);
        final wet = rms(samples);
        expect(
          wet,
          lessThan(dry * 0.2),
          reason: 'Low-pass should attenuate the 6 kHz tone',
        );
        player.clearFilter(transition: const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 350));
        samples.clear();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(rms(samples), greaterThan(dry * 0.8));
      } finally {
        SoLoud.instance.stopMixerOutputStream();
        await capture?.cancel();
        await player.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
}
