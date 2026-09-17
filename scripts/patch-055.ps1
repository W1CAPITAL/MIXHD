$ErrorActionPreference = 'Stop'

$p = 'ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s = Get-Content $p -Raw

$fieldNeedle = 'private volatile String activeUserAgent = "";'
if (!$s.Contains($fieldNeedle)) { throw 'activeUserAgent field not found' }
$fieldReplacement = $fieldNeedle + [Environment]::NewLine + '    private volatile String currentGamePage = "";'
$s = $s.Replace($fieldNeedle, $fieldReplacement)

$proxyNeedle = @'
if(typeof callbackFn==='function'){try{callbackFn({success:true,id:replaceElemId,ref:el||null});}catch(cb){}}return true;
'@
$proxyNeedle = $proxyNeedle.Trim()
if (!$s.Contains($proxyNeedle)) { throw 'swfobject callback needle not found' }
$proxyReplacement = @'
var ref=el||{};try{if(typeof Proxy==='function'){ref=new Proxy(ref,{get:function(t,p){if(p in t)return t[p];if(p==='PercentLoaded')return function(){return 100;};if(p==='GetVariable')return function(v){return '';};if(p==='SetVariable')return function(){return '';};if(p==='CallFunction')return function(x){window.__narutoAirFlashCalls=window.__narutoAirFlashCalls||[];window.__narutoAirFlashCalls.push(String(x));return '';};return function(){return '';};}});}}catch(pe){}if(typeof callbackFn==='function'){try{callbackFn({success:true,id:replaceElemId,ref:ref});}catch(cb){window.__narutoAirErrors=window.__narutoAirErrors||[];window.__narutoAirErrors.push(String(cb));}}return true;
'@
$proxyReplacement = $proxyReplacement.Trim()
$s = $s.Replace($proxyNeedle, $proxyReplacement)

$tailNeedle = 'window.__narutoAirAdapterInstalled=true;window.__narutoAirPatch();'
if (!$s.Contains($tailNeedle)) { throw 'adapter tail not found' }
$tailReplacement = @'
window.__narutoAirErrors=window.__narutoAirErrors||[];try{window.addEventListener('error',function(ev){try{window.__narutoAirErrors.push(String(ev.message||ev.error||'js-error'));}catch(x){}});}catch(x){}window.__narutoAirAdapterInstalled=true;window.__narutoAirPatch();
'@
$s = $s.Replace($tailNeedle, $tailReplacement.Trim())

$chromeNeedle = 'webView.setWebChromeClient(new WebChromeClient());'
if (!$s.Contains($chromeNeedle)) { throw 'WebChromeClient line not found' }
$chromeReplacement = @'
webView.setWebChromeClient(new WebChromeClient() {
    @Override public boolean onConsoleMessage(android.webkit.ConsoleMessage cm) {
        try {
            String msg = cm == null ? "" : String.valueOf(cm.message());
            String low = msg.toLowerCase();
            if (!msg.isEmpty() && (low.contains("swf") || low.contains("flash") || low.contains("server") || low.contains("game"))) {
                setState("JS console: " + msg);
            }
        } catch (Throwable ignored) { }
        return super.onConsoleMessage(cm);
    }
});
'@
$s = $s.Replace($chromeNeedle, $chromeReplacement.Trim())

$pageNeedle = 'setState("page-started " + pageUrl);'
if (!$s.Contains($pageNeedle)) { throw 'page-started line not found' }
$pageReplacement = $pageNeedle + [Environment]::NewLine + '                        if (isLikelyGameUrl(pageUrl)) currentGamePage = pageUrl;'
$s = $s.Replace($pageNeedle, $pageReplacement)

$methodStart = $s.IndexOf('@Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request)')
if ($methodStart -lt 0) { throw 'shouldInterceptRequest start not found' }
$returnMarker = 'return super.shouldInterceptRequest(view, request);'
$returnPos = $s.IndexOf($returnMarker, $methodStart)
if ($returnPos -lt 0) { throw 'shouldInterceptRequest return not found' }
$closePos = $s.IndexOf('}', $returnPos + $returnMarker.Length)
if ($closePos -lt 0) { throw 'shouldInterceptRequest closing brace not found' }
$networkBlock = @'
@Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                        String u = request.getUrl().toString();
                        String low = u.toLowerCase();
                        if (!launchSent && low.contains(".swf")) {
                            if (isPlaceholderSwf(u)) {
                                setState("placeholder-swf-request ignored " + u);
                            } else {
                                setState("real-swf-request observed " + u);
                                captureNetworkSwf(u, request);
                            }
                        } else if (!launchSent && isInterestingResource(u)) {
                            setState("game-resource observed " + abbreviate(u, 180));
                        }
                        return super.shouldInterceptRequest(view, request);
                    }
