# AGENTS.md

給後續在這個 repo 裡工作的 AI agent／開發者的指引。

## 這是什麼專案

`kage-engine` 是 KAGE 漢字字形生成引擎，把「筆畫資料字串」轉成向量多邊形輪廓（可輸出 SVG/EPS），用來產生明朝體/黑體風格的漢字字形。

**本 repo（`frankslin/kage-engine`）的引擎本體來自 [`kurgm/kage-engine`](https://github.com/kurgm/kage-engine)**
（GPL-3.0，已設為 remote `kurgm`），它本身是 GlyphWiki 官方上游 `kamichikoichi/kage-engine` 的 fork。
本 fork 自己的內容是：

- `prototype/` — 拼字法造字工具（瀏覽器端）
- `doc/` — 繁體中文的引擎導覽與 KAGE 資料格式規格

詳細架構、資料格式、演算法說明見 [`doc/WALKTHROUGH.md`](./doc/WALKTHROUGH.md)——**開始改程式碼前務必先讀那份文件**，這裡不重複展開。

## 工具鏈

TypeScript + npm + eslint + rollup（全部繼承自 kurgm）：

```bash
npm install
npm run build      # build:lib（tsc → lib/esm + lib/cjs）+ build:dist（rollup → dist/）
npm test           # node test/index.js
npm run lint       # eslint 'src/**/*.ts'
```

`lib/`、`dist/`、`prototype/dist/` 都是建置產物，已被 gitignore。

### 如何驗證修改

`npm test` 跑兩個檔（兩者都在上游 kurgm，本 repo 不另外維護）：

- **`test/index.js`** — 三個手寫字形對照內嵌的多邊形座標，逐點比對（容差 0.5）、
  檢查 on/off-curve 旗標與 NaN。精確但範圍窄：只觸及 **10 組**（筆畫類型／頭形／尾形）
  組合，全為明朝體且 `kUseCurve` 關閉，筆畫類型 3／6／7 從未被畫出，黑體從未渲染。
  **它通過時是靜默的**，輸出只看得到 `Buhin#onMissing: ok`——別因此以為筆畫繪製沒測試。
- **`test/strokes.js`** — 7,614 個 case 的矩陣回歸測試：筆畫類型 × 頭形 × 尾形 ×
  四種幾何（含刻意由右往左、由下往上的方向）× 明朝/黑體 × `kUseCurve`，另加部件展開、
  伸縮參數、翻轉旋轉的整字案例。比對指紋（多邊形數、頂點數、座標 sha1），
  黃金檔在 `test/strokes-golden.tsv`。本 fork 提出、已併入上游
  （[kurgm/kage-engine#19](https://github.com/kurgm/kage-engine/pull/19)）。

**兩者都只能回答「輸出有沒有變」，不能回答「字形對不對」。** 改動 `src/font/**` 之後仍然要：

1. **視覺檢查**：`node samples/sample.js > result.svg`（需先 `npm run build:lib`），
   或用瀏覽器開 `samples/sample.html`，肉眼比對有無缺口、破圖、曲線扭曲。範例字硬編碼
   `u6f22`（漢）；若改動涉及特定筆畫類型，額外加一個包含該類型的字。
2. **有意改變輸出時**：`UPDATE_GOLDEN=1 node test/strokes.js` 重新產生黃金檔，然後
   **逐行看 diff**——每一行變動都是一個形狀跑掉的筆畫，diff 比預期大就代表改動範圍
   超出預期。不要不看 diff 就直接重新產生。

kurgm 自己另有一套獨立的跨版本輸出比對腳本
[`kage-engine-compare`](https://github.com/kurgm/kage-engine-compare)，做的是同一件事。

## 程式碼慣例

- **TypeScript**，tab 縮排，`const`/`let`，class 語法。型別用法很淺（`readonly`/`interface`/少量 union），不要為了型別體操把它複雜化。
- 內部 API 標 `@internal`；公開 API 加 TSDoc（會被 typedoc 收進 `docs/`）。
- 明朝體與黑體是**各自獨立的類別**（`src/font/mincho/`、`src/font/gothic/`），明朝體專屬的
  `adjust*` 微調只存在於 `Mincho`。舊版靠 `if (kShotai == kMincho)` 隔離、曾經漏判導致黑體輸出損壞
  （上游 PR #7「fix-gothic」），新結構從型別層面就避開了——**不要**為了共用而把 adjust\* 上移到共同基底。
- 筆畫類型/頭尾形狀的十進位旗標打包（`+100`/`+1000`/`+10000`），解包集中在 `Stroke` 建構子
  （`src/stroke.ts`），繪製端讀 `a2_100`/`a2_opt_1` 這類具名屬性。**不要**在繪製端重新寫
  `Math.floor((ta1 % 10000) / 1000)`，也不要用改寫類型編號的方式傳遞調整量（改用具名參數）。
- 座標計算優先透過 `Pen`（`src/pen.ts`）以區域座標表達，不要為「水平/垂直/斜向」各寫一份三角函數——
  消除這類重複正是 kurgm 這一支的核心價值。
- Commit 訊息：引擎相關的可延續上游慣例用日文、簡短、直接引用筆畫類型編號或書法術語
  （見 `doc/WALKTHROUGH.md` 第 10 節的術語對照表）；本 fork 自己的內容用繁體中文。

## prototype/ 與引擎的介面

`prototype/index.html` 以 `<script src="../dist/kage.js">` 載入 rollup 打的 IIFE bundle
（開發用未壓縮版；`build-dist.sh` 部署時會換成 `kage.min.js`，34 KB vs 124 KB）。
**該 bundle 只在 global scope 定義 `Kage`**，`Polygons`/`Buhin` 掛在它上面，所以頁面裡有一行
`var Polygons = Kage.Polygons;`。改動引擎後要重跑 `npm run build:dist` 才會反映到頁面上。

它用到的引擎介面：`new Kage()`、`kage.kBuhin.push()`、`makeGlyph()`、`makeGlyph3()`、
`polygons.array[i].array`——以及 `kage.getEachStrokes()`，**後者在 kurgm 的型別上是 `protected`**
（執行期正常，但不屬於公開 API）。升級引擎時要留意這一個。

部署：`sh prototype/build-dist.sh` 組裝 `prototype/dist/`（腳本會先呼叫根目錄的 `npm run build:dist`）。
Cloudflare Pages 的輸出目錄設定在 `wrangler.toml`。

## 跟進上游

```bash
git fetch kurgm && git merge kurgm/master
```

`kurgm` 持續維護中（2026-06 仍有 commit），且會併回官方上游的修正，所以跟著 `kurgm/master` 就同時跟上了兩邊。

## 關於其他 fork：選型結論（2026-07-29 實測修訂）

> 本節在 2026-07-26 曾有一版相反的結論（「以 `ge9/kage-engine-2` 為基礎」）。
> 那版是只讀原始碼、沒有實際建置與執行得出的，2026-07-29 實測後推翻。以下為修訂版。

- **`kamichikoichi/kage-engine`** — GlyphWiki 官方上游，24 個 commit，純 JS 無工具鏈。維護節奏極慢（2026 全年 1 個 commit），且外部 PR 幾乎都來自 kurgm。
- **`kurgm/kage-engine`** — **本 repo 現在的基礎**。354 個 commit，最後一次 2026-06-21；
  `git rev-list --left-right --count upstream/master...HEAD` = `0 330`，即包含官方上游全部歷史且零落後。
  發布為 npm 套件 `@kurgm/kage-engine`，有 CI/eslint/typedoc/CHANGELOG。
- **`ge9/kage-engine-2`** — 純 JS（ESM），為作者自己的字型專案 `NazonoMincho` 服務。

實測依據（都是實際 clone、建置、執行後的結果，不是讀碼推論）：

| | kurgm | ge9 |
|---|---|---|
| 最後 commit | 2026-06-21 | **2024-01-06**（停更兩年半） |
| 相對官方上游 | 落後 0 | **落後 17 個 commit**（缺 2022/2023/2026 的修正） |
| 建置測試 | `npm install && npm run build && npm test` 一次過 | 無 package.json，Node 無法直接 import（需手動補 `{"type":"module"}`） |
| 可執行範例 | samples/ 可跑 | **`sample.js` 仍 `load("kagecd.js")`——該檔早已不存在；`sample.html` 已刪除**，沒有可用入口 |
| 文件 | README + typedoc + CHANGELOG | 無 README |
| 810 例隨機筆畫資料 | 0 次崩潰 | **11 次崩潰**（如收筆 8「止め」配直線直接 `throw` 裸字串，而該組合是上游合法資料） |
| 與上游輸出相容性 | `u6f22` 逐位元組相同；810 例中僅 2 例不同，**且該 2 例是上游在 `kagecd.js:217` 崩潰而 kurgm 正常出圖** | 刻意偏離（自有設計與字重） |

**ge9 唯一值得移植的是它的輸出形式與筆法**：它輸出真正的貝茲 `<path>`（上游/kurgm 輸出採樣後的
`<polygon>` 折線），並用寬度函數（`util.js` 的 `widfun`/`widfun_d`）做變寬描邊、`fit-curve.js` 做曲線擬合，
另有多段粗細分層參數（`kMinWidthYY`/`kMinWidthC`/`kMinWidthT_adjust`）與新筆畫類型（`CONNECT_THIN` 等）。
做字型輸出時這是實打實的品質提升。

**但這應當作獨立課題，參考 `fontcanvas.js` + `util.js` 的想法在 kurgm 上重新實作，而不是 fork ge9。**
兩者皆 GPL-3.0，移植沒有授權問題。

## 授權

GPL v3（見 `COPYING`）。任何移植/引用其他 fork 的程式碼時注意授權相容性（上述各 fork 皆為 GPL-3.0，相容）。
