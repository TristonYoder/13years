# 13YearsClockKit

`ThirteenYearsClockKit` is the 13 Years engine as a Swift package: the models and wire types (`CuePacket`, `RoleCue`, `PCOTimerItem`, `TimerAnchor`, `SyncHash`), `CueEngine` with Sync v2, the Control API router, models and event hub, the remote-control mirror, and the Planning Center and Plotiphar clients.

It is the single engine behind every Producer:

```
ThirteenYearsClockKit  (this package: Apple platforms + Linux)
├── Apple adapters, inside the package behind #if canImport
│     Network.framework LAN feed and Bonjour, ControlAPIServer, Keychain, os.Logger, OAuth
├── Producer Mac / iPad, Pager iOS / Mac / TV apps  (project.yml links the package; Sources/Shared/ClockKitExports.swift re-exports it)
└── Headless Producer (private 13years-server repo, Linux)
      SwiftNIO LAN backend via LANTransportRegistry, Hummingbird front for ControlAPIRouter / ControlAPIEventHub
```

## Platforms

- **Apple** (macOS 14, iOS 17, tvOS 17, watchOS 10): behaviour is identical to the code before extraction. The Watch target still compiles a handful of model files by path (see `project.yml`).
- **Linux** (Swift 6.3): Combine comes from OpenCombine and CryptoKit from swift-crypto, both Linux-only dependencies.
  - Logging goes to stderr through an `os.Logger`-compatible shim; set the level with `THIRTEEN_LOG_LEVEL`.
  - The Keychain is a JSON file store in `THIRTEEN_DATA_DIR`.
  - `UserDefaults` persists to `$XDG_CONFIG_HOME/<process>.plist`. The host calls `synchronize()` itself.
  - The device name comes from `THIRTEEN_NAME`.
  - Timers use `MainLoopTimer`, which is a main-queue dispatch timer on Linux, so the host must park the main thread in `dispatchMain()`. `RunLoop.main.run()` does not run main-actor jobs on Linux.
  - The LAN feed is supplied by the host through `LANTransportRegistry.makeServer` / `makeClient`.
  - The Control API is hosted outside the engine: build `ControlAPIRouter(engine:connectedClientCount:)`, then `ControlAPIEventHub(engine:broadcaster:router:)` with your own `ControlAPIBroadcaster`.

## Building

```bash
swift build
xcodegen generate && xcodebuild -scheme ProducerMac build
```

The first command builds the package alone, on macOS or Linux. The second builds the apps, run from the repository root.

The app test suite (`ThirteenYearsTests`) uses `@testable import ThirteenYearsClockKit`.
