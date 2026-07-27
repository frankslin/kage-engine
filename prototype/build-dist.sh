#!/bin/sh
# 組裝可獨立部署的 prototype/dist/：
#   - 上層 8 個 KAGE 引擎檔 → dist/engine/
#   - index.html（../X.js 引用改寫成 engine/X.js）→ dist/
#   - components.js → dist/
# dist/ 是建置產物（已被 .gitignore 排除），每次部署前重跑本腳本即可，
# 平常開發直接開 prototype/index.html（引用上層引擎檔，改完即生效）。
#
# 部署：把 dist/ 的內容整個上傳到靜態伺服器。
set -e
cd "$(dirname "$0")"

rm -rf dist
mkdir -p dist/engine

for f in 2d.js buhin.js curve.js kage.js kagecd.js kagedf.js polygon.js polygons.js; do
  cp "../$f" "dist/engine/$f"
done

sed 's|<script src="\.\./\([a-z0-9]*\.js\)"></script>|<script src="engine/\1"></script>|' \
  index.html > dist/index.html

cp components.js dist/

# 驗證：dist/index.html 不得再有目錄外引用
if grep -q '\.\./' dist/index.html; then
  echo "錯誤：dist/index.html 仍有 ../ 引用" >&2
  exit 1
fi
echo "dist/ 組裝完成："
find dist -type f | sort
