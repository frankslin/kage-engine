# AGENTS.md

給後續在這個 repo 裡工作的 AI agent／開發者的指引。

## 這是什麼專案

`kage-engine` 是 KAGE 漢字字形生成引擎，把「筆畫資料字串」轉成向量多邊形輪廓（可輸出 SVG/EPS），用來產生明朝體/黑體風格的漢字字形。

**本 repo（`frankslin/kage-engine`）是 `kamichikoichi/kage-engine` 的 fork**，fork 當下與上游完全一致——既有 commit 均出自上游作者 Koichi Kamichi 及被合併的貢獻者（Kurogoma/kurgm、MihailJP）。文件類提交（AGENTS.md/CLAUDE.md/WALKTHROUGH.md）之後的 commit 才是本 fork 的獨立開發。

詳細架構、資料格式、演算法說明見 [`WALKTHROUGH.md`](./WALKTHROUGH.md)——**開始改程式碼前務必先讀那份文件**，這裡不重複展開。

## 現況：沒有建置/測試/lint 工具鏈

這個 repo 是**純 JavaScript、無 `package.json`、無建置工具、無自動化測試、無 lint**的扁平結構（8 個 `.js` 檔 + 3 個 `sample.*`）。這是刻意維持的老派風格，不要在沒有明確被要求的情況下引入 TypeScript、bundler、npm 依賴或模組系統——這會偏離這個 fork 的既有慣例。

### 如何驗證修改

沒有測試可以跑，**驗證方式是視覺檢查**：

```bash
# SpiderMonkey
js sample.js > result.svg

# 或 Rhino
java -jar js.jar sample.js > result.svg

# 或直接在瀏覽器打開 sample.html
```

`sample.js`/`sample.html` 目前硬編碼渲染 `u6f22`（漢）、`u9ebb`（麻）。修改 `kagecd.js`/`kagedf.js` 裡任何筆畫繪製邏輯後，**一定要重新產生並肉眼比對輸出**（有無缺口、破圖、曲線扭曲），不能只憑程式碼审查判斷正確性。如果修改涉及特定筆畫類型或特定字，最好額外在 `sample.js` 裡加一個包含該筆畫類型的字做驗證，而不是只驗證原有的兩個範例字。

### 檔案載入順序

`2d.js` 和 `curve.js`（提供 `Polygon`/`calculateBezier` 等）必須在 `kagecd.js` 之前載入。若新增檔案或調整 `sample.html`/`sample.js`，維持原本的順序：

```
2d.js → buhin.js → curve.js → kage.js → kagecd.js → kagedf.js → polygon.js → polygons.js
```

## 程式碼慣例

- ES3/ES5 風格：`var`、建構子函式 + `Foo.prototype.method = ...`，**不要**改寫成 class 語法或引入 `let`/`const`，除非使用者明確要求現代化。
- 沒有模組系統（非 ESM 非 CommonJS），全部靠 global scope + 載入順序運作，修改時保持一致。
- 筆畫類型/頭尾形狀是用十進位數字打包多個旗標（例如 `Math.floor((ta1 % 10000) / 1000)`），改動這類邏輯前務必先理解 `WALKTHROUGH.md` 第 3 節的編碼規則，不要憑猜測改數字。
- 明朝體專屬的 `adjust*` 系列函式（`kage.js`）**不可**套用在黑體上（`kShotai == kMincho` 時才執行）——這是 PR #7「fix-gothic」修過的坑，之後改動這一塊時要小心不要重蹈覆轍。
- Commit 訊息延續專案慣例可用日文，簡短、直接引用筆畫類型編號或書法術語（見 `WALKTHROUGH.md` 第 10 節的術語對照表）。

## 關於其他 fork：選定的開發策略

這個 repo 是眾多 KAGE engine fork 之一。分析比較如下（2026-07-26 調查，皆為讀取上游/各 fork 實際原始碼後的結論）：

- **`kamichikoichi/kage-engine`** — 官方上游（GlyphWiki 使用），純 JS，無工具鏈。目前這個本地 repo 就是它的完整鏡像。
- **`kurgm/kage-engine`** — 改寫成 TypeScript，發布為 npm 套件 `@kurgm/kage-engine`，有測試/ESLint/typedoc/CHANGELOG。核心貢獻是把 `kagecd.js`/`kagedf.js` 裡「水平/垂直/斜向」「明朝/黑體/線/曲線/貝茲」的大量重複分支，抽出成共用的 `Pen`（座標旋轉）+ `Stroke`（筆畫資料封裝）+ 統一的 `cdDrawCurveU`，並用專門的輸出比對腳本驗證重構沒有改變行為。TS 用法很淺（只有 `readonly`/`interface`/一個 union type，沒有 generics），去型別化風險低。**刻意不新增任何筆畫類型或風格參數**，維持跟上游輸出一致。
- **`ge9/kage-engine-2`** — 純 JS，明確聲明「不是一個可獨立使用的函式庫」，服務於作者自己的字型專案 `NazonoMincho`。特點是新增了大量上游/kurgm 都沒有的東西：多段粗細分層（`kMinWidthYY`/`kMinWidthC`/`kMinWidthT_adjust`）、新筆畫類型（如 `CONNECT_THIN`）、以及大量客製化調整啟發式。已經獨立重新發明了類似 kurgm `Pen` 的座標轉換抽象（`pointmaker.js` 的 `PointMaker`），但 `gothic.js`/`mincho.js` 內部繪製邏輯仍保留原本重複的分支風格，沒有做 kurgm 那種去重複重構。

**決定：以 `ge9/kage-engine-2` 作為後續開發基礎，把 `kurgm/kage-engine` 的去重複重構（`Pen`/`Stroke`/旋轉矩陣抽象）手動移植進來，保留 ge9 既有的粗細分層與新筆畫類型不動。**

理由：
1. ge9 自己的 `PointMaker` 已經是 kurgm `Pen` 的雛形，移植 kurgm 的重構思路不是引入陌生抽象，只是把 ge9 現有的重複分支收斂到已有的抽象上——是一個範圍明確、有 kurgm 實際 commit/diff 可以照抄的內部重構。
2. 反過來（fork kurgm，把 ge9 的功能移植進去）需要在 kurgm 更嚴格的 TS class 階層（`interface FontInterface`、`class Gothic extends Mincho`）裡**發明**新的粗細分層與筆畫類型概念，而且 ge9 那些 commit 大多沒有文件說明，也沒有「改之前」的版本可以對照 diff，等於要重新設計，而非機械式搬運。

實作上的建議順序：
1. 先把 ge9 fork 下來當作新的開發基礎，跑一輪 `sample.js`/對應範例確認能重現現有輸出。
2. 讀 kurgm 的 `src/pen.ts`、`src/stroke.ts`、`src/font/{mincho,gothic}/{index,cd}.ts`，對照 ge9 現有的 `pointmaker.js`、`mincho.js`、`gothic.js`、`stroketype.js`，找出對應關係。
3. 逐步把 ge9 `gothic.js`/`mincho.js` 裡三份重複的 line/curve/bezier 繪製邏輯，改寫成呼叫統一的 `cdDrawCurveU` 等價函式，中途保留每一步都能用既有範例字驗證輸出沒有跑掉。
4. ge9 專屬的粗細分層參數（`kMinWidthYY` 等）與新筆畫類型（`CONNECT_THIN` 等）維持原邏輯，只是改成透過新的共用抽象呼叫，不需要改動其語意。

## 授權

GPL v3（見 `COPYING`）。任何移植/引用其他 fork 的程式碼時，注意授權相容性（`kurgm` fork 同樣是 GPL-3.0，相容）。
