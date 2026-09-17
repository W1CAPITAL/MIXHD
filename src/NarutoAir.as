package {
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.display.Loader;
    import flash.events.Event;
    import flash.events.HTTPStatusEvent;
    import flash.events.IOErrorEvent;
    import flash.events.ProgressEvent;
    import flash.events.SecurityErrorEvent;
    import flash.events.StatusEvent;
    import flash.events.TimerEvent;
    import flash.net.URLRequest;
    import flash.net.URLRequestHeader;
    import flash.system.ApplicationDomain;
    import flash.system.LoaderContext;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.utils.Timer;
    import flash.utils.getDefinitionByName;

    public class NarutoAir extends Sprite {
        private var bridge:*;
        private var loader:Loader;
        private var logField:TextField;
        private var launched:Boolean = false;
        private var pollTimer:Timer;
        private var loadTimeout:Timer;
        private var lastNativeStatus:String = "";
        private var swfStarted:Boolean = false;
        private var lastProgress:int = -1;

        public function NarutoAir() {
            addEventListener(Event.ADDED_TO_STAGE, init);
        }

        private function init(e:Event):void {
            removeEventListener(Event.ADDED_TO_STAGE, init);
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.align = StageAlign.TOP_LEFT;
            stage.frameRate = 30;
            graphics.beginFill(0x000000);
            graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
            graphics.endFill();
            createLog();
            log("Naruto AIR 0.5.1 - hybrid UA + AIR loader...");

            try {
                var WrapperClass:Class = getDefinitionByName("br.davi.narutoair.portal.PortalMarker") as Class;
                if (!WrapperClass) {
                    log("ERRO: PortalMarker nao encontrado.");
                    return;
                }
                bridge = new WrapperClass();
                log("ANE wrapper carregado.");
            } catch (err:Error) {
                log("ERRO ANE wrapper #" + err.errorID + ": " + err.message);
                return;
            }

            bridge.addEventListener(StatusEvent.STATUS, onNativeStatus);

            try { log("PING ANE: " + String(bridge.ping())); }
            catch (pingErr:Error) { log("ERRO ping #" + pingErr.errorID + ": " + pingErr.message); }

            try { log("OPEN ANE: " + String(bridge.openPortal("https://naruto.narutowebgame.com/pt/serverlist/"))); }
            catch (openErr:Error) { log("ERRO open #" + openErr.errorID + ": " + openErr.message); }

            pollTimer = new Timer(700);
            pollTimer.addEventListener(TimerEvent.TIMER, pollNativeStatus);
            pollTimer.start();
        }

        private function createLog():void {
            logField = new TextField();
            logField.defaultTextFormat = new TextFormat("_sans", 17, 0xFFFFFF);
            logField.multiline = true;
            logField.wordWrap = true;
            logField.selectable = true;
            logField.width = Math.max(600, stage.stageWidth - 40);
            logField.height = Math.max(240, stage.stageHeight - 40);
            logField.x = 20;
            logField.y = 20;
            addChild(logField);
        }

        private function log(s:String):void {
            if (!logField) return;
            logField.appendText(s + "\n");
            logField.scrollV = logField.maxScrollV;
        }

        private function report(s:String):void {
            log(s);
            try { if (bridge) bridge.report(s); } catch (e:Error) { }
        }

        private function pollNativeStatus(e:TimerEvent):void {
            if (!bridge) return;
            try {
                var value:Object = bridge.status();
                var s:String = value == null ? "null" : String(value);
                if (s != lastNativeStatus) {
                    lastNativeStatus = s;
                    log("STATUS ANE: " + s);
                }
            } catch (err:Error) {
                log("ERRO status #" + err.errorID + ": " + err.message);
                pollTimer.stop();
            }
        }

        private function onNativeStatus(e:StatusEvent):void {
            if (e.code == "log") {
                log("EVENTO: " + e.level);
                return;
            }
            if (e.code == "launch" && !launched) {
                try {
                    var info:Object = JSON.parse(e.level);
                    var swf:String = info.swf ? String(info.swf) : "";
                    if (!swf || swf.toLowerCase().indexOf(".swf") < 0) {
                        report("Captura recebida sem SWF valido.");
                        return;
                    }
                    launched = true;
                    report("SWF capturado; iniciando pelo AIR...");
                    log("SWF: " + swf);
                    log("Pagina origem: " + String(info.page || ""));
                    log("FlashVars: " + countKeys(info.flashvars || {}));
                    launchSwf(
                        swf,
                        info.flashvars || {},
                        String(info.cookie || ""),
                        String(info.page || ""),
                        String(info.userAgent || "")
                    );
                } catch (err:Error) {
                    launched = false;
                    report("Falha ao interpretar dados do portal: " + err.message);
                }
            }
        }

        private function launchSwf(url:String, params:Object, cookie:String, referer:String, userAgent:String):void {
            try {
                loader = new Loader();
                loader.contentLoaderInfo.addEventListener(Event.OPEN, onSwfOpen);
                loader.contentLoaderInfo.addEventListener(Event.INIT, onSwfInit);
                loader.contentLoaderInfo.addEventListener(Event.COMPLETE, onLoaded);
                loader.contentLoaderInfo.addEventListener(ProgressEvent.PROGRESS, onProgress);
                loader.contentLoaderInfo.addEventListener(HTTPStatusEvent.HTTP_STATUS, onHttpStatus);
                loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
                loader.contentLoaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);

                var stringParams:Object = stringifyParams(params);
                var requestUrl:String = appendMissingParams(url, stringParams);
                var req:URLRequest = new URLRequest(requestUrl);
                req.followRedirects = true;
                req.manageCookies = false;
                req.idleTimeout = 30000;
                if (userAgent && userAgent.length > 0) req.userAgent = userAgent;

                var headers:Array = [];
                if (cookie) headers.push(new URLRequestHeader("Cookie", cookie));
                if (referer) headers.push(new URLRequestHeader("Referer", referer));
                headers.push(new URLRequestHeader("X-Flash-Version", "32,0,0,465"));
                headers.push(new URLRequestHeader("Accept", "application/x-shockwave-flash,*/*;q=0.8"));
                req.requestHeaders = headers;

                var ctx:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain, null);
                ctx.parameters = stringParams;

                report("Solicitando SWF com sessao do portal...");
                log("Cookie nativo: " + (cookie ? "SIM (" + cookie.length + " chars)" : "NAO"));
                log("User-Agent recebido do WebView: " + (userAgent ? "SIM" : "NAO"));
                swfStarted = false;
                lastProgress = -1;
                loader.load(req, ctx);

                loadTimeout = new Timer(25000, 1);
                loadTimeout.addEventListener(TimerEvent.TIMER_COMPLETE, onLoadTimeout);
                loadTimeout.start();
            } catch (err:Error) {
                launched = false;
                report("ERRO sincronico SWF #" + err.errorID + ": " + err.message);
                showPortal();
            }
        }

        private function onSwfOpen(e:Event):void {
            swfStarted = true;
            report("SWF OPEN: conexao aceita.");
        }

        private function onHttpStatus(e:HTTPStatusEvent):void {
            report("HTTP STATUS SWF: " + e.status + (e.redirected ? " redirect" : ""));
        }

        private function onProgress(e:ProgressEvent):void {
            if (e.bytesTotal <= 0) return;
            var pct:int = int((e.bytesLoaded * 100) / e.bytesTotal);
            var bucket:int = int(pct / 10) * 10;
            if (bucket != lastProgress && (bucket == 10 || bucket == 20 || bucket == 30 || bucket == 40 || bucket == 50 || bucket == 60 || bucket == 70 || bucket == 80 || bucket >= 90)) {
                lastProgress = bucket;
                report("SWF download: " + pct + "%");
            }
        }

        private function onSwfInit(e:Event):void {
            report("SWF INIT: codigo principal iniciou.");
            hidePortal();
            if (loader && !contains(loader)) addChildAt(loader, 0);
        }

        private function onLoaded(e:Event):void {
            stopLoadTimeout();
            report("SWF COMPLETE: jogo principal carregado.");
            hidePortal();
            if (loader && !contains(loader)) addChildAt(loader, 0);
            if (loader) {
                try {
                    loader.x = 0;
                    loader.y = 0;
                    loader.width = stage.stageWidth;
                    loader.height = stage.stageHeight;
                } catch (sizeErr:Error) {
                    log("Aviso ao ajustar tamanho: " + sizeErr.message);
                }
            }
        }

        private function onLoadTimeout(e:TimerEvent):void {
            report("TIMEOUT 25s: OPEN=" + (swfStarted ? "SIM" : "NAO"));
            launched = false;
            try { if (loader) loader.close(); } catch (closeErr:Error) { }
            showPortal();
        }

        private function onLoadError(e:IOErrorEvent):void {
            stopLoadTimeout();
            launched = false;
            report("IO ERROR SWF: " + e.text);
            showPortal();
        }

        private function onSecurityError(e:SecurityErrorEvent):void {
            stopLoadTimeout();
            launched = false;
            report("SECURITY ERROR SWF: " + e.text);
            showPortal();
        }

        private function hidePortal():void {
            try { if (bridge) bridge.hide(); }
            catch (err:Error) { log("ERRO hide: " + err.message); }
        }

        private function showPortal():void {
            try { if (bridge) bridge.show(); }
            catch (err:Error) { log("ERRO show: " + err.message); }
        }

        private function stopLoadTimeout():void {
            if (loadTimeout) {
                loadTimeout.stop();
                loadTimeout = null;
            }
        }

        private function stringifyParams(o:Object):Object {
            var out:Object = {};
            if (!o) return out;
            for (var k:String in o) {
                try { out[k] = o[k] == null ? "" : String(o[k]); }
                catch (e:Error) { out[k] = ""; }
            }
            return out;
        }

        private function appendMissingParams(url:String, p:Object):String {
            var result:String = url;
            var sep:String = result.indexOf("?") >= 0 ? "&" : "?";
            for (var k:String in p) {
                var token:String = encodeURIComponent(k) + "=";
                if (result.indexOf(token) >= 0) continue;
                result += sep + encodeURIComponent(k) + "=" + encodeURIComponent(String(p[k]));
                sep = "&";
            }
            return result;
        }

        private function countKeys(o:Object):int {
            var n:int = 0;
            for (var k:String in o) n++;
            return n;
        }
    }
}
