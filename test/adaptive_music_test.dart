import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_music/src/envelope.dart';

void main() {
  test('retargeting a fade continues from the audible value', () {
    final envelope = Envelope(1);
    envelope.moveTo(0, 0, 1000);
    expect(envelope.at(400), closeTo(0.6, 0.0001));
    envelope.moveTo(1, 400, 600);
    expect(envelope.at(400), closeTo(0.6, 0.0001));
    expect(envelope.at(700), closeTo(0.8, 0.0001));
    expect(envelope.at(1000), 1);
  });
}
