# FakeTwitter

Companion demo app for reliable data uploading on iOS across four levels.

## Structure

- `FakeTwitter/FakeTwitter/Shared`
- `FakeTwitter/FakeTwitter/Level1`
- `FakeTwitter/FakeTwitter/Level2`
- `FakeTwitter/FakeTwitter/Level3`
- `FakeTwitter/FakeTwitter/Level4`
- `FakeTwitter/Server`
- `FakeTwitter/Server/src/levels/level1.js`
- `FakeTwitter/Server/src/levels/level2.js`
- `FakeTwitter/Server/src/levels/level3.js`
- `FakeTwitter/Server/src/levels/level4.js`

Each tab reuses the same timeline/composer UI and injects a different upload service.

## Run the local API

```bash
cd FakeTwitter/Server
npm install
npm start
```

## Run the app

1. Open `FakeTwitter/FakeTwitter.xcodeproj`.
2. Run on iOS Simulator.
3. Ensure the server is running at `http://localhost:8080`.

If testing on a physical device, update `FakeTwitter/FakeTwitter/Shared/Config/AppEnvironment.swift` to your Mac's LAN IP, e.g. `http://192.168.1.50:8080`.

## Level behavior

- **Level 1**: one-shot fire-and-forget upload.
- **Level 2**: retry strategies selectable in segmented control.
- **Level 3**: resumable video upload with persisted offset + background URLSession chunk uploads.
  - In this sample, each chunk can continue in the background, but scheduling the next chunk happens when app code runs again.
- **Level 4**: durable SwiftData queue and state machine (`pending/uploading/failed/succeeded`) retried on launch.
