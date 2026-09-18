$ErrorActionPreference='Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# Runtime proxy fields: the Android replacement for the desktop CEF+Flash asset pipeline.
$field='private volatile String currentGamePage = "";'
if(!$s.Contains($field)){throw 'currentGamePage field missing'}
if(!$s.Contains('runtimeProxyServer')){
$fields=@'
    private volatile java.net.ServerSocket runtimeProxyServer;
    private volatile Thread runtimeProxyThread;
    private volatile int runtimeProxyPort = 0;
    private volatile String runtimeProxyOrigin = "";
    private volatile String runtimeProxyReferer = "";
    private volatile String runtimeProxyCookie = "";
    private volatile String runtimeProxyUa = "";
'@
  $s=$s.Replace($field,$field+[Environment]::NewLine+$fields.TrimEnd())
}

# Stop proxy on native context disposal.
$dispose='@Override public void dispose() { destroyWebView(); }'
if(!$s.Contains($dispose)){throw 'dispose marker missing'}
$s=$s.Replace($dispose,'@Override public void dispose() { destroyWebView(); stopRuntimeProxy(); }')

# Insert local HTTP proxy implementation before sendLaunchPayload.
$marker='    private void sendLaunchPayload(final JSONObject payload, final String source) {'
if(!$s.Contains($marker)){throw 'sendLaunchPayload marker missing'}
if(!$s.Contains('private synchronized String ensureRuntimeProxy')){
$helper=@'
    private synchronized String ensureRuntimeProxy(String originSwf, String page, String cookie, String ua) {
        try {
            java.net.URL u = new java.net.URL(originSwf);
            runtimeProxyOrigin = u.getProtocol() + "://" + u.getHost() + (u.getPort() > 0 ? ":" + u.getPort() : "");
            runtimeProxyReferer = page == null ? "" : page;
            runtimeProxyCookie = cookie == null ? "" : cookie;
            runtimeProxyUa = ua == null ? "" : ua;

            if (runtimeProxyServer == null || runtimeProxyServer.isClosed()) {
                runtimeProxyServer = new java.net.ServerSocket(0, 32, java.net.InetAddress.getByName("127.0.0.1"));
                runtimeProxyPort = runtimeProxyServer.getLocalPort();
                runtimeProxyThread = new Thread(() -> runtimeProxyAcceptLoop(), "NarutoRuntimeProxy");
                runtimeProxyThread.setDaemon(true);
                runtimeProxyThread.start();
                setState("MOBILE RUNTIME PROXY listening 127.0.0.1:" + runtimeProxyPort);
            }

            String file = u.getFile();
            if (file == null || file.isEmpty()) file = "/";
            return "http://127.0.0.1:" + runtimeProxyPort + file;
        } catch (Throwable t) {
            setState("RUNTIME PROXY START ERROR " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
            return "";
        }
    }

    private void runtimeProxyAcceptLoop() {
        while (runtimeProxyServer != null && !runtimeProxyServer.isClosed()) {
            try {
                final java.net.Socket socket = runtimeProxyServer.accept();
                Thread t = new Thread(() -> handleRuntimeProxySocket(socket), "NarutoRuntimeProxyClient");
                t.setDaemon(true);
                t.start();
            } catch (Throwable t) {
                if (runtimeProxyServer != null && !runtimeProxyServer.isClosed()) {
                    send("log", "RUNTIME PROXY ACCEPT ERROR " + t.getClass().getSimpleName());
                }
            }
        }
    }

    private String proxyReadLine(java.io.InputStream in) throws java.io.IOException {
        java.io.ByteArrayOutputStream b = new java.io.ByteArrayOutputStream();
        int prev = -1;
        while (true) {
            int c = in.read();
            if (c < 0) break;
            if (prev == '\r' && c == '\n') {
                byte[] a = b.toByteArray();
                int n = a.length;
                if (n > 0 && a[n - 1] == '\r') n--;
                return new String(a, 0, n, "ISO-8859-1");
            }
            b.write(c);
            prev = c;
            if (b.size() > 65536) throw new java.io.IOException("header too large");
        }
        if (b.size() == 0) return null;
        return new String(b.toByteArray(), "ISO-8859-1");
    }

    private void handleRuntimeProxySocket(java.net.Socket socket) {
        try {
            socket.setSoTimeout(30000);
            java.io.BufferedInputStream in = new java.io.BufferedInputStream(socket.getInputStream());
            java.io.BufferedOutputStream out = new java.io.BufferedOutputStream(socket.getOutputStream());

            String requestLine = proxyReadLine(in);
            if (requestLine == null || requestLine.isEmpty()) return;
            String[] first = requestLine.split(" ", 3);
            if (first.length < 2) return;
            String method = first[0].toUpperCase(java.util.Locale.US);
            String target = first[1];

            java.util.Map<String,String> headers = new java.util.HashMap<>();
            int contentLength = 0;
            while (true) {
                String line = proxyReadLine(in);
                if (line == null || line.isEmpty()) break;
                int p = line.indexOf(':');
                if (p > 0) {
                    String k = line.substring(0, p).trim().toLowerCase(java.util.Locale.US);
                    String v = line.substring(p + 1).trim();
                    headers.put(k, v);
                    if ("content-length".equals(k)) {
                        try { contentLength = Integer.parseInt(v); } catch (Throwable ignored) { }
                    }
                }
            }

            byte[] requestBody = new byte[Math.max(0, contentLength)];
            int off = 0;
            while (off < requestBody.length) {
                int n = in.read(requestBody, off, requestBody.length - off);
                if (n < 0) break;
                off += n;
            }

            if (target.startsWith("http://") || target.startsWith("https://")) {
                java.net.URL abs = new java.net.URL(target);
                target = abs.getFile();
            }
            if (!target.startsWith("/")) target = "/" + target;

            if (target.startsWith("/crossdomain.xml")) {
                byte[] body = ("<?xml version=\"1.0\"?><cross-domain-policy>" +
                        "<allow-access-from domain=\"*\" secure=\"false\"/>" +
                        "<allow-http-request-headers-from domain=\"*\" headers=\"*\" secure=\"false\"/>" +
                        "</cross-domain-policy>").getBytes("UTF-8");
                proxyWriteResponse(out, 200, "OK", "text/x-cross-domain-policy", body, "no-cache");
                return;
            }

            String upstream = runtimeProxyOrigin + target;
            java.net.HttpURLConnection c = null;
            try {
                c = openRuntimeUpstream(upstream, method, headers, requestBody, off);
            } catch (Throwable httpsError) {
                if (upstream.startsWith("https://")) {
                    String fallback = "http://" + upstream.substring("https://".length());
                    send("log", "RUNTIME PROXY TLS fallback " + abbreviate(fallback, 180));
                    c = openRuntimeUpstream(fallback, method, headers, requestBody, off);
                } else {
                    throw httpsError;
                }
            }

            int code = c.getResponseCode();
            java.io.InputStream bodyIn = code >= 400 ? c.getErrorStream() : c.getInputStream();
            java.io.ByteArrayOutputStream bos = new java.io.ByteArrayOutputStream();
            if (bodyIn != null && !"HEAD".equals(method)) {
                byte[] buf = new byte[32768];
                int n;
                while ((n = bodyIn.read(buf)) >= 0) bos.write(buf, 0, n);
                try { bodyIn.close(); } catch (Throwable ignored) { }
            }
            byte[] body = bos.toByteArray();
            String ct = c.getContentType();
            if (ct == null || ct.isEmpty()) ct = guessRuntimeContentType(target);
            String cache = c.getHeaderField("Cache-Control");
            if (cache == null || cache.isEmpty()) cache = "public, max-age=3600";

            if (isInterestingRuntimeAsset(target) || code >= 400) {
                send("log", "RUNTIME ASSET " + code + " " + target + " bytes=" + body.length);
            }

            proxyWriteResponse(out, code, c.getResponseMessage(), ct, body, cache);
            c.disconnect();
        } catch (Throwable t) {
            try {
                java.io.OutputStream raw = socket.getOutputStream();
                byte[] body = ("Naruto runtime proxy error: " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage())).getBytes("UTF-8");
                String h = "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: " + body.length + "\r\nConnection: close\r\n\r\n";
                raw.write(h.getBytes("ISO-8859-1"));
                raw.write(body);
                raw.flush();
            } catch (Throwable ignored) { }
            send("log", "RUNTIME PROXY ERROR " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
        } finally {
            try { socket.close(); } catch (Throwable ignored) { }
        }
    }

    private java.net.HttpURLConnection openRuntimeUpstream(String url, String method, java.util.Map<String,String> requestHeaders, byte[] body, int bodyLength) throws Exception {
        java.net.HttpURLConnection c = (java.net.HttpURLConnection) new java.net.URL(url).openConnection();
        c.setConnectTimeout(20000);
        c.setReadTimeout(30000);
        c.setInstanceFollowRedirects(true);
        c.setUseCaches(true);
        c.setRequestMethod(method);
        c.setRequestProperty("Accept", "*/*");
        c.setRequestProperty("Accept-Encoding", "identity");
        if (runtimeProxyUa != null && !runtimeProxyUa.isEmpty()) c.setRequestProperty("User-Agent", runtimeProxyUa);
        if (runtimeProxyReferer != null && !runtimeProxyReferer.isEmpty()) c.setRequestProperty("Referer", runtimeProxyReferer);
        if (runtimeProxyCookie != null && !runtimeProxyCookie.isEmpty()) c.setRequestProperty("Cookie", runtimeProxyCookie);
        String range = requestHeaders.get("range");
        if (range != null && !range.isEmpty()) c.setRequestProperty("Range", range);
        String ct = requestHeaders.get("content-type");
        if (ct != null && !ct.isEmpty()) c.setRequestProperty("Content-Type", ct);

        if (("POST".equals(method) || "PUT".equals(method)) && bodyLength > 0) {
            c.setDoOutput(true);
            c.setFixedLengthStreamingMode(bodyLength);
            java.io.OutputStream os = c.getOutputStream();
            os.write(body, 0, bodyLength);
            os.flush();
            os.close();
        }
        return c;
    }

    private void proxyWriteResponse(java.io.OutputStream out, int code, String reason, String contentType, byte[] body, String cache) throws java.io.IOException {
        if (reason == null || reason.isEmpty()) reason = code == 200 ? "OK" : "Status";
        if (contentType == null || contentType.isEmpty()) contentType = "application/octet-stream";
        if (body == null) body = new byte[0];
        String h = "HTTP/1.1 " + code + " " + reason + "\r\n" +
                "Content-Type: " + contentType + "\r\n" +
                "Content-Length: " + body.length + "\r\n" +
                "Cache-Control: " + (cache == null ? "no-cache" : cache) + "\r\n" +
                "Access-Control-Allow-Origin: *\r\n" +
                "Access-Control-Allow-Headers: *\r\n" +
                "Connection: close\r\n\r\n";
        out.write(h.getBytes("ISO-8859-1"));
        out.write(body);
        out.flush();
    }

    private boolean isInterestingRuntimeAsset(String target) {
        String t = target == null ? "" : target.toLowerCase(java.util.Locale.US);
        return t.contains("/config/") || t.contains("/syscmd/") || t.contains("/flash/") ||
                t.endsWith(".swf") || t.contains(".swf?") || t.endsWith(".cfg") || t.contains(".cfg?") ||
                t.endsWith(".xml") || t.contains(".xml?") || t.endsWith(".dat") || t.contains(".dat?");
    }

    private String guessRuntimeContentType(String target) {
        String t = target == null ? "" : target.toLowerCase(java.util.Locale.US);
        if (t.contains(".swf")) return "application/x-shockwave-flash";
        if (t.contains(".xml")) return "text/xml";
        if (t.contains(".json")) return "application/json";
        if (t.contains(".js")) return "application/javascript";
        if (t.contains(".css")) return "text/css";
        if (t.contains(".png")) return "image/png";
        if (t.contains(".jpg") || t.contains(".jpeg")) return "image/jpeg";
        if (t.contains(".gif")) return "image/gif";
        if (t.contains(".cfg") || t.contains(".txt")) return "text/plain";
        return "application/octet-stream";
    }

    private synchronized void stopRuntimeProxy() {
        try { if (runtimeProxyServer != null) runtimeProxyServer.close(); } catch (Throwable ignored) { }
        runtimeProxyServer = null;
        runtimeProxyThread = null;
        runtimeProxyPort = 0;
    }

'@
$s=$s.Replace($marker,$helper+$marker)
}

# Route the final resolved CDN bootstrap through the loopback runtime proxy.
$needle='if (cookie != null && !cookie.isEmpty()) payload.put("cookie", cookie);'
if(!$s.Contains($needle)){throw 'cookie payload marker missing'}
if(!$s.Contains('payload.put("originSwf"')){
$inject=@'
            if (cookie != null && !cookie.isEmpty()) payload.put("cookie", cookie);

            String originalSwf = swf;
            String lowerOriginal = originalSwf.toLowerCase(java.util.Locale.US);
            if (lowerOriginal.contains("cdnnaruto-pt.oasgames.com/") && lowerOriginal.contains("/entry.swf")) {
                String localSwf = ensureRuntimeProxy(originalSwf, page, cookie, nativeUserAgent);
                if (localSwf != null && !localSwf.isEmpty()) {
                    payload.put("originSwf", originalSwf);
                    payload.put("runtimeProxyBase", "http://127.0.0.1:" + runtimeProxyPort + "/");
                    payload.put("swf", localSwf);
                    swf = localSwf;
                    setState("FINAL CDN entry.swf -> MOBILE runtime proxy " + abbreviate(localSwf, 160));
                }
            }
'@
$s=$s.Replace($needle,$inject.Trim())
}

Set-Content $p $s -Encoding UTF8

# AIR side: trust imported remote game code and keep loopback URL pristine.
$a='src\NarutoAir.as'
$x=Get-Content $a -Raw

$x=$x.Replace('var isNarutoCdn:Boolean = url.indexOf("cdnnaruto-pt.oasgames.com/") >= 0;',
              'var isNarutoCdn:Boolean = url.indexOf("cdnnaruto-pt.oasgames.com/") >= 0 || url.indexOf("127.0.0.1:") >= 0;')

$ctx='var ctx:LoaderContext = new LoaderContext(false, new ApplicationDomain(ApplicationDomain.currentDomain), null);'
if(!$x.Contains($ctx)){throw '0.8.2 LoaderContext marker missing'}
if(!$x.Contains('ctx.allowCodeImport = true;')){
  $x=$x.Replace($ctx,$ctx+[Environment]::NewLine+'                ctx.allowCodeImport = true;')
}

$log='log("Pagina origem: " + String(info.page || ""));'
if(!$x.Contains($log)){throw 'page origin log marker missing'}
if(!$x.Contains('SWF origem CDN:')){
  $x=$x.Replace($log,$log+[Environment]::NewLine+'                    if (info.originSwf) log("SWF origem CDN: " + String(info.originSwf));'+[Environment]::NewLine+'                    if (info.runtimeProxyBase) log("Proxy runtime: " + String(info.runtimeProxyBase));')
}

$x=$x.Replace('Naruto AIR 0.8.2 - CDN runtime asset chain + final entry.swf...','Naruto AIR 0.9.0 - full mobile runtime proxy + asset chain...')
Set-Content $a $x -Encoding UTF8

# Version metadata.
$app=Get-Content 'NarutoAir-app.xml' -Raw
$app=$app.Replace('<versionNumber>0.8.2</versionNumber>','<versionNumber>0.9.0</versionNumber>')
$app=$app.Replace('<versionLabel>0.8.2 CDN runtime asset chain</versionLabel>','<versionLabel>0.9.0 full mobile launcher runtime</versionLabel>')
$app=$app.Replace('<name>Naruto AIR Experimental 0.8.2</name>','<name>Naruto Online Mobile 0.9.0</name>')
Set-Content 'NarutoAir-app.xml' $app -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.8.2";','public static const VERSION:String = "0.9.0";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.9.0 patch applied: Android loopback runtime proxy replaces desktop CEF/Flash asset transport and serves relative config/syscmd/flash/SWF chain.'
