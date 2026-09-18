$ErrorActionPreference='Stop'

$p='ane-java\src\br\davi\narutoair\portal\PortalContext.java'
$s=Get-Content $p -Raw

# 0.8.0: the static main.html parser can only see a generic entry.swf token.
# Do not launch it. Wait until the live page resolves the real CDN URL:
# https://cdnnaruto-pt.oasgames.com/PT_NarutoAlpha.../entry.swf
$old=@'
            handler.post(() -> {
                if (!launchSent) {
                    setState("NATIVE main.html -> AIR entry.swf handoff");
                    sendLaunchPayload(payload, "native-html");
                }
            });
'@
if(!$s.Contains($old.Trim())){throw 'native-html immediate handoff block missing'}
$new=@'
            final String deferredSwf = swf;
            handler.post(() -> {
                if (!launchSent) {
                    trace("NATIVE HTML candidate deferred; waiting resolved CDN entry.swf " + abbreviate(deferredSwf, 180));
                }
            });
'@
$s=$s.Replace($old.Trim(),$new.Trim())

# Make native parser explicitly reject root-level /entry.swf as non-final.
$foundNeedle='trace("NATIVE HTML SWF FOUND " + abbreviate(swf, 190) + " flashvars=" + fv.length());'
if(!$s.Contains($foundNeedle)){throw 'native HTML SWF found marker missing'}
$s=$s.Replace($foundNeedle,@'
if (swf.matches("(?i)^https?://naruto-pt\\.oasgames\\.com/entry\\.swf(?:[?#].*)?$")) {
                trace("NATIVE HTML generic /entry.swf ignored; final CDN path not resolved yet");
            } else {
                trace("NATIVE HTML SWF CANDIDATE " + abbreviate(swf, 190) + " flashvars=" + fv.length());
            }
'@.Trim())

# Strong log for the real CDN handoff.
$captureNeedle='trace("REAL SWF bridge capture source=" + payload.optString("source","js") + " swf=" + abbreviate(payload.optString("swf",""),180));'
if(!$s.Contains($captureNeedle)){throw 'real SWF bridge marker missing'}
$s=$s.Replace($captureNeedle,@'
String finalSwf = payload.optString("swf","");
                    if (finalSwf.contains("cdnnaruto-pt.oasgames.com/") && finalSwf.toLowerCase().contains("/entry.swf")) {
                        setState("FINAL CDN entry.swf resolved; handing to AIR");
                    }
                    trace("REAL SWF bridge capture source=" + payload.optString("source","js") + " swf=" + abbreviate(finalSwf,180));
'@.Trim())

Set-Content $p $s -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>0.7.9</versionNumber>','<versionNumber>0.8.0</versionNumber>')
$x=$x.Replace('<versionLabel>0.7.9 native html swf handoff</versionLabel>','<versionLabel>0.8.0 final CDN SWF handoff</versionLabel>')
$x=$x.Replace('<name>Naruto AIR Experimental 0.7.9</name>','<name>Naruto AIR Experimental 0.8.0</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$a=Get-Content 'src\NarutoAir.as' -Raw
$a=$a.Replace('Naruto AIR 0.7.9 - native main.html entry.swf handoff...','Naruto AIR 0.8.0 - final CDN entry.swf handoff...')
Set-Content 'src\NarutoAir.as' $a -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "0.7.9";','public static const VERSION:String = "0.8.0";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '0.8.0 patch applied: generic root entry.swf is deferred; only resolved live CDN SWF can launch AIR.'
