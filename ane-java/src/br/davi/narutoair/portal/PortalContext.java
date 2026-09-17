package br.davi.narutoair.portal;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import com.adobe.fre.FREContext;
import com.adobe.fre.FREFunction;
import com.adobe.fre.FREObject;

import org.json.JSONObject;
import org.json.JSONTokener;

import java.util.HashMap;
import java.util.Map;

public class PortalContext extends FREContext {
    private WebView webView;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean launchSent = false;
    private boolean flashRepairAttempted = false;
    private boolean desktopGameUaActive = false;
    private volatile String state = "native-context-ready";
    private volatile String nativeUserAgent = "";
    private volatile String activeUserAgent = "";

    private static final String FLASH_ADAPTER_JS =
            "(function(){try{" +
            "if(window.__narutoAirAdapterInstalled){try{window.__narutoAirPatch&&window.__narutoAirPatch();}catch(e){}return 'already';}" +
            "var plugin={name:'Shockwave Flash',description:'Shockwave Flash 32.0 r0',filename:'pepflashplayer.dll'};" +
            "var plugins={0:plugin,length:1,item:function(i){return i===0?plugin:null;},namedItem:function(n){return /shockwave flash/i.test(String(n))?plugin:null;},refresh:function(){}};plugins['Shockwave Flash']=plugin;" +
            "var mime={type:'application/x-shockwave-flash',suffixes:'swf',description:'Shockwave Flash',enabledPlugin:plugin};" +
            "var mimes={0:mime,length:1,item:function(i){return i===0?mime:null;},namedItem:function(n){return String(n)==='application/x-shockwave-flash'?mime:null;}};mimes['application/x-shockwave-flash']=mime;" +
            "try{Object.defineProperty(navigator,'plugins',{get:function(){return plugins;},configurable:true});}catch(e){try{Object.defineProperty(Navigator.prototype,'plugins',{get:function(){return plugins;},configurable:true});}catch(x){}}" +
            "try{Object.defineProperty(navigator,'mimeTypes',{get:function(){return mimes;},configurable:true});}catch(e){try{Object.defineProperty(Navigator.prototype,'mimeTypes',{get:function(){return mimes;},configurable:true});}catch(x){}}" +
            "if(!window.ActiveXObject){window.ActiveXObject=function(n){if(/shockwaveflash/i.test(String(n)))return{GetVariable:function(v){return String(v)==='$version'?'WIN 32,0,0,465':'';}};throw new Error('ActiveX unavailable');};}" +
            "window.__narutoAirPatch=function(){try{" +
            "var s=window.swfobject;if(!s)return false;" +
            "s.hasFlashPlayerVersion=function(){return true;};s.getFlashPlayerVersion=function(){return{major:32,minor:0,release:0};};" +
            "s.ua=s.ua||{};s.ua.w3=true;s.ua.win=true;s.ua.mac=false;s.ua.pv=[32,0,0];" +
            "if(!s.__narutoAirPatched){s.__narutoAirPatched=true;s.__narutoAirOriginalEmbed=s.embedSWF;" +
            "s.embedSWF=function(swfUrl,replaceElemId,width,height,version,expressInstallUrl,flashvars,params,attrs,callbackFn){" +
            "try{var abs=(new URL(String(swfUrl),location.href)).href;window.__narutoAirLaunch={swf:abs,flashvars:flashvars||{},params:params||{},page:location.href};" +
            "var el=document.getElementById(replaceElemId);if(el){el.setAttribute('data-narutoair-swf',abs);el.setAttribute('data-narutoair-flashvars',JSON.stringify(flashvars||{}));}" +
            "if(typeof callbackFn==='function'){try{callbackFn({success:true,id:replaceElemId,ref:el||null});}catch(cb){}}return true;}catch(z){return false;}};}return true;}catch(e){return false;}};" +
            "window.__narutoAirAdapterInstalled=true;window.__narutoAirPatch();" +
            "window.setInterval(function(){try{window.__narutoAirPatch();}catch(e){}},75);" +
            "return 'installed';}catch(e){return 'ERR:'+String(e);}})();";

