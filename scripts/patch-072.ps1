$ErrorActionPreference='Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# Auto guest test mode: do not block startup with the native account dialog.
$old=@'
if (url != null && url.contains("gamebox3.narutowebgame.com") && url.contains("/template/login.php")) {
                    setState("waiting native account dialog");
                    promptAccountThenLoad(activity, url);
                } else {
                    webView.loadUrl(url);
                    setState("loadUrl-called " + url);
                }
'@
$new=@'
if (url != null && url.contains("gamebox3.narutowebgame.com") && url.contains("/template/login.php")) {
                    manualLoginEmail = "";
                    manualLoginPassword = "";
                    webView.loadUrl(url);
                    setState("guest quick-register flow started");
                } else {
                    webView.loadUrl(url);
                    setState("loadUrl-called " + url);
                }
'@
if(!$s.Contains($old.Trim())){throw '0.7.1 initial account dialog block missing'}
$s=$s.Replace($old.Trim(),$new.Trim())

# A missing callback is normal in the official launcher and must never execute null(...).
$guard='if (callback == null || callback.trim().isEmpty() || webView == null) return;'
if(!$s.Contains($guard)){throw 'executeLauncherCallback guard missing'}
$s=$s.Replace($guard,'if (callback == null || callback.trim().isEmpty() || "null".equalsIgnoreCase(callback.trim()) || "undefined".equalsIgnoreCase(callback.trim()) || webView == null) return;')

# Same WebView already owns the real login cookies. Remove the invented oas_user cookie.
$cookieBlock=@'
                    try {
                        CookieManager cm = CookieManager.getInstance();
                        if (!token.isEmpty()) {
                            cm.setCookie("https://gamebox3.narutowebgame.com", "oas_user=" + token + "; Path=/");
                            cm.setCookie("https://naruto.narutowebgame.com", "oas_user=" + token + "; Path=/");
                            if (android.os.Build.VERSION.SDK_INT >= 21) cm.flush();
                        }
                    } catch (Throwable ignored) { }

'@
if($s.Contains($cookieBlock)){
    $s=$s.Replace($cookieBlock,'                    trace("OFFICIAL cookies preserved from login WebView");'+[Environment]::NewLine)
}

# Make the official callback semantics visible without leaking token/password.
$cbLine='executeLauncherCallback(callback, answer.toString());'
if(!$s.Contains($cbLine)){throw 'login callback marker missing'}
$s=$s.Replace($cbLine,$cbLine+[Environment]::NewLine+'                    trace("OFFICIAL login callback returned JWT + encoded username");')

# Give the official callback a little time to finish, then open the exact webVersion=2.4.1 game page.
$delay='}, 650);'
if($s.Contains($delay)){$s=$s.Replace($delay,'}, 1100);')}

# Extend the deep inspector on game pages to expose script/object/embed URLs before black screen.
$observerNeedle="var fs=document.querySelectorAll('iframe[src]');for(var i=0;i<fs.length;i++)rep('IFRAME '+fs[i].src);"
if($s.Contains($observerNeedle)){
  $observerReplacement=$observerNeedle+"var ss=document.querySelectorAll('script[src]');for(var si=0;si<ss.length;si++)rep('SCRIPT '+ss[si].src);var oe=document.querySelectorAll('object,embed,param');for(var oi=0;oi<oe.length;oi++){var ou=oe[oi].getAttribute('data')||oe[oi].getAttribute('src')||oe[oi].getAttribute('value')||'';if(ou&&String(ou).toLowerCase().indexOf('.swf')>=0)rep('SWF DOM '+ou);}"
  $s=$s.Replace($observerNeedle,$observerReplacement)
}

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.7.1</versionNumber>','<versionNumber>0.7.2</versionNumber>')
$x=$x.Replace('<versionLabel>0.7.1 native account and game bridge</versionLabel>','<versionLabel>0.7.2 guest game bootstrap</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.7.1</name>','<name>Naruto AIR Experimental 0.7.2</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.7.1 - native account + official launcher + early game Flash bridge...','Naruto AIR 0.7.2 - guest quick-register + official game bootstrap...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.7.1";','public static const VERSION:String = "0.7.2";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.7.2 patch applied: automatic guest flow, official cookie semantics, early game bootstrap trace.'
