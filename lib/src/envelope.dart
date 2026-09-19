import 'dart:math' as math;
import 'models.dart';

/// A retargetable linear gain envelope, with time expressed in microseconds.
class Envelope {
  Envelope(double value) : _from = value, target = value;
  double _from;
  double target;
  int _start = 0;
  int _duration = 0;
  double at(int time) {
    if (_duration == 0) return target;
    final fraction = ((time - _start) / _duration).clamp(0.0, 1.0);
    return _from + (target - _from) * fraction;
  }

  void moveTo(double value, int now, int duration) {
    _from = at(now);
    target = value;
    _start = now;
    _duration = duration;
  }
}

/// A complete gain plan evaluated against the engine clock, independent of UI ticks.
class GainAutomation {
  GainAutomation({
    required this.start,
    required this.end,
    required this.fadeIn,
    required this.fadeOut,
    required this.fixedGain,
    required this.curve,
    required this.volume,
    required this.duck,
    required this.transport,
  });
  final int start, end, fadeIn, fadeOut;
  final double fixedGain;
  final FadeCurve curve;
  final Envelope volume, duck, transport;

  double at(int now) =>
      clipGain(
        math.max(now, start),
        start,
        end,
        fadeIn,
        fadeOut,
        fixedGain,
        curve,
      ) *
      volume.at(now) *
      duck.at(now) *
      transport.at(now);
}

double clipGain(
  int time,
  int start,
  int end,
  int fadeIn,
  int fadeOut,
  double fixedGain,
  FadeCurve curve,
) {
  if (time >= end) return 0;
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
