$ErrorActionPreference = 'Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

$field='private boolean desktopGameUaActive = false;'
if(!$s.Contains($field)){throw 'desktopGameUaActive field not found'}
$s=$s.Replace($field,$field+[Environment]::NewLine+'    private boolean bootstrapReplayAttempted = false;')

$reset='launchSent = false;'
$resetPos=$s.IndexOf($reset)
if($resetPos -lt 0){throw 'launch reset not found'}
$s=$s.Remove($resetPos,$reset.Length).Insert($resetPos,$reset+[Environment]::NewLine+'                bootstrapReplayAttempted = false;')

$tail='window.__narutoAirAdapterInstalled=true;window.__narutoAirPatch();'
if(!$s.Contains($tail)){throw 'adapter tail not found'}
$early=@'
window.__narutoAirReport=function(u,fv){try{if(!u)return;u=(new URL(String(u),location.href)).href;var low=u.toLowerCase();if(low.indexOf('.swf')<0)return;var clean=low.split('?')[0].split('#')[0];var c={swf:u,flashvars:fv||{},page:location.href};window.__narutoAirCandidates=window.__narutoAirCandidates||[];window.__narutoAirCandidates.push(c);if(clean.slice(-9)==='empty.swf'||clean.slice(-9)==='blank.swf')return;window.__narutoAirLaunch=c;try{if(window.NarutoAirNative&&window.NarutoAirNative.capture)window.NarutoAirNative.capture(JSON.stringify(c));}catch(nb){}}catch(e){}};try{var oldSA=Element.prototype.setAttribute;Element.prototype.setAttribute=function(n,v){try{var ln=String(n).toLowerCase(),sv=String(v||'');if((ln==='src'||ln==='data'||ln==='movie'||ln==='value')&&sv.toLowerCase().indexOf('.swf')>=0)window.__narutoAirReport(sv,{});}catch(e){}return oldSA.apply(this,arguments);};}catch(e){}try{function naScan(n){if(!n||n.nodeType!==1)return;var vals=[];try{vals.push(n.getAttribute('src'),n.getAttribute('data'),n.getAttribute('value'));}catch(e){}for(var i=0;i<vals.length;i++){var v=vals[i];if(v&&String(v).toLowerCase().indexOf('.swf')>=0)window.__narutoAirReport(v,{});}try{var qs=n.querySelectorAll?n.querySelectorAll('object,embed,param'):[];for(var j=0;j<qs.length;j++){var q=qs[j],a=q.getAttribute('src')||q.getAttribute('data')||q.getAttribute('value');if(a&&String(a).toLowerCase().indexOf('.swf')>=0)window.__narutoAirReport(a,{});}}catch(e){}}if(document.documentElement){naScan(document.documentElement);new MutationObserver(function(ms){for(var i=0;i<ms.length;i++){var m=ms[i];if(m.type==='attributes')naScan(m.target);if(m.addedNodes)for(var j=0;j<m.addedNodes.length;j++)naScan(m.addedNodes[j]);}}).observe(document.documentElement,{subtree:true,childList:true,attributes:true,attributeFilter:['src','data','value']});}}catch(e){}
'@
$early=$early -replace '\r?\n',''
$s=$s.Replace($tail,$early+$tail)

$finish='setState("page-finished " + pageUrl);'
if(!$s.Contains($finish)){throw 'page-finished marker missing'}
$s=$s.Replace($finish,$finish+[Environment]::NewLine+'                        if (isLikelyGameUrl(pageUrl) && !bootstrapReplayAttempted && !launchSent) replayGamePageWithEarlyAdapter(view, pageUrl);')

$methodMarker='    private void detectCloudflareBlock(final WebView view) {'
if(!$s.Contains($methodMarker)){throw 'detectCloudflareBlock marker missing'}
$method=@'
    private void replayGamePageWithEarlyAdapter(final WebView view, final String pageUrl) {
        if (view == null || bootstrapReplayAttempted || launchSent) return;
        bootstrapReplayAttempted = true;
        setState("bootstrap-replay armed " + pageUrl);
        handler.postDelayed(() -> {
            if (view != webView || launchSent) return;
            final String grab = "(function(){try{return document.documentElement?document.documentElement.outerHTML:'';}catch(e){return '';}})();";
            view.evaluateJavascript(grab, value -> {
                if (view != webView || launchSent || value == null || "null".equals(value)) return;
                try {
                    Object parsed = new JSONTokener(value).nextValue();
                    String html = parsed instanceof String ? (String) parsed : "";
                    if (html == null || html.length() < 100) {
                        setState("bootstrap-replay skipped: HTML unavailable");
                        return;
                    }
                    String injected = "<script>" + FLASH_ADAPTER_JS + "</script>";
                    String lower = html.toLowerCase();
                    int head = lower.indexOf("<head");
                    if (head >= 0) {
                        int end = html.indexOf('>', head);
                        if (end >= 0) html = html.substring(0, end + 1) + injected + html.substring(end + 1);
                        else html = injected + html;
                    } else {
                        html = injected + html;
                    }
                    setState("bootstrap-replay loading early Flash adapter");
                    view.loadDataWithBaseURL(pageUrl, html, "text/html", "UTF-8", pageUrl);
                } catch (Throwable t) {
                    setState("bootstrap-replay ERROR " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
                }
            });
        }, 350);
    }

'@
$s=$s.Replace($methodMarker,$method+$methodMarker)

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.5.4</versionNumber>','<versionNumber>0.5.7</versionNumber>')
$x=$x.Replace('<versionLabel>0.5.4 real SWF hunter</versionLabel>','<versionLabel>0.5.7 early bootstrap replay</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.5.4</name>','<name>Naruto AIR Experimental 0.5.7</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.5.4 - real SWF hunter + AIR loader...','Naruto AIR 0.5.7 - early bootstrap replay + AIR loader...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.5.4";','public static const VERSION:String = "0.5.7";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.5.7 patch applied: early HTML bootstrap replay + DOM SWF observer.'
