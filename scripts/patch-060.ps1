$ErrorActionPreference = 'Stop'
$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

$tail='window.__narutoAirAdapterInstalled=true;window.__narutoAirPatch();'
if(!$s.Contains($tail)){throw 'adapter tail missing'}
$js=@'
try{if(!window.__narutoAirSameTab){window.__narutoAirSameTab=true;var nav=function(u){try{if(!u)return;var a=(new URL(String(u),location.href)).href;if(window.NarutoAirNative&&window.NarutoAirNative.openGameUrl){window.NarutoAirNative.openGameUrl(a);}}catch(e){}};var fakeLoc={};try{Object.defineProperty(fakeLoc,'href',{configurable:true,get:function(){return '';},set:function(v){nav(v);}});}catch(e){}var fakeWin={closed:false,focus:function(){},blur:function(){},close:function(){},location:fakeLoc};var oldOpen=window.open;window.open=function(u,n,f){try{if(u){nav(u);return fakeWin;}return fakeWin;}catch(e){try{return oldOpen?oldOpen.apply(window,arguments):null;}catch(x){return null;}}};var fixTargets=function(root){try{root=root||document;var xs=root.querySelectorAll?root.querySelectorAll('a[target],form[target]'):[];for(var i=0;i<xs.length;i++){var t=(xs[i].getAttribute('target')||'').toLowerCase();if(t&&t!=='_self'&&t!=='_top'&&t!=='_parent')xs[i].setAttribute('target','_self');}}catch(e){}};fixTargets(document);try{new MutationObserver(function(ms){for(var i=0;i<ms.length;i++){var m=ms[i];if(m.addedNodes)for(var j=0;j<m.addedNodes.length;j++){var n=m.addedNodes[j];if(n&&n.nodeType===1){try{if(n.matches&&n.matches('a[target],form[target]'))n.setAttribute('target','_self');}catch(e){}fixTargets(n);}}}}).observe(document.documentElement||document,{subtree:true,childList:true});}catch(e){}}}catch(e){}
'@
$js=$js -replace '\r?\n',''
$s=$s.Replace($tail,$js+$tail)

$bridgeMarker='        @JavascriptInterface' + [Environment]::NewLine + '        public void capture(final String json) {'
if(!$s.Contains($bridgeMarker)){throw 'PortalJsBridge capture marker missing'}
$method=@'
        @JavascriptInterface
        public void openGameUrl(final String target) {
            handler.post(() -> {
                if (target == null || target.isEmpty()) return;
                try {
                    String u = target;
                    if (isLegacyGameHttps(u)) u = legacyHttpUrl(u);
                    currentGamePage = u;
                    setState("same-tab game handoff " + abbreviate(u, 180));
                    WebView active = webView;
                    if (active != null) {
                        active.loadUrl(u);
                        active.bringToFront();
                    }
                } catch (Throwable t) {
                    setState("same-tab handoff ERROR " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
                }
            });
        }

'@
$s=$s.Replace($bridgeMarker,$method+$bridgeMarker)

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.5.9</versionNumber>','<versionNumber>0.6.0</versionNumber>')
$x=$x.Replace('<versionLabel>0.5.9 popup game window bridge</versionLabel>','<versionLabel>0.6.0 same tab game handoff</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.5.9</name>','<name>Naruto AIR Experimental 0.6.0</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.5.9 - popup game window + SWF capture...','Naruto AIR 0.6.0 - same-tab game handoff + multi-SWF capture...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.5.9";','public static const VERSION:String = "0.6.0";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.6.0 patch applied: window.open and target blank forced into active WebView.'

. .\scripts\patch-061.ps1
