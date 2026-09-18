$ErrorActionPreference='Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# 0.7.6: when the real SWF exists in DOM but WebView cannot execute it, capture it directly.
$needle="var oe=document.querySelectorAll('object,embed,param');for(var oi=0;oi<oe.length;oi++){var ou=oe[oi].getAttribute('data')||oe[oi].getAttribute('src')||oe[oi].getAttribute('value')||'';if(ou&&String(ou).toLowerCase().indexOf('.swf')>=0)rep('SWF DOM '+ou);}"
if(!$s.Contains($needle)){throw 'deep inspector SWF DOM scanner missing'}

$replacement=@'
var oe=document.querySelectorAll('object,embed,param');for(var oi=0;oi<oe.length;oi++){var node=oe[oi];var ou=node.getAttribute('data')||node.getAttribute('src')||node.getAttribute('value')||'';if(ou&&String(ou).toLowerCase().indexOf('.swf')>=0){rep('SWF DOM '+ou);try{var abs=(new URL(String(ou),location.href)).href;var low=abs.toLowerCase();if(low.indexOf('/empty.swf')<0&&low.indexOf('/blank.swf')<0){window.__naCapturedSwfs=window.__naCapturedSwfs||{};if(!window.__naCapturedSwfs[abs]){window.__naCapturedSwfs[abs]=true;var fv={};var ps={};var owner=node.tagName&&String(node.tagName).toLowerCase()==='param'?node.parentElement:node;try{if(owner){var pp=owner.querySelectorAll?owner.querySelectorAll('param'):[];for(var pi=0;pi<pp.length;pi++){var pn=(pp[pi].getAttribute('name')||'').toLowerCase();var pv=pp[pi].getAttribute('value')||'';ps[pn]=pv;if(pn==='flashvars'){var parts=String(pv).split('&');for(var fi=0;fi<parts.length;fi++){var eq=parts[fi].indexOf('=');if(eq>=0){var fk=decodeURIComponent(parts[fi].slice(0,eq));var fval=decodeURIComponent(parts[fi].slice(eq+1));fv[fk]=fval;}}}}var ef=owner.getAttribute&&owner.getAttribute('flashvars');if(ef){var ep=String(ef).split('&');for(var ei=0;ei<ep.length;ei++){var ee=ep[ei].indexOf('=');if(ee>=0)fv[decodeURIComponent(ep[ei].slice(0,ee))]=decodeURIComponent(ep[ei].slice(ee+1));}}}}catch(pe){}var launch={swf:abs,flashvars:fv,params:ps,page:location.href,source:'dom-real-swf'};rep('REAL SWF DOM CAPTURE '+abs);if(window.NarutoAirNative&&window.NarutoAirNative.capture)window.NarutoAirNative.capture(JSON.stringify(launch));}}}catch(ce){rep('REAL SWF DOM CAPTURE ERROR '+ce);}}}}
'@
$replacement=$replacement -replace '\r?\n',''
$s=$s.Replace($needle,$replacement)

# Also add a dedicated forced scanner to the S876/main.html loop.
$scanNeedle="return JSON.stringify({flash:!!(navigator.plugins&&navigator.plugins['Shockwave Flash']),plugins:navigator.plugins?navigator.plugins.length:-1,swfs:a,swfobject:typeof window.swfobject});"
if(!$s.Contains($scanNeedle)){throw 'S876 flash env scanner missing'}
$scanReplacement="try{for(var z=0;z<q.length;z++){var n=q[z];var u=n.getAttribute('data')||n.getAttribute('src')||n.getAttribute('value')||'';if(u&&String(u).toLowerCase().indexOf('.swf')>=0&&!/empty\\.swf|blank\\.swf/i.test(String(u))){var abs=(new URL(String(u),location.href)).href;if(window.NarutoAirNative&&window.NarutoAirNative.capture)window.NarutoAirNative.capture(JSON.stringify({swf:abs,flashvars:{},params:{},page:location.href,source:'forced-dom-scan'}));break;}}}catch(e){}return JSON.stringify({flash:!!(navigator.plugins&&navigator.plugins['Shockwave Flash']),plugins:navigator.plugins?navigator.plugins.length:-1,swfs:a,swfobject:typeof window.swfobject});"
$s=$s.Replace($scanNeedle,$scanReplacement)

# Native bridge: normalize the legacy SWF to HTTP before sending to AIR, preserving signed page as referer.
$captureNeedle='JSONObject payload = new JSONObject(json);' + [Environment]::NewLine + '                    sendLaunchPayload(payload, "document-start-js");'
if(!$s.Contains($captureNeedle)){throw 'PortalJsBridge capture payload marker missing'}
$captureReplacement=@'
JSONObject payload = new JSONObject(json);
                    String capturedSwf = payload.optString("swf", "");
                    if (capturedSwf.startsWith("https://naruto-pt.oasgames.com/")) {
                        String httpSwf = legacyHttpUrl(capturedSwf);
                        payload.put("swf", httpSwf);
                        trace("REAL SWF normalized legacy HTTPS -> HTTP " + abbreviate(httpSwf, 180));
                    }
                    trace("REAL SWF bridge capture source=" + payload.optString("source","js") + " swf=" + abbreviate(payload.optString("swf",""),180));
                    sendLaunchPayload(payload, "document-start-js");
'@
$s=$s.Replace($captureNeedle,$captureReplacement.Trim())

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.7.5</versionNumber>','<versionNumber>0.7.6</versionNumber>')
$x=$x.Replace('<versionLabel>0.7.5 exact official playUrl</versionLabel>','<versionLabel>0.7.6 direct real SWF handoff</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.7.5</name>','<name>Naruto AIR Experimental 0.7.6</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.7.5 - exact official launcher playUrl + AIR runtime...','Naruto AIR 0.7.6 - direct entry.swf handoff + AIR runtime...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.7.5";','public static const VERSION:String = "0.7.6";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.7.6 patch applied: real entry.swf DOM capture with params/FlashVars/page/cookies -> AIR.'
