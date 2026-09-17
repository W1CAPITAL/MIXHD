package br.davi.narutoair.portal {
    import flash.events.EventDispatcher;
    import flash.events.StatusEvent;
    import flash.external.ExtensionContext;

    /**
     * ActionScript side of the ANE. This class must live in the ANE library.swf.
     * AIR 51.3.x can reject createExtensionContext() with #2113 when it is called
     * directly from the application's main SWF instead of from the ANE wrapper.
     */
    public final class PortalBridge extends EventDispatcher {
        private var context:ExtensionContext;

        public function PortalBridge() {
            context = ExtensionContext.createExtensionContext("br.davi.narutoair.portal", null);
            if (!context) {
                throw new Error("ExtensionContext retornou null para br.davi.narutoair.portal");
            }
            context.addEventListener(StatusEvent.STATUS, onNativeStatus);
        }

        public function ping():Object {
            return context.call("ping");
        }

        public function status():Object {
            return context.call("status");
        }

        public function openPortal(url:String):Object {
            return context.call("open", url);
        }

        public function hide():Object {
            return context.call("hide");
        }

        public function show():Object {
            return context.call("show");
        }

        public function close():Object {
            return context.call("close");
        }

        public function dispose():void {
            if (!context) return;
            try { context.removeEventListener(StatusEvent.STATUS, onNativeStatus); } catch (e:Error) { }
            try { context.dispose(); } catch (e2:Error) { }
            context = null;
        }

        private function onNativeStatus(e:StatusEvent):void {
            dispatchEvent(new StatusEvent(StatusEvent.STATUS, false, false, e.code, e.level));
        }
    }
}
