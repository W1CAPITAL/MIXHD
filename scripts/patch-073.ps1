$ErrorActionPreference='Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# Do not proxy game.php with HttpURLConnection. The real Android WebView session already reaches it.
$proxy=@'
                        if (isGameboxGameHtml(u)) {
                            WebResourceResponse early = fetchGameboxHtmlWithAdapter(u, request);
                            if (early != null) return early;
                        }
'@
if($s.Contains($proxy.Trim())){
  $s=$s.Replace($proxy.Trim(),'                        // 0.7.3: direct WebView game.php navigation; preserves Cloudflare/session/browser state.')
}

# Stronger earliest-possible JS injection after onPageStarted.
$burst=@'
        injectFlashAdapter(view, "start");
        handler.postDelayed(() -> { if (view == webView) injectFlashAdapter(view, "30ms"); }, 30);
        handler.postDelayed(() -> { if (view == webView) injectFlashAdapter(view, "120ms"); }, 120);
        handler.postDelayed(() -> { if (view == webView) injectFlashAdapter(view, "350ms"); }, 350);
'@
if(!$s.Contains($burst.Trim())){throw 'injectBurst body marker missing'}
$burst2=@'
        injectFlashAdapter(view, "start");
        handler.postDelayed(() -> { if (view == webView) injectFlashAdapter(view, "5ms"); }, 5);
        handler.postDelayed(() -> { if (view == webView) injectFlashAdapter(view, "15ms"); }, 15);
        handler.postDelayed(() -> { if (view == webView) injectFlashAdapter(view, "30ms"); }, 30);
        handler.postDelayed(() -> { if (view == webView) injectFlashAdapter(view, "75ms"); }, 75);
        handler.postDelayed(() -> { if (view == webView) injectFlashAdapter(view, "150ms"); }, 150);
        handler.postDelayed(() -> { if (view == webView) injectFlashAdapter(view, "350ms"); }, 350);
'@
$s=$s.Replace($burst.Trim(),$burst2.Trim())

# Diagnostic imports.
if(!$s.Contains('import android.net.http.SslError;')){
  $s=$s.Replace('import android.graphics.Color;','import android.graphics.Color;'+[Environment]::NewLine+'import android.net.http.SslError;')
}
if(!$s.Contains('import android.webkit.SslErrorHandler;')){
  $s=$s.Replace('import android.webkit.WebResourceResponse;','import android.webkit.WebResourceResponse;'+[Environment]::NewLine+'import android.webkit.SslErrorHandler;'+[Environment]::NewLine+'import android.webkit.RenderProcessGoneDetail;')
}

# Convert JS console errors into easy-to-find trace errors.
$console='if (cm != null) trace("CONSOLE " + cm.messageLevel() + " " + cm.sourceId() + ":" + cm.lineNumber() + " " + cm.message());'
if($s.Contains($console)){
  $s=$s.Replace($console,'if (cm != null) {'+[Environment]::NewLine+
'                            String cp = cm.messageLevel() == ConsoleMessage.MessageLevel.ERROR ? "ERROR JS " : "CONSOLE ";'+[Environment]::NewLine+
'                            trace(cp + cm.messageLevel() + " " + cm.sourceId() + ":" + cm.lineNumber() + " " + cm.message());'+[Environment]::NewLine+
'                        }')
}

# Detailed WebView failures.
$old=@'
                    @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                        super.onReceivedError(view, request, error);
                        if (request != null && request.isForMainFrame()) setState("ERROR webview " + String.valueOf(error));
                    }
'@
if(!$s.Contains($old.Trim())){throw 'main onReceivedError marker missing'}
$new=@'
                    @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                        super.onReceivedError(view, request, error);
                        String eu = request == null || request.getUrl() == null ? "" : request.getUrl().toString();
                        String ed = error == null ? "" : String.valueOf(error.getDescription());
                        int ec = error == null ? 0 : error.getErrorCode();
                        trace("ERROR WEBVIEW code=" + ec + " main=" + (request != null && request.isForMainFrame()) + " url=" + abbreviate(eu,220) + " desc=" + ed);
                        if (request != null && request.isForMainFrame()) setState("ERROR WEBVIEW MAIN code=" + ec + " " + ed);
                    }

                    @Override public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse response) {
                        super.onReceivedHttpError(view, request, response);
                        try {
                            String eu = request == null || request.getUrl() == null ? "" : request.getUrl().toString();
                            int ec = response == null ? 0 : response.getStatusCode();
                            if (ec >= 400) trace("ERROR HTTP " + ec + " main=" + (request != null && request.isForMainFrame()) + " url=" + abbreviate(eu,220));
                        } catch (Throwable t) { trace("ERROR HTTP hook " + t); }
                    }

                    @Override public void onReceivedSslError(WebView view, SslErrorHandler sslHandler, SslError sslError) {
                        String eu = sslError == null ? "" : sslError.getUrl();
                        int ep = sslError == null ? -1 : sslError.getPrimaryError();
                        trace("ERROR SSL primary=" + ep + " url=" + abbreviate(eu,220));
                        super.onReceivedSslError(view, sslHandler, sslError);
                    }

                    @Override public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
                        trace("ERROR RENDER PROCESS GONE crashed=" + (detail != null && detail.didCrash()) + " priority=" + (detail == null ? -1 : detail.rendererPriorityAtExit()));
                        setState("ERROR RENDER PROCESS GONE");
                        return true;
                    }
'@
$s=$s.Replace($old.Trim(),$new.Trim())

# Report whether Flash spoof is visible to the page after it starts.
$finish='setState("page-finished " + pageUrl);'
if(!$s.Contains($finish)){throw 'page-finished marker missing'}
$diag=@'
setState("page-finished " + pageUrl);
                        if (pageUrl != null && pageUrl.contains("gamebox3.narutowebgame.com") && pageUrl.contains("/template/game.php")) {
                            handler.postDelayed(() -> {
                                if (view != webView) return;
                                view.evaluateJavascript("(function(){try{return JSON.stringify({plugins:navigator.plugins?navigator.plugins.length:-1,mimes:navigator.mimeTypes?navigator.mimeTypes.length:-1,flash:!!(navigator.plugins&&navigator.plugins['Shockwave Flash']),swfobj:typeof window.swfobject,href:location.href});}catch(e){return 'ERR '+e;}})();",
                                    v -> trace("GAME FLASH ENV " + String.valueOf(v)));
                            }, 500);
                        }
'@
$s=$s.Replace($finish,$diag.Trim())

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.7.2</versionNumber>','<versionNumber>0.7.3</versionNumber>')
$x=$x.Replace('<versionLabel>0.7.2 guest game bootstrap</versionLabel>','<versionLabel>0.7.3 direct game session diagnostics</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.7.2</name>','<name>Naruto AIR Experimental 0.7.3</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.7.2 - guest quick-register + official game bootstrap...','Naruto AIR 0.7.3 - guest flow + direct game session + Flash diagnostics...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.7.2";','public static const VERSION:String = "0.7.3";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.7.3 patch applied: direct game.php session, aggressive early adapter, explicit HTTP/SSL/JS/render diagnostics.'
