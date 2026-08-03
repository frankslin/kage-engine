#!/bin/sh
# 組裝可獨立部署的 prototype/dist/：
#   - 引擎 bundle 的壓縮版（dist/kage.min.js）→ dist/engine/kage.min.js
#   - index.html（../dist/kage.js 引用改寫成 engine/kage.min.js）→ dist/
#   - components.js → dist/
#
# 開發時頁面引用未壓縮的 ../dist/kage.js（可讀、可下中斷點），部署改用壓縮版：
# 34 KB vs 124 KB。兩者輸出逐位元組相同（terser 預設不改屬性名，所以
# Kage.Polygons、getEachStrokes 這些頁面用到的名稱都在）。
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

cp ../dist/kage.min.js dist/engine/kage.min.js

sed 's|<script src="\.\./dist/kage\.js"></script>|<script src="engine/kage.min.js"></script>|' \
  index.html > dist/index.html

# 驗證：改寫確實發生（sed 沒中就會留下 ../ 引用，下面那關會擋，但錯誤訊息不明確）
if ! grep -q '<script src="engine/kage\.min\.js"></script>' dist/index.html; then
  echo "錯誤：index.html 的引擎引用沒有被改寫，請檢查 index.html 裡的 script 標籤" >&2
  exit 1
fi

cp components.js dist/

# 手寫搜尋模型（kurgm/gwtegaki，MIT）：已建置的 wasm，隨頁面一起部署。
# 連 LICENSE 一起複製——MIT 要求保留著作權聲明，部署出去的那份也算散布。
mkdir -p dist/vendor/gwtegaki
cp vendor/gwtegaki/gwtegaki_model.js vendor/gwtegaki/gwtegaki_model_wasm.js \
   vendor/gwtegaki/LICENSE dist/vendor/gwtegaki/

# 驗證：dist/index.html 不得再有目錄外引用
if grep -q '\.\./' dist/index.html; then
  echo "錯誤：dist/index.html 仍有 ../ 引用" >&2
  exit 1
fi
echo "dist/ 組裝完成："
find dist -type f | sort
