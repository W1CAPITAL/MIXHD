# Naruto Online Android Port 1.0

This port rebuilds the Windows launcher functionality for Android ARM64 instead of attempting to execute Windows PE binaries.

## Source client mapping

- `NarutoOnlinept.exe`: replaced by Android Activity + AIR application flow.
- `cefsimple.dll`, `libcef.dll`, CEF PAK/locale/ICU files: replaced by Android System WebView for login, portal, cookies and JavaScript.
- `PepperFlash/pepflashplayer32.dll`: the supplied original client identifies as `WIN 21,0,0,213`; replaced by the captive Adobe AIR AVM2/Stage3D runtime.
- `libEGL.dll`, `libGLESv2.dll`, `d3dcompiler_*.dll`: replaced by Android OpenGL ES/Stage3D.
- Windows helper/uninstaller/debug binaries: not required at runtime on Android.
- Kaguya `NPSWF32_30_0_0_113.dll`: replaced by AIR.
- Kaguya/Fiddler/OpenSSL Windows binaries: not executable on ARM64; legacy OAS HTTP/TLS handling is implemented in the Android native bridge.
- Portable `.swf`, `.png`, config and crossdomain assets can be retained without CPU conversion because they are data/Flash bytecode, not x86 native code.

## Runtime chain

The app preserves the official flow:

`login -> server S876 -> main.html -> token/server/version -> resolved CDN entry.swf -> config/ -> syscmd/ -> flash/ -> child SWFs/assets`

The final CDN URL is deliberately not rewritten with FlashVars. FlashVars are passed through `LoaderContext.parameters` so relative resource resolution remains anchored to:

`https://cdnnaruto-pt.oasgames.com/PT_NarutoAlpha9.34Build300/`

## Original launcher compatibility reproduced

The supplied official launcher uses CEF with the PPAPI switches `ppapi-flash-path`, `ppapi-flash-version` and `enable-gpu-plugin`, and the supplied PepperFlash binary reports `WIN 21,0,0,213`. Version 1.0 reproduces that Flash fingerprint in the browser bridge and sends the matching `X-Flash-Version` header while AIR executes the AS3 code.

The AIR LoaderContext enables remote code import so the bootstrap and its loaded child SWFs can execute inside the captive Android runtime.
