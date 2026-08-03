#!/bin/sh
# 重新產生 tegaki-index.js（手寫搜尋的本地索引）。
#
# 平常不需要跑。要跑的時機只有兩個：
#   1. components.js 換了（部件清單變動）
#   2. vendor/gwtegaki/ 的模型升版（MODEL_VERSION 變了，索引必須跟著重建）
#
# 流程：
#   components.js ──> names.txt ─┐
#   GlyphWiki dump ──────────────┴─> index_subset.rs ─> features.tsv ─> make-index.js ─> tegaki-index.js
#
# 特徵函數用的是 gwtegaki 的 model crate，跟頁面上查詢時用的 wasm 同一份程式碼——
# 索引側與查詢側自洽就夠了，不需要跟上游後端的索引對齊（我們已經不連它了）。
#
# 需要：git、Rust（含 wasm32 以外的原生 target 即可）、curl、Node。
# 注意：若 rustc/cargo 來自 Homebrew 的 rust formula 而非 rustup，見 build-gwtegaki.sh 的說明。
set -e
cd "$(dirname "$0")"

REPO=https://github.com/kurgm/gwtegaki.git
COMMIT=8ec778cf418ac9cf3830fe6df535a8f5f842e218   # 與 build-gwtegaki.sh 同一個，兩者必須一致

DUMP=${1:-}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [ -z "$DUMP" ]; then
  echo "未指定 dump，從 GlyphWiki 下載（約 111 MB）⋯"
  echo "（已有檔案可用：sh build-tegaki-index.sh /path/to/dump_newest_only.txt）"
  curl -# -o "$WORK/dump.tar.gz" https://glyphwiki.org/dump.tar.gz
  tar xzf "$WORK/dump.tar.gz" -C "$WORK" dump_newest_only.txt
  DUMP="$WORK/dump_newest_only.txt"
fi
[ -f "$DUMP" ] || { echo "找不到 dump：$DUMP" >&2; exit 1; }

# 1. 從 components.js 取出部件名清單
node -e '
import("node:fs").then(({ readFileSync, writeFileSync }) => {
  const src = readFileSync("components.js", "utf8");
  const GW_COMPONENTS = new Function(src + "; return GW_COMPONENTS;")();
  const names = new Set();
  for (const ch in GW_COMPONENTS.chars) {
    for (const [name] of GW_COMPONENTS.chars[ch]) names.add(name);
  }
  writeFileSync(process.argv[1], [...names].sort().join("\n") + "\n");
  process.stderr.write(`部件名 ${names.size} 個\n`);
});
' "$WORK/names.txt"

# 2. 建 gwtegaki 的取特徵工具（用他們的 kage.rs／dump_reader.rs，換上我們的 main）
git clone --quiet "$REPO" "$WORK/gwtegaki"
git -C "$WORK/gwtegaki" checkout --quiet "$COMMIT"
cp tools/index_subset.rs "$WORK/gwtegaki/build_index/src/main.rs"
(cd "$WORK/gwtegaki" && cargo build --release -p gwtegaki-build_index 2>&1 | tail -1)

# 3. 算特徵
"$WORK/gwtegaki/target/release/gwtegaki-build_index" "$DUMP" "$WORK/names.txt" > "$WORK/features.tsv"

# 4. 量化打包
node tools/make-index.js "$WORK/features.tsv" > tegaki-index.js

echo
echo "tegaki-index.js 已更新："
ls -lh tegaki-index.js
echo "gzip 後：$(gzip -c tegaki-index.js | wc -c | awk '{printf "%.2f MB", $1/1048576}')"
echo
echo "索引的 v 必須等於 wasm 的 model_version()，頁面載入時會檢查；"
echo "改了 vendor/gwtegaki/ 就要重跑這支。"
