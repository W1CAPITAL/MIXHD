$ErrorActionPreference='Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

$start=$s.IndexOf('    private static final String FLASH_ADAPTER_JS =')
if($start -lt 0){throw 'FLASH_ADAPTER_JS start missing'}
$end=$s.IndexOf('    @Override public Map<String, FREFunction> getFunctions()',$start)
if($end -lt 0){throw 'FLASH_ADAPTER_JS end marker missing'}

$newConst=@'
    private static final String FLASH_ADAPTER_JS =
            "(function(){try{" +
            "if(window.__naSafeFlashInstalled){try{window.__naSafeScan&&window.__naSafeScan();}catch(e){}return 'already';}" +
            "var p={name:'Shockwave Flash',description:'Shockwave Flash 32.0 r0',filename:'pepflashplayer.dll'};" +
            "var ps={0:p,length:1,item:function(i){return i===0?p:null;},namedItem:function(n){return String(n).toLowerCase().indexOf('shockwave flash')>=0?p:null;},refresh:function(){}};ps['Shockwave Flash']=p;" +
            "var m={type:'application/x-shockwave-flash',suffixes:'swf',description:'Shockwave Flash',enabledPlugin:p};" +
            "var ms={0:m,length:1,item:function(i){return i===0?m:null;},namedItem:function(n){return String(n)==='application/x-shockwave-flash'?m:null;}};ms['application/x-shockwave-flash']=m;" +
            "try{Object.defineProperty(navigator,'plugins',{configurable:true,get:function(){return ps;}});}catch(e){}" +
            "try{Object.defineProperty(navigator,'mimeTypes',{configurable:true,get:function(){return ms;}});}catch(e){}" +
            "if(!window.ActiveXObject){window.ActiveXObject=function(n){if(String(n).toLowerCase().indexOf('shockwaveflash')>=0)return{GetVariable:function(v){return String(v)==='$version'?'WIN 32,0,0,465':'';}};throw new Error('ActiveX unavailable');};}" +
            "window.__naSafeCaptured={};" +
            "window.__naSafeScan=function(){try{" +
            "var nodes=document.querySelectorAll('object,embed,param');" +
            "for(var i=0;i<nodes.length;i++){" +
            "var n=nodes[i];var raw=n.getAttribute('data')||n.getAttribute('src')||n.getAttribute('value')||'';" +
            "if(!raw||String(raw).toLowerCase().indexOf('.swf')<0)continue;" +
            "var abs;try{abs=(new URL(String(raw),document.baseURI||location.href)).href;}catch(x){continue;}" +
            "var low=abs.toLowerCase();if(low.indexOf('empty.swf')>=0||low.indexOf('blank.swf')>=0)continue;" +
            "if(window.__naSafeCaptured[abs])continue;window.__naSafeCaptured[abs]=true;" +
            "var owner=(n.tagName&&String(n.tagName).toLowerCase()==='param')?n.parentElement:n;" +
            "var fv={};var params={};" +
            "try{if(owner&&owner.querySelectorAll){var pp=owner.querySelectorAll('param');for(var j=0;j<pp.length;j++){var k=(pp[j].getAttribute('name')||'').toLowerCase();var v=pp[j].getAttribute('value')||'';params[k]=v;if(k==='flashvars'){var a=String(v).split('&');for(var z=0;z<a.length;z++){var q=a[z].indexOf('=');if(q>0){try{fv[decodeURIComponent(a[z].substring(0,q))]=decodeURIComponent(a[z].substring(q+1));}catch(dx){}}}}}}}catch(pe){}" +
            "try{var ev=owner&&owner.getAttribute?owner.getAttribute('flashvars'):'';if(ev){var ea=String(ev).split('&');for(var e=0;e<ea.length;e++){var eq=ea[e].indexOf('=');if(eq>0){try{fv[decodeURIComponent(ea[e].substring(0,eq))]=decodeURIComponent(ea[e].substring(eq+1));}catch(ex){}}}}}catch(ee){}" +
            "var payload={swf:abs,flashvars:fv,params:params,page:location.href,source:'safe-adapter'};" +
            "try{if(window.NarutoAirNative&&window.NarutoAirNative.log)window.NarutoAirNative.log('REAL SWF SAFE CAPTURE '+abs);}catch(le){}" +
            "try{if(window.NarutoAirNative&&window.NarutoAirNative.capture)window.NarutoAirNative.capture(JSON.stringify(payload));}catch(ce){}" +
            "}" +
            "}catch(scanErr){try{if(window.NarutoAirNative&&window.NarutoAirNative.log)window.NarutoAirNative.log('SAFE SCAN ERROR '+scanErr);}catch(ignore){}}};" +
            "window.__naSafeFlashInstalled=true;" +
            "window.__naSafeScan();" +
            "try{new MutationObserver(function(){window.__naSafeScan();}).observe(document.documentElement||document,{subtree:true,childList:true,attributes:true,attributeFilter:['src','data','value','flashvars']});}catch(me){}" +
            "window.setInterval(function(){try{window.__naSafeScan();}catch(e){}},500);" +
            "return 'installed';" +
            "}catch(e){return 'ERR:'+String(e);}})();";

'@

$s=$s.Substring(0,$start)+$newConst+$s.Substring($end)

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.7.7</versionNumber>','<versionNumber>0.7.8</versionNumber>')
$x=$x.Replace('<versionLabel>0.7.7 safe real SWF capture</versionLabel>','<versionLabel>0.7.8 clean flash adapter</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.7.7</name>','<name>Naruto AIR Experimental 0.7.8</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.7.7 - safe entry.swf capture + AIR runtime...','Naruto AIR 0.7.8 - clean Flash adapter + entry.swf AIR handoff...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.7.7";','public static const VERSION:String = "0.7.8";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.7.8 patch applied: entire FLASH_ADAPTER_JS replaced with clean minimal valid implementation.'
