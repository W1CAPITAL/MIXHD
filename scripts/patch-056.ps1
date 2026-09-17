$ErrorActionPreference = 'Stop'
. .\scripts\patch-055.ps1
$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw
$old=@'
        if (!desktopGameUaActive && isLikelyGameUrl(target)) {
            activateDesktopGameUa(view, "game-navigation");
            injectBurst(view);
            view.loadUrl(target);
            return true;
        }
        if (desktopGameUaActive && isPortalOrLoginPage(target) && !isLikelyGameUrl(target)) {
            restoreNativeUa(view, "portal-navigation");
            view.loadUrl(target);
            return true;
        }
'@
$new=@'
        if (isLikelyGameUrl(target)) {
            currentGamePage = target;
            injectBurst(view);
            setState("game-navigation native-UA preserved");
            return false;
        }
'@
if(!$s.Contains($old.Trim())){throw 'navigation block not found'}
$s=$s.Replace($old.Trim(),$new.Trim())
$old2=@'
                    flashRepairAttempted = true;
                    activateDesktopGameUa(view, "server-side-flash-fallback");
                    setState("flash-warning detected; desktop-UA reload-once");
                    injectBurst(view);
                    handler.postDelayed(() -> {
                        if (view == webView && !launchSent) {
                            setState("flash-repair reload-once desktop-UA");
                            view.reload();
                        }
                    }, 180);
'@
$new2=@'
                    flashRepairAttempted = true;
                    setState("flash-warning detected; native-UA preserved; JS adapter reinforced");
                    injectBurst(view);
                    inspectSoon(view, 100);
                    inspectSoon(view, 500);
                    inspectSoon(view, 1500);
                    inspectSoon(view, 4000);
'@
if(!$s.Contains($old2.Trim())){throw 'repair block not found'}
$s=$s.Replace($old2.Trim(),$new2.Trim())
$s=$s.Replace('if (desktopGameUaActive || !isPortalOrLoginPage(pageUrl)) injectBurst(view);','if (!isPortalOrLoginPage(pageUrl) || isLikelyGameUrl(pageUrl)) injectBurst(view);')
$s=$s.Replace('if (desktopGameUaActive || !isPortalOrLoginPage(pageUrl)) {','if (!isPortalOrLoginPage(pageUrl) || isLikelyGameUrl(pageUrl)) {')
Set-Content $p $s -Encoding UTF8
$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.5.5</versionNumber>','<versionNumber>0.5.6</versionNumber>').Replace('<versionLabel>0.5.5 bridge proxy network handoff</versionLabel>','<versionLabel>0.5.6 native UA network hunter</versionLabel>').Replace('<name>Naruto AIR Experimental 0.5.5</name>','<name>Naruto AIR Experimental 0.5.6</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8
$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.5.5 - bridge proxy + network SWF handoff...','Naruto AIR 0.5.6 - native UA + network SWF hunter...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8
$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.5.5";','public static const VERSION:String = "0.5.6";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8
Write-Host '0.5.6 native-UA patch applied.'
