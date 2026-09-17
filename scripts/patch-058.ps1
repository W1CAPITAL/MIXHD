$ErrorActionPreference = 'Stop'
. .\scripts\patch-057.ps1

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# Imports for host-scoped HTTP fallback.
$importNeedle='import java.util.Set;'
if(!$s.Contains($importNeedle)){throw 'java util Set import not found'}
$imports=@'
import java.util.Set;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLConnection;
'@
$s=$s.Replace($importNeedle,$imports.TrimEnd())

# Allow mixed content because the legacy Naruto game host no longer negotiates modern TLS.
$settingsNeedle='s.setCacheMode(WebSettings.LOAD_DEFAULT);'
if(!$s.Contains($settingsNeedle)){throw 'WebSettings cache marker not found'}
$settingsReplacement=@'
s.setCacheMode(WebSettings.LOAD_DEFAULT);
                if (android.os.Build.VERSION.SDK_INT >= 21) {
                    s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
                }
'@
$s=$s.Replace($settingsNeedle,$settingsReplacement.Trim())

# Rewrite only the obsolete game host, preserving the signed query string byte-for-byte.
$handleNeedle='if (view == null || target == null || target.isEmpty()) return false;'
if(!$s.Contains($handleNeedle)){throw 'handleNavigation marker not found'}
$handleReplacement=@'
if (view == null || target == null || target.isEmpty()) return false;
        if (isLegacyGameHttps(target)) {
            String fallback = legacyHttpUrl(target);
            currentGamePage = fallback;
            activeUserAgent = nativeUserAgent;
            desktopGameUaActive = false;
            setState("legacy-game TLS incompatible; HTTP fallback " + abbreviate(fallback, 140));
            view.loadUrl(fallback);
            return true;
        }
'@
$s=$s.Replace($handleNeedle,$handleReplacement.Trim())

# Intercept absolute HTTPS subresources from the same legacy host and fetch them through HTTP.
$interceptNeedle='String low = u.toLowerCase();'
$interceptPos=$s.IndexOf('@Override public WebResourceResponse shouldInterceptRequest')
if($interceptPos -lt 0){throw 'shouldInterceptRequest not found'}
$lowPos=$s.IndexOf($interceptNeedle,$interceptPos)
if($lowPos -lt 0){throw 'intercept low marker missing'}
$insertPos=$lowPos+$interceptNeedle.Length
$interceptExtra=@'

                        if (isLegacyGameHttps(u)) {
                            WebResourceResponse proxied = fetchLegacyHttpResource(u, request);
                            if (proxied != null) return proxied;
                        }
'@
$s=$s.Insert($insertPos,$interceptExtra)

