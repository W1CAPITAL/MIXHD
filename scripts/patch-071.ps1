$ErrorActionPreference='Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# Additional imports for native account dialog.
if(!$s.Contains('import android.text.InputType;')){
  $s=$s.Replace('import android.util.Base64;','import android.util.Base64;'+[Environment]::NewLine+'import android.text.InputType;')
}
if(!$s.Contains('import android.widget.LinearLayout;')){
  $s=$s.Replace('import android.widget.EditText;','import android.widget.EditText;'+[Environment]::NewLine+'import android.widget.LinearLayout;')
}

# Fields for in-memory credentials only.
$field='private volatile String launcherUsername = "";'
if(!$s.Contains($field)){throw 'launcherUsername field missing'}
$fields=@'
private volatile String launcherUsername = "";
    private volatile String manualLoginEmail = "";
    private volatile String manualLoginPassword = "";
    private volatile String lastObservedLocation = "";
'@
$s=$s.Replace($field,$fields.Trim())

# Fix JS observer location spam.
$old="var scan=function(){try{var fs=document.querySelectorAll('iframe[src]');for(var i=0;i<fs.length;i++)rep('IFRAME '+fs[i].src);var forms=document.querySelectorAll('form[action]');for(var j=0;j<forms.length;j++)rep('FORM '+forms[j].method+' '+forms[j].action+' target='+(forms[j].target||''));var as=document.querySelectorAll('a[href][target]');for(var k=0;k<as.length;k++)rep('LINK '+as[k].href+' target='+(as[k].target||''));rep('LOCATION '+location.href);}catch(e){}};"
$new="var __lastLoc='';var scan=function(){try{var fs=document.querySelectorAll('iframe[src]');for(var i=0;i<fs.length;i++)rep('IFRAME '+fs[i].src);var forms=document.querySelectorAll('form[action]');for(var j=0;j<forms.length;j++)rep('FORM '+forms[j].method+' '+forms[j].action+' target='+(forms[j].target||''));var as=document.querySelectorAll('a[href][target]');for(var k=0;k<as.length;k++)rep('LINK '+as[k].href+' target='+(as[k].target||''));if(location.href!==__lastLoc){__lastLoc=location.href;rep('LOCATION '+location.href);}}catch(e){}};"
if($s.Contains($old)){$s=$s.Replace($old,$new)}

