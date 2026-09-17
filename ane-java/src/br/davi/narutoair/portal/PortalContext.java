package br.davi.narutoair.portal;

import android.app.Activity;
import android.graphics.Color;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
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

    @Override public Map<String, FREFunction> getFunctions() {
        Map<String, FREFunction> map = new HashMap<>();
        map.put("open", new OpenFunction());
        map.put("hide", new HideFunction());
        map.put("show", new ShowFunction());
        map.put("close", new CloseFunction());
        return map;
    }

    @Override public void dispose() {
        destroyWebView();
    }

    private void send(String code, String level) {
        try { dispatchStatusEventAsync(code, level == null ? "" : level); }
        catch (Throwable ignored) { }
    }

    private void createAndOpen(final String url) {
        final Activity activity = getActivity();
        if (activity == null) {
            send("log", "ERRO: Activity Android indisponivel.");
            return;
        }

        activity.runOnUiThread(() -> {
            try {
                removeWebViewNow();
                launchSent = false;

                webView = new WebView(activity);
                webView.setBackgroundColor(Color.WHITE);
                webView.setVisibility(View.VISIBLE);
                webView.setFocusable(true);
                webView.setFocusableInTouchMode(true);
                webView.setClickable(true);
                webView.requestFocus(View.FOCUS_DOWN);
                if (android.os.Build.VERSION.SDK_INT >= 21) webView.setElevation(1000f);

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
                s.setUserAgentString(s.getUserAgentString() + " NarutoAIR/0.4.3");

                CookieManager cm = CookieManager.getInstance();
                cm.setAcceptCookie(true);
                cm.setAcceptThirdPartyCookies(webView, true);

                webView.setWebChromeClient(new WebChromeClient());
                webView.setWebViewClient(new WebViewClient() {
                    @Override public void onPageFinished(WebView view, String pageUrl) {
                        super.onPageFinished(view, pageUrl);
                        send("log", "Pagina carregada: " + pageUrl);
                        inspectSoon(view, 250);
                        inspectSoon(view, 1200);
                        inspectSoon(view, 3000);
                    }

                    @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                        super.onReceivedError(view, request, error);
                        if (request != null && request.isForMainFrame()) {
                            send("log", "ERRO WebView: " + error);
                        }
                    }

                    @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                        String u = request.getUrl().toString();
                        if (!launchSent && u.toLowerCase().contains(".swf")) {
                            send("log", "Requisicao SWF detectada: " + u);
                        }
                        return super.shouldInterceptRequest(view, request);
                    }
                });

                Window window = activity.getWindow();
                View decor = window != null ? window.getDecorView() : null;
                if (!(decor instanceof ViewGroup)) {
                    throw new IllegalStateException("decorView nao e ViewGroup");
                }

                ViewGroup root = (ViewGroup) decor;
                FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                );
                root.addView(webView, lp);
                webView.bringToFront();
                root.invalidate();
                webView.invalidate();

                send("log", "WebView anexada ao decorView: " + root.getClass().getName());
                send("log", "Abrindo portal: " + url);
                webView.loadUrl(url);
            } catch (Throwable t) {
                send("log", "ERRO ao criar WebView: " + t.getClass().getSimpleName() + ": " + t.getMessage());
            }
        });
    }

    private void inspectSoon(final WebView view, long delayMs) {
        handler.postDelayed(() -> {
            if (view != webView || launchSent) return;
            final String js = "(function(){try{" +
                    "var out={page:location.href,cookie:document.cookie||'',swf:'',flashvars:{}};" +
                    "function addKV(str){if(!str)return;str=String(str).replace(/^\\?/,'');str.split('&').forEach(function(p){if(!p)return;var i=p.indexOf('=');var k=i>=0?p.slice(0,i):p;var v=i>=0?p.slice(i+1):'';try{k=decodeURIComponent(k.replace(/\\+/g,' '));v=decodeURIComponent(v.replace(/\\+/g,' '));}catch(e){}if(k)out.flashvars[k]=v;});}" +
                    "var nodes=document.querySelectorAll('embed,object');for(var i=0;i<nodes.length;i++){var n=nodes[i];var src=n.getAttribute('src')||n.getAttribute('data')||'';if(src&&src.toLowerCase().indexOf('.swf')>=0&&!out.swf)out.swf=new URL(src,location.href).href;var fv=n.getAttribute('flashvars');if(fv)addKV(fv);}" +
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
                        launchSent = true;
                        send("log", "SWF e parametros de lancamento capturados.");
                        send("launch", json);
                    }
                } catch (Throwable t) {
                    send("log", "Falha ao interpretar captura: " + t.getMessage());
                }
            });
        }, delayMs);
    }

    private void setVisible(final boolean visible) {
        Activity a = getActivity();
        if (a == null) return;
        a.runOnUiThread(() -> {
            if (webView != null) {
                webView.setVisibility(visible ? View.VISIBLE : View.GONE);
                if (visible) webView.bringToFront();
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

    private class OpenFunction implements FREFunction {
        @Override public FREObject call(FREContext context, FREObject[] args) {
            String url = "https://naruto.narutowebgame.com/pt/serverlist";
            try { if (args != null && args.length > 0 && args[0] != null) url = args[0].getAsString(); }
            catch (Throwable ignored) { }
            send("log", "Comando open recebido pela extensao nativa.");
            createAndOpen(url);
            return null;
        }
    }
    private class HideFunction implements FREFunction { @Override public FREObject call(FREContext c, FREObject[] a) { setVisible(false); return null; } }
    private class ShowFunction implements FREFunction { @Override public FREObject call(FREContext c, FREObject[] a) { setVisible(true); return null; } }
    private class CloseFunction implements FREFunction { @Override public FREObject call(FREContext c, FREObject[] a) { destroyWebView(); return null; } }
}
