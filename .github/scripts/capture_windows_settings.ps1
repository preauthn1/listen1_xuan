$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class UI {
 [StructLayout(LayoutKind.Sequential)] public struct Rect {public int l,t,r,b;}
 [DllImport("user32")] public static extern bool GetClientRect(IntPtr w,out Rect r);
 [DllImport("user32")] public static extern bool PrintWindow(IntPtr w,IntPtr dc,uint mode);
 [DllImport("user32")] public static extern bool SetWindowPos(IntPtr w,IntPtr after,int x,int y,int width,int height,uint flags);
 [DllImport("user32")] public static extern IntPtr WindowFromPoint(System.Drawing.Point pt);
 [DllImport("user32")] public static extern IntPtr GetAncestor(IntPtr w,uint flag);
 [DllImport("user32")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32")] public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr extra);
}
'@ -ReferencedAssemblies System.Drawing
$p=Start-Process (Resolve-Path app/listen1_xuan.exe) -WorkingDirectory (Resolve-Path app) -PassThru -RedirectStandardOutput "$env:RUNNER_TEMP/app.out" -RedirectStandardError "$env:RUNNER_TEMP/app.err"
for($i=0;$i -lt 60;$i++){Start-Sleep 1;$p.Refresh();if($p.HasExited){throw "App exited: $($p.ExitCode)"};if($p.MainWindowHandle -ne [intptr]::Zero){break}}
$w=$p.MainWindowHandle;if($w -eq [intptr]::Zero){throw 'No app window'}
$root=[Windows.Automation.AutomationElement]::FromHandle($w)
function Named($text){$items=$root.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition);foreach($e in $items){if($e.Current.Name -like "*$text*" -or $e.Current.HelpText -eq $text){$b=$e.Current.BoundingRectangle;if(!$b.IsEmpty -and $b.Width -gt 0){return $e}}}}
function Activate($text){for($i=0;$i -lt 20;$i++){ $e=Named $text;if($e){break};Start-Sleep 1};if(!$e){throw "Control unavailable: $text"};$b=$e.Current.BoundingRectangle;$x=[int]($b.X+$b.Width/2);$y=[int]($b.Y+$b.Height/2);if([UI]::GetAncestor([UI]::WindowFromPoint([Drawing.Point]::new($x,$y)),2) -ne $w){throw 'Control obscured'};[UI]::SetCursorPos($x,$y)|Out-Null;[UI]::mouse_event(2,0,0,0,0);[UI]::mouse_event(4,0,0,0,0);Start-Sleep 2}
function Snap($name){$r=New-Object UI+Rect;[UI]::GetClientRect($w,[ref]$r)|Out-Null;$bmp=[Drawing.Bitmap]::new($r.r,$r.b);$g=[Drawing.Graphics]::FromImage($bmp);$dc=$g.GetHdc();try{if(![UI]::PrintWindow($w,$dc,3)){throw 'Window capture failed'}}finally{$g.ReleaseHdc($dc);$g.Dispose()};$bmp.Save("$PWD/visual_output/$name.png",[Drawing.Imaging.ImageFormat]::Png);$bmp.Dispose();Write-Host "$name $($r.r)x$($r.b)"}
New-Item -Type Directory visual_output|Out-Null
Activate '设置';Activate '第三方平台登录';Snap 'default-expanded';[UI]::SetWindowPos($w,0,0,0,1500,850,0x40)|Out-Null;Start-Sleep 3;Snap 'wide-expanded'
