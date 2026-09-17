package br.davi.narutoair.portal;

import com.adobe.fre.FREContext;
import com.adobe.fre.FREExtension;

public class PortalExtension implements FREExtension {
    @Override public FREContext createContext(String extId) { return new PortalContext(); }
    @Override public void initialize() { }
    @Override public void dispose() { }
}
