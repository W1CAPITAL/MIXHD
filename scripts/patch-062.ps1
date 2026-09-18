$ErrorActionPreference = 'Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# Android inspector imports.
$imp='import android.content.ClipData;'
if(!$s.Contains($imp)){
  $anchor='import android.app.Activity;'
  if(!$s.Contains($anchor)){throw 'Activity import missing'}
  $extra=@'
import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
'@
  $s=$s.Replace($anchor,$extra.TrimEnd())
}
if(!$s.Contains('import android.webkit.ConsoleMessage;')){
  $s=$s.Replace('import android.webkit.CookieManager;','import android.webkit.CookieManager;' + [Environment]::NewLine + 'import android.webkit.ConsoleMessage;')
}

# Trace fields.
$field='private WebChromeClient portalChromeClient;'
if(!$s.Contains($field)){throw 'portalChromeClient field missing'}
$fields=@'
private WebChromeClient portalChromeClient;
    private final StringBuilder traceBuffer = new StringBuilder();
    private int traceLines = 0;
'@
$s=$s.Replace($field,$fields.Trim())

# Trace helpers before setState.
$marker='    private void setState(String s) {'
if(!$s.Contains($marker)){throw 'setState marker missing'}
$helpers=@'
    private void trace(String message) {
        try {
            String m = message == null ? "" : message;
            synchronized (traceBuffer) {
                traceBuffer.append(System.currentTimeMillis()).append(" | ").append(m).append("\n");
                traceLines++;
                if (traceBuffer.length() > 450000) {
                    int cut = traceBuffer.length() - 300000;
                    traceBuffer.delete(0, cut);
                }
            }
        } catch (Throwable ignored) { }
    }

    private String traceText() {
        synchronized (traceBuffer) { return traceBuffer.toString(); }
    }

    private boolean shouldTraceUrl(String u) {
        String low = u == null ? "" : u.toLowerCase();
        return low.contains("narutowebgame.com") || low.contains("oasgames.com") ||
               low.contains(".swf") || low.contains("fcgi-bin") || low.contains("main.html");
    }

    private void injectInspector(final WebView view) {
        if (view == null) return;
        final String js = "(function(){try{if(document.getElementById('na-inspector-btn'))return;" +
                "var b=document.createElement('button');b.id='na-inspector-btn';b.textContent='LOG';" +
                "b.style='position:fixed;right:8px;bottom:8px;z-index:2147483647;background:#111;color:#fff;border:1px solid #fff;border-radius:8px;padding:8px 12px;font-size:14px';" +
                "b.onclick=function(){try{var old=document.getElementById('na-inspector-panel');if(old){old.remove();return;}var p=document.createElement('div');p.id='na-inspector-panel';p.style='position:fixed;inset:4%;z-index:2147483646;background:rgba(0,0,0,.96);padding:10px';" +
                "var x=document.createElement('button');x.textContent='FECHAR';x.style='float:right;padding:8px';x.onclick=function(){p.remove();};" +
                "var c=document.createElement('button');c.textContent='COPIAR';c.style='float:right;margin-right:8px;padding:8px';c.onclick=function(){try{NarutoAirNative.copyTrace();}catch(e){}};" +
                "var t=document.createElement('textarea');t.readOnly=true;t.style='width:100%;height:88%;margin-top:8px;background:#050505;color:#fff;font-size:10px';t.value=(NarutoAirNative&&NarutoAirNative.getTrace)?NarutoAirNative.getTrace():'sem trace';" +
                "p.appendChild(x);p.appendChild(c);p.appendChild(t);document.body.appendChild(p);}catch(e){}};" +
                "document.documentElement.appendChild(b);return 'ok';}catch(e){return String(e);}})();";
        try { view.evaluateJavascript(js, null); } catch (Throwable ignored) { }
    }

'@
$s=$s.Replace($marker,$helpers+$marker)

# Ensure setState is persisted in the trace buffer.
$oldSet=@'
    private void setState(String s) {
        state = s == null ? "" : s;
        send("log", state);
    }
'@
$newSet=@'
    private void setState(String s) {
        state = s == null ? "" : s;
        trace("STATE " + state);
        send("log", state);
    }
'@
if(!$s.Contains($oldSet.Trim())){throw 'setState body missing'}
$s=$s.Replace($oldSet.Trim(),$newSet.Trim())

