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

## 版本對版

模型的 `MODEL_VERSION`（目前 `"2"`）必須等於後端索引的 `v`，否則後端回 404。
確認方式：

```bash
curl -sX POST https://gwtegaki-backend-nodegcr-pxofktfxwq-uc.a.run.app/warmup
# {"dumpTime":1773162020000,"numItems":364317,"v":"2"}
```

升上游版本前先確認後端也換了，不然升完就搜不動。

## 授權

本 repo 是 GPL-3.0，這份是 MIT——MIT 可併入 GPL-3.0 作品，保留上述著作權聲明即可
（`LICENSE` 檔就是為此保留的）。
