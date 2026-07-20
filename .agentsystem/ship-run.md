# Ship run: Windows media controls app

Detected: CREATE
Risk: high — native Windows media-session APIs, an async platform boundary, and adaptive interactive UI
Mode: production — integration risk triggers the full gated workflow
Routing: inline (Skill tool unavailable; canonical add-feature instructions run in the parent context)

## Pipeline

- [x] Clarify — confirmed Windows 11 scope; excluded always-on-top and custom draggable region
- [x] Explore existing Flutter and Windows code — mapped the stock Flutter UI, Windows runner seam, toolchain, and test harness
- [x] Design native contract, responsive UI, and tests — selected an app-owned C++/WinRT bridge with capability-aware snapshots and adaptive Fluent UI
- [x] Approve implementation plan — user approved the revised frameless window design
- [x] Implement Flutter UI and Windows integration — added Fluent/Acrylic adaptive UI, frameless window setup, typed Dart controller, and C++/WinRT GSMTC bridge
- [x] Verify builds, tests, and live Windows path — analyzer clean, debug Windows build passed, current tests passed, and manager initialized live
- [x] Run gated reviews — code, native contract/concurrency, efficiency, duplication, loading, accessibility, dependency, and test-quality passes completed
- [x] Add automated tests — 25 model, controller, channel-contract, interaction, responsive, loading, backdrop, and semantics tests pass
- [x] Simplify and polish UI — removed redundant rebuilds/I/O, fixed pending/error lifecycles, and completed production UI polish

## Findings

- The project is a fresh Flutter 3.44.6 scaffold; no reusable app components or utilities exist.
- The final window contract is title-bar-free, resizable, intentionally has no in-app drag surface, and relies on the user's external window manager for positioning.
- GSMTC is asynchronous and event-driven; session swaps, stale metadata/artwork reads, rejected commands, and event cleanup require explicit handling.
- Packaged Windows builds need the `globalMediaControl` capability; unpackaged development behavior must be live-tested.
- Mica is intentionally opaque, so the widget uses Desktop Acrylic with a lighter Flutter surface tint.
- The native runner uses Flutter's normal activation and focus behavior; Dart does not explicitly focus or show the window through `window_manager`.
- The final native bridge caches media properties between timeline/playback events, rejects stale session commands and artwork reads, and caps artwork payloads at 4 MiB.
- The final launch probe confirmed Acrylic backdrop type 3, no `WS_EX_NOACTIVATE` style, normal foreground activation, and a responsive Windows-default window; the app does not set that geometry itself.
- The remaining integration-test boundary is Windows GSMTC itself: automated tests pin the Dart/native channel contract, while native availability is covered by a Windows compile and live manager launch probe because active third-party media sessions are external state.

## Proposed implementation plan

- Add Fluent UI, Windows Mica, and `window_manager`; hide the native title bar without adding any in-app drag surface.
- Do not set a Dart-side initial size or center position, and let the native runner use normal Windows launch activation.
- Add Dart media models, a platform service abstraction, and a controller that follows the active session and extrapolates timeline progress.
- Add an app-owned C++/WinRT bridge using MethodChannel for commands and EventChannel for atomic session snapshots.
- Subscribe to manager/session changes, revoke tokens on replacement/shutdown, gate commands by advertised capabilities, and protect async work with session revisions.
- Cache bounded Windows artwork bytes and expose them on demand.
- Build compact, medium, and large responsive layouts with empty, loading, error, and missing-artwork states.
- Add model/controller/widget tests, run analyzer/tests/build, then exercise the live Windows media path.
- Run gated contract, concurrency, observability, failure-UX, accessibility/responsive, bundle, dependency, code, and duplication reviews.