    @Override public Map<String, FREFunction> getFunctions() {
        Map<String, FREFunction> map = new HashMap<>();
        map.put("ping", new PingFunction());
        map.put("status", new StatusFunction());
        map.put("open", new OpenFunction());
        map.put("hide", new HideFunction());
        map.put("show", new ShowFunction());
        map.put("close", new CloseFunction());
        map.put("report", new ReportFunction());
        return map;
    }

    @Override public void dispose() { destroyWebView(); }

    private void setState(String s) {
        state = s == null ? "" : s;
        send("log", state);
    }

    private void send(String code, String level) {
        try { dispatchStatusEventAsync(code, level == null ? "" : level); }
        catch (Throwable ignored) { }
    }

    private FREObject stringObject(String value) {
        try { return FREObject.newObject(value == null ? "" : value); }
        catch (Throwable ignored) { return null; }
    }

    private boolean isPortalOrLoginPage(String url) {
        String u = url == null ? "" : url.toLowerCase();
        return u.contains("/serverlist") || u.contains("login") || u.contains("passport") || u.contains("oauth") || u.contains("account");
    }

    private boolean isAllowedGameHost(String url) {
        String u = url == null ? "" : url.toLowerCase();
        return u.contains("narutowebgame.com") || u.contains("oasgames.com");
    }

    private boolean isLikelyGameUrl(String url) {
        String u = url == null ? "" : url.toLowerCase();
        if (!isAllowedGameHost(u)) return false;
        if (u.contains("login") || u.contains("passport") || u.contains("oauth") || u.contains("account")) return false;
        return u.contains("/game") || u.contains("/play") || u.contains("game?") || u.contains("serverid=") || u.contains("server_id=") || u.contains("sid=") || (u.contains("server=") && !u.contains("/serverlist"));
    }

    private String buildDesktopGameUa(String sourceUa) {
        String chrome = "Chrome/140.0.0.0";
        try {
            if (sourceUa != null) {
                int p = sourceUa.indexOf("Chrome/");
                if (p >= 0) {
                    int end = sourceUa.indexOf(' ', p);
                    chrome = end > p ? sourceUa.substring(p, end) : sourceUa.substring(p);
                }
            }
        } catch (Throwable ignored) { }
        return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " + chrome + " Safari/537.36";
    }

    private void activateDesktopGameUa(final WebView view, String reason) {
        if (view == null) return;
        try {
            String desktopUa = buildDesktopGameUa(nativeUserAgent);
            view.getSettings().setUserAgentString(desktopUa);
            activeUserAgent = desktopUa;
            desktopGameUaActive = true;
            setState("desktop-game-UA active: " + reason);
        } catch (Throwable t) {
            setState("ERROR desktop-game-UA " + t.getMessage());
        }
    }

    private void restoreNativeUa(final WebView view, String reason) {
        if (view == null || nativeUserAgent == null || nativeUserAgent.isEmpty()) return;
        try {
            view.getSettings().setUserAgentString(nativeUserAgent);
            activeUserAgent = nativeUserAgent;
            desktopGameUaActive = false;
            setState("native-UA restored: " + reason);
        } catch (Throwable t) {
            setState("ERROR native-UA restore " + t.getMessage());
        }
    }

    private void injectFlashAdapter(final WebView view, final String reason) {
        if (view == null) return;
        try {
            view.evaluateJavascript(FLASH_ADAPTER_JS, value -> {
                if (value != null && value.contains("ERR:")) setState("adapter-error " + value);
            });
        } catch (Throwable t) {
            setState("adapter-exception " + reason + " " + t.getMessage());
        }
    }

    private void injectBurst(final WebView view) {
        injectFlashAdapter(view, "start");
        handler.postDelayed(() -> { if (view == webView) injectFlashAdapter(view, "30ms"); }, 30);
        handler.postDelayed(() -> { if (view == webView) injectFlashAdapter(view, "120ms"); }, 120);
        handler.postDelayed(() -> { if (view == webView) injectFlashAdapter(view, "350ms"); }, 350);
    }

    private boolean handleNavigation(final WebView view, String target) {
        if (view == null || target == null || target.isEmpty()) return false;
        if (!desktopGameUaActive && isLikelyGameUrl(target)) {
            activateDesktopGameUa(view, "game-navigation");
            injectBurst(view);
            view.loadUrl(target);
            return true;
        }
        if (desktopGameUaActive && isPortalOrLoginPage(target) && !isLikelyGameUrl(target)) {
            restoreNativeUa(view, "portal-navigation");
            view.loadUrl(target);
            return true;
        }
        return false;
    }

