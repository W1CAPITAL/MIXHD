$ErrorActionPreference='Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# Add one-shot Cloudflare fallback state.
$field='private volatile String lastObservedLocation = "";'
if(!$s.Contains($field)){throw 'lastObservedLocation field missing'}
if(!$s.Contains('private volatile boolean cloudflareLoginFallbackStarted')){
  $s=$s.Replace($field,$field+[Environment]::NewLine+'    private volatile boolean cloudflareLoginFallbackStarted = false;')
}

# Initial gamebox login must keep the real Android UA.
$uaBlock=@'
                if (url != null && url.contains("gamebox3.narutowebgame.com")) {
                    String launcherUa = buildDesktopGameUa(nativeUserAgent);
                    s.setUserAgentString(launcherUa);
                    activeUserAgent = launcherUa;
                    desktopGameUaActive = true;
                    setState("official-launcher desktop UA enabled");
                }
'@
if(!$s.Contains($uaBlock.Trim())){throw 'initial desktop UA block missing'}
$uaNew=@'
                if (url != null && url.contains("gamebox3.narutowebgame.com") && url.contains("/template/login.php")) {
                    s.setUserAgentString(nativeUserAgent);
                    activeUserAgent = nativeUserAgent;
                    desktopGameUaActive = false;
                    setState("official-login native Android UA enabled");
                } else if (url != null && url.contains("gamebox3.narutowebgame.com")) {
                    String launcherUa = buildDesktopGameUa(nativeUserAgent);
                    s.setUserAgentString(launcherUa);
                    activeUserAgent = launcherUa;
                    desktopGameUaActive = true;
                    setState("official-launcher desktop UA enabled");
                }
'@
$s=$s.Replace($uaBlock.Trim(),$uaNew.Trim())

# Helper for server-side 403/WAF fallback.
$marker='    private void detectCloudflareBlock(final WebView view) {'
if(!$s.Contains($marker)){throw 'detectCloudflareBlock marker missing'}
$helper=@'
    private void startCloudflareLoginFallback(final WebView view, String blockedUrl) {
        if (view == null || cloudflareLoginFallbackStarted) return;
        String low = blockedUrl == null ? "" : blockedUrl.toLowerCase();
        if (!low.contains("gamebox3.narutowebgame.com") || !low.contains("/template/login.php")) return;
        cloudflareLoginFallbackStarted = true;
        setState("CLOUDFLARE 403 login -> public Naruto portal fallback");
        handler.postDelayed(() -> {
            if (view != webView) return;
            try {
                view.stopLoading();
                if (nativeUserAgent != null && !nativeUserAgent.isEmpty()) {
                    view.getSettings().setUserAgentString(nativeUserAgent);
                    activeUserAgent = nativeUserAgent;
                    desktopGameUaActive = false;
                }
                String fallback = "https://naruto.narutowebgame.com/pt/serverlist/?leftbar_collapse=yes&logintype=4";
                currentGamePage = fallback;
                view.loadUrl(fallback);
                trace("CLOUDFLARE FALLBACK loadUrl " + fallback);
            } catch (Throwable t) {
                setState("CLOUDFLARE fallback ERROR " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
            }
        }, 250);
    }

'@
$s=$s.Replace($marker,$helper+$marker)

# DOM Cloudflare detection should trigger fallback, not only log it.
$cfOld='if (value != null && value.toLowerCase().contains("yes")) setState("CLOUDFLARE BLOCK: current-UA=" + (desktopGameUaActive ? "desktop-game" : "native"));'
if(!$s.Contains($cfOld)){throw 'Cloudflare DOM detection line missing'}
$cfNew=@'
if (value != null && value.toLowerCase().contains("yes")) {
                    setState("CLOUDFLARE BLOCK: current-UA=" + (desktopGameUaActive ? "desktop-game" : "native"));
                    startCloudflareLoginFallback(view, view.getUrl());
                }
'@
$s=$s.Replace($cfOld,$cfNew.Trim())

# HTTP 403 main-frame detection should trigger immediately.
$httpLine='if (ec >= 400) trace("ERROR HTTP " + ec + " main=" + (request != null && request.isForMainFrame()) + " url=" + abbreviate(eu,220));'
if(!$s.Contains($httpLine)){throw 'HTTP error trace line missing'}
$httpNew=@'
if (ec >= 400) trace("ERROR HTTP " + ec + " main=" + (request != null && request.isForMainFrame()) + " url=" + abbreviate(eu,220));
                            if (ec == 403 && request != null && request.isForMainFrame()) {
                                startCloudflareLoginFallback(view, eu);
                            }
'@
$s=$s.Replace($httpLine,$httpNew.Trim())

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.8.0</versionNumber>','<versionNumber>0.8.1</versionNumber>')
$x=$x.Replace('<versionLabel>0.8.0 final CDN SWF handoff</versionLabel>','<versionLabel>0.8.1 Cloudflare login fallback</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.8.0</name>','<name>Naruto AIR Experimental 0.8.1</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.8.0 - final CDN entry.swf handoff...','Naruto AIR 0.8.1 - Cloudflare login fallback + final CDN entry.swf...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.8.0";','public static const VERSION:String = "0.8.1";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.8.1 patch applied: native UA on gamebox login and automatic public portal fallback on Cloudflare 403.'
