#ifndef RUNNER_BACKDROP_H_
#define RUNNER_BACKDROP_H_

#include <windows.h>

namespace apexo {

// Paints the window's background with a DWM system backdrop (Mica): the
// desktop wallpaper, blurred and tinted, drawn by the compositor behind the
// client area. Flutter's view has to leave its own background unpainted for the
// material to show, so the Dart side only does that when this call succeeded.
//
// Returns false on Windows 10, on a build older than 22H2 (where the attribute
// does not exist) and whenever DWM refuses the request; the app then paints its
// own stand-in material.
bool ApplyMicaBackdrop(HWND window, bool dark);

// Switches the caption and the backdrop between light and dark, following the
// app's own theme rather than the system's.
void SetBackdropDark(HWND window, bool dark);

}  // namespace apexo

#endif  // RUNNER_BACKDROP_H_
