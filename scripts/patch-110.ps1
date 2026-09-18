$ErrorActionPreference='Stop'

# Final combined Android port: 1.0 full launcher emulation + 0.9 runtime asset proxy.
$a='src\NarutoAir.as'
$t=Get-Content $a -Raw
$t=$t.Replace('Naruto AIR 1.0.0 - full Android port of OAS launcher + Flash runtime...','Naruto AIR 1.1.0 - full Android launcher + AIR Flash + runtime asset proxy...')
$t=$t.Replace('Naruto AIR 0.9.0 - full mobile runtime proxy + asset chain...','Naruto AIR 1.1.0 - full Android launcher + AIR Flash + runtime asset proxy...')
if(!$t.Contains('FULL MOBILE PORT runtime')){
  $marker='                report("Solicitando SWF real com sessao do portal...");'
  if($t.Contains($marker)){
    $t=$t.Replace($marker,'                report("FULL MOBILE PORT runtime: OAS launcher convertido para Android + proxy config/syscmd/flash");'+[Environment]::NewLine+$marker)
  }
}
Set-Content $a $t -Encoding UTF8

$x=Get-Content 'NarutoAir-app.xml' -Raw
$x=$x.Replace('<versionNumber>1.0.0</versionNumber>','<versionNumber>1.1.0</versionNumber>')
$x=$x.Replace('<versionNumber>0.9.0</versionNumber>','<versionNumber>1.1.0</versionNumber>')
$x=$x.Replace('<versionLabel>1.0.0 full Android launcher port</versionLabel>','<versionLabel>1.1.0 full Android launcher and asset runtime</versionLabel>')
$x=$x.Replace('<versionLabel>0.9.0 full mobile launcher runtime</versionLabel>','<versionLabel>1.1.0 full Android launcher and asset runtime</versionLabel>')
$x=$x.Replace('<name>Naruto Online Android Port 1.0</name>','<name>Naruto Online Android Port 1.1</name>')
$x=$x.Replace('<name>Naruto Online Mobile 0.9.0</name>','<name>Naruto Online Android Port 1.1</name>')
Set-Content 'NarutoAir-app.xml' $x -Encoding UTF8

$m=Get-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' -Raw
$m=$m.Replace('public static const VERSION:String = "1.0.0";','public static const VERSION:String = "1.1.0";')
$m=$m.Replace('public static const VERSION:String = "0.9.0";','public static const VERSION:String = "1.1.0";')
Set-Content 'ane-as\src\br\davi\narutoair\portal\PortalMarker.as' $m -Encoding UTF8

Write-Host '1.1.0 combined full Android port applied.'
