/// Width of the side panel on [screenWidth].
///
/// A panel is a fixed `350px` column, and fills the screen on phone-width
/// viewports (`< 490`), where there is no room for anything beside it.
///
/// Panels never widen for their content. An editor that needs more room — the
/// dental chart, for one — opens in its own window (`WindowsLayer`), so a panel
/// never resizes the screen behind it.
double computePanelWidth({required double screenWidth}) {
  return screenWidth < 490 ? screenWidth : 350;
}

