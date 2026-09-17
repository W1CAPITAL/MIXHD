$ErrorActionPreference = 'Stop'
. .\scripts\patch-056.ps1

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

$importNeedle='import android.webkit.CookieManager;'
if(!$s.Contains($importNeedle)){throw 'CookieManager import not found'}
$s=$s.Replace($importNeedle,$importNeedle+[Environment]::NewLine+'import android.webkit.JavascriptInterface;')

$addBridge='webView.setWebChromeClient(new WebChromeClient() {'
if(!$s.Contains($addBridge)){throw 'chrome client marker not found'}
$s=$s.Replace($addBridge,'webView.addJavascriptInterface(new JsBridge(), "NarutoAIRNative");'+[Environment]::NewLine+'                '+$addBridge)

$marker='    private boolean isInterestingResource(String url) {'
if(!$s.Contains($marker)){throw 'helper marker missing'}
$helper=@'
    private class JsBridge {
        @JavascriptInterface
        public void swf(final String rawUrl, final String page, final String flashvarsJson) {
            handler.post(() -> {
                if (launchSent || rawUrl == null || rawUrl.isEmpty()) return;
                String swfUrl = rawUrl;
                try {
                    String base = (page == null || page.isEmpty()) ? currentGamePage : page;
                    if (base != null && !base.isEmpty()) swfUrl = new java.net.URL(new java.net.URL(base), rawUrl).toString();
                } catch (Throwable ignored) { }
                if (!swfUrl.toLowerCase().contains(".swf") || isPlaceholderSwf(swfUrl)) {
                    setState("JS bridge placeholder ignored " + abbreviate(swfUrl, 160));
                    return;
                }
                try {
                    JSONObject payload = new JSONObject();
                    payload.put("swf", swfUrl);
                    JSONObject fv = new JSONObject();
                    if (flashvarsJson != null && !flashvarsJson.isEmpty()) {
                        try { fv = new JSONObject(flashvarsJson); } catch (Throwable ignored) { }
                    }
                    payload.put("flashvars", fv);
                    payload.put("source", "javascript-interface");
                    String referer = (page == null || page.isEmpty()) ? currentGamePage : page;
                    payload.put("page", referer == null ? "" : referer);
                    String cookie = null;
                    try { cookie = CookieManager.getInstance().getCookie(swfUrl); } catch (Throwable ignored) { }
                    if ((cookie == null || cookie.isEmpty()) && referer != null && !referer.isEmpty()) {
                        try { cookie = CookieManager.getInstance().getCookie(referer); } catch (Throwable ignored) { }
                    }
                    if (cookie != null && !cookie.isEmpty()) payload.put("cookie", cookie);
                    payload.put("userAgent", activeUserAgent == null ? "" : activeUserAgent);
                    launchSent = true;
                    setState("REAL JS launch-captured " + swfUrl);
                    send("launch", payload.toString());
                } catch (Throwable t) {
                    setState("ERROR JS bridge capture " + t.getMessage());
                }
            });
        }

        @JavascriptInterface
        public void log(final String message) {
            handler.post(() -> setState("JS bridge: " + abbreviate(message, 180)));
        }
    }

'@
$s=$s.Replace($marker,$helper+$marker)

$tail='window.__narutoAirErrors=window.__narutoAirErrors||[];try{window.addEventListener(''error'',function(ev){try{window.__narutoAirErrors.push(String(ev.message||ev.error||''js-error''));}catch(x){}});}catch(x){}window.__narutoAirAdapterInstalled=true;window.__narutoAirPatch();'
if(!$s.Contains($tail)){throw 'adapter tail after 0.5.5 not found'}
$enhanced=@'
window.__narutoAirErrors=window.__narutoAirErrors||[];window.__narutoAirReport=function(u,fv){try{if(!u)return;u=(new URL(String(u),location.href)).href;var clean=u.toLowerCase().split('?')[0].split('#')[0];window.__narutoAirCandidates=window.__narutoAirCandidates||[];var c={swf:u,flashvars:fv||{},page:location.href};window.__narutoAirCandidates.push(c);if(clean.slice(-10)!='/empty.swf'&&clean.slice(-10)!='/blank.swf'&&clean!=='empty.swf'&&clean!=='blank.swf'){window.__narutoAirLaunch=c;try{if(window.NarutoAIRNative&&NarutoAIRNative.swf)NarutoAIRNative.swf(u,location.href,JSON.stringify(fv||{}));}catch(nb){}}}catch(e){}};try{var oldSA=Element.prototype.setAttribute;Element.prototype.setAttribute=function(n,v){try{var ln=String(n).toLowerCase(),sv=String(v||'');if((ln==='src'||ln==='data'||ln==='movie'||ln==='value')&&sv.toLowerCase().indexOf('.swf')>=0)window.__narutoAirReport(sv,{});}catch(e){}return oldSA.apply(this,arguments);};}catch(e){}try{function scanNode(n){if(!n||n.nodeType!==1)return;var vals=[];try{vals.push(n.getAttribute('src'),n.getAttribute('data'),n.getAttribute('value'));}catch(e){}for(var i=0;i<vals.length;i++){var v=vals[i];if(v&&String(v).toLowerCase().indexOf('.swf')>=0)window.__narutoAirReport(v,{});}try{var qs=n.querySelectorAll?n.querySelectorAll('object,embed,param'):[];for(var j=0;j<qs.length;j++){var q=qs[j];var a=q.getAttribute('src')||q.getAttribute('data')||q.getAttribute('value');if(a&&a.toLowerCase().indexOf('.swf')>=0)window.__narutoAirReport(a,{});}}catch(e){}}if(document.documentElement){scanNode(document.documentElement);new MutationObserver(function(ms){for(var i=0;i<ms.length;i++){var m=ms[i];if(m.type==='attributes')scanNode(m.target);if(m.addedNodes)for(var j=0;j<m.addedNodes.length;j++)scanNode(m.addedNodes[j]);}}).observe(document.documentElement,{subtree:true,childList:true,attributes:true,attributeFilter:['src','data','value']});}}catch(e){}try{window.addEventListener('error',function(ev){try{window.__narutoAirErrors.push(String(ev.message||ev.error||'js-error'));}catch(x){}});}catch(x){}window.__narutoAirAdapterInstalled=true;window.__narutoAirPatch();
'@
$enhanced=$enhanced -replace '\r?\n',''
$s=$s.Replace($tail,$enhanced)

$embedNeedle='window.__narutoAirCandidates=window.__narutoAirCandidates||[];window.__narutoAirCandidates.push(c);'
if(!$s.Contains($embedNeedle)){throw 'embed candidate marker not found'}
$s=$s.Replace($embedNeedle,$embedNeedle+'try{window.__narutoAirReport&&window.__narutoAirReport(abs,flashvars||{});}catch(rr){}')

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.5.6</versionNumber>','<versionNumber>0.5.7</versionNumber>').Replace('<versionLabel>0.5.6 native UA network hunter</versionLabel>','<versionLabel>0.5.7 DOM bridge SWF capture</versionLabel>').Replace('<name>Naruto AIR Experimental 0.5.6</name>','<name>Naruto AIR Experimental 0.5.7</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.5.6 - native UA + network SWF hunter...','Naruto AIR 0.5.7 - DOM bridge + network SWF capture...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.5.6";','public static const VERSION:String = "0.5.7";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8
Write-Host '0.5.7 DOM bridge patch applied.'