# Add native account prompt helpers before attachNativeInspector.
$marker='    private void attachNativeInspector(final Activity activity) {'
if(!$s.Contains($marker)){throw 'attachNativeInspector marker missing'}
$helpers=@'
    private void promptAccountThenLoad(final Activity activity, final String url) {
        try {
            LinearLayout box = new LinearLayout(activity);
            box.setOrientation(LinearLayout.VERTICAL);
            int pad = 24;
            box.setPadding(pad,pad,pad,pad);

            EditText email = new EditText(activity);
            email.setHint("Email da conta Oasis");
            email.setSingleLine(true);
            email.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS);
            if (!manualLoginEmail.isEmpty()) email.setText(manualLoginEmail);

            EditText pass = new EditText(activity);
            pass.setHint("Senha");
            pass.setSingleLine(true);
            pass.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);

            box.addView(email, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
            box.addView(pass, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

            AlertDialog dlg = new AlertDialog.Builder(activity)
                    .setTitle("Naruto Online - conta")
                    .setMessage("Os dados ficam somente na memória desta execução e não são gravados no APK/GitHub.")
                    .setView(box)
                    .setPositiveButton("ENTRAR", null)
                    .setNegativeButton("ABRIR LOGIN NORMAL", null)
                    .create();

            dlg.setOnShowListener(x -> {
                dlg.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
                    String e = email.getText() == null ? "" : email.getText().toString().trim();
                    String pw = pass.getText() == null ? "" : pass.getText().toString();
                    if (e.isEmpty() || pw.isEmpty()) {
                        email.setError(e.isEmpty() ? "Informe o email" : null);
                        pass.setError(pw.isEmpty() ? "Informe a senha" : null);
                        return;
                    }
                    manualLoginEmail = e;
                    manualLoginPassword = pw;
                    trace("MANUAL ACCOUNT configured user=" + e.replaceAll("(?<=.).(?=.*@)", "*") + " password=(redacted)");
                    dlg.dismiss();
                    if (webView != null) {
                        webView.loadUrl(url);
                        setState("official login loaded with manual account cache");
                    }
                });
                dlg.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener(v -> {
                    manualLoginEmail = "";
                    manualLoginPassword = "";
                    dlg.dismiss();
                    if (webView != null) {
                        webView.loadUrl(url);
                        setState("official login loaded without manual cache");
                    }
                });
            });
            dlg.setCancelable(false);
            dlg.show();
        } catch (Throwable t) {
            setState("account dialog ERROR " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
            if (webView != null) webView.loadUrl(url);
        }
    }

    private String manualUserCacheJson() {
        try {
            if (manualLoginEmail.isEmpty() || manualLoginPassword.isEmpty()) return "[]";
            JSONObject item = new JSONObject();
            item.put("type", b64Encode("oas"));
            item.put("username", b64Encode(manualLoginEmail));
            item.put("pwd", b64Encode(manualLoginPassword));
            item.put("remember", b64Encode("true"));
            item.put("automatic", b64Encode("true"));
            JSONArray arr = new JSONArray();
            arr.put(item);
            return arr.toString();
        } catch (Throwable t) {
            trace("manualUserCacheJson ERROR " + t);
            return "[]";
        }
    }

    private boolean isGameboxGameHtml(String u) {
        String low = u == null ? "" : u.toLowerCase();
        return low.startsWith("https://gamebox3.narutowebgame.com/") && low.contains("/template/game.php");
    }

    private WebResourceResponse fetchGameboxHtmlWithAdapter(String originalUrl, WebResourceRequest request) {
        if (!isGameboxGameHtml(originalUrl)) return null;
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(originalUrl).openConnection();
            conn.setInstanceFollowRedirects(true);
            conn.setConnectTimeout(12000);
            conn.setReadTimeout(25000);
            conn.setRequestMethod("GET");
            conn.setRequestProperty("User-Agent", buildDesktopGameUa(nativeUserAgent));
            conn.setRequestProperty("Accept", "text/html,application/xhtml+xml,*/*;q=0.8");
            try {
                Map<String,String> hs = request == null ? null : request.getRequestHeaders();
                if (hs != null) {
                    for (Map.Entry<String,String> e : hs.entrySet()) {
                        String k=e.getKey(), v=e.getValue();
                        if (k==null || v==null) continue;
                        if ("host".equalsIgnoreCase(k) || "connection".equalsIgnoreCase(k) || "accept-encoding".equalsIgnoreCase(k)) continue;
                        conn.setRequestProperty(k,v);
                    }
                }
            } catch (Throwable ignored) { }
            String cookie = null;
            try { cookie = CookieManager.getInstance().getCookie(originalUrl); } catch (Throwable ignored) { }
            if (cookie != null && !cookie.isEmpty()) conn.setRequestProperty("Cookie", cookie);

            int code = conn.getResponseCode();
            if (code < 200 || code >= 400) {
                trace("GAMEBOX HTML status=" + code + " " + abbreviate(originalUrl,160));
                return null;
            }

            InputStream in = conn.getInputStream();
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            byte[] buf = new byte[16384];
            int n;
            while ((n=in.read(buf))>0) bos.write(buf,0,n);
            try { in.close(); } catch(Throwable ignored) {}

            String encoding="UTF-8";
            String ct=conn.getContentType();
            if(ct!=null){
                for(String part:ct.split(";")){
                    String q=part.trim();
                    if(q.toLowerCase().startsWith("charset=")) encoding=q.substring(q.indexOf('=')+1).trim();
                }
            }
            Charset cs;
            try { cs=Charset.forName(encoding); } catch(Throwable t){cs=Charset.forName("UTF-8");}
            String html=new String(bos.toByteArray(),cs);
            String injected="<script>"+FLASH_ADAPTER_JS+"</script>";
            String lowHtml=html.toLowerCase();
            int head=lowHtml.indexOf("<head");
            if(head>=0){
                int end=html.indexOf('>',head);
                html=end>=0?html.substring(0,end+1)+injected+html.substring(end+1):injected+html;
            } else html=injected+html;

            try {
                Map<String,java.util.List<String>> all=conn.getHeaderFields();
                java.util.List<String> sc=all.get("Set-Cookie");
                if(sc==null) sc=all.get("set-cookie");
                if(sc!=null){
                    CookieManager cm=CookieManager.getInstance();
                    for(String v:sc) if(v!=null) cm.setCookie(originalUrl,v);
                    if(android.os.Build.VERSION.SDK_INT>=21) cm.flush();
                }
            } catch(Throwable ignored){}

            WebResourceResponse resp=new WebResourceResponse("text/html",encoding,new ByteArrayInputStream(html.getBytes(cs)));
            if(android.os.Build.VERSION.SDK_INT>=21){
                Map<String,String> rh=new HashMap<>();
                for(Map.Entry<String,java.util.List<String>> e:conn.getHeaderFields().entrySet()){
                    if(e.getKey()==null || e.getValue()==null || e.getValue().isEmpty()) continue;
                    String k=e.getKey();
                    if("content-length".equalsIgnoreCase(k)||"content-encoding".equalsIgnoreCase(k)||"content-security-policy".equalsIgnoreCase(k)) continue;
                    rh.put(k,e.getValue().get(0));
                }
                resp.setResponseHeaders(rh);
                resp.setStatusCodeAndReasonPhrase(code,"OK");
            }
            setState("GAMEBOX EARLY Flash adapter injected into game.php");
            return resp;
        } catch(Throwable t){
            setState("GAMEBOX HTML proxy ERROR "+t.getClass().getSimpleName()+": "+String.valueOf(t.getMessage()));
            return null;
        }
    }