# Add console tracing to the WebChromeClient.
$chromeMarker='portalChromeClient = new WebChromeClient() {' + [Environment]::NewLine + '                    @Override public boolean onCreateWindow'
if(!$s.Contains($chromeMarker)){throw 'portalChromeClient onCreateWindow marker missing'}
$console=@'
portalChromeClient = new WebChromeClient() {
                    @Override public boolean onConsoleMessage(ConsoleMessage cm) {
                        if (cm != null) trace("CONSOLE " + cm.messageLevel() + " " + cm.sourceId() + ":" + cm.lineNumber() + " " + cm.message());
                        return super.onConsoleMessage(cm);
                    }

                    @Override public boolean onCreateWindow
'@
$s=$s.Replace($chromeMarker,$console.TrimEnd())

# Inject inspector on page starts/finishes and trace load resources.
$pageStart='setState("page-started " + pageUrl);'
if(!$s.Contains($pageStart)){throw 'page-started marker missing'}
$s=$s.Replace($pageStart,$pageStart+[Environment]::NewLine+'                        injectInspector(view);')

$pageFinish='setState("page-finished " + pageUrl);'
if(!$s.Contains($pageFinish)){throw 'page-finished marker missing'}
$s=$s.Replace($pageFinish,$pageFinish+[Environment]::NewLine+'                        injectInspector(view);')

# Add request trace in both WebView clients.
$req='String u = request.getUrl().toString();' + [Environment]::NewLine + '                        String low = u.toLowerCase();'
if(!$s.Contains($req)){throw 'main request marker missing'}
$s=$s.Replace($req,'String u = request.getUrl().toString();' + [Environment]::NewLine +
'                        if (shouldTraceUrl(u)) trace("REQ " + request.getMethod() + " " + u);' + [Environment]::NewLine +
'                        String low = u.toLowerCase();')

$popupReq='String u = request.getUrl().toString();' + [Environment]::NewLine + '                String low = u.toLowerCase();'
if($s.Contains($popupReq)){
  $s=$s.Replace($popupReq,'String u = request.getUrl().toString();' + [Environment]::NewLine +
'                if (shouldTraceUrl(u)) trace("POPUP REQ " + request.getMethod() + " " + u);' + [Environment]::NewLine +
'                String low = u.toLowerCase();')
}

# Full same-tab handoff trace.
$handoff='setState("same-tab game handoff " + abbreviate(u, 180));'
if($s.Contains($handoff)){
  $s=$s.Replace($handoff,'trace("HANDOFF FULL " + u);' + [Environment]::NewLine + '                    '+$handoff)
}

# Expose trace to the page itself.
$bridgeMarker='        @JavascriptInterface' + [Environment]::NewLine + '        public void capture(final String json) {'
if(!$s.Contains($bridgeMarker)){throw 'bridge capture marker missing'}
$bridgeMethods=@'
        @JavascriptInterface
        public void log(final String message) {
            trace("JS " + (message == null ? "" : message));
        }

        @JavascriptInterface
        public String getTrace() {
            return traceText();
        }

        @JavascriptInterface
        public void copyTrace() {
            handler.post(() -> {
                try {
                    Activity a = getActivity();
                    if (a == null) return;
                    ClipboardManager cb = (ClipboardManager) a.getSystemService(Context.CLIPBOARD_SERVICE);
                    if (cb != null) cb.setPrimaryClip(ClipData.newPlainText("Naruto AIR trace", traceText()));
                    setState("TRACE COPIADO");
                } catch (Throwable t) {
                    setState("copyTrace ERROR " + String.valueOf(t.getMessage()));
                }
            });
        }

'@
$s=$s.Replace($bridgeMarker,$bridgeMethods+$bridgeMarker)

# Add a JS observer that reports iframe/form/link/window location candidates into native trace.
$tail='window.__narutoAirAdapterInstalled=true;window.__narutoAirPatch();'
if(!$s.Contains($tail)){throw 'adapter tail missing for inspector observer'}
$observer=@'
try{if(!window.__naDeepInspect){window.__naDeepInspect=true;var rep=function(m){try{if(window.NarutoAirNative&&window.NarutoAirNative.log)window.NarutoAirNative.log(String(m));}catch(e){}};var scan=function(){try{var fs=document.querySelectorAll('iframe[src]');for(var i=0;i<fs.length;i++)rep('IFRAME '+fs[i].src);var forms=document.querySelectorAll('form[action]');for(var j=0;j<forms.length;j++)rep('FORM '+forms[j].method+' '+forms[j].action+' target='+(forms[j].target||''));var as=document.querySelectorAll('a[href][target]');for(var k=0;k<as.length;k++)rep('LINK '+as[k].href+' target='+(as[k].target||''));rep('LOCATION '+location.href);}catch(e){}};scan();try{new MutationObserver(function(){scan();}).observe(document.documentElement||document,{subtree:true,childList:true,attributes:true,attributeFilter:['src','href','action','target']});}catch(e){}setInterval(scan,3000);}}catch(e){}
'@
$observer=$observer -replace '\r?\n',''
$s=$s.Replace($tail,$observer+$tail)

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.6.1</versionNumber>','<versionNumber>0.6.2</versionNumber>')
$x=$x.Replace('<versionLabel>0.6.1 early HTML flash bridge</versionLabel>','<versionLabel>0.6.2 full flow inspector</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.6.1</name>','<name>Naruto AIR Experimental 0.6.2</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.6.1 - early HTML Flash bridge + SWF bootstrap...','Naruto AIR 0.6.2 - full flow inspector + SWF bootstrap...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.6.1";','public static const VERSION:String = "0.6.2";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.6.2 patch applied: full-flow inspector, trace buffer, LOG overlay and copy button.'

. .\scripts\patch-070.ps1
