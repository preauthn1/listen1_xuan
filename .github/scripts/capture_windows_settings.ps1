$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class UI {
 [StructLayout(LayoutKind.Sequential)] public struct Rect {public int l,t,r,b;}
 [StructLayout(LayoutKind.Sequential)] public struct Pt {public int x,y;}
 [DllImport("user32")] public static extern bool ClientToScreen(IntPtr w,ref Pt pt);
 [DllImport("user32")] public static extern bool GetClientRect(IntPtr w,out Rect r);
 [DllImport("user32")] public static extern bool PrintWindow(IntPtr w,IntPtr dc,uint mode);
 [DllImport("user32")] public static extern bool SetWindowPos(IntPtr w,IntPtr after,int x,int y,int width,int height,uint flags);
 [DllImport("user32")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32")] public static extern bool SetForegroundWindow(IntPtr w);
 [DllImport("user32")] public static extern void mouse_event(uint f,uint x,uint y,int d,UIntPtr extra);
 [DllImport("user32")] public static extern void keybd_event(byte vk,byte scan,uint f,UIntPtr extra);
}
'@ -ReferencedAssemblies System.Drawing
$p=Start-Process (Resolve-Path app/listen1_xuan.exe) -WorkingDirectory (Resolve-Path app) -PassThru
for($i=0;$i -lt 60;$i++){Start-Sleep 1;$p.Refresh();if($p.HasExited){throw "App exited: $($p.ExitCode)"};if($p.MainWindowHandle -ne [intptr]::Zero){break}}
$w=$p.MainWindowHandle;if($w -eq [intptr]::Zero){throw 'No app window'}
New-Item -Type Directory visual_output -Force|Out-Null
function MoveTo($x,$y){$pt=New-Object UI+Pt;$pt.x=$x;$pt.y=$y;[UI]::ClientToScreen($w,[ref]$pt)|Out-Null;[UI]::SetCursorPos($pt.x,$pt.y)|Out-Null}
function Click($x,$y,$wait=2){[UI]::SetForegroundWindow($w)|Out-Null;MoveTo $x $y;[UI]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[UI]::mouse_event(4,0,0,0,[UIntPtr]::Zero);Start-Sleep $wait}
function Wheel($x,$y,$n){MoveTo $x $y;$d=if($n -gt 0){-120}else{120};for($i=0;$i -lt [math]::Abs($n);$i++){[UI]::mouse_event(0x800,0,0,$d,[UIntPtr]::Zero);Start-Sleep -Milliseconds 100};Start-Sleep 1}
function Esc(){[UI]::keybd_event(0x1B,0,0,[UIntPtr]::Zero);[UI]::keybd_event(0x1B,0,2,[UIntPtr]::Zero);Start-Sleep 1}
function Snap($name){MoveTo 300 5;Start-Sleep -Milliseconds 500;$r=New-Object UI+Rect;[UI]::GetClientRect($w,[ref]$r)|Out-Null;$bmp=[Drawing.Bitmap]::new($r.r,$r.b);$g=[Drawing.Graphics]::FromImage($bmp);$dc=$g.GetHdc();try{[UI]::PrintWindow($w,$dc,3)|Out-Null}finally{$g.ReleaseHdc($dc);$g.Dispose()};$bmp.Save("$PWD/visual_output/$name.png",[Drawing.Imaging.ImageFormat]::Png);$bmp.Dispose();Write-Host "$name $($r.r)x$($r.b)"}
function Step($name,[scriptblock]$b){try{& $b}catch{Write-Host "STEP $name failed: $_"}}
Start-Sleep 14
function Home(){ for($k=0;$k -lt 4;$k++){ Esc }; Click 600 300 1 }
function Settings(){ Home; Click 138 599 3 }
Step home {Snap '01-home'}
Step created {Click 90 135 4; Snap '02-my-created'}
Step bili {Click 90 225 5; Snap '04-bili'}
Step queue {Click 743 661 2; Snap '06-queue'; Esc}
Step settings {Settings; Snap '10-settings'}
$rows=@(@('12-thirdparty',117),@('13-playlist-config',174),@('14-cache',231),@('15-desktop',289),@('16-update',353),@('17-appearance',418),@('18-playback',475),@('19-misc',532))
foreach($r in $rows){ Step $r[0] { Settings; Wheel 600 300 -60; Click 500 $r[1] 2; Snap ($r[0]+'-a'); Wheel 600 300 4; Snap ($r[0]+'-b'); Wheel 600 300 -60; Click 500 $r[1] 2 } }
Step bottom { Settings; Wheel 600 400 60; Snap '20-settings-bottom' }
Stop-Process $p -Force -ErrorAction SilentlyContinue
Start-Sleep 2
# 第二轮：系统切到深色，应用以「跟随系统」启动
$k='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
New-Item -Path $k -Force | Out-Null
Set-ItemProperty -Path $k -Name AppsUseLightTheme -Value 0 -Type DWord
Set-ItemProperty -Path $k -Name SystemUsesLightTheme -Value 0 -Type DWord
$p=Start-Process (Resolve-Path app/listen1_xuan.exe) -WorkingDirectory (Resolve-Path app) -PassThru
for($i=0;$i -lt 60;$i++){Start-Sleep 1;$p.Refresh();if($p.MainWindowHandle -ne [intptr]::Zero){break}}
$w=$p.MainWindowHandle
Start-Sleep 14
Step darkhome { Snap '32-dark-home' }
Step darkset { Settings; Snap '30-dark-settings'; Click 500 117 2; Snap '31-dark-thirdparty' }
Step darkqueue { Home; Click 704 661 2; Snap '33-dark-queue'; Esc }
Step wide { [UI]::SetWindowPos($w,[IntPtr]::Zero,0,0,1500,850,0x40)|Out-Null; Start-Sleep 3; Snap '40-wide-dark-home' }
Stop-Process $p -Force -ErrorAction SilentlyContinue
