$ErrorActionPreference='Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# 0.7.7: replace the 0.7.6 malformed deep-inspector fragment with a minimal, syntax-safe capture.
$bad=@'
var oe=document.querySelectorAll('object,embed,param');for(var oi=0;oi<oe.length;oi++){var node=oe[oi];var ou=node.getAttribute('data')||node.getAttribute('src')||node.getAttribute('value')||'';if(ou&&String(ou).toLowerCase().indexOf('.swf')>=0){rep('SWF DOM '+ou);try{var abs=(new URL(String(ou),location.href)).href;var low=abs.toLowerCase();if(low.indexOf('/empty.swf')<0&&low.indexOf('/blank.swf')<0){window.__naCapturedSwfs=window.__naCapturedSwfs||{};if(!window.__naCapturedSwfs[abs]){window.__naCapturedSwfs[abs]=true;var fv={};var ps={};var owner=node.tagName&&String(node.tagName).toLowerCase()==='param'?node.parentElement:node;try{if(owner){var pp=owner.querySelectorAll?owner.querySelectorAll('param'):[];for(var pi=0;pi<pp.length;pi++){var pn=(pp[pi].getAttribute('name')||'').toLowerCase();var pv=pp[pi].getAttribute('value')||'';ps[pn]=pv;if(pn==='flashvars'){var parts=String(pv).split('&');for(var fi=0;fi<parts.length;fi++){var eq=parts[fi].indexOf('=');if(eq>=0){var fk=decodeURIComponent(parts[fi].slice(0,eq));var fval=decodeURIComponent(parts[fi].slice(eq+1));fv[fk]=fval;}}}}var ef=owner.getAttribute&&owner.getAttribute('flashvars');if(ef){var ep=String(ef).split('&');for(var ei=0;ei<ep.length;ei++){var ee=ep[ei].indexOf('=');if(ee>=0)fv[decodeURIComponent(ep[ei].slice(0,ee))]=decodeURIComponent(ep[ei].slice(ee+1));}}}}catch(pe){}var launch={swf:abs,flashvars:fv,params:ps,page:location.href,source:'dom-real-swf'};rep('REAL SWF DOM CAPTURE '+abs);if(window.NarutoAirNative&&window.NarutoAirNative.capture)window.NarutoAirNative.capture(JSON.stringify(launch));}}}catch(ce){rep('REAL SWF DOM CAPTURE ERROR '+ce);}}}}
'@
if(!$s.Contains($bad.Trim())){throw '0.7.6 malformed SWF scanner fragment missing'}

$good=@'
var oe=document.querySelectorAll('object,embed,param');for(var oi=0;oi<oe.length;oi++){var node=oe[oi];var ou=node.getAttribute('data')||node.getAttribute('src')||node.getAttribute('value')||'';if(ou&&String(ou).toLowerCase().indexOf('.swf')>=0){rep('SWF DOM '+ou);try{var abs=(new URL(String(ou),location.href)).href;var low=abs.toLowerCase();if(low.indexOf('empty.swf')<0&&low.indexOf('blank.swf')<0){window.__naCapturedSwfs=window.__naCapturedSwfs||{};if(!window.__naCapturedSwfs[abs]){window.__naCapturedSwfs[abs]=true;var fv={};var ps={};var owner=(node.tagName&&String(node.tagName).toLowerCase()==='param')?node.parentElement:node;if(owner&&owner.querySelectorAll){var pp=owner.querySelectorAll('param');for(var pi=0;pi<pp.length;pi++){var pn=(pp[pi].getAttribute('name')||'').toLowerCase();var pv=pp[pi].getAttribute('value')||'';ps[pn]=pv;if(pn==='flashvars'){var fp=String(pv).split('&');for(var fi=0;fi<fp.length;fi++){var eq=fp[fi].indexOf('=');if(eq>0){fv[decodeURIComponent(fp[fi].substring(0,eq))]=decodeURIComponent(fp[fi].substring(eq+1));}}}}}var ev=owner&&owner.getAttribute?owner.getAttribute('flashvars'):'';if(ev){var ep=String(ev).split('&');for(var ei=0;ei<ep.length;ei++){var ee=ep[ei].indexOf('=');if(ee>0){fv[decodeURIComponent(ep[ei].substring(0,ee))]=decodeURIComponent(ep[ei].substring(ee+1));}}}}var launch={swf:abs,flashvars:fv,params:ps,page:location.href,source:'dom-real-swf-safe'};rep('REAL SWF DOM CAPTURE '+abs);if(window.NarutoAirNative&&window.NarutoAirNative.capture){window.NarutoAirNative.capture(JSON.stringify(launch));}}}}catch(ce){rep('REAL SWF DOM CAPTURE ERROR '+ce);}}}
'@
$good=$good -replace '\r?\n',''
$s=$s.Replace($bad.Trim(),$good)

# Remove the extra forced scanner inserted into the generic environment probe.
$forced="try{for(var z=0;z<q.length;z++){var n=q[z];var u=n.getAttribute('data')||n.getAttribute('src')||n.getAttribute('value')||'';if(u&&String(u).toLowerCase().indexOf('.swf')>=0&&String(u).toLowerCase().indexOf('empty.swf')<0&&String(u).toLowerCase().indexOf('blank.swf')<0){var abs=(new URL(String(u),location.href)).href;if(window.NarutoAirNative&&window.NarutoAirNative.capture)window.NarutoAirNative.capture(JSON.stringify({swf:abs,flashvars:{},params:{},page:location.href,source:'forced-dom-scan'}));break;}}}catch(e){}"
if($s.Contains($forced)){$s=$s.Replace($forced,'')}

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.7.6</versionNumber>','<versionNumber>0.7.7</versionNumber>')
$x=$x.Replace('<versionLabel>0.7.6 direct real SWF handoff</versionLabel>','<versionLabel>0.7.7 safe real SWF capture</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.7.6</name>','<name>Naruto AIR Experimental 0.7.7</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.7.6 - direct entry.swf handoff + AIR runtime...','Naruto AIR 0.7.7 - safe entry.swf capture + AIR runtime...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.7.6";','public static const VERSION:String = "0.7.7";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.7.7 patch applied: malformed JS removed; minimal syntax-safe entry.swf DOM capture enabled.'
