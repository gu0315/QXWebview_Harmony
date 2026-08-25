#!/bin/bash
# 把鸿蒙 App 的 WebView DevTools 端口转发到本机 9222，供 Chrome chrome://inspect 调试。
#
# 用法：./devtools.sh [包名]
# 默认包名 com.cheryge.greenenergy。App 重启后 pid 会变，重跑一次即可。
#
# Chrome 侧：chrome://inspect/#devices → Configure... → 添加 localhost:9222

set -e

PKG="${1:-com.cheryge.greenenergy}"
PORT=9222
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"

if [ ! -x "$HDC" ]; then
  HDC="$(command -v hdc)" || { echo "找不到 hdc，请确认 DevEco Studio 已安装"; exit 1; }
fi

if [ -z "$("$HDC" list targets | grep -v '^\s*$' | grep -v 'Empty')" ]; then
  echo "没有已连接的鸿蒙设备"
  exit 1
fi

# 找出该包的 devtools socket（一台设备可能有多个 App 开着 WebView）
SOCK=""
while read -r line; do
  name="${line##*@}"
  [ -z "$name" ] && continue
  pid="${name##*_}"
  proc="$("$HDC" shell "ps -p $pid -o ARGS=" 2>/dev/null | tr -d ' \r\n')"
  if [ "$proc" = "$PKG" ]; then
    SOCK="$name"
    break
  fi
done < <("$HDC" shell "cat /proc/net/unix | grep devtools" 2>/dev/null)

if [ -z "$SOCK" ]; then
  echo "没找到 $PKG 的 devtools socket。"
  echo "确认：1) 装的是 debug 包（release 包不开调试） 2) App 已经打开过 H5 页面"
  exit 1
fi

# 清掉旧的同端口转发，避免指向已退出的 pid（fport rm 要传完整任务串）
"$HDC" fport ls 2>/dev/null | grep "tcp:$PORT" | sed -E 's/^[^ ]+[[:space:]]+(tcp:[0-9]+ localabstract:[^ ]+).*/\1/' \
  | while read -r task; do "$HDC" fport rm $task >/dev/null 2>&1 || true; done
"$HDC" fport "tcp:$PORT" "localabstract:$SOCK"

echo "已转发 $SOCK -> localhost:$PORT"
echo
echo "Chrome 打开 chrome://inspect/#devices"
echo "  首次需点 Configure... 添加 localhost:$PORT，并勾选 Discover network targets"
echo
echo "当前页面："
curl -s "http://localhost:$PORT/json/list" | grep '"url"' || echo "  （还没有页面，在设备上进入 H5 后刷新 chrome://inspect）"
