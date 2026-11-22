#!/usr/bin/env bash
# 在模拟器上安装 debug APK 并巡览界面；每一步都留截图、UI 树和权限状态。
# 单步失败只记录，不中断整轮巡览。
set -uo pipefail
APK="$1"
OUT="$2"
PKG=com.xiebian.listen1_xuan
mkdir -p "$OUT"
log() { echo "[tour] $*" | tee -a "$OUT/tour.log"; }

snap() {
  local name="$1"
  dismiss_system_dialogs
  adb exec-out screencap -p > "$OUT/$name.png" 2>/dev/null || log "screencap $name failed"
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 && adb pull /sdcard/ui.xml "$OUT/$name.xml" >/dev/null 2>&1
  log "snap $name"
}

# 在 UI 树里按 text/content-desc 找节点中心并点击（Flutter 语义树会导出到无障碍）。
tap_text() {
  local pattern="$1"
  dismiss_system_dialogs
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || return 1
  adb pull /sdcard/ui.xml "$OUT/_last.xml" >/dev/null 2>&1 || return 1
  local xy
  xy=$(python3 - "$OUT/_last.xml" "$pattern" <<'PY'
import re, sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
pat = re.compile(sys.argv[2])
for n in root.iter('node'):
    label = (n.get('content-desc') or n.get('text') or '').strip()
    if pat.fullmatch(label) or pat.fullmatch(label.split('\n')[0]):
        m = re.findall(r'\d+', n.get('bounds', ''))
        if len(m) == 4:
            x1, y1, x2, y2 = map(int, m)
            print((x1 + x2) // 2, (y1 + y2) // 2)
            break
PY
)
  if [[ -z "$xy" ]]; then log "tap_text '$pattern' not found"; return 1; fi
  log "tap '$pattern' at $xy"
  adb shell input tap $xy
}


# 模拟器偶发系统 ANR（如 Pixel Launcher 无响应），会盖住应用并吞掉点击。
dismiss_system_dialogs() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || return 0
  adb pull /sdcard/ui.xml "$OUT/_sys.xml" >/dev/null 2>&1 || return 0
  if grep -q "isn't responding\|has stopped\|keeps stopping" "$OUT/_sys.xml"; then
    log "system dialog detected; pressing Wait"
    local xy
    xy=$(python3 - "$OUT/_sys.xml" <<'PY2'
import re, sys, xml.etree.ElementTree as ET
for n in ET.parse(sys.argv[1]).getroot().iter('node'):
    if (n.get('text') or '') in ('Wait', 'Close app') and (n.get('text') == 'Wait'):
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', n.get('bounds')))
        print((x1 + x2) // 2, (y1 + y2) // 2); break
PY2
)
    [[ -n "$xy" ]] && adb shell input tap $xy
    sleep 2
  fi
  rm -f "$OUT/_sys.xml"
}


# 点击 y 坐标大于 $1 的第一个可点击节点（用于点开首页第一张歌单、歌单第一首歌的「更多」）。
tap_first_below() {
  local miny="$1" pattern="${2:-.+}"
  dismiss_system_dialogs
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || return 1
  adb pull /sdcard/ui.xml "$OUT/_last.xml" >/dev/null 2>&1 || return 1
  local xy
  xy=$(python3 - "$OUT/_last.xml" "$miny" "$pattern" <<'PY3'
import re, sys, xml.etree.ElementTree as ET
miny = int(sys.argv[2]); pat = re.compile(sys.argv[3])
skip = {'我的','B站','网易','QQ','酷狗','设置','全部','歌曲替换列表','正在播放列表','未播放'}
for n in ET.parse(sys.argv[1]).getroot().iter('node'):
    label = (n.get('content-desc') or n.get('text') or '').strip()
    if n.get('clickable') != 'true' or not label or label in skip: continue
    if not pat.fullmatch(label.split('\n')[0]): continue
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', n.get('bounds')))
    if y1 >= miny:
        print((x1 + x2) // 2, (y1 + y2) // 2); break
PY3
)
  if [[ -z "$xy" ]]; then log "tap_first_below $miny not found"; return 1; fi
  log "tap first below $miny at $xy"
  adb shell input tap $xy
}

perms() {
  log "permissions ($1):"
  adb shell dumpsys package "$PKG" | grep -E "permission\.(MANAGE_EXTERNAL_STORAGE|READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|READ_PHONE_STATE|POST_NOTIFICATIONS|READ_MEDIA)" | sort -u | tee -a "$OUT/tour.log"
  adb shell appops get "$PKG" MANAGE_EXTERNAL_STORAGE 2>/dev/null | tee -a "$OUT/tour.log"
}


adb wait-for-device
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb logcat -c
log "install $APK (API $(adb shell getprop ro.build.version.sdk | tr -d '\r'))"
adb install -r "$APK" 2>&1 | tee -a "$OUT/tour.log"
perms before-launch
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 30
snap 01-first-launch
tap_text '网易' && sleep 8
snap 02-netease
tap_first_below 400 && sleep 10
snap 03-playlist
tap_text '更多' && sleep 3
snap 04-track-menu
tap_text '下载' && sleep 3
snap 05-after-download-tap
# Android 9：下载时才申请存储权限，这里授予
tap_text 'ALLOW|Allow' && sleep 2
snap 06-after-permission
for i in 1 2 3 4 5 6 7 8 9 10; do
  sleep 4
  adb shell ls /sdcard/Download/Listen1/Music 2>/dev/null | grep -q '\.mp3\|\.flac\|\.m4a' && break
done
sleep 8
snap 07-download-done
perms after-download
log "public downloads:"
adb shell ls -la /sdcard/Download/Listen1/Music 2>&1 | tee -a "$OUT/tour.log"
log "media store:"
adb shell content query --uri content://media/external/audio/media --projection _display_name:_data:mime_type 2>&1 | tail -5 | tee -a "$OUT/tour.log"
adb logcat -d -v time > "$OUT/logcat.txt" 2>&1
grep -nE "FATAL EXCEPTION|E/flutter|Unhandled Exception|════════ Exception" "$OUT/logcat.txt" | head -80 > "$OUT/errors.txt" || true
log "error lines: $(wc -l < "$OUT/errors.txt")"
rm -f "$OUT/_last.xml"
exit 0