'@
$s = $s.Substring(0, $methodStart) + $networkBlock.TrimEnd() + $s.Substring($closePos + 1)

$helperMarker = '    private void detectCloudflareBlock(final WebView view) {'
if (!$s.Contains($helperMarker)) { throw 'helper insertion marker not found' }
$helpers = @'
    private boolean isInterestingResource(String url) {
        String u = url == null ? "" : url.toLowerCase();
        if (!(u.contains("narutowebgame.com") || u.contains("oasgames.com"))) return false;
        return u.contains("flash") || u.contains("game") || u.contains("server") || u.contains("loader") || u.contains("config") || u.contains("bootstrap");
    }

    private String abbreviate(String s, int max) {
        if (s == null) return "";
        return s.length() <= max ? s : s.substring(0, max) + "...";
    }

    private void captureNetworkSwf(final String swfUrl, final WebResourceRequest request) {
        final Map<String, String> reqHeaders = new HashMap<>();
        try {
            Map<String, String> h = request == null ? null : request.getRequestHeaders();
            if (h != null) reqHeaders.putAll(h);
        } catch (Throwable ignored) { }

        handler.post(() -> {
            if (launchSent || swfUrl == null || swfUrl.isEmpty() || isPlaceholderSwf(swfUrl)) return;
            try {
                JSONObject payload = new JSONObject();
                payload.put("swf", swfUrl);
                payload.put("flashvars", new JSONObject());
                payload.put("source", "network-request");

                String referer = "";
                for (Map.Entry<String, String> e : reqHeaders.entrySet()) {
                    if (e.getKey() != null && "referer".equalsIgnoreCase(e.getKey())) {
                        referer = e.getValue() == null ? "" : e.getValue();
                        break;
                    }
                }
                if (referer.isEmpty()) referer = currentGamePage == null ? "" : currentGamePage;
                payload.put("page", referer);

                String cookie = null;
                try { cookie = CookieManager.getInstance().getCookie(swfUrl); } catch (Throwable ignored) { }
                if ((cookie == null || cookie.isEmpty()) && !referer.isEmpty()) {
                    try { cookie = CookieManager.getInstance().getCookie(referer); } catch (Throwable ignored) { }
                }
                if (cookie != null && !cookie.isEmpty()) payload.put("cookie", cookie);
                payload.put("userAgent", activeUserAgent == null ? "" : activeUserAgent);

                launchSent = true;
                setState("REAL network launch-captured " + swfUrl);
                send("launch", payload.toString());
            } catch (Throwable t) {
                setState("ERROR network SWF capture " + t.getMessage());
            }
        });
    }

'@
$s = $s.Replace($helperMarker, $helpers + $helperMarker)
Set-Content -Path $p -Value $s -Encoding UTF8

$xml = 'NarutoAir-app.xml'
$x = Get-Content $xml -Raw
$x = $x.Replace('<versionNumber>0.5.4</versionNumber>', '<versionNumber>0.5.5</versionNumber>')
$x = $x.Replace('<versionLabel>0.5.4 real SWF hunter</versionLabel>', '<versionLabel>0.5.5 bridge proxy network handoff</versionLabel>')
$x = $x.Replace('<name>Naruto AIR Experimental 0.5.4</name>', '<name>Naruto AIR Experimental 0.5.5</name>')
Set-Content -Path $xml -Value $x -Encoding UTF8

$app = 'src\NarutoAir.as'
$a = Get-Content $app -Raw
$a = $a.Replace('Naruto AIR 0.5.4 - real SWF hunter + AIR loader...', 'Naruto AIR 0.5.5 - bridge proxy + network SWF handoff...')
$a = $a.Replace('log("Pagina origem: " + String(info.page || ""));', 'log("Pagina origem: " + String(info.page || "")); if (info.source) log("Fonte captura: " + String(info.source));')
Set-Content -Path $app -Value $a -Encoding UTF8

$marker = 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as'
$m = Get-Content $marker -Raw
$m = $m.Replace('public static const VERSION:String = "0.5.4";', 'public static const VERSION:String = "0.5.5";')
Set-Content -Path $marker -Value $m -Encoding UTF8

Write-Host '0.5.5 patch applied: Flash callback proxy + native cross-frame network SWF handoff.'
