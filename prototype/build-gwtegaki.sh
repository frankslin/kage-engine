#!/bin/sh
# 重新產生 vendor/gwtegaki/ 裡的手寫搜尋模型（平常不需要跑；只有要跟上 gwtegaki
# 上游、或 MODEL_VERSION 改版時才跑）。
#
# 產物是**已建置的 WebAssembly**，已提交進版控——因為 Cloudflare Pages 的建置環境
# 只有 Node，沒有 Rust/wasm-pack，部署時無法現場編。
#
# 需要：git、Rust（含 wasm32-unknown-unknown target）、wasm-pack。
#   brew install wasm-pack
#   rustup target add wasm32-unknown-unknown
# 注意：若 rustc/cargo 來自 Homebrew 的 rust formula 而非 rustup，wasm-pack 會找不到
# wasm32 target。此時把 rustup 的 toolchain 放到 PATH 前面：
#   PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH" sh build-gwtegaki.sh
set -e
cd "$(dirname "$0")"

# 釘住 commit：模型換版會改變特徵向量的語意，而後端索引是按 MODEL_VERSION 對版的，
# 對不上後端會回 404。升版前先確認 https://kurgm.github.io/gwtegaki/ 的後端也換了。
REPO=https://github.com/kurgm/gwtegaki.git
COMMIT=8ec778cf418ac9cf3830fe6df535a8f5f842e218

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git clone --quiet "$REPO" "$WORK/gwtegaki"
git -C "$WORK/gwtegaki" checkout --quiet "$COMMIT"

# --target no-modules：產生可用一般 <script> 標籤載入的膠水碼（定義全域 wasm_bindgen）。
# 用 ESM 版的話 file:// 下會因為 module 的 CORS 限制載不起來。
(cd "$WORK/gwtegaki/model" && wasm-pack build --no-pack --profile release-wasm \
  --target no-modules --out-dir pkg-nomod >/dev/null 2>&1)

mkdir -p vendor/gwtegaki
cp "$WORK/gwtegaki/model/pkg-nomod/gwtegaki_model.js" vendor/gwtegaki/gwtegaki_model.js
cp "$WORK/gwtegaki/LICENSE" vendor/gwtegaki/LICENSE

# .wasm 以 base64 內嵌成 .js：file:// 下 fetch 取不到同目錄的 .wasm 檔。
node -e '
const fs = require("fs");
const b = fs.readFileSync(process.argv[1]).toString("base64");
fs.writeFileSync("vendor/gwtegaki/gwtegaki_model_wasm.js",
  "// gwtegaki 特徵抽取模型的 WebAssembly 位元組，以 base64 內嵌。\n" +
  "// 內嵌而非另存 .wasm 檔是為了讓本頁在 file:// 下也能用（fetch 取不到 file:// 的資源）。\n" +
  "// 由 build-gwtegaki.sh 產生，請勿手改。來源：kurgm/gwtegaki@" + process.argv[2] + " model/（MIT）\n" +
  "var GWTEGAKI_WASM_BASE64 = \"" + b + "\";\n");
' "$WORK/gwtegaki/model/pkg-nomod/gwtegaki_model_bg.wasm" "$COMMIT"

echo "vendor/gwtegaki/ 已更新（來源 $COMMIT）："
ls -l vendor/gwtegaki/
echo
echo "請確認模型版本與後端索引一致："
echo "  grep MODEL_VERSION 模型原始碼 → 應等於 curl -sX POST \$API/warmup 回傳的 v"
