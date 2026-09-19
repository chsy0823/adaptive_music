// SoLoud's public isolate bindings only touch the shared native mixer here.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:isolate';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'envelope.dart';

/// Keeps gain automation running when the host's UI isolate is busy.
/// Loading, playback registration and engine ownership stay on the host isolate.
class GainWorker {
  GainWorker._(this._commands);
  final SendPort _commands;

  static Future<GainWorker> start() async {
    final ready = ReceivePort();
    await Isolate.spawn(_run, ready.sendPort);
    final commands = await ready.first as SendPort;
    ready.close();
    return GainWorker._(commands);
  }

  void automate(int voice, GainAutomation automation) =>
      _commands.send((voice, automation));

  void gain(int voice, double value, Duration smoothing) =>
      _commands.send((voice, value, smoothing));

  Future<void> remove(int voice) async {
    final reply = ReceivePort();
    _commands.send((voice, reply.sendPort));
    await reply.first;
    reply.close();
  }

  Future<void> dispose() async {
    final reply = ReceivePort();
    _commands.send(reply.sendPort);
    await reply.first;
    reply.close();
  }
}

void _run(SendPort ready) {
  final commands = ReceivePort();
  final engine = SoLoudIsolate.instance.bindings;
  final plans = <int, GainAutomation>{};
  void apply(int voice, double value, Duration smoothing) {
    final handle = SoundHandle(voice);
    if (!engine.getIsValidVoiceHandle(handle)) return;
    if (smoothing == Duration.zero) {
      engine.setVolume(handle, value);
    } else {
      engine.fadeVolume(handle, value, smoothing);
    }
  }

  void update(int voice, GainAutomation plan) {
    final now = engine.getEngineTime().inMicroseconds;
    apply(
      voice,
      plan.at(now),
      now < plan.start ? Duration.zero : const Duration(milliseconds: 10),
    );
  }

  final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
    for (final entry in plans.entries) {
      update(entry.key, entry.value);
    }
  });
  commands.listen((message) {
    switch (message) {
      case (int voice, GainAutomation plan):
        plans[voice] = plan;
        update(voice, plan);
      case (int voice, double value, Duration smoothing):
        plans.remove(voice);
        apply(voice, value, smoothing);
      case (int voice, SendPort reply):
        plans.remove(voice);
        reply.send(null);
      case SendPort reply:
        timer.cancel();
        plans.clear();
        commands.close();
        reply.send(null);
    }
  });
  ready.send(commands.sendPort);
}
