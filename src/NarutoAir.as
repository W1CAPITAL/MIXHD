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
            log("Naruto AIR 0.4.7 - sessao WebView -> AIR...");

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
                        log("Captura recebida sem SWF valido.");
                        return;
                    }
                    launched = true;
                    log("SWF capturado: " + swf);
                    log("Pagina origem: " + String(info.page || ""));
                    log("FlashVars: " + countKeys(info.flashvars || {}));
                    launchSwf(swf, info.flashvars || {}, String(info.cookie || ""), String(info.page || ""));
                } catch (err:Error) {
                    launched = false;
                    log("Falha ao interpretar dados do portal: " + err.message);
                }
            }
        }

        private function launchSwf(url:String, params:Object, cookie:String, referer:String):void {
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

                var headers:Array = [];
                if (cookie) headers.push(new URLRequestHeader("Cookie", cookie));
                if (referer) headers.push(new URLRequestHeader("Referer", referer));
                headers.push(new URLRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/99 Safari/537.36 NarutoAIR/0.4.7"));
                headers.push(new URLRequestHeader("X-Flash-Version", "32,0,0,465"));
                headers.push(new URLRequestHeader("Accept", "application/x-shockwave-flash,*/*;q=0.8"));
                req.requestHeaders = headers;

                var ctx:LoaderContext = new LoaderContext(false);
                ctx.parameters = stringParams;

                log("Solicitando SWF com sessao do portal...");
                log("Cookie disponivel: " + (cookie ? "SIM (" + cookie.length + " chars)" : "NAO"));
                swfStarted = false;
                loader.load(req, ctx);

                try { bridge.hide(); } catch (hideErr:Error) { log("ERRO hide: " + hideErr.message); }

                loadTimeout = new Timer(20000, 1);
                loadTimeout.addEventListener(TimerEvent.TIMER_COMPLETE, onLoadTimeout);
                loadTimeout.start();
            } catch (err:Error) {
                launched = false;
                log("ERRO sincronico ao iniciar SWF #" + err.errorID + ": " + err.message);
                try { if (bridge) bridge.show(); } catch (showErr:Error) { }
            }
        }

        private function onSwfOpen(e:Event):void {
            swfStarted = true;
            log("SWF OPEN: conexao aceita.");
        }

        private function onHttpStatus(e:HTTPStatusEvent):void {
            log("HTTP STATUS SWF: " + e.status + (e.redirected ? " (redirect)" : ""));
        }

        private function onProgress(e:ProgressEvent):void {
            if (e.bytesTotal > 0) {
                var pct:int = int((e.bytesLoaded * 100) / e.bytesTotal);
                if (pct == 1 || pct == 10 || pct == 25 || pct == 50 || pct == 75 || pct >= 99) {
                    log("SWF download: " + pct + "% (" + e.bytesLoaded + "/" + e.bytesTotal + ")");
                }
            }
        }

        private function onSwfInit(e:Event):void {
            log("SWF INIT: codigo principal iniciou.");
            if (loader && !contains(loader)) addChildAt(loader, 0);
        }

        private function onLoaded(e:Event):void {
            stopLoadTimeout();
            log("SWF COMPLETE: arquivo principal carregado.");
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
            log("TIMEOUT: SWF nao concluiu em 20s. OPEN recebido=" + (swfStarted ? "SIM" : "NAO"));
            launched = false;
        }

        private function onLoadError(e:IOErrorEvent):void {
            stopLoadTimeout();
            launched = false;
            log("IO ERROR SWF: " + e.text);
        }

        private function onSecurityError(e:SecurityErrorEvent):void {
            stopLoadTimeout();
            launched = false;
            log("SECURITY ERROR SWF: " + e.text);
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
