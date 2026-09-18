$ErrorActionPreference='Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# 0.7.5: exact WINIE_LoginOK semantics from official AddAccountsBridge.
# Remove the fake callback response that causes the page to build /gamebox/3.4.7/template/game.php with a corrupted token.
$fake=@'
                    JSONObject answer = new JSONObject();
                    answer.put("code", b64Encode("1"));
                    answer.put("token", token);
                    answer.put("name", b64Encode(username));
                    executeLauncherCallback(callback, answer.toString());
                    trace("OFFICIAL login callback returned JWT + encoded username");

                    trace("OFFICIAL cookies preserved from login WebView");
                    setState("official launcher login accepted; waiting official game.php navigation");
                    trace("0.7.4 official JS owns game.php navigation; no synthetic URL");
'@
if(!$s.Contains($fake.Trim())){throw '0.7.4 fake WINIE_LoginOK callback block missing'}
$real=@'
                    // Official AddAccountsBridge.WINIE_LoginOK does NOT execute the page callback.
                    // It updates the oas_user cookie with LoginUser.token and opens GameConfig.playUrl(loginUser).
                    try {
                        CookieManager cm = CookieManager.getInstance();
                        cm.setCookie("https://gamebox3.narutowebgame.com", "oas_user=" + token + "; Path=/; SameSite=None; Secure");
                        cm.setCookie("https://naruto.narutowebgame.com", "oas_user=" + token + "; Path=/; SameSite=None; Secure");
                        cm.setCookie("https://oasgames.com", "oas_user=" + token + "; Path=/; SameSite=None; Secure");
                        if (android.os.Build.VERSION.SDK_INT >= 21) cm.flush();
                        trace("OFFICIAL oas_user cookie replaced from LoginUser.token");
                    } catch (Throwable cookieError) {
                        trace("OFFICIAL cookie ERROR " + cookieError);
                    }

                    String play = launcherPlayUrl(token, username);
                    currentGamePage = play;
                    setState("official launcher login accepted; opening exact 2.4.1 playUrl");
                    handler.postDelayed(() -> {
                        WebView active = webView;
                        if (active != null) {
                            try {
                                active.getSettings().setUserAgentString(buildDesktopGameUa(nativeUserAgent));
                                active.loadUrl(play);
                                trace("OFFICIAL playUrl " + abbreviate(play, 180));
                            } catch (Throwable t) {
                                setState("official playUrl ERROR " + String.valueOf(t.getMessage()));
                            }
                        }
                    }, 350);
'@
$s=$s.Replace($fake.Trim(),$real.Trim())

# The official launcher uses its existing CEF request context for scripts.
# Our 0.7.4 HttpURLConnection bootstrap fetch is what produced 403 and "File not found".
# Disable that proxy completely; keep the normal WebView request/session intact.
$call='WebResourceResponse boot = interceptOfficialFlashBootstrap(u, request);' + [Environment]::NewLine + '                        if (boot != null) return boot;'
if($s.Contains($call)){
  $s=$s.Replace($call,'// 0.7.5: do not proxy official JS; preserve browser request context/cookies.')
}
$call2='WebResourceResponse boot = interceptOfficialFlashBootstrap(u, request);' + [Environment]::NewLine + '                if (boot != null) return boot;'
if($s.Contains($call2)){
  $s=$s.Replace($call2,'// 0.7.5: do not proxy official JS; preserve browser request context/cookies.')
}

# Redirect any accidental /gamebox/3.4.7/template/game.php navigation to the exact official 2.4.1 URL.
$navNeedle='if (view == null || target == null || target.isEmpty()) return false;'
if(!$s.Contains($navNeedle)){throw 'handleNavigation marker missing'}
$navFix=@'
if (view == null || target == null || target.isEmpty()) return false;
        if (target.contains("gamebox3.narutowebgame.com/gamebox/3.4.7/template/game.php")) {
            if (launcherToken != null && !launcherToken.isEmpty() && launcherUsername != null && !launcherUsername.isEmpty()) {
                String fixed = launcherPlayUrl(launcherToken, launcherUsername);
                trace("FIX 3.4.7 game.php -> official 2.4.1 playUrl");
                currentGamePage = fixed;
                view.loadUrl(fixed);
                return true;
            }
        }
'@
$s=$s.Replace($navNeedle,$navFix.Trim())

# Explicitly mark 2.4.1 game page and S876 transitions.
$finish='setState("page-finished " + pageUrl);'
if(!$s.Contains($finish)){throw 'page-finished marker missing'}
$finish2=@'
setState("page-finished " + pageUrl);
                        if (pageUrl != null && pageUrl.contains("/gamebox/2.4.1/template/game.php")) {
                            trace("OFFICIAL 2.4.1 game.php loaded successfully");
                        }
                        if (pageUrl != null && pageUrl.contains("/serverlist/s876")) {
                            trace("OFFICIAL S876 page loaded successfully");
                        }
'@
$s=$s.Replace($finish,$finish2.Trim())

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.7.4</versionNumber>','<versionNumber>0.7.5</versionNumber>')
$x=$x.Replace('<versionLabel>0.7.4 official flash bootstrap</versionLabel>','<versionLabel>0.7.5 exact official playUrl</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.7.4</name>','<name>Naruto AIR Experimental 0.7.5</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.7.4 - official Flash bootstrap + AIR runtime...','Naruto AIR 0.7.5 - exact official launcher playUrl + AIR runtime...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.7.4";','public static const VERSION:String = "0.7.5";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.7.5 patch applied: exact official AddAccountsBridge cookie/playUrl flow, no fake login callback, no JS proxy 403.'
