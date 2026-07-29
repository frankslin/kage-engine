#!/bin/sh
# 組裝可獨立部署的 prototype/dist/：
#   - 引擎 bundle（根目錄 npm run build:dist 的產物 dist/kage.js）→ dist/engine/kage.js
#   - index.html（../dist/kage.js 引用改寫成 engine/kage.js）→ dist/
#   - components.js → dist/
# prototype/dist/ 是建置產物（已被 prototype/.gitignore 排除），每次部署前重跑本腳本即可。
#
# 平常開發：先在根目錄跑一次 `npm install && npm run build:dist`，
# 之後直接開 prototype/index.html（引用根目錄的 dist/kage.js）。
# 改動 src/*.ts 後要重跑 `npm run build:dist` 才會反映到頁面上。
#
# 部署：把 prototype/dist/ 的內容整個上傳到靜態伺服器。
set -e
cd "$(dirname "$0")"

# 確保引擎 bundle 是最新的（src/*.ts → dist/kage.js）
(cd .. && npm run build:dist)

rm -rf dist
mkdir -p dist/engine

cp ../dist/kage.js dist/engine/kage.js

sed 's|<script src="\.\./dist/kage\.js"></script>|<script src="engine/kage.js"></script>|' \
  index.html > dist/index.html

cp components.js dist/

# 驗證：dist/index.html 不得再有目錄外引用
if grep -q '\.\./' dist/index.html; then
  echo "錯誤：dist/index.html 仍有 ../ 引用" >&2
  exit 1
fi
echo "dist/ 組裝完成："
find dist -type f | sort
