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

log "install $APK"
adb install -r -g "$APK" 2>&1 | tee -a "$OUT/tour.log"
# -g 会预授予运行时权限，这会掩盖「是否弹权限框」。撤销存储/通知类权限，模拟真实首次安装。
for p in android.permission.READ_EXTERNAL_STORAGE android.permission.WRITE_EXTERNAL_STORAGE android.permission.POST_NOTIFICATIONS; do
  adb shell pm revoke "$PKG" "$p" >/dev/null 2>&1 || true
done
adb shell appops set "$PKG" MANAGE_EXTERNAL_STORAGE default >/dev/null 2>&1 || true
adb shell dumpsys package "$PKG" | grep -A40 "requested permissions:" | sed -n '1,40p' > "$OUT/requested_permissions.txt"
perms before-launch

adb shell am force-stop com.google.android.apps.nexuslauncher >/dev/null 2>&1 || true
sleep 10
dismiss_system_dialogs
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

# 竖屏首页：切到 QQ 标签，再弹出键盘，确认标签不会被重置
tap_text 'QQ' && sleep 4
snap 03-tab-qq
log "tap search field"
adb shell input tap 560 202; sleep 3
snap 04-search-keyboard
adb shell input keyevent KEYCODE_BACK; sleep 2
adb shell input keyevent KEYCODE_BACK; sleep 3
snap 05-after-keyboard
tap_text '我的' && sleep 3

# 设置页
tap_text '设置' && sleep 5
snap 06-settings
tap_text '第三方平台登录' && sleep 3
snap 07-settings-login
tap_text '导入 Cookie' && sleep 3
snap 07b-cookie-dialog
# 粘贴一条缺少 MUSIC_U 的示例，看是否给出明确提示（不使用真实凭据）
tap_text '' >/dev/null 2>&1; adb shell input tap 540 1300; sleep 1; adb shell input text 'demo=1'; sleep 2
snap 07b2-cookie-typed
tap_text '导入并验证' && sleep 3
snap 07c-cookie-missing
adb shell input keyevent KEYCODE_BACK; sleep 1
tap_text '取消' ; sleep 2
tap_text '第三方平台登录' && sleep 2
tap_text '缓存' && sleep 3
adb shell input swipe 540 1700 540 900 400; sleep 2
snap 08-settings-cache
tap_text '缓存' && sleep 2
adb shell input swipe 540 900 540 1900 300; sleep 2
tap_text '歌单/配置文件' && sleep 3
snap 09-settings-config
tap_text '歌单/配置文件' && sleep 2
adb shell input swipe 540 1900 540 400 300; sleep 2
adb shell input swipe 540 1900 540 400 300; sleep 2
snap 09b-settings-bottom
adb shell input keyevent KEYCODE_BACK; sleep 3

# 下载：网易云首页第一张歌单 → 第一首的「更多」→「下载」
tap_text '网易' && sleep 8
snap 14-netease-home
tap_first_below 400 && sleep 10
snap 15-playlist
tap_text '下载全部' >/dev/null 2>&1; sleep 3
snap 15b-download-all-confirm
tap_text '取消' ; sleep 2
# 先授予通知权限，便于检查下载进度/完成通知
adb shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
tap_text '更多' && sleep 3
snap 16-track-menu
tap_text '下载' && sleep 2
snap 17-after-download-tap
for i in 1 2 3 4 5 6 7 8; do
  sleep 4
  snap "17b-progress-$i"
  grep -q '已下载\|保存在' "$OUT/17b-progress-$i.xml" 2>/dev/null && break
done
sleep 10
snap 18-download-done
grep -o 'content-desc="已下载"' "$OUT/18-download-done.xml" | head -1 | sed 's/^/badge: /' | tee -a "$OUT/tour.log"
tap_text '更多' && sleep 3
snap 18a-menu-after-download
adb shell input keyevent KEYCODE_BACK; sleep 2
adb shell cmd statusbar expand-notifications; sleep 3
snap 18b-notification
adb shell cmd statusbar collapse; sleep 2
log "public downloads:"
adb shell ls -la /sdcard/Download/Listen1/Music 2>&1 | tee -a "$OUT/tour.log"
adb shell content query --uri content://media/external/downloads --projection _display_name:relative_path:mime_type:_size 2>&1 | tail -10 | tee -a "$OUT/tour.log"
adb shell dumpsys notification --noredact 2>/dev/null | grep -A3 "track_downloads" | head -20 | tee -a "$OUT/tour.log"
adb shell input keyevent KEYCODE_BACK; sleep 2
adb shell input keyevent KEYCODE_BACK; sleep 2
tap_text '我的' && sleep 2
tap_text '设置' && sleep 4
# 展开状态会被记住：点一次没出现入口就再点一次
# 「下载管理」是缓存分组的第一行，展开后不滚动直接点；没找到则说明分组被收起，再点一次。
for attempt in 1 2; do
  tap_text '缓存' && sleep 3
  snap "19a-cache-$attempt"
  tap_text '下载管理.*' && break
done
sleep 4
snap 19-downloads-page
# 第二次点同一首：菜单应显示「重新下载」
adb shell input keyevent KEYCODE_BACK; sleep 2
adb shell input keyevent KEYCODE_BACK; sleep 2
adb shell input keyevent KEYCODE_BACK; sleep 2

# 转屏再转回
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 1; sleep 6
# 首次进入沉浸模式时系统会提示「Viewing full screen」，先关掉
tap_text 'Got it' && sleep 2
snap 10-landscape
tap_text '歌曲替换列表' && sleep 4
snap 10b-landscape-song-replace
adb shell input keyevent KEYCODE_BACK; sleep 3
adb shell settings put system user_rotation 0; sleep 6
snap 11-portrait-again

# 深色模式
adb shell cmd uimode night yes; sleep 6
snap 12-dark-home
tap_text '设置' && sleep 4
snap 13-dark-settings
adb shell input keyevent KEYCODE_BACK; sleep 2

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
