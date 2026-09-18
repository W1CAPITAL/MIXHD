$ErrorActionPreference='Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# Imports for detailed WebView diagnostics.
if(!$s.Contains('import android.net.http.SslError;')){
  $s=$s.Replace('import android.graphics.Color;','import android.graphics.Color;'+[Environment]::NewLine+'import android.net.http.SslError;')
}
if(!$s.Contains('import android.webkit.SslErrorHandler;')){
  $s=$s.Replace('import android.webkit.WebResourceResponse;','import android.webkit.WebResourceResponse;'+[Environment]::NewLine+'import android.webkit.SslErrorHandler;'+[Environment]::NewLine+'import android.webkit.RenderProcessGoneDetail;')
}

# Stop forcing game.php through HttpURLConnection: it gets 403 while WebView navigation itself succeeds.
$needle=@'
                        if (isGameboxGameHtml(u)) {
                            WebResourceResponse early = fetchGameboxHtmlWithAdapter(u, request);
                            if (early != null) return early;
                        }
'@
if($s.Contains($needle.Trim())){
  $s=$s.Replace($needle.Trim(),'                        // 0.7.2: do not proxy game.php; direct WebView request preserves launcher session and avoids false 403.')
}

# Convert console errors into explicit ERROR lines.
$old='if (cm != null) trace("CONSOLE " + cm.messageLevel() + " " + cm.sourceId() + ":" + cm.lineNumber() + " " + cm.message());'
if($s.Contains($old)){
  $new='if (cm != null) {'+[Environment]::NewLine+
'                            String pfx = cm.messageLevel() == ConsoleMessage.MessageLevel.ERROR ? "ERROR JS " : "CONSOLE ";'+[Environment]::NewLine+
'                            trace(pfx + cm.messageLevel() + " " + cm.sourceId() + ":" + cm.lineNumber() + " " + cm.message());'+[Environment]::NewLine+
'                        }'
  $s=$s.Replace($old,$new)
}

# Add WebView error hooks to the main client.
$mainMarker=@'
                    @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                        super.onReceivedError(view, request, error);
                        if (request != null && request.isForMainFrame()) setState("ERROR webview " + String.valueOf(error));
                    }
'@
if(!$s.Contains($mainMarker.Trim())){throw 'main onReceivedError marker missing'}
$mainHooks=@'
                    @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                        super.onReceivedError(view, request, error);
                        String u = request == null || request.getUrl() == null ? "" : request.getUrl().toString();
                        String d = error == null ? "" : String.valueOf(error.getDescription());
                        int c = error == null ? 0 : error.getErrorCode();
                        trace("ERROR WEBVIEW code=" + c + " main=" + (request != null && request.isForMainFrame()) + " url=" + abbreviate(u,180) + " desc=" + d);
                        if (request != null && request.isForMainFrame()) setState("ERROR WEBVIEW MAIN code=" + c + " " + d);
                    }

                    @Override public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse response) {
                        super.onReceivedHttpError(view, request, response);
                        try {
                            String u = request == null || request.getUrl() == null ? "" : request.getUrl().toString();
                            int code = response == null ? 0 : response.getStatusCode();
                            if (code >= 400) trace("ERROR HTTP " + code + " main=" + (request != null && request.isForMainFrame()) + " url=" + abbreviate(u,220));
                        } catch (Throwable t) { trace("ERROR HTTP hook " + t); }
                    }

                    @Override public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
                        String u = error == null ? "" : error.getUrl();
                        int primary = error == null ? -1 : error.getPrimaryError();
                        trace("ERROR SSL primary=" + primary + " url=" + abbreviate(u,220));
                        super.onReceivedSslError(view, handler, error);
                    }

                    @Override public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
                        trace("ERROR RENDER PROCESS GONE crashed=" + (detail != null && detail.didCrash()) + " priority=" + (detail == null ? -1 : detail.rendererPriorityAtExit()));
                        setState("ERROR RENDER PROCESS GONE");
                        return true;
                    }
'@
$s=$s.Replace($mainMarker.Trim(),$mainHooks.Trim())

# Early-inject Flash adapter into S876/serverlist launch HTML before any scripts execute.
$reqMarker='String u = request.getUrl().toString();' + [Environment]::NewLine + '                        if (shouldTraceUrl(u)) trace("REQ " + request.getMethod() + " " + u);'
if(!$s.Contains($reqMarker)){throw 'request marker missing'}
$extra=@'
String u = request.getUrl().toString();
                        if (shouldTraceUrl(u)) trace("REQ " + request.getMethod() + " " + u);
                        if (request.isForMainFrame() && isServerLaunchRoute(u)) {
                            WebResourceResponse earlyServer = fetchServerLaunchHtmlWithAdapter(u, request);
                            if (earlyServer != null) return earlyServer;
                        }
'@
$s=$s.Replace($reqMarker,$extra.TrimEnd())

