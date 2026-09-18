$ErrorActionPreference='Stop'

# === Native Android bridge: mimic the original launcher/CEF + Flash 21 behavior ===
$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

if(!$s.Contains('import android.content.pm.ActivityInfo;')){
  $s=$s.Replace('import android.app.Activity;','import android.app.Activity;'+[Environment]::NewLine+'import android.content.pm.ActivityInfo;')
}
if(!$s.Contains('import android.view.WindowManager;')){
  $s=$s.Replace('import android.view.ViewGroup;','import android.view.ViewGroup;'+[Environment]::NewLine+'import android.view.WindowManager;')
}

# The official supplied launcher uses Pepper Flash WIN 21,0,0,213.
$s=$s.Replace("description:'Shockwave Flash 32.0 r0'","description:'Shockwave Flash 21.0 r0'")
$s=$s.Replace("return String(v)==='$version'?'WIN 32,0,0,465':'';","return String(v)==='$version'?'WIN 21,0,0,213':'';")
$s=$s.Replace("filename:'pepflashplayer.dll'","filename:'pepflashplayer32.dll'")

# Older variants may still exist in the pre-0.7.8 body; keep them consistent too.
$s=$s.Replace("Shockwave Flash 32.0 r0","Shockwave Flash 21.0 r0")
$s=$s.Replace("WIN 32,0,0,465","WIN 21,0,0,213")
$s=$s.Replace("major:32,minor:0,release:0","major:21,minor:0,release:0")
$s=$s.Replace("s.ua.pv=[32,0,0]","s.ua.pv=[21,0,0]")