'@
$s=$s.Replace($marker,$helpers+$marker)

# Intercept game.php before page scripts.
$needle='String u = request.getUrl().toString();' + [Environment]::NewLine + '                        if (shouldTraceUrl(u)) trace("REQ " + request.getMethod() + " " + u);'
if(!$s.Contains($needle)){throw 'request trace marker missing'}
$replacement='String u = request.getUrl().toString();' + [Environment]::NewLine +
'                        if (shouldTraceUrl(u)) trace("REQ " + request.getMethod() + " " + u);' + [Environment]::NewLine +
'                        if (isGameboxGameHtml(u)) {' + [Environment]::NewLine +
'                            WebResourceResponse early = fetchGameboxHtmlWithAdapter(u, request);' + [Environment]::NewLine +
'                            if (early != null) return early;' + [Environment]::NewLine +
'                        }'
$s=$s.Replace($needle,$replacement)

# Load official login only after the native account dialog.
$loadNeedle='webView.loadUrl(url);' + [Environment]::NewLine + '                setState("loadUrl-called " + url);'
if(!$s.Contains($loadNeedle)){throw 'initial load marker missing'}
$loadReplacement=@'
if (url != null && url.contains("gamebox3.narutowebgame.com") && url.contains("/template/login.php")) {
                    setState("waiting native account dialog");
                    promptAccountThenLoad(activity, url);
                } else {
                    webView.loadUrl(url);
                    setState("loadUrl-called " + url);
                }
'@
$s=$s.Replace($loadNeedle,$loadReplacement.Trim())

