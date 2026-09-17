package br.davi.narutoair.portal {
    import flash.events.EventDispatcher;
    import flash.events.StatusEvent;
    import flash.external.ExtensionContext;

    public final class PortalMarker extends EventDispatcher {
        public static const VERSION:String = "0.5.1";
        private var context:ExtensionContext;

        public function PortalMarker() {
            context = ExtensionContext.createExtensionContext("br.davi.narutoair.portal", null);
            if (!context) {
                throw new Error("ExtensionContext retornou null para br.davi.narutoair.portal");
            }
            context.addEventListener(StatusEvent.STATUS, onNativeStatus);
        }

        public function ping():Object { return context.call("ping"); }
        public function status():Object { return context.call("status"); }
        public function openPortal(url:String):Object { return context.call("open", url); }
        public function hide():Object { return context.call("hide"); }
        public function show():Object { return context.call("show"); }
        public function close():Object { return context.call("close"); }
        public function report(message:String):Object { return context.call("report", message); }

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
