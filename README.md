# Windows 11 Media Controls

A frameless Flutter control surface for the active Windows 11 media session. It follows Fluent styling, uses a translucent Acrylic backdrop when Windows supports it, and adapts from a compact controls-only widget to a larger player with a timeline and album artwork.

## Behavior

- Follows the current Windows Global System Media Transport Controls session.
- Shows title, artist, album, source app, playback state, timeline, and artwork when the active source exposes them.
- Enables play, pause, previous, next, and seek only when the source advertises each capability.
- Uses compact metadata and controls below 500 logical pixels wide or 360 high, adds the timeline at medium sizes, and adds artwork at 760×400 or larger.
- Hides the native title bar without adding an in-app drag region.
- Lets Windows or an external window manager choose the initial position and size.
- Uses the normal Windows launch activation behavior. The Dart startup does not explicitly call `windowManager.focus()` or `windowManager.show()`, and the window is not always on top.
- Falls back to an opaque Fluent surface if Acrylic initialization fails.

## Requirements

- Windows 11
- Flutter 3.44.6 or another compatible Flutter release with Dart 3.12
- Visual Studio with the Desktop development with C++ workload

## Run and verify

```powershell
flutter pub get
flutter run -d windows
```

Run the automated checks with:

```powershell
dart analyze lib test
flutter test
flutter build windows --debug
```

Start playback in an application that publishes a Windows media session, such as a browser or music player. The app follows whichever session Windows reports as current.

## Implementation

The Dart layer uses `fluent_ui`, `flutter_acrylic`, and `window_manager`. An app-owned C++/WinRT bridge in `windows/runner/media_session_bridge.cpp` connects Flutter method and event channels to `GlobalSystemMediaTransportControlsSessionManager`. Session revisions protect commands and asynchronous artwork reads from being applied to a session that has already changed.

If you package the runner as MSIX, declare the `globalMediaControl` restricted capability in the package manifest so the packaged app can request global media-session access. The unpackaged Flutter development runner does not use an AppX manifest.
