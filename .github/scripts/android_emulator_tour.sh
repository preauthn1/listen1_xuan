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
  adb exec-out screencap -p > "$OUT/$name.png" 2>/dev/null || log "screencap $name failed"
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 && adb pull /sdcard/ui.xml "$OUT/$name.xml" >/dev/null 2>&1
  log "snap $name"
}

# 在 UI 树里按 text/content-desc 找节点中心并点击（Flutter 语义树会导出到无障碍）。
tap_text() {
  local pattern="$1"
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || return 1
  adb pull /sdcard/ui.xml "$OUT/_last.xml" >/dev/null 2>&1 || return 1
  local xy
  xy=$(python3 - "$OUT/_last.xml" "$pattern" <<'PY'
import re, sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
pat = re.compile(sys.argv[2])
for n in root.iter('node'):
    label = (n.get('text') or '') + ' ' + (n.get('content-desc') or '')
    if pat.search(label):
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

log "install $APK"
adb install -r -g "$APK" 2>&1 | tee -a "$OUT/tour.log"
# -g 会预授予运行时权限，这会掩盖「是否弹权限框」。撤销存储/通知类权限，模拟真实首次安装。
for p in android.permission.READ_EXTERNAL_STORAGE android.permission.WRITE_EXTERNAL_STORAGE android.permission.POST_NOTIFICATIONS; do
  adb shell pm revoke "$PKG" "$p" >/dev/null 2>&1 || true
done
adb shell appops set "$PKG" MANAGE_EXTERNAL_STORAGE default >/dev/null 2>&1 || true
adb shell dumpsys package "$PKG" | grep -A40 "requested permissions:" | sed -n '1,40p' > "$OUT/requested_permissions.txt"
perms before-launch

log "launch"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 25
snap 01-first-launch
# 如果系统弹出了权限页/对话框，记录当前前台 Activity
adb shell dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity" | head -3 | tee -a "$OUT/tour.log"
# 关闭通知权限框（若出现），不授予
tap_text '不允许|Don.t allow' && sleep 2
sleep 8
snap 02-home

# 竖屏首页：切到第三个平台标签，再弹出键盘，确认标签不会被重置
tap_text '^QQ$|QQ 音乐' && sleep 4
snap 03-tab-qq
tap_text '搜索' && sleep 3
snap 04-search-keyboard
adb shell input keyevent KEYCODE_BACK; sleep 2
adb shell input keyevent KEYCODE_BACK; sleep 3
snap 05-after-keyboard

# 设置页
tap_text '设置' && sleep 5
snap 06-settings
tap_text '缓存' && sleep 3
snap 07-settings-cache
adb shell input swipe 540 1700 540 700 400; sleep 2
snap 08-settings-cache-scrolled
tap_text '缓存' ; sleep 2
tap_text '歌单/配置文件|配置文件' && sleep 3
snap 09-settings-config
adb shell input keyevent KEYCODE_BACK; sleep 3

# 转屏再转回
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 1; sleep 6
snap 10-landscape
adb shell settings put system user_rotation 0; sleep 6
snap 11-portrait-again

# 深色模式
adb shell cmd uimode night yes; sleep 6
snap 12-dark-home

perms after-tour
log "app files:"
adb shell run-as "$PKG" ls -la files 2>&1 | head -20 | tee -a "$OUT/tour.log"
adb shell ls -la "/sdcard/Android/data/$PKG/files" 2>&1 | head -20 | tee -a "$OUT/tour.log"
adb shell ls -la /sdcard/Download 2>&1 | head -20 | tee -a "$OUT/tour.log"

adb logcat -d -v time > "$OUT/logcat.txt" 2>&1
grep -nE "FATAL EXCEPTION|E/flutter|Unhandled Exception|════════ Exception" "$OUT/logcat.txt" | head -80 > "$OUT/errors.txt" || true
log "error lines: $(wc -l < "$OUT/errors.txt")"
rm -f "$OUT/_last.xml"
exit 0
