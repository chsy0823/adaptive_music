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
