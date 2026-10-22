import 'package:apexo/ui/workspace/panel_width.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the panel fills a phone and keeps a fixed 350px column elsewhere', () {
    expect(computePanelWidth(screenWidth: 360), 360);
    expect(computePanelWidth(screenWidth: 800), 350);
    expect(computePanelWidth(screenWidth: 1600), 350);
  });
}