$helperMarker='    private void detectCloudflareBlock(final WebView view) {'
if(!$s.Contains($helperMarker)){throw 'helper insertion marker missing'}
$helpers=@'
    private String abbreviate(String s, int max) {
        if (s == null) return "";
        return s.length() <= max ? s : s.substring(0, max) + "...";
    }

    private boolean isLegacyGameHttps(String url) {
        String u = url == null ? "" : url.toLowerCase();
        return u.startsWith("https://naruto-pt.oasgames.com/");
    }

    private boolean isLegacyGameHost(String url) {
        String u = url == null ? "" : url.toLowerCase();
        return u.startsWith("https://naruto-pt.oasgames.com/") || u.startsWith("http://naruto-pt.oasgames.com/");
    }

    private String legacyHttpUrl(String url) {
        if (url == null) return "";
        if (url.regionMatches(true, 0, "https://naruto-pt.oasgames.com/", 0, "https://naruto-pt.oasgames.com/".length())) {
            return "http://naruto-pt.oasgames.com/" + url.substring("https://naruto-pt.oasgames.com/".length());
        }
        return url;
    }

    private WebResourceResponse fetchLegacyHttpResource(String originalUrl, WebResourceRequest request) {
        if (!isLegacyGameHttps(originalUrl)) return null;
        HttpURLConnection conn = null;
        try {
            String current = legacyHttpUrl(originalUrl);
            for (int redirects = 0; redirects < 5; redirects++) {
                URLConnection raw = new URL(current).openConnection();
                if (!(raw instanceof HttpURLConnection)) return null;
                conn = (HttpURLConnection) raw;
                conn.setInstanceFollowRedirects(false);
                conn.setConnectTimeout(12000);
                conn.setReadTimeout(25000);
                conn.setRequestMethod("GET");
                conn.setRequestProperty("User-Agent", nativeUserAgent == null ? "" : nativeUserAgent);
                conn.setRequestProperty("Accept", "*/*");

                try {
                    Map<String,String> hs = request == null ? null : request.getRequestHeaders();
                    if (hs != null) {
                        for (Map.Entry<String,String> e : hs.entrySet()) {
                            String k = e.getKey();
                            String v = e.getValue();
                            if (k == null || v == null) continue;
                            if ("host".equalsIgnoreCase(k) || "connection".equalsIgnoreCase(k) || "accept-encoding".equalsIgnoreCase(k)) continue;
                            conn.setRequestProperty(k, v);
                        }
                    }
                } catch (Throwable ignored) { }

                String cookie = null;
                try { cookie = CookieManager.getInstance().getCookie(originalUrl); } catch (Throwable ignored) { }
                if (cookie != null && !cookie.isEmpty()) conn.setRequestProperty("Cookie", cookie);

                int code = conn.getResponseCode();
                if (code >= 300 && code < 400) {
                    String loc = conn.getHeaderField("Location");
                    if (loc == null || loc.isEmpty()) return null;
                    URL next = new URL(new URL(current), loc);
                    String nextUrl = next.toString();
                    if (isLegacyGameHttps(nextUrl)) nextUrl = legacyHttpUrl(nextUrl);
                    conn.disconnect();
                    conn = null;
                    current = nextUrl;
                    continue;
                }

                if (code < 200 || code >= 400) {
                    setState("legacy HTTP resource status=" + code + " " + abbreviate(current, 140));
                    return null;
                }

                String contentType = conn.getContentType();
                String mime = "application/octet-stream";
                String encoding = "UTF-8";
                if (contentType != null) {
                    String[] parts = contentType.split(";");
                    if (parts.length > 0 && !parts[0].trim().isEmpty()) mime = parts[0].trim();
                    for (String part : parts) {
                        String p = part.trim().toLowerCase();
                        if (p.startsWith("charset=")) encoding = part.substring(part.indexOf('=') + 1).trim();
                    }
                }
                if (current.toLowerCase().contains(".swf")) mime = "application/x-shockwave-flash";

                InputStream body = conn.getInputStream();
                WebResourceResponse response = new WebResourceResponse(mime, encoding, body);
                if (android.os.Build.VERSION.SDK_INT >= 21) {
                    Map<String,String> responseHeaders = new HashMap<>();
                    for (Map.Entry<String, java.util.List<String>> e : conn.getHeaderFields().entrySet()) {
                        if (e.getKey() != null && e.getValue() != null && !e.getValue().isEmpty()) {
                            responseHeaders.put(e.getKey(), e.getValue().get(0));
                        }
                    }
                    response.setResponseHeaders(responseHeaders);
                    response.setStatusCodeAndReasonPhrase(code, "OK");
                }
                setState("legacy HTTPS resource proxied over HTTP " + abbreviate(current, 140));
                return response;
            }
        } catch (Throwable t) {
            setState("legacy HTTP proxy failed " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
            try { if (conn != null) conn.disconnect(); } catch (Throwable ignored) { }
        }
        return null;
    }

'@
$s=$s.Replace($helperMarker,$helpers+$helperMarker)

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.5.7</versionNumber>','<versionNumber>0.5.8</versionNumber>')
$x=$x.Replace('<versionLabel>0.5.7 early bootstrap replay</versionLabel>','<versionLabel>0.5.8 legacy TLS HTTP bridge</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.5.7</name>','<name>Naruto AIR Experimental 0.5.8</name>')
$x=$x.Replace('android:usesCleartextTraffic="false"','android:usesCleartextTraffic="true"')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.5.7 - early bootstrap replay + AIR loader...','Naruto AIR 0.5.8 - legacy TLS HTTP bridge + AIR loader...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.5.7";','public static const VERSION:String = "0.5.8";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.5.8 patch applied: host-scoped legacy TLS -> HTTP bridge for naruto-pt.oasgames.com.'
