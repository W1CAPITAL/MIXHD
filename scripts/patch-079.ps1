$ErrorActionPreference='Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# Capture the real bootstrap SWF directly from main.html bytes before WebView/JS gets involved.
$needle='String html = new String(bos.toByteArray(), cs);'
if(!$s.Contains($needle)){throw 'main.html decode marker missing'}
$s=$s.Replace($needle,$needle+[Environment]::NewLine+'                        captureNativeHtmlSwf(originalUrl, html);')

$marker='    private void detectCloudflareBlock(final WebView view) {'
if(!$s.Contains($marker)){throw 'helper insertion marker missing'}

$helper=@'
    private void captureNativeHtmlSwf(final String pageUrl, final String html) {
        if (launchSent || pageUrl == null || html == null) return;
        String lowPage = pageUrl.toLowerCase();
        if (!lowPage.contains("naruto-pt.oasgames.com/main.html")) return;
        try {
            String raw = "";
            java.util.regex.Matcher entry = java.util.regex.Pattern
                    .compile("(?i)([A-Za-z0-9_./-]*entry\\.swf[^\\s\"'<>]*)")
                    .matcher(html);
            if (entry.find()) raw = entry.group(1);

            if (raw == null || raw.isEmpty()) {
                java.util.regex.Matcher any = java.util.regex.Pattern
                        .compile("(?i)([A-Za-z0-9_./-]+\\.swf[^\\s\"'<>]*)")
                        .matcher(html);
                while (any.find()) {
                    String c = any.group(1);
                    String lc = c == null ? "" : c.toLowerCase();
                    if (!lc.contains("empty.swf") && !lc.contains("blank.swf")) {
                        raw = c;
                        break;
                    }
                }
            }

            if (raw == null || raw.isEmpty()) {
                trace("NATIVE HTML SWF: main.html parsed but no real SWF literal found");
                return;
            }

            raw = raw.replace("&amp;", "&").replace("\\/", "/");
            String base = legacyHttpUrl(pageUrl);
            String swf = new URL(new URL(base), raw).toString();
            if (isLegacyGameHttps(swf)) swf = legacyHttpUrl(swf);

            final JSONObject payload = new JSONObject();
            payload.put("swf", swf);
            payload.put("page", pageUrl);

            JSONObject fv = new JSONObject();

            // Preserve every signed main.html query parameter exactly enough for AIR loaderInfo.parameters.
            try {
                String query = new URL(pageUrl).getQuery();
                if (query != null && !query.isEmpty()) {
                    String[] pairs = query.split("&");
                    for (String pair : pairs) {
                        if (pair == null || pair.isEmpty()) continue;
                        int eq = pair.indexOf('=');
                        String k = eq >= 0 ? pair.substring(0, eq) : pair;
                        String v = eq >= 0 ? pair.substring(eq + 1) : "";
                        k = android.net.Uri.decode(k);
                        v = android.net.Uri.decode(v);
                        if (k != null && !k.isEmpty()) fv.put(k, v == null ? "" : v);
                    }
                }
            } catch (Throwable queryError) {
                trace("NATIVE HTML SWF query parse ERROR " + queryError.getClass().getSimpleName());
            }

            // Merge classic FlashVars if main.html contains them literally.
            try {
                java.util.regex.Matcher fm = java.util.regex.Pattern
                        .compile("(?is)flashvars\\s*[=:]\\s*[\"']([^\"']*)[\"']")
                        .matcher(html);
                if (fm.find()) {
                    String flashText = fm.group(1).replace("&amp;", "&");
                    for (String pair : flashText.split("&")) {
                        if (pair == null || pair.isEmpty()) continue;
                        int eq = pair.indexOf('=');
                        if (eq <= 0) continue;
                        String k = android.net.Uri.decode(pair.substring(0, eq));
                        String v = android.net.Uri.decode(pair.substring(eq + 1));
                        if (k != null && !k.isEmpty()) fv.put(k, v == null ? "" : v);
                    }
                }
            } catch (Throwable ignored) { }

            payload.put("flashvars", fv);
            payload.put("params", new JSONObject());
            trace("NATIVE HTML SWF FOUND " + abbreviate(swf, 190) + " flashvars=" + fv.length());

            handler.post(() -> {
                if (!launchSent) {
                    setState("NATIVE main.html -> AIR entry.swf handoff");
                    sendLaunchPayload(payload, "native-html");
                }
            });
        } catch (Throwable t) {
            trace("NATIVE HTML SWF ERROR " + t.getClass().getSimpleName() + ": " + String.valueOf(t.getMessage()));
        }
    }

'@

$s=$s.Replace($marker,$helper+$marker)

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.7.8</versionNumber>','<versionNumber>0.7.9</versionNumber>')
$x=$x.Replace('<versionLabel>0.7.8 clean flash adapter</versionLabel>','<versionLabel>0.7.9 native html swf handoff</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.7.8</name>','<name>Naruto AIR Experimental 0.7.9</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.7.8 - clean Flash adapter + entry.swf AIR handoff...','Naruto AIR 0.7.9 - native main.html entry.swf handoff...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.7.8";','public static const VERSION:String = "0.7.9";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.7.9 patch applied: native main.html parser captures entry.swf + signed query directly to AIR.'
