/// A fixed 350px column that fills phone-width screens (`< 490`). Panels never
/// widen for content, so an editor that needs room opens in its own window.
double computePanelWidth({required double screenWidth}) {
  return screenWidth < 490 ? screenWidth : 350;
}

