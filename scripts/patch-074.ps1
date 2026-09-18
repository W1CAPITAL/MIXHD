$ErrorActionPreference='Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# 0.7.4: stop manual game.php handoff. The official launcher JS already opens the correct 2.4.1 page.
$manual=@'
                    String play = launcherPlayUrl(token, username);
                    currentGamePage = play;
                    setState("official launcher login accepted; opening game.php");
                    handler.postDelayed(() -> {
                        WebView active = webView;
                        if (active != null) {
                            try {
                                active.getSettings().setUserAgentString(buildDesktopGameUa(nativeUserAgent));
                                active.loadUrl(play);
                            } catch (Throwable t) {
                                setState("game.php load ERROR " + String.valueOf(t.getMessage()));
                            }
                        }
                    }, 1100);
'@
if($s.Contains($manual.Trim())){
  $s=$s.Replace($manual.Trim(),@'
                    setState("official launcher login accepted; waiting official game.php navigation");
                    trace("0.7.4 official JS owns game.php navigation; no synthetic URL");
'@.Trim())
}

# Prefix the official Naruto game scripts with the Flash adapter before their own code runs.
$interceptMarker='@Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {'
$first=$s.IndexOf($interceptMarker)
if($first -lt 0){throw 'shouldInterceptRequest missing'}
$needle='String u = request.getUrl().toString();'
$pos=$s.IndexOf($needle,$first)
if($pos -lt 0){throw 'request URL marker missing'}
$insertPos=$pos+$needle.Length
$inject=@'

                        WebResourceResponse boot = interceptOfficialFlashBootstrap(u, request);
                        if (boot != null) return boot;
'@
$s=$s.Insert($insertPos,$inject)

# Do same for popup/secondary WebView if present.
$second=$s.IndexOf($interceptMarker,$first+$interceptMarker.Length)
if($second -ge 0){
  $pos2=$s.IndexOf($needle,$second)
  if($pos2 -ge 0){
    $insertPos2=$pos2+$needle.Length
    $s=$s.Insert($insertPos2,$inject.Replace('                        ','                '))
  }
}

# Helpers before detectCloudflareBlock.
$helperMarker='    private void detectCloudflareBlock(final WebView view) {'
if(!$s.Contains($helperMarker)){throw 'helper marker missing'}
$helpers=@'
    private boolean isOfficialFlashBootstrapScript(String url) {
        String u = url == null ? "" : url.toLowerCase();
        return u.contains("img.oasgames.com/upload/1553679028/play/index.js") ||
               (u.contains("gamebox3.narutowebgame.com/") && u.contains("/static/scripts/oas.game.js")) ||
               (u.contains("gamebox3.narutowebgame.com/") && u.contains("/static/scripts/oas.gamebox.js"));
    }

    private WebResourceResponse interceptOfficialFlashBootstrap(String url, WebResourceRequest request) {
        if (!isOfficialFlashBootstrapScript(url)) return null;
        HttpURLConnection conn = null;
        try {
            URLConnection raw = new URL(url).openConnection();
            if (!(raw instanceof HttpURLConnection)) return null;
            conn = (HttpURLConnection) raw;
            conn.setInstanceFollowRedirects(true);
            conn.setConnectTimeout(12000);
            conn.setReadTimeout(25000);
            conn.setRequestMethod("GET");
            conn.setRequestProperty("User-Agent", activeUserAgent == null || activeUserAgent.isEmpty() ? buildDesktopGameUa(nativeUserAgent) : activeUserAgent);
            conn.setRequestProperty("Accept", "*/*");
            try {
                Map<String,String> hs = request == null ? null : request.getRequestHeaders();
                if (hs != null) {
                    for (Map.Entry<String,String> e : hs.entrySet()) {
                        String k=e.getKey(), v=e.getValue();
                        if (k == null || v == null) continue;
                        if ("host".equalsIgnoreCase(k) || "connection".equalsIgnoreCase(k) || "accept-encoding".equalsIgnoreCase(k)) continue;
                        conn.setRequestProperty(k,v);
                    }
                }
            } catch (Throwable ignored) { }

            String cookie = null;
            try { cookie = CookieManager.getInstance().getCookie(url); } catch (Throwable ignored) { }
            if (cookie != null && !cookie.isEmpty()) conn.setRequestProperty("Cookie", cookie);

            int code = conn.getResponseCode();
            if (code < 200 || code >= 400) {
                trace("FLASH BOOTSTRAP proxy status=" + code + " " + abbreviate(url,180));
                return null;
            }

            InputStream in = conn.getInputStream();
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            byte[] buf = new byte[16384];
            int n;
            while ((n=in.read(buf))>0) bos.write(buf,0,n);
            try { in.close(); } catch (Throwable ignored) { }

            String original = new String(bos.toByteArray(), "UTF-8");
            String prefix =
                    "try{Object.defineProperty(navigator,'plugins',{configurable:true,get:function(){var p={name:'Shockwave Flash',description:'Shockwave Flash 32.0 r0',filename:'pepflashplayer.dll'};var a={0:p,length:1,item:function(i){return i===0?p:null;},namedItem:function(n){return /shockwave flash/i.test(String(n))?p:null;}};a['Shockwave Flash']=p;return a;}});}catch(e){};" +
                    "try{Object.defineProperty(navigator,'mimeTypes',{configurable:true,get:function(){var p=(navigator.plugins&&navigator.plugins['Shockwave Flash'])||{name:'Shockwave Flash'};var m={type:'application/x-shockwave-flash',suffixes:'swf',description:'Shockwave Flash',enabledPlugin:p};var a={0:m,length:1,item:function(i){return i===0?m:null;},namedItem:function(n){return String(n)==='application/x-shockwave-flash'?m:null;}};a['application/x-shockwave-flash']=m;return a;}});}catch(e){};" +
                    FLASH_ADAPTER_JS +
                    "try{if(window.NarutoAirNative&&window.NarutoAirNative.log)window.NarutoAirNative.log('FLASH BOOTSTRAP injected '+location.href);}catch(e){};";
            byte[] out = (prefix + "\n" + original).getBytes("UTF-8");
            WebResourceResponse resp = new WebResourceResponse("application/javascript","UTF-8",new ByteArrayInputStream(out));
            if (android.os.Build.VERSION.SDK_INT >= 21) {
                Map<String,String> headers = new HashMap<>();
                headers.put("Cache-Control","no-store");
                headers.put("Access-Control-Allow-Origin","*");
                resp.setResponseHeaders(headers);
                resp.setStatusCodeAndReasonPhrase(200,"OK");
            }
            trace("FLASH BOOTSTRAP PREFIXED " + abbreviate(url,180));
            return resp;
        } catch (Throwable t) {
            trace("FLASH BOOTSTRAP ERROR " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
            try { if (conn != null) conn.disconnect(); } catch (Throwable ignored) { }
            return null;
        }
    }

'@
$s=$s.Replace($helperMarker,$helpers+$helperMarker)

# Strong diagnostic on S876 and capture DOM SWF state for 30 seconds.
$pageFinish='setState("page-finished " + pageUrl);'
if(!$s.Contains($pageFinish)){throw 'page finish marker missing'}
$extra=@'
setState("page-finished " + pageUrl);
                        if (pageUrl != null && pageUrl.contains("/serverlist/s876")) {
                            trace("S876 READY; forcing Flash adapter + DOM SWF scan");
                            injectFlashAdapter(view, "s876-finished");
                            final WebView scanView = view;
                            for (int d : new int[]{50,150,300,600,1000,2000,4000,8000,12000,20000,30000}) {
                                handler.postDelayed(() -> {
                                    if (scanView != webView) return;
                                    injectFlashAdapter(scanView, "s876-scan");
                                    scanView.evaluateJavascript("(function(){try{var a=[];var q=document.querySelectorAll('object,embed,param');for(var i=0;i<q.length;i++){var u=q[i].getAttribute('data')||q[i].getAttribute('src')||q[i].getAttribute('value')||'';if(u&&String(u).toLowerCase().indexOf('.swf')>=0)a.push(u);}return JSON.stringify({flash:!!(navigator.plugins&&navigator.plugins['Shockwave Flash']),plugins:navigator.plugins?navigator.plugins.length:-1,swfs:a,swfobject:typeof window.swfobject});}catch(e){return 'ERR '+e;}})();",
                                        v -> trace("S876 FLASH ENV " + String.valueOf(v)));
                                }, d);
                            }
                        }
'@
$s=$s.Replace($pageFinish,$extra.Trim())

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.7.3</versionNumber>','<versionNumber>0.7.4</versionNumber>')
$x=$x.Replace('<versionLabel>0.7.3 direct game session diagnostics</versionLabel>','<versionLabel>0.7.4 official flash bootstrap</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.7.3</name>','<name>Naruto AIR Experimental 0.7.4</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.7.3 - guest flow + direct game session + Flash diagnostics...','Naruto AIR 0.7.4 - official Flash bootstrap + AIR runtime...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.7.3";','public static const VERSION:String = "0.7.4";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.7.4 patch applied: official script bootstrap is prefixed with Flash environment before Naruto game JS executes.'

. .\scripts\patch-075.ps1