# Fullscreen/landscape/keep-screen-on: Android replacement for the desktop window.
$uiMarker='                setState("ui-thread creating-webview");'
if(!$s.Contains($uiMarker)){throw 'UI marker missing'}
$uiAdd=@'
                try {
                    activity.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
                    activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                    View decor = activity.getWindow().getDecorView();
                    decor.setSystemUiVisibility(
                            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY |
                            View.SYSTEM_UI_FLAG_FULLSCREEN |
                            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION |
                            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN |
                            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION |
                            View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
                } catch (Throwable ignored) { }
'@
if(!$s.Contains('SCREEN_ORIENTATION_SENSOR_LANDSCAPE')){
  $s=$s.Replace($uiMarker,$uiMarker+[Environment]::NewLine+$uiAdd.TrimEnd())
}

# Browser settings closer to the old CEF launcher while still using Android WebView.
$cacheMarker='                s.setCacheMode(WebSettings.LOAD_DEFAULT);'
if(!$s.Contains($cacheMarker)){throw 'WebSettings cache marker missing'}
$settings=@'
                s.setDefaultTextEncodingName("UTF-8");
                s.setSupportZoom(false);
                if (android.os.Build.VERSION.SDK_INT >= 21) {
                    s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
                }
                webView.setOverScrollMode(View.OVER_SCROLL_NEVER);
                webView.setKeepScreenOn(true);
'@
if(!$s.Contains('s.setDefaultTextEncodingName("UTF-8")')){
  $s=$s.Replace($cacheMarker,$cacheMarker+[Environment]::NewLine+$settings.TrimEnd())
}

Set-Content $p $s -Encoding UTF8

# === AIR runtime: Android replacement for PepperFlash PPAPI ===
$a='src\NarutoAir.as'
$t=Get-Content $a -Raw

if(!$t.Contains('import flash.system.Security;')){
  $t=$t.Replace('import flash.system.LoaderContext;','import flash.system.LoaderContext;'+[Environment]::NewLine+'    import flash.system.Security;')
}
if(!$t.Contains('import flash.ui.Multitouch;')){
  $t=$t.Replace('import flash.utils.getDefinitionByName;','import flash.utils.getDefinitionByName;'+[Environment]::NewLine+'    import flash.ui.Multitouch;'+[Environment]::NewLine+'    import flash.ui.MultitouchInputMode;')
}

$stageMarker='            stage.frameRate = 30;'
if(!$t.Contains($stageMarker)){throw 'stage marker missing'}
$runtimeInit=@'
            try {
                Multitouch.inputMode = MultitouchInputMode.TOUCH_POINT;
            } catch (touchErr:Error) { }

            // Browser Flash/PPAPI replacement: let the remote Naruto bootstrap and
            // its child SWFs share the runtime and reach the original game domains.
            try {
                Security.allowDomain(
                    "naruto-pt.oasgames.com",
                    "cdnnaruto-pt.oasgames.com",
                    "naruto-pt-login.oasgames.com",
                    "naruto.narutowebgame.com",
                    "gamebox3.narutowebgame.com",
                    "odp3.oasgames.com"
                );
                Security.allowInsecureDomain(
                    "naruto-pt.oasgames.com",
                    "cdnnaruto-pt.oasgames.com",
                    "naruto-pt-login.oasgames.com",
                    "naruto.narutowebgame.com",
                    "gamebox3.narutowebgame.com"
                );
                Security.loadPolicyFile("https://cdnnaruto-pt.oasgames.com/crossdomain.xml");
                Security.loadPolicyFile("http://report.huoying.qq.com/crossdomain.xml");
            } catch (securityInitErr:Error) {
                log("Aviso security init: " + securityInitErr.message);
            }
'@
if(!$t.Contains('Security.allowDomain(')){
  $t=$t.Replace($stageMarker,$stageMarker+[Environment]::NewLine+$runtimeInit.TrimEnd())
}

# Exact Flash version header used by the original supplied launcher.
$t=$t.Replace('new URLRequestHeader("X-Flash-Version", "32,0,0,465")','new URLRequestHeader("X-Flash-Version", "21,0,0,213")')

# AIR blocks imported remote ActionScript by default unless allowCodeImport is enabled.
$ctx='var ctx:LoaderContext = new LoaderContext(false, new ApplicationDomain(ApplicationDomain.currentDomain), null);'
if(!$t.Contains($ctx)){throw '0.8.2 LoaderContext marker missing'}
if(!$t.Contains('ctx.allowCodeImport = true;')){
  $t=$t.Replace($ctx,$ctx+[Environment]::NewLine+'                ctx.allowCodeImport = true;')
}

# Log the compatibility mode so the next device trace proves the full port path.
$reportMarker='                report("Solicitando SWF real com sessao do portal...");'
if(!$t.Contains($reportMarker)){throw 'request report marker missing'}
if(!$t.Contains('FULL MOBILE PORT runtime')){
  $t=$t.Replace($reportMarker,'                report("FULL MOBILE PORT runtime: AIR AVM2/Stage3D substituindo PepperFlash 21.0.0.213");'+[Environment]::NewLine+$reportMarker)
}

$t=$t.Replace('Naruto AIR 0.8.2 - CDN runtime asset chain + final entry.swf...','Naruto AIR 1.0.0 - full Android port of OAS launcher + Flash runtime...')
Set-Content $a $t -Encoding UTF8

# === Descriptor ===
$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.8.2</versionNumber>','<versionNumber>1.0.0</versionNumber>')
$x=$x.Replace('<versionLabel>0.8.2 CDN runtime asset chain</versionLabel>','<versionLabel>1.0.0 full Android launcher port</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.8.2</name>','<name>Naruto Online Android Port 1.0</name>')
$x=$x.Replace('<description>Cliente experimental Android/AIR para o portal oficial do Naruto Online.</description>','<description>Port Android do launcher OAS: WebView para login/portal e AIR AVM2/Stage3D para o cliente Flash.</description>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.8.2";','public static const VERSION:String = "1.0.0";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '1.0.0 full Android launcher port patch applied: original Flash 21 fingerprint, AIR remote code import, domain policy, immersive landscape, touch and CDN runtime chain.'
