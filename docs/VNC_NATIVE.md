# Native VNC Viewer (LibVNCClient)

Goal: replace the WebView/noVNC path with a native VNC client implemented via N-API, rendering frames in ArkTS.

## Status
- Build plumbing added: CMake detects `third_party/libvncclient/libvncclient.a` and defines `LIBVNC_HAVE_CLIENT` when present.
- N-API surface (stubs implemented):
  - `vncAvailable(): boolean`
  - `vncCreate(): number` — returns a session id
  - `vncConnect(id: number, host: string, port: number): boolean`
  - `vncDisconnect(id: number): boolean`
  - `vncGetFrame(id: number): { width, height, pixels: ArrayBuffer } | null`
- ArkTS wrappers:
  - `entry/src/main/ets/managers/VNCNativeClient.ets`
  - Page: `pages/VNCNativeViewer` (Start VM with `display: vnc=:1` and attempt native connect)

Real frame decoding is not wired yet — code compiles and UI is in place to switch away from noVNC and verify availability. Once `libvncclient.a` is provided, we can implement the event loop and frame callbacks.

## How to provide LibVNCClient

Place the prebuilt client static library and headers under:

- `entry/src/main/cpp/third_party/libvncclient/libvncclient.a`
- Headers (expected include root): `entry/src/main/cpp/third_party/libvncclient/include/rfb/rfbclient.h` (and deps)

Rebuild native: `hvigor :entry:default@BuildNativeWithNinja`

CMake will print:
- `Found VNC client library: .../libvncclient.a`
- `LIBVNC_HAVE_CLIENT` defined

## Next steps (implementation plan)

1) Wire LibVNCClient
- Create `VncSession` (rfbClient*, worker thread)
- Set callbacks: `MallocFrameBuffer`, `GotFrameBufferUpdate`, `SoftCursor*`, `GotXCutText`
- Connect via `rfbInitClient()` with `serverHost/Port` set

2) Frame pipeline
- Convert rfbClient->frameBuffer (8/16/32 bpp) to RGBA8888
- Push into a ring buffer protected by mutex
- Expose via `vncGetFrame()` returning an ArrayBuffer

3) Input
- N-API: `vncSendPointer(x,y,mask)`, `vncSendKey(key,down)` mapping to LibVNCClient helpers

4) ArkTS rendering
- Use Canvas (drawPixelMap) or PixelMap to blit RGBA frames
- Poll on a timer (30–60 fps) and render latest frame

5) Feature parity
- Resize handling, clipboard, encodings (start with RAW/Tight/ZRLE), perf knobs

## Why client (not server)
While the project name is LibVNCServer, the same repo ships LibVNCClient which is what we need to connect to QEMU’s VNC server.

