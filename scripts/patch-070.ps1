$ErrorActionPreference = 'Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# Imports for official launcher compatibility + native inspector.
$anchor='import android.app.Activity;'
if(!$s.Contains($anchor)){throw 'Activity import missing'}
if(!$s.Contains('import android.app.AlertDialog;')){
  $s=$s.Replace($anchor,$anchor+[Environment]::NewLine+'import android.app.AlertDialog;')
}
if(!$s.Contains('import android.view.Gravity;')){
  $s=$s.Replace('import android.view.ViewGroup;','import android.view.ViewGroup;'+[Environment]::NewLine+'import android.view.Gravity;')
}
if(!$s.Contains('import android.widget.Button;')){
  $s=$s.Replace('import android.widget.FrameLayout;','import android.widget.FrameLayout;'+[Environment]::NewLine+'import android.widget.Button;'+[Environment]::NewLine+'import android.widget.EditText;')
}
if(!$s.Contains('import android.util.Base64;')){
  $s=$s.Replace('import android.os.Message;','import android.os.Message;'+[Environment]::NewLine+'import android.util.Base64;')
}
if(!$s.Contains('import java.net.URLEncoder;')){
  $s=$s.Replace('import java.net.URLConnection;','import java.net.URLConnection;'+[Environment]::NewLine+'import java.net.URLEncoder;')
}

# Constants/fields discovered from the decompiled official 3.4.7.0 launcher.
$field='private int traceLines = 0;'
if(!$s.Contains($field)){throw 'trace field marker missing'}
$fields=@'
private int traceLines = 0;
    private Button nativeLogButton;
    private volatile String launcherToken = "";
    private volatile String launcherUsername = "";
    private static final String OFFICIAL_LAUNCHER_LOGIN =
            "https://gamebox3.narutowebgame.com/gamebox/2.4.1/template/login.php?lg=pt&gameid=narutopt&maintype=play&page=login&account=oas&version=3.4.7.0&channel=oas&playertype=logingame";
'@
$s=$s.Replace($field,$fields.Trim())

# Register the exact window.external bridge used by the official CefSharp launcher.
$jsif='webView.addJavascriptInterface(new PortalJsBridge(), "NarutoAirNative");'
if(!$s.Contains($jsif)){throw 'main JavascriptInterface marker missing'}
$s=$s.Replace($jsif,$jsif+[Environment]::NewLine+'                webView.addJavascriptInterface(new LauncherExternalBridge(), "external");')

$popupJsif='child.addJavascriptInterface(new PortalJsBridge(), "NarutoAirNative");'
if($s.Contains($popupJsif) -and !$s.Contains('child.addJavascriptInterface(new LauncherExternalBridge(), "external");')){
  $s=$s.Replace($popupJsif,$popupJsif+[Environment]::NewLine+'        child.addJavascriptInterface(new LauncherExternalBridge(), "external");')
}

# Force desktop CEF-like UA for the official gamebox pages.
$uaMarker='nativeUserAgent = s.getUserAgentString();' + [Environment]::NewLine + '                activeUserAgent = nativeUserAgent;'
if(!$s.Contains($uaMarker)){throw 'UA marker missing'}
$uaReplace=@'
nativeUserAgent = s.getUserAgentString();
                activeUserAgent = nativeUserAgent;
                if (url != null && url.contains("gamebox3.narutowebgame.com")) {
                    String launcherUa = buildDesktopGameUa(nativeUserAgent);
                    s.setUserAgentString(launcherUa);
                    activeUserAgent = launcherUa;
                    desktopGameUaActive = true;
                    setState("official-launcher desktop UA enabled");
                }
'@
$s=$s.Replace($uaMarker,$uaReplace.Trim())

# Add a native LOG button above WebView; this survives black/blank HTML and does not depend on JS injection.
$attachMarker='activity.addContentView(webView, lp);' + [Environment]::NewLine + '                webView.bringToFront();'
if(!$s.Contains($attachMarker)){throw 'webview attach marker missing'}
$attachReplace=@'
activity.addContentView(webView, lp);
                webView.bringToFront();
                attachNativeInspector(activity);
                if (nativeLogButton != null) nativeLogButton.bringToFront();
'@
$s=$s.Replace($attachMarker,$attachReplace.Trim())