    private void createAndOpen(final String url) {
        final Activity activity = getActivity();
        if (activity == null) { setState("ERROR activity-null"); return; }
        setState("open-scheduled activity=" + activity.getClass().getName());
        activity.runOnUiThread(() -> {
            try {
                removeWebViewNow();
                launchSent = false;
                flashRepairAttempted = false;
                desktopGameUaActive = false;
                setState("ui-thread creating-webview");

                webView = new WebView(activity);
                webView.setBackgroundColor(Color.WHITE);
                webView.setVisibility(View.VISIBLE);
                webView.setFocusable(true);
                webView.setFocusableInTouchMode(true);
                webView.setClickable(true);
                webView.requestFocus(View.FOCUS_DOWN);
                webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);
                if (android.os.Build.VERSION.SDK_INT >= 21) webView.setElevation(10000f);

                WebSettings s = webView.getSettings();
                s.setJavaScriptEnabled(true);
                s.setDomStorageEnabled(true);
                s.setDatabaseEnabled(true);
                s.setAllowContentAccess(true);
                s.setAllowFileAccess(true);
                s.setMediaPlaybackRequiresUserGesture(false);
                s.setLoadWithOverviewMode(true);
                s.setUseWideViewPort(true);
                s.setBuiltInZoomControls(false);
                s.setDisplayZoomControls(false);
                s.setJavaScriptCanOpenWindowsAutomatically(true);
                s.setSupportMultipleWindows(false);
                s.setCacheMode(WebSettings.LOAD_DEFAULT);
                nativeUserAgent = s.getUserAgentString();
                activeUserAgent = nativeUserAgent;
                setState("native-webview-ua-ready");

                CookieManager cm = CookieManager.getInstance();
                cm.setAcceptCookie(true);
                cm.setAcceptThirdPartyCookies(webView, true);

                webView.setWebChromeClient(new WebChromeClient());
                webView.setWebViewClient(new WebViewClient() {
                    @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                        try { return handleNavigation(view, request.getUrl().toString()); }
                        catch (Throwable t) { setState("navigation-error " + t.getMessage()); return false; }
                    }
                    @Override public boolean shouldOverrideUrlLoading(WebView view, String target) {
                        try { return handleNavigation(view, target); }
                        catch (Throwable t) { setState("navigation-error " + t.getMessage()); return false; }
                    }
                    @Override public void onPageStarted(WebView view, String pageUrl, Bitmap favicon) {
                        super.onPageStarted(view, pageUrl, favicon);
                        setState("page-started " + pageUrl);
                        if (desktopGameUaActive || !isPortalOrLoginPage(pageUrl)) injectBurst(view);
                    }
                    @Override public void onPageFinished(WebView view, String pageUrl) {
                        super.onPageFinished(view, pageUrl);
                        setState("page-finished " + pageUrl);
                        detectCloudflareBlock(view);
                        if (desktopGameUaActive || !isPortalOrLoginPage(pageUrl)) {
                            injectFlashAdapter(view, "finished");
                            inspectSoon(view, 80);
                            inspectSoon(view, 350);
                            inspectSoon(view, 900);
                            inspectSoon(view, 1800);
                            inspectSoon(view, 3500);
                        }
                        detectFlashWarningAndRepair(view);
                    }
                    @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                        super.onReceivedError(view, request, error);
                        if (request != null && request.isForMainFrame()) setState("ERROR webview " + String.valueOf(error));
                    }
                    @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                        String u = request.getUrl().toString();
                        if (!launchSent && u.toLowerCase().contains(".swf")) setState("swf-request " + u);
                        return super.shouldInterceptRequest(view, request);
                    }
                });

                FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
                activity.addContentView(webView, lp);
                webView.bringToFront();
                webView.requestLayout();
                webView.invalidate();
                setState("webview-attached");
                webView.loadUrl(url);
                setState("loadUrl-called " + url);
            } catch (Throwable t) {
                setState("ERROR create-webview " + t.getClass().getSimpleName() + ": " + t.getMessage());
            }
        });
    }

    private void detectCloudflareBlock(final WebView view) {
        final String js = "(function(){try{var t=((document.body&&document.body.innerText)||'').toLowerCase();return (t.indexOf('sorry, you have been blocked')>=0||t.indexOf('unable to access')>=0)?'yes':'no';}catch(e){return 'no';}})();";
        handler.postDelayed(() -> {
            if (view != webView) return;
            view.evaluateJavascript(js, value -> {
                if (value != null && value.toLowerCase().contains("yes")) setState("CLOUDFLARE BLOCK: current-UA=" + (desktopGameUaActive ? "desktop-game" : "native"));
            });
        }, 200);
    }

    private void detectFlashWarningAndRepair(final WebView view) {
        if (flashRepairAttempted || launchSent) return;
        final String js = "(function(){try{var t=((document.body&&document.body.innerText)||'').toLowerCase();return (t.indexOf('flash player')>=0||t.indexOf('adobe flash')>=0||t.indexOf('instale o flash')>=0||t.indexOf('flash não')>=0||t.indexOf('flash nao')>=0||t.indexOf('browser não suporta mais o flash')>=0||t.indexOf('browser nao suporta mais o flash')>=0)?'yes':'no';}catch(e){return 'no';}})();";
        handler.postDelayed(() -> {
            if (view != webView || launchSent || flashRepairAttempted) return;
            view.evaluateJavascript(js, value -> {
                if (value != null && value.toLowerCase().contains("yes")) {
                    flashRepairAttempted = true;
                    activateDesktopGameUa(view, "server-side-flash-fallback");
                    setState("flash-warning detected; adapter reinjected without reload");
                    injectBurst(view);
                    inspectSoon(view, 150);
                    inspectSoon(view, 900);
                }
            });
        }, 250);
    }

    private void inspectSoon(final WebView view, long delayMs) {
        handler.postDelayed(() -> {
            if (view != webView || launchSent) return;
            final String js = "(function(){try{" +
                    "var out={page:location.href,cookie:document.cookie||'',swf:'',flashvars:{}};" +
                    "function mergeObj(o){if(!o)return;for(var k in o){try{out.flashvars[String(k)]=String(o[k]);}catch(e){}}}" +
                    "function addKV(str){if(!str)return;str=String(str).replace(/^\\?/,'');str.split('&').forEach(function(p){if(!p)return;var i=p.indexOf('=');var k=i>=0?p.slice(0,i):p;var v=i>=0?p.slice(i+1):'';try{k=decodeURIComponent(k.replace(/\\+/g,' '));v=decodeURIComponent(v.replace(/\\+/g,' '));}catch(e){}if(k)out.flashvars[k]=v;});}" +
                    "if(window.__narutoAirLaunch){try{out.swf=String(window.__narutoAirLaunch.swf||'');mergeObj(window.__narutoAirLaunch.flashvars||{});}catch(e){}}" +
                    "var nodes=document.querySelectorAll('[data-narutoair-swf],embed,object');for(var i=0;i<nodes.length;i++){var n=nodes[i];var src=n.getAttribute('data-narutoair-swf')||n.getAttribute('src')||n.getAttribute('data')||'';if(src&&src.toLowerCase().indexOf('.swf')>=0&&!out.swf)out.swf=new URL(src,location.href).href;var fv=n.getAttribute('flashvars')||n.getAttribute('data-narutoair-flashvars');if(fv){try{var jo=JSON.parse(fv);mergeObj(jo);}catch(x){addKV(fv);}}}" +
                    "var ps=document.querySelectorAll('param');for(var j=0;j<ps.length;j++){var p=ps[j];var name=(p.getAttribute('name')||'').toLowerCase();var val=p.getAttribute('value')||'';if((name==='movie'||name==='src')&&val.toLowerCase().indexOf('.swf')>=0&&!out.swf)out.swf=new URL(val,location.href).href;if(name==='flashvars')addKV(val);}" +
                    "var html=document.documentElement?document.documentElement.outerHTML:'';if(!out.swf){var m=html.match(/(?:https?:)?\\/\\/[^\\\"'<> ]+\\.swf[^\\\"'<> ]*/i)||html.match(/[^\\\"'<> ]*NarutoServer\\.swf[^\\\"'<> ]*/i);if(m){try{out.swf=new URL(m[0],location.href).href;}catch(e){out.swf=m[0];}}}" +
                    "var q=(out.swf||'').split('?')[1];if(q)addKV(q);" +
                    "return JSON.stringify(out);}catch(e){return JSON.stringify({error:String(e),page:location.href});}})();";
            view.evaluateJavascript(js, value -> {
                if (launchSent || value == null || "null".equals(value)) return;
                try {
                    Object parsed = new JSONTokener(value).nextValue();
                    String json = parsed instanceof String ? (String) parsed : value;
                    JSONObject payload = new JSONObject(json);
                    String swf = payload.optString("swf", "");
                    if (!swf.isEmpty() && swf.toLowerCase().contains(".swf")) {
                        String page = payload.optString("page", "");
                        String nativeCookie = null;
                        try { nativeCookie = CookieManager.getInstance().getCookie(swf); } catch (Throwable ignored) { }
                        if ((nativeCookie == null || nativeCookie.isEmpty()) && !page.isEmpty()) {
                            try { nativeCookie = CookieManager.getInstance().getCookie(page); } catch (Throwable ignored) { }
                        }
                        if (nativeCookie != null && !nativeCookie.isEmpty()) payload.put("cookie", nativeCookie);
                        payload.put("userAgent", activeUserAgent == null ? "" : activeUserAgent);
                        launchSent = true;
                        setState("launch-captured " + swf);
                        send("launch", payload.toString());
                    }
                } catch (Throwable t) { setState("ERROR capture " + t.getMessage()); }
            });
        }, delayMs);
    }

    private void setVisible(final boolean visible) {
        Activity a = getActivity();
        if (a == null) { setState("ERROR show-hide activity-null"); return; }
        a.runOnUiThread(() -> {
            if (webView != null) {
                webView.setVisibility(visible ? View.VISIBLE : View.GONE);
                if (visible) webView.bringToFront();
                setState(visible ? "webview-visible" : "webview-hidden");
            }
        });
    }

    private void removeWebViewNow() {
        if (webView != null) {
            try {
                ViewGroup parent = webView.getParent() instanceof ViewGroup ? (ViewGroup) webView.getParent() : null;
                if (parent != null) parent.removeView(webView);
                webView.stopLoading();
                webView.loadUrl("about:blank");
                webView.removeAllViews();
                webView.destroy();
            } catch (Throwable ignored) { }
            webView = null;
        }
    }

    private void destroyWebView() {
        Activity a = getActivity();
        if (a == null) return;
        a.runOnUiThread(this::removeWebViewNow);
    }

    private class PingFunction implements FREFunction {
        @Override public FREObject call(FREContext c, FREObject[] a) {
            Activity activity = getActivity();
            return stringObject("native-ok activity=" + (activity == null ? "null" : activity.getClass().getName()));
        }
    }
    private class StatusFunction implements FREFunction { @Override public FREObject call(FREContext c, FREObject[] a) { return stringObject(state); } }
    private class OpenFunction implements FREFunction {
        @Override public FREObject call(FREContext context, FREObject[] args) {
            String url = "https://naruto.narutowebgame.com/pt/serverlist/";
            try { if (args != null && args.length > 0 && args[0] != null) url = args[0].getAsString(); } catch (Throwable ignored) { }
            createAndOpen(url);
            return stringObject("open-accepted");
        }
    }
    private class HideFunction implements FREFunction { @Override public FREObject call(FREContext c, FREObject[] a) { setVisible(false); return stringObject("hide-accepted"); } }
    private class ShowFunction implements FREFunction { @Override public FREObject call(FREContext c, FREObject[] a) { setVisible(true); return stringObject("show-accepted"); } }
    private class CloseFunction implements FREFunction { @Override public FREObject call(FREContext c, FREObject[] a) { destroyWebView(); return stringObject("close-accepted"); } }
    private class ReportFunction implements FREFunction {
        @Override public FREObject call(FREContext c, FREObject[] a) {
            try { if (a != null && a.length > 0 && a[0] != null) setState("AIR: " + a[0].getAsString()); } catch (Throwable ignored) { }
            return stringObject("report-accepted");
        }
    }
}
