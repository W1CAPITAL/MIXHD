package {
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.events.StatusEvent;
    import flash.events.TimerEvent;
    import flash.net.URLRequest;
    import flash.display.Loader;
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
        private var lastNativeStatus:String = "";

        public function NarutoAir() {
            addEventListener(Event.ADDED_TO_STAGE, init);
        }

        private function init(e:Event):void {
            removeEventListener(Event.ADDED_TO_STAGE, init);
            stage.scaleMode = StageScaleMode.NO_SCALE;
            stage.align = StageAlign.TOP_LEFT;
            graphics.beginFill(0x000000);
            graphics.drawRect(0, 0, stage.stageWidth, stage.stageHeight);
            graphics.endFill();
            createLog();
            log("Naruto AIR 0.4.5 - carregando wrapper da ANE...");

            try {
                var WrapperClass:Class = getDefinitionByName("br.davi.narutoair.portal.PortalMarker") as Class;
                if (!WrapperClass) {
                    log("ERRO: classe PortalMarker nao encontrada no library.swf.");
                    return;
                }
                bridge = new WrapperClass();
                log("ANE wrapper carregado pelo library.swf.");
            } catch (err:Error) {
                log("ERRO ANE wrapper #" + err.errorID + ": " + err.message);
                return;
            }

            bridge.addEventListener(StatusEvent.STATUS, onNativeStatus);

            try {
                var pingResult:Object = bridge.ping();
                log("PING ANE: " + String(pingResult));
            } catch (pingErr:Error) {
                log("ERRO ping #" + pingErr.errorID + ": " + pingErr.message);
            }

            try {
                var openResult:Object = bridge.openPortal("https://naruto.narutowebgame.com/pt/serverlist/");
                log("OPEN ANE: " + String(openResult));
            } catch (openErr:Error) {
                log("ERRO open #" + openErr.errorID + ": " + openErr.message);
            }

            pollTimer = new Timer(700);
            pollTimer.addEventListener(TimerEvent.TIMER, pollNativeStatus);
            pollTimer.start();
        }

        private function createLog():void {
            logField = new TextField();
            logField.defaultTextFormat = new TextFormat("_sans", 18, 0xFFFFFF);
            logField.multiline = true;
            logField.wordWrap = true;
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
                    if (!swf || swf.indexOf(".swf") < 0) {
                        log("Captura recebida sem SWF valido.");
                        return;
                    }
                    launched = true;
                    log("SWF capturado: " + swf);
                    bridge.hide();
                    launchSwf(swf, info.flashvars || {});
                } catch (err:Error) {
                    log("Falha ao interpretar dados do portal: " + err.message);
                }
            }
        }

        private function launchSwf(url:String, params:Object):void {
            loader = new Loader();
            loader.contentLoaderInfo.addEventListener(Event.COMPLETE, onLoaded);
            loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
            loader.contentLoaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onSecurityError);

            var ctx:LoaderContext = new LoaderContext(true);
            ctx.parameters = params;

            log("Iniciando jogo com FlashVars: " + countKeys(params));
            loader.load(new URLRequest(url), ctx);
        }

        private function onLoaded(e:Event):void {
            log("SWF principal carregado. Inicializando cena...");
            if (loader && !contains(loader)) {
                addChildAt(loader, 0);
                loader.width = stage.stageWidth;
                loader.height = stage.stageHeight;
            }
        }

        private function onLoadError(e:IOErrorEvent):void {
            launched = false;
            log("Erro de rede ao carregar SWF: " + e.text);
            try { if (bridge) bridge.show(); } catch (err:Error) { log("ERRO show: " + err.message); }
        }

        private function onSecurityError(e:SecurityErrorEvent):void {
            launched = false;
            log("Erro de seguranca do SWF: " + e.text);
            try { if (bridge) bridge.show(); } catch (err:Error) { log("ERRO show: " + err.message); }
        }

        private function countKeys(o:Object):int {
            var n:int = 0;
            for (var k:String in o) n++;
            return n;
        }
    }
}
