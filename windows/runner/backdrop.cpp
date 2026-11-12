#include "backdrop.h"

#include <dwmapi.h>

namespace apexo {
namespace {

// The Windows SDK the runner builds against may predate the Windows 11
// backdrop attributes, so the values are restated here.
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
constexpr DWORD kDwmwaBorderColor = 34;
constexpr DWORD kDwmwaCaptionColor = 35;
#ifndef DWMWA_SYSTEMBACKDROP_TYPE
#define DWMWA_SYSTEMBACKDROP_TYPE 38
#endif

// DWMWA_COLOR_NONE: let the backdrop paint the caption and border too, instead
// of a colour that would cut a band across the glass.
constexpr DWORD kColorNone = 0xFFFFFFFE;

// DWMSBT_MAINWINDOW.
constexpr int kBackdropMica = 2;

void ApplyCaptionColors(HWND window) {
  COLORREF none = kColorNone;
  ::DwmSetWindowAttribute(window, kDwmwaCaptionColor, &none, sizeof(none));
  ::DwmSetWindowAttribute(window, kDwmwaBorderColor, &none, sizeof(none));
}

void ApplyDarkMode(HWND window, bool dark) {
  BOOL enable = dark;
  ::DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &enable,
                          sizeof(enable));
}

}  // namespace

bool ApplyMicaBackdrop(HWND window, bool dark) {
  if (window == nullptr) return false;

  int backdrop = kBackdropMica;
  if (FAILED(::DwmSetWindowAttribute(window, DWMWA_SYSTEMBACKDROP_TYPE,
                                     &backdrop, sizeof(backdrop)))) {
    return false;
  }

  ApplyDarkMode(window, dark);
  ApplyCaptionColors(window);

  // Treat the whole client area as part of the frame, which is what makes the
  // backdrop reach the pixels Flutter does not paint.
  MARGINS margins = {-1, -1, -1, -1};
  ::DwmExtendFrameIntoClientArea(window, &margins);
  return true;
}

void SetBackdropDark(HWND window, bool dark) {
  if (window == nullptr) return;
  ApplyDarkMode(window, dark);
  ApplyCaptionColors(window);
}

}  // namespace apexo