# Helper to proxy only server launch HTML, not gamebox game.php.
$helperMarker='    private boolean isGameboxGameHtml(String u) {'
if(!$s.Contains($helperMarker)){throw 'helper insertion point missing'}
$helper=@'
    private WebResourceResponse fetchServerLaunchHtmlWithAdapter(String originalUrl, WebResourceRequest request) {
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(originalUrl).openConnection();
            conn.setInstanceFollowRedirects(true);
            conn.setConnectTimeout(12000);
            conn.setReadTimeout(25000);
            conn.setRequestMethod("GET");
            conn.setRequestProperty("User-Agent", buildDesktopGameUa(nativeUserAgent));
            conn.setRequestProperty("Accept", "text/html,application/xhtml+xml,*/*;q=0.8");
            conn.setRequestProperty("Accept-Language", "pt-BR,pt;q=0.9,en;q=0.7");
            try {
                Map<String,String> hs = request == null ? null : request.getRequestHeaders();
                if (hs != null) for (Map.Entry<String,String> e : hs.entrySet()) {
                    String k=e.getKey(), v=e.getValue();
                    if(k==null||v==null) continue;
                    if("host".equalsIgnoreCase(k)||"connection".equalsIgnoreCase(k)||"accept-encoding".equalsIgnoreCase(k)) continue;
                    conn.setRequestProperty(k,v);
                }
            } catch(Throwable ignored){}
            String cookie=null;
            try { cookie=CookieManager.getInstance().getCookie(originalUrl); } catch(Throwable ignored){}
            if(cookie!=null&&!cookie.isEmpty()) conn.setRequestProperty("Cookie",cookie);

            int code=conn.getResponseCode();
            if(code<200||code>=400){
                trace("ERROR SERVER HTML HTTP "+code+" url="+abbreviate(originalUrl,180));
                return null;
            }

            InputStream in=conn.getInputStream();
            ByteArrayOutputStream bos=new ByteArrayOutputStream();
            byte[] buf=new byte[16384];
            int n;
            while((n=in.read(buf))>0) bos.write(buf,0,n);
            try{in.close();}catch(Throwable ignored){}

            String encoding="UTF-8";
            String ct=conn.getContentType();
            if(ct!=null){
                for(String part:ct.split(";")){
                    String q=part.trim();
                    if(q.toLowerCase().startsWith("charset=")) encoding=q.substring(q.indexOf('=')+1).trim();
                }
            }
            Charset cs;
            try{cs=Charset.forName(encoding);}catch(Throwable t){cs=Charset.forName("UTF-8");}
            String html=new String(bos.toByteArray(),cs);

            String injected="<script>"+FLASH_ADAPTER_JS+"</script>";
            String low=html.toLowerCase();
            int h=low.indexOf("<head");
            if(h>=0){
                int end=html.indexOf('>',h);
                html=end>=0?html.substring(0,end+1)+injected+html.substring(end+1):injected+html;
            } else html=injected+html;

            WebResourceResponse resp=new WebResourceResponse("text/html",encoding,new ByteArrayInputStream(html.getBytes(cs)));
            if(android.os.Build.VERSION.SDK_INT>=21){
                Map<String,String> rh=new HashMap<>();
                for(Map.Entry<String,java.util.List<String>> e:conn.getHeaderFields().entrySet()){
                    if(e.getKey()==null||e.getValue()==null||e.getValue().isEmpty()) continue;
                    String k=e.getKey();
                    if("content-length".equalsIgnoreCase(k)||"content-encoding".equalsIgnoreCase(k)||"content-security-policy".equalsIgnoreCase(k)) continue;
                    rh.put(k,e.getValue().get(0));
                }
                resp.setResponseHeaders(rh);
                resp.setStatusCodeAndReasonPhrase(code,"OK");
            }
            setState("SERVER HTML EARLY Flash adapter injected");
            return resp;
        } catch(Throwable t){
            trace("ERROR SERVER HTML PROXY "+t.getClass().getSimpleName()+": "+String.valueOf(t.getMessage()));
            return null;
        }
    }

'@
$s=$s.Replace($helperMarker,$helper+$helperMarker)

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.7.1</versionNumber>','<versionNumber>0.7.2</versionNumber>')
$x=$x.Replace('<versionLabel>0.7.1 native account and game bridge</versionLabel>','<versionLabel>0.7.2 error diagnostics and server flash injection</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.7.1</name>','<name>Naruto AIR Experimental 0.7.2</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.7.1 - native account + official launcher + early game Flash bridge...','Naruto AIR 0.7.2 - explicit error diagnostics + S876 early Flash injection...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.7.1";','public static const VERSION:String = "0.7.2";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.7.2 patch applied: explicit HTTP/SSL/JS/render errors, remove game.php proxy 403, inject Flash adapter before S876 scripts.'
