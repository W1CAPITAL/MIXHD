$ErrorActionPreference = 'Stop'
. .\scripts\patch-058.ps1

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

$imp='import android.os.Looper;'
if(!$s.Contains($imp)){throw 'Looper import missing'}
$s=$s.Replace($imp,$imp+[Environment]::NewLine+'import android.os.Message;')

$field='private volatile String currentGamePage = "";'
if(!$s.Contains($field)){throw 'currentGamePage field missing'}
$s=$s.Replace($field,$field+[Environment]::NewLine+'    private WebChromeClient portalChromeClient;')

$multi='s.setSupportMultipleWindows(false);'
if(!$s.Contains($multi)){throw 'supportMultipleWindows marker missing'}
$s=$s.Replace($multi,'s.setSupportMultipleWindows(true);')

$likely='if (!isAllowedGameHost(u)) return false;'
if(!$s.Contains($likely)){throw 'isLikelyGameUrl marker missing'}
$s=$s.Replace($likely,$likely+[Environment]::NewLine+'        if (u.contains("naruto-pt.oasgames.com/main.html")) return true;')

$chrome='webView.setWebChromeClient(new WebChromeClient());'
if(!$s.Contains($chrome)){throw 'WebChromeClient marker missing'}
$chromeNew=@'
portalChromeClient = new WebChromeClient() {
                    @Override public boolean onCreateWindow(WebView view, boolean isDialog, boolean isUserGesture, Message resultMsg) {
                        try {
                            Activity a = getActivity();
                            if (a == null) {
                                setState("popup rejected: activity-null");
                                return false;
                            }
                            WebView child = new WebView(a);
                            configurePopupWebView(child);
                            FrameLayout.LayoutParams popupLp = new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
                            a.addContentView(child, popupLp);
                            child.bringToFront();
                            child.requestFocus(View.FOCUS_DOWN);
                            webView = child;
                            WebView.WebViewTransport transport = (WebView.WebViewTransport) resultMsg.obj;
                            transport.setWebView(child);
                            resultMsg.sendToTarget();
                            setState("game popup accepted; switched active WebView");
                            return true;
                        } catch (Throwable t) {
                            setState("popup ERROR " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
                            return false;
                        }
                    }

                    @Override public void onCloseWindow(WebView window) {
                        try {
                            if (window != null && window != webView) {
                                ViewGroup p = window.getParent() instanceof ViewGroup ? (ViewGroup) window.getParent() : null;
                                if (p != null) p.removeView(window);
                                window.destroy();
                            }
                        } catch (Throwable ignored) { }
                        setState("popup close requested");
                    }
                };
                webView.setWebChromeClient(portalChromeClient);
'@
$s=$s.Replace($chrome,$chromeNew.Trim())

$marker='    private void detectCloudflareBlock(final WebView view) {'
if(!$s.Contains($marker)){throw 'helper marker missing'}
$helper=@'
    private void configurePopupWebView(final WebView child) {
        child.setBackgroundColor(Color.BLACK);
        child.setVisibility(View.VISIBLE);
        child.setFocusable(true);
        child.setFocusableInTouchMode(true);
        child.setClickable(true);
        child.setLayerType(View.LAYER_TYPE_HARDWARE, null);
        if (android.os.Build.VERSION.SDK_INT >= 21) child.setElevation(11000f);

        WebSettings ps = child.getSettings();
        ps.setJavaScriptEnabled(true);
        ps.setDomStorageEnabled(true);
        ps.setDatabaseEnabled(true);
        ps.setAllowContentAccess(true);
        ps.setAllowFileAccess(true);
        ps.setMediaPlaybackRequiresUserGesture(false);
        ps.setLoadWithOverviewMode(true);
        ps.setUseWideViewPort(true);
        ps.setBuiltInZoomControls(false);
        ps.setDisplayZoomControls(false);
        ps.setJavaScriptCanOpenWindowsAutomatically(true);
        ps.setSupportMultipleWindows(true);
        ps.setCacheMode(WebSettings.LOAD_DEFAULT);
        if (android.os.Build.VERSION.SDK_INT >= 21) ps.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        if (nativeUserAgent != null && !nativeUserAgent.isEmpty()) ps.setUserAgentString(nativeUserAgent);

        CookieManager cm = CookieManager.getInstance();
        cm.setAcceptCookie(true);
        cm.setAcceptThirdPartyCookies(child, true);
        child.addJavascriptInterface(new PortalJsBridge(), "NarutoAirNative");
        if (portalChromeClient != null) child.setWebChromeClient(portalChromeClient);

        child.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                try { return popupNavigation(view, request.getUrl().toString()); }
                catch (Throwable t) { setState("popup navigation ERROR " + t.getMessage()); return false; }
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, String target) {
                try { return popupNavigation(view, target); }
                catch (Throwable t) { setState("popup navigation ERROR " + t.getMessage()); return false; }
            }
            @Override public void onPageStarted(WebView view, String pageUrl, Bitmap favicon) {
                super.onPageStarted(view, pageUrl, favicon);
                currentGamePage = pageUrl == null ? "" : pageUrl;
                setState("popup page-started " + pageUrl);
                injectBurst(view);
            }
            @Override public void onPageFinished(WebView view, String pageUrl) {
                super.onPageFinished(view, pageUrl);
                currentGamePage = pageUrl == null ? "" : pageUrl;
                setState("popup page-finished " + pageUrl);
                injectFlashAdapter(view, "popup-finished");
                inspectSoon(view, 80);
                inspectSoon(view, 300);
                inspectSoon(view, 800);
                inspectSoon(view, 1600);
                inspectSoon(view, 3000);
                inspectSoon(view, 6000);
                inspectSoon(view, 10000);
                inspectSoon(view, 15000);
            }
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                String u = request.getUrl().toString();
                String low = u.toLowerCase();
                if (isLegacyGameHttps(u)) {
                    WebResourceResponse proxied = fetchLegacyHttpResource(u, request);
                    if (proxied != null) return proxied;
                }
                if (!launchSent && low.contains(".swf")) {
                    if (isPlaceholderSwf(u)) setState("popup placeholder-swf ignored " + u);
                    else {
                        setState("popup real-swf-request observed " + u);
                        captureNetworkSwf(u, request);
                    }
                }
                return super.shouldInterceptRequest(view, request);
            }
        });
    }

    private boolean popupNavigation(final WebView view, String target) {
        if (view == null || target == null || target.isEmpty()) return false;
        setState("popup navigation " + abbreviate(target, 180));
        if (isLegacyGameHttps(target)) {
            String fallback = legacyHttpUrl(target);
            currentGamePage = fallback;
            setState("popup legacy TLS fallback -> HTTP");
            view.loadUrl(fallback);
            return true;
        }
        currentGamePage = target;
        return false;
    }

'@
$s=$s.Replace($marker,$helper+$marker)

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.5.8</versionNumber>','<versionNumber>0.5.9</versionNumber>')
$x=$x.Replace('<versionLabel>0.5.8 legacy TLS HTTP bridge</versionLabel>','<versionLabel>0.5.9 popup game window bridge</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.5.8</name>','<name>Naruto AIR Experimental 0.5.9</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.5.8 - legacy TLS HTTP bridge + AIR loader...','Naruto AIR 0.5.9 - popup game window + SWF capture...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.5.8";','public static const VERSION:String = "0.5.9";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.5.9 patch applied: popup game WebView + legacy HTTP bridge + SWF capture.'
