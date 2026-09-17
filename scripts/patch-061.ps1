$ErrorActionPreference = 'Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

$import='import java.io.InputStream;'
if(!$s.Contains($import)){throw 'InputStream import missing'}
$imports=@'
import java.io.InputStream;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.Charset;
'@
$s=$s.Replace($import,$imports.TrimEnd())

# Proxy both HTTP and HTTPS requests for the legacy host, so HTML can be modified before its first script runs.
$cond='if (isLegacyGameHttps(u)) {' + [Environment]::NewLine + '                            WebResourceResponse proxied = fetchLegacyHttpResource(u, request);'
if(!$s.Contains($cond)){throw 'main legacy intercept condition missing'}
$s=$s.Replace($cond,'if (isLegacyGameHost(u)) {' + [Environment]::NewLine + '                            WebResourceResponse proxied = fetchLegacyHttpResource(u, request);')

$cond2='if (isLegacyGameHttps(u)) {' + [Environment]::NewLine + '                    WebResourceResponse proxied = fetchLegacyHttpResource(u, request);'
if($s.Contains($cond2)){
  $s=$s.Replace($cond2,'if (isLegacyGameHost(u)) {' + [Environment]::NewLine + '                    WebResourceResponse proxied = fetchLegacyHttpResource(u, request);')
}

$methodNeedle='if (!isLegacyGameHttps(originalUrl)) return null;'
if(!$s.Contains($methodNeedle)){throw 'legacy fetch guard missing'}
$s=$s.Replace($methodNeedle,'if (!isLegacyGameHost(originalUrl)) return null;')

$currentNeedle='String current = legacyHttpUrl(originalUrl);'
if(!$s.Contains($currentNeedle)){throw 'legacy current URL marker missing'}
$s=$s.Replace($currentNeedle,'String current = isLegacyGameHttps(originalUrl) ? legacyHttpUrl(originalUrl) : originalUrl;')

$bodyNeedle=@'
                InputStream body = conn.getInputStream();
                WebResourceResponse response = new WebResourceResponse(mime, encoding, body);
'@
if(!$s.Contains($bodyNeedle.Trim())){throw 'response body marker missing'}
$bodyReplacement=@'
                InputStream body = conn.getInputStream();
                boolean htmlDocument = mime != null && mime.toLowerCase().contains("text/html");
                if (htmlDocument) {
                    try {
                        ByteArrayOutputStream bos = new ByteArrayOutputStream();
                        byte[] buf = new byte[16384];
                        int n;
                        while ((n = body.read(buf)) > 0) bos.write(buf, 0, n);
                        try { body.close(); } catch (Throwable ignored) { }
                        Charset cs;
                        try { cs = Charset.forName(encoding == null || encoding.isEmpty() ? "UTF-8" : encoding); }
                        catch (Throwable ignored) { cs = Charset.forName("UTF-8"); }
                        String html = new String(bos.toByteArray(), cs);
                        String injected = "<script>" + FLASH_ADAPTER_JS + "</script>";
                        String lowerHtml = html.toLowerCase();
                        int head = lowerHtml.indexOf("<head");
                        if (head >= 0) {
                            int end = html.indexOf('>', head);
                            html = end >= 0 ? html.substring(0, end + 1) + injected + html.substring(end + 1) : injected + html;
                        } else {
                            html = injected + html;
                        }
                        html = html.replace("https://naruto-pt.oasgames.com/", "http://naruto-pt.oasgames.com/");
                        body = new ByteArrayInputStream(html.getBytes(cs));
                        setState("EARLY HTML bridge injected before game scripts " + abbreviate(current, 150));
                    } catch (Throwable injectError) {
                        setState("EARLY HTML bridge ERROR " + injectError.getClass().getSimpleName() + ": " + String.valueOf(injectError.getMessage()));
                        body = conn.getInputStream();
                    }
                }
                WebResourceResponse response = new WebResourceResponse(mime, encoding, body);
'@
$s=$s.Replace($bodyNeedle.Trim(),$bodyReplacement.Trim())

$headersNeedle=@'
                    for (Map.Entry<String, java.util.List<String>> e : conn.getHeaderFields().entrySet()) {
                        if (e.getKey() != null && e.getValue() != null && !e.getValue().isEmpty()) {
                            responseHeaders.put(e.getKey(), e.getValue().get(0));
                        }
                    }
'@
if(!$s.Contains($headersNeedle.Trim())){throw 'response headers marker missing'}
$headersReplacement=@'
                    for (Map.Entry<String, java.util.List<String>> e : conn.getHeaderFields().entrySet()) {
                        if (e.getKey() != null && e.getValue() != null && !e.getValue().isEmpty()) {
                            String hk = e.getKey();
                            if (htmlDocument && ("content-length".equalsIgnoreCase(hk) || "content-encoding".equalsIgnoreCase(hk) || "content-security-policy".equalsIgnoreCase(hk))) continue;
                            responseHeaders.put(hk, e.getValue().get(0));
                        }
                    }
'@
$s=$s.Replace($headersNeedle.Trim(),$headersReplacement.Trim())

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.6.0</versionNumber>','<versionNumber>0.6.1</versionNumber>')
$x=$x.Replace('<versionLabel>0.6.0 same tab game handoff</versionLabel>','<versionLabel>0.6.1 early HTML flash bridge</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.6.0</name>','<name>Naruto AIR Experimental 0.6.1</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.6.0 - same-tab game handoff + multi-SWF capture...','Naruto AIR 0.6.1 - early HTML Flash bridge + SWF bootstrap...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.6.0";','public static const VERSION:String = "0.6.1";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.6.1 patch applied: legacy HTML is proxied and Flash bridge is injected before page scripts.'
