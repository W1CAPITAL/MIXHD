$ErrorActionPreference='Stop'

$p='src\NarutoAir.as'
$s=Get-Content $p -Raw

if(!$s.Contains('import flash.events.UncaughtErrorEvent;')){
  $s=$s.Replace('import flash.events.TimerEvent;','import flash.events.TimerEvent;'+[Environment]::NewLine+'    import flash.events.UncaughtErrorEvent;'+[Environment]::NewLine+'    import flash.events.ErrorEvent;')
}

$field='private var lastProgress:int = -1;'
if(!$s.Contains($field)){throw 'lastProgress field missing'}
if(!$s.Contains('private var runtimeBase:String = "";')){
  $s=$s.Replace($field,$field+[Environment]::NewLine+'        private var runtimeBase:String = "";')
}

$listener='loader.contentLoaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);'
if(!$s.Contains($listener)){throw 'loader security listener marker missing'}
if(!$s.Contains('UncaughtErrorEvent.UNCAUGHT_ERROR')){
  $s=$s.Replace($listener,$listener+[Environment]::NewLine+'                loader.contentLoaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onGameUncaughtError);')
}

$oldReq=@'
                var stringParams:Object = stringifyParams(params);
                var requestUrl:String = appendMissingParams(url, stringParams);
                var req:URLRequest = new URLRequest(requestUrl);
'@
if(!$s.Contains($oldReq.Trim())){throw 'request URL block missing'}
$newReq=@'
                var stringParams:Object = stringifyParams(params);

                // The real Naruto entry.swf is only the bootstrap. It later requests
                // config/, syscmd/, flash/ and other files relative to its own CDN URL.
                // Keep the CDN SWF URL pristine so loaderInfo.url/base resolution remains
                // identical to the official Flash Player. FlashVars go through LoaderContext.
                var isNarutoCdn:Boolean = url.indexOf("cdnnaruto-pt.oasgames.com/") >= 0;
                var requestUrl:String = isNarutoCdn ? url : appendMissingParams(url, stringParams);

                var baseProbe:String = requestUrl;
                var qPos:int = baseProbe.indexOf("?");
                if (qPos >= 0) baseProbe = baseProbe.substring(0, qPos);
                var slashPos:int = baseProbe.lastIndexOf("/");
                runtimeBase = slashPos >= 0 ? baseProbe.substring(0, slashPos + 1) : "";
                log("Runtime base CDN: " + runtimeBase);
                log("FlashVars via LoaderContext: " + countKeys(stringParams));

                var req:URLRequest = new URLRequest(requestUrl);
'@
$s=$s.Replace($oldReq.Trim(),$newReq.Trim())

$oldCtx='var ctx:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain, null);'
if(!$s.Contains($oldCtx)){throw 'LoaderContext marker missing'}
$s=$s.Replace($oldCtx,'var ctx:LoaderContext = new LoaderContext(false, new ApplicationDomain(ApplicationDomain.currentDomain), null);')

$insertMarker='        private function onSecurityError(e:SecurityErrorEvent):void {'
if(!$s.Contains($insertMarker)){throw 'onSecurityError marker missing'}
if(!$s.Contains('private function onGameUncaughtError')){
$fn=@'
        private function onGameUncaughtError(e:UncaughtErrorEvent):void {
            var msg:String = "";
            try {
                if (e.error is ErrorEvent) {
                    msg = ErrorEvent(e.error).text;
                } else if (e.error is Error) {
                    var er:Error = Error(e.error);
                    msg = "#" + er.errorID + " " + er.message;
                    if (er.getStackTrace()) msg += " | " + er.getStackTrace();
                } else {
                    msg = String(e.error);
                }
            } catch (x:Error) {
                msg = String(e.error);
            }
            report("GAME UNCAUGHT: " + msg);
            if (runtimeBase) log("Base de recursos: " + runtimeBase);
            try { e.preventDefault(); } catch (ignore:Error) { }
        }

'@
$s=$s.Replace($insertMarker,$fn+$insertMarker)
}

# Version strings after prior patches.
$s=$s.Replace('Naruto AIR 0.8.1 - Cloudflare login fallback + final CDN entry.swf...','Naruto AIR 0.8.2 - CDN runtime asset chain + final entry.swf...')
$s=$s.Replace('Naruto AIR 0.8.0 - final CDN entry.swf handoff...','Naruto AIR 0.8.2 - CDN runtime asset chain + final entry.swf...')

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.8.1</versionNumber>','<versionNumber>0.8.2</versionNumber>')
$x=$x.Replace('<versionLabel>0.8.1 Cloudflare login fallback</versionLabel>','<versionLabel>0.8.2 CDN runtime asset chain</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.8.1</name>','<name>Naruto AIR Experimental 0.8.2</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.8.1";','public static const VERSION:String = "0.8.2";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.8.2 patch applied: preserve final CDN URL/base for config/syscmd/flash asset chain, child ApplicationDomain, uncaught runtime diagnostics.'