# Correct login bridge semantics: login WINIE_Localstorage has no callback and must not call null().
$localStart='        @JavascriptInterface' + [Environment]::NewLine + '        public void WINIE_Localstorage(final String json) {'
$localPos=$s.IndexOf($localStart,$s.IndexOf('private class LauncherExternalBridge'))
if($localPos -lt 0){throw 'LauncherExternalBridge WINIE_Localstorage missing'}
$nextPos=$s.IndexOf('        @JavascriptInterface',$localPos+$localStart.Length)
if($nextPos -lt 0){throw 'next JS method after Localstorage missing'}
$oldLocal=$s.Substring($localPos,$nextPos-$localPos)
$newLocal=@'
        @JavascriptInterface
        public void WINIE_Localstorage(final String json) {
            handler.post(() -> {
                try {
                    JSONObject data = new JSONObject(json == null ? "{}" : json);
                    String callback = (!data.has("callback") || data.isNull("callback")) ? "" : data.optString("callback", "");
                    if ("null".equalsIgnoreCase(callback)) callback = "";
                    if (callback.isEmpty()) {
                        trace("WINIE_Localstorage login-state stored; callback absent (official behavior)");
                        return;
                    }

                    trace("WINIE_Localstorage GAME callback=" + callback);
                    JSONObject cfg = new JSONObject();
                    cfg.put("name", "Naruto Online");
                    cfg.put("ico", "//gamebox3.narutowebgame.com/gamebox/2.4.1/static/games/narutopt/icon.jpg");
                    cfg.put("serverbgpic", "//gamebox3.narutowebgame.com/gamebox/2.4.1/static/games/narutopt/list.jpg");
                    cfg.put("accountbgpic", "//gamebox3.narutowebgame.com/gamebox/2.4.1/static/games/narutopt/smallload.jpg");
                    cfg.put("url", "//odp3.oasgames.com/api/game/serverlist?gamecode=narutopt&uid={uid}");
                    cfg.put("openGamesFlag", 1);
                    cfg.put("login_css", "//gamebox3.narutowebgame.com/gamebox/2.4.1/static/css/oas.narutopt.css");
                    cfg.put("login_skin", "2");
                    cfg.put("getNewsUrl", "//odp3.oasgames.com/api/game/gbox-news?gamecode=narutopt");

                    JSONObject wrapped = new JSONObject();
                    wrapped.put("data", b64Encode(cfg.toString()));
                    executeLauncherCallback(callback, wrapped.toString());
                } catch (Throwable t) {
                    setState("WINIE_Localstorage ERROR " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
                }
            });
        }

'@
$s=$s.Remove($localPos,$nextPos-$localPos).Insert($localPos,$newLocal)

# Return the native-entered account cache instead of always [].
$oldInit='executeLauncherCallback(data.optString("callback", ""), "[]");' + [Environment]::NewLine + '                    trace("WINIE_InitUserData -> []");'
if(!$s.Contains($oldInit)){throw 'InitUserData [] marker missing'}
$newInit='String cache = manualUserCacheJson();' + [Environment]::NewLine +
'                    executeLauncherCallback(data.optString("callback", ""), cache);' + [Environment]::NewLine +
'                    trace("WINIE_InitUserData -> " + (manualLoginEmail.isEmpty() ? "[]" : "[manual account redacted]"));'
$s=$s.Replace($oldInit,$newInit)

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.7.0</versionNumber>','<versionNumber>0.7.1</versionNumber>')
$x=$x.Replace('<versionLabel>0.7.0 official launcher bridge</versionLabel>','<versionLabel>0.7.1 native account and game bridge</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.7.0</name>','<name>Naruto AIR Experimental 0.7.1</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.7.0 - official 3.4.7.0 launcher bridge + native inspector...','Naruto AIR 0.7.1 - native account + official launcher + early game Flash bridge...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.7.0";','public static const VERSION:String = "0.7.1";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.7.1 patch applied: native credential dialog, correct login Localstorage, manual account cache, early game.php Flash adapter.'
