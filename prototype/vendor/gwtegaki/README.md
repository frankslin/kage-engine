# vendor/gwtegaki/

手寫搜尋用的特徵抽取模型，來自 **[kurgm/gwtegaki](https://github.com/kurgm/gwtegaki)**
（MIT，作者 Kurogoma／@kurgm，與 kage-engine 的作者同一人），釘在 commit
`8ec778cf418ac9cf3830fe6df535a8f5f842e218`（2026-07-20）。

| 檔案 | 說明 |
|---|---|
| `gwtegaki_model.js` | wasm-pack `--target no-modules` 產生的膠水碼（定義全域 `wasm_bindgen`），未修改 |
| `gwtegaki_model_wasm.js` | 同次建置的 `.wasm`（26 KB）以 base64 內嵌，由 `../build-gwtegaki.sh` 產生 |
| `LICENSE` | 上游的 MIT 授權原文 |

重新產生：`sh prototype/build-gwtegaki.sh`（需要 Rust + wasm-pack，見腳本開頭）。

## 為什麼提交建置產物

1. Cloudflare Pages 的建置環境只有 Node，沒有 Rust 工具鏈，部署時無法現場編。
2. `.wasm` 以 base64 內嵌成 `.js`，是為了讓本頁在 `file://` 下也能用——
   `file://` 下 `fetch()` 取不到同目錄的檔案，ESM 版的膠水碼也會被 module 的
   CORS 規則擋掉，所以用 `no-modules` + 內嵌位元組這組合。

## 只用模型，不用它的服務

上游還有一個 Cloud Run 後端（索引 GlyphWiki 全部 36 萬個字形）。本頁**不連它**——
本地索引 `../../tegaki-index.js` 只收 2,677 個常用部件，暴力全掃約 3.5 ms。
理由見 `prototype/README.md`「手寫搜尋的本地索引」一節（簡短版：那台是上游作者
自費的私人服務；36 萬全集的候選品質對拼字工具反而更差）。

## 版本對版

模型的 `MODEL_VERSION`（目前 `"2"`）必須等於 `tegaki-index.js` 的 `v`，
頁面載入索引時會檢查，不符會直接報錯。**動了這個目錄就要重跑
`sh prototype/build-tegaki-index.sh`**，兩支腳本裡釘的 commit 也要保持一致。

## 授權

本 repo 是 GPL-3.0，這份是 MIT——MIT 可併入 GPL-3.0 作品，保留上述著作權聲明即可
（`LICENSE` 檔就是為此保留的）。