# Remove the native inspector together with the WebView.
$removeMarker='    private void removeWebViewNow() {' + [Environment]::NewLine + '        if (webView != null) {'
if(!$s.Contains($removeMarker)){throw 'removeWebView marker missing'}
$removeReplace=@'
    private void removeWebViewNow() {
        if (nativeLogButton != null) {
            try {
                ViewGroup bp = nativeLogButton.getParent() instanceof ViewGroup ? (ViewGroup) nativeLogButton.getParent() : null;
                if (bp != null) bp.removeView(nativeLogButton);
            } catch (Throwable ignored) { }
            nativeLogButton = null;
        }
        if (webView != null) {
'@
$s=$s.Replace($removeMarker,$removeReplace.TrimEnd())

# Insert native inspector helpers before destroyWebView.
$destroyMarker='    private void destroyWebView() {'
if(!$s.Contains($destroyMarker)){throw 'destroyWebView marker missing'}
$nativeInspector=@'
    private void attachNativeInspector(final Activity activity) {
        try {
            if (nativeLogButton != null) {
                ViewGroup old = nativeLogButton.getParent() instanceof ViewGroup ? (ViewGroup) nativeLogButton.getParent() : null;
                if (old != null) old.removeView(nativeLogButton);
            }
            Button b = new Button(activity);
            b.setText("LOG");
            b.setTextSize(12f);
            b.setAllCaps(false);
            b.setAlpha(0.92f);
            b.setOnClickListener(v -> showNativeTrace(activity));
            FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(150, 92);
            bp.gravity = Gravity.BOTTOM | Gravity.END;
            bp.setMargins(0, 0, 18, 18);
            activity.addContentView(b, bp);
            if (android.os.Build.VERSION.SDK_INT >= 21) b.setElevation(20000f);
            nativeLogButton = b;
            trace("NATIVE INSPECTOR attached");
        } catch (Throwable t) {
            setState("native inspector ERROR " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
        }
    }

    private void showNativeTrace(final Activity activity) {
        try {
            EditText text = new EditText(activity);
            text.setText(traceText());
            text.setTextSize(10f);
            text.setTextColor(Color.WHITE);
            text.setBackgroundColor(Color.rgb(8,8,8));
            text.setGravity(Gravity.TOP | Gravity.START);
            text.setSelectAllOnFocus(false);
            text.setHorizontallyScrolling(false);
            text.setMinLines(18);
            text.setMaxLines(30);
            text.setPadding(18,18,18,18);
            AlertDialog dialog = new AlertDialog.Builder(activity)
                    .setTitle("Naruto AIR - trace")
                    .setView(text)
                    .setPositiveButton("COPIAR", (d, which) -> {
                        try {
                            ClipboardManager cb = (ClipboardManager) activity.getSystemService(Context.CLIPBOARD_SERVICE);
                            if (cb != null) cb.setPrimaryClip(ClipData.newPlainText("Naruto AIR trace", traceText()));
                        } catch (Throwable ignored) { }
                    })
                    .setNeutralButton("ATUALIZAR", null)
                    .setNegativeButton("FECHAR", null)
                    .create();
            dialog.setOnShowListener(x -> {
                try {
                    dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(v -> text.setText(traceText()));
                } catch (Throwable ignored) { }
            });
            dialog.show();
        } catch (Throwable t) {
            setState("show trace ERROR " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
        }
    }

    private String b64Decode(String v) {
        try {
            if (v == null || v.isEmpty()) return "";
            return new String(Base64.decode(v, Base64.DEFAULT), "UTF-8");
        } catch (Throwable t) {
            return v == null ? "" : v;
        }
    }

    private String b64Encode(String v) {
        try {
            return Base64.encodeToString((v == null ? "" : v).getBytes("UTF-8"), Base64.NO_WRAP);
        } catch (Throwable t) {
            return "";
        }
    }

    private String urlEncode(String v) {
        try { return URLEncoder.encode(v == null ? "" : v, "UTF-8"); }
        catch (Throwable t) { return ""; }
    }

    private void executeLauncherCallback(String callback, String payload) {
        try {
            if (callback == null || callback.trim().isEmpty() || webView == null) return;
            String js = callback + "(" + JSONObject.quote(payload == null ? "" : payload) + ");";
            trace("CALLBACK " + callback);
            webView.evaluateJavascript(js, null);
        } catch (Throwable t) {
            setState("launcher callback ERROR " + String.valueOf(t.getMessage()));
        }
    }

    private String launcherPlayUrl(String token, String username) {
        return "https://gamebox3.narutowebgame.com/gamebox/2.4.1/template/game.php?" +
                "channel=oas&token=" + urlEncode(token) +
                "&lg=pt&gameid=narutopt&name=" + urlEncode(username) +
                "&version=3.4.7.0&gamename=" + urlEncode("Naruto Online");
    }

'@
$s=$s.Replace($destroyMarker,$nativeInspector+$destroyMarker)

# Insert official launcher's Javascript bridge before PortalJsBridge.
$bridgeMarker='    private class PortalJsBridge {'
if(!$s.Contains($bridgeMarker)){throw 'PortalJsBridge class marker missing'}
$externalBridge=@'
    private class LauncherExternalBridge {
        @JavascriptInterface
        public void WINIE_LoginOK(final String json) {
            handler.post(() -> {
                try {
                    JSONObject data = new JSONObject(json == null ? "{}" : json);
                    String token = b64Decode(data.optString("token", ""));
                    String username = b64Decode(data.optString("username", ""));
                    String callback = data.optString("callback", "");
                    launcherToken = token;
                    launcherUsername = username;
                    trace("OFFICIAL LOGIN OK user=" + (username.isEmpty() ? "(empty)" : username.replaceAll("(?<=.).(?=.*@)", "*")) + " token=(redacted)");

                    JSONObject answer = new JSONObject();
                    answer.put("code", b64Encode("1"));
                    answer.put("token", token);
                    answer.put("name", b64Encode(username));
                    executeLauncherCallback(callback, answer.toString());

                    try {
                        CookieManager cm = CookieManager.getInstance();
                        if (!token.isEmpty()) {
                            cm.setCookie("https://gamebox3.narutowebgame.com", "oas_user=" + token + "; Path=/");
                            cm.setCookie("https://naruto.narutowebgame.com", "oas_user=" + token + "; Path=/");
                            if (android.os.Build.VERSION.SDK_INT >= 21) cm.flush();
                        }
                    } catch (Throwable ignored) { }

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
                    }, 650);
                } catch (Throwable t) {
                    setState("WINIE_LoginOK ERROR " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
                }
            });
        }

        @JavascriptInterface
        public void WINIE_InitUserData(final String json) {
            handler.post(() -> {
                try {
                    JSONObject data = new JSONObject(json == null ? "{}" : json);
                    executeLauncherCallback(data.optString("callback", ""), "[]");
                    trace("WINIE_InitUserData -> []");
                } catch (Throwable t) { trace("WINIE_InitUserData ERROR " + t); }
            });
        }

        @JavascriptInterface
        public void WINIE_InitBoxType(final String json) {
            trace("WINIE_InitBoxType");
        }

        @JavascriptInterface
        public void WINIE_Localstorage(final String json) {
            handler.post(() -> {
                try {
                    JSONObject data = new JSONObject(json == null ? "{}" : json);
                    String callback = data.optString("callback", "");
                    trace("WINIE_Localstorage callback=" + callback);
                    if (!callback.isEmpty()) {
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
                    }
                } catch (Throwable t) {
                    setState("WINIE_Localstorage ERROR " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
                }
            });
        }

        @JavascriptInterface
        public void WINIE_DelMainUser(final String json) {
            handler.post(() -> {
                try {
                    JSONObject data = new JSONObject(json == null ? "{}" : json);
                    executeLauncherCallback(data.optString("callback", ""), "1");
                } catch (Throwable ignored) { }
            });
        }

        @JavascriptInterface
        public void WINIE_ShowMsgBox(final String json) {
            trace("WINIE_ShowMsgBox " + (json == null ? "" : abbreviate(json, 180)));
        }

        @JavascriptInterface
        public void WINIE_LoginFacebook(final String url) {
            trace("WINIE_LoginFacebook " + abbreviate(url, 180));
            handler.post(() -> { if (webView != null && url != null && !url.isEmpty()) webView.loadUrl(url); });
        }

        @JavascriptInterface
        public void WINIE_GetXiaoUrl(final String json) {
            trace("WINIE_GetXiaoUrl");
        }

        @JavascriptInterface
        public void WINIE_SetGameMsg(final String json) {
            trace("WINIE_SetGameMsg " + abbreviate(json, 180));
        }

        @JavascriptInterface
        public void WINIE_OpenWithSystemBrowser(final String url) {
            trace("WINIE_OpenWithSystemBrowser " + abbreviate(url, 180));
        }
    }

'@
$s=$s.Replace($bridgeMarker,$externalBridge+$bridgeMarker)

# Default native OpenFunction URL also becomes the official launcher login.
$defaultOpen='String url = "https://naruto.narutowebgame.com/pt/serverlist/";'
if(!$s.Contains($defaultOpen)){throw 'default OpenFunction URL missing'}
$s=$s.Replace($defaultOpen,'String url = OFFICIAL_LAUNCHER_LOGIN;')

Set-Content $p $s -Encoding UTF8

# Open the exact login page used by the decompiled official launcher, not the public browser server list.
$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('bridge.openPortal("https://naruto.narutowebgame.com/pt/serverlist/")','bridge.openPortal("https://gamebox3.narutowebgame.com/gamebox/2.4.1/template/login.php?lg=pt&gameid=narutopt&maintype=play&page=login&account=oas&version=3.4.7.0&channel=oas&playertype=logingame")')
$a=$a.Replace('Naruto AIR 0.6.2 - full flow inspector + SWF bootstrap...','Naruto AIR 0.7.0 - official 3.4.7.0 launcher bridge + native inspector...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.6.2</versionNumber>','<versionNumber>0.7.0</versionNumber>')
$x=$x.Replace('<versionLabel>0.6.2 full flow inspector</versionLabel>','<versionLabel>0.7.0 official launcher bridge</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.6.2</name>','<name>Naruto AIR Experimental 0.7.0</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.6.2";','public static const VERSION:String = "0.7.0";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.7.0 patch applied: official CefSharp launcher flow, window.external bridge, game.php handoff and native LOG inspector.'

. .\scripts\patch-071.ps1
