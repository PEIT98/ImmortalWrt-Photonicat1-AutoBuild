#!/bin/sh
# 仅调整编译树中的 QuickStart：屏蔽旧切源入口和 POST，保留首页状态与网口功能。
set -eu

package=${1:?需要 luci-app-quickstart 构建目录}
bundle="$package/htdocs/luci-static/quickstart/index.js"
proxy="$package/luasrc/controller/istore_backend.lua"
init="${package%/luci-app-quickstart}/quickstart/files/quickstart.init"
test -f "$bundle" && test -f "$proxy" && test -f "$init"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 上游为压缩过的单文件 JS；匹配必须唯一，上游变更则停止构建。
perl -0777 -pe '
  BEGIN {
    $menu = q|t("div",{class:"item",style:{backgroundColor:"#fbf5fa"},onClick:_},[Y(Za,{color:"#f6339a",class:"icon"}),t("span",null,i(e(n)("\u8F6F\u4EF6\u6E90\u914D\u7F6E")),1)])|;
    $button = q|t("div",a8,[t("button",{class:"btn-pink",onClick:b},i(e(n)("\u8F6F\u4EF6\u6E90\u914D\u7F6E")),1)])|;
  }
  $a = s/\Q$menu\E/D("",!0)/g;
  $b = s/\Q$button\E/D("",!0)/g;
  END { die "QuickStart 软件源入口已变化\n" unless $a == 1 && $b == 1 }
' "$bundle" > "$tmp/index.js"

awk '
  /^function istore_backend\(\)/ {
    n++
    print
    print "  -- Pwrt 的软件源只由光影猫管理修改；旧 QuickStart 切源会写入 OpenWrt 地址。"
    print "  local path = (http.getenv(\"REQUEST_URI\") or \"\"):match(\"^[^?]*\")"
    print "  if http.getenv(\"REQUEST_METHOD\") == \"POST\" and"
    print "      path:match(\"/istore/guide/soft%-source/?$\") then"
    print "    http.status(403, \"Forbidden\")"
    print "    http.prepare_content(\"application/json\")"
    print "    http.write_json({success=1, error=\"请到光影猫管理修改软件源\"})"
    print "    return"
    print "  end"
    next
  }
  { print }
  END { if (n != 1) exit 1 }
' "$proxy" > "$tmp/istore_backend.lua"

awk '
  /^[[:space:]]*procd_open_instance[[:space:]]*$/ {
    n++
    print
    print "\tprocd_set_param env \"PATH=/usr/libexec/quickstart/compat:/usr/sbin:/usr/bin:/sbin:/bin\""
    next
  }
  { print }
  END { if (n != 1) exit 1 }
' "$init" > "$tmp/quickstart.init"

if command -v luac >/dev/null 2>&1; then luac -p "$tmp/istore_backend.lua"; fi
sh -n "$tmp/quickstart.init"
cp "$tmp/index.js" "$bundle"
cp "$tmp/istore_backend.lua" "$proxy"
cp "$tmp/quickstart.init" "$init"
