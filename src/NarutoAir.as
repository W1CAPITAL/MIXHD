package {
    import flash.display.Sprite;
    import flash.display.StageAlign;
    import flash.display.StageScaleMode;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.events.StatusEvent;
    import flash.external.ExtensionContext;
    import flash.net.URLRequest;
    import flash.display.Loader;
    import flash.system.LoaderContext;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.utils.Dictionary;

    public class NarutoAir extends Sprite {
        private var ext:ExtensionContext;
        private var loader:Loader;
        private var logField:TextField;
        private var launched:Boolean = false;

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
            log("Naruto AIR 0.4 - abrindo portal oficial...");

            ext = ExtensionContext.createExtensionContext("br.davi.narutoair.portal", null);
            if (!ext) {
                log("Falha ao iniciar ponte Android/WebView.");
                return;
            }
            ext.addEventListener(StatusEvent.STATUS, onNativeStatus);
            ext.call("open", "https://naruto.narutowebgame.com/pt/serverlist");
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

        private function onNativeStatus(e:StatusEvent):void {
            if (e.code == "log") {
                log(e.level);
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
                    ext.call("hide");
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
            ext.call("show");
        }

        private function onSecurityError(e:SecurityErrorEvent):void {
            launched = false;
            log("Erro de seguranca do SWF: " + e.text);
            ext.call("show");
        }

        private function countKeys(o:Object):int {
            var n:int = 0;
            for (var k:String in o) n++;
            return n;
        }
    }
}
