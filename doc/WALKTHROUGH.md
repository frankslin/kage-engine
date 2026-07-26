# kage-engine 程式碼導覽（walkthrough）

> 本文件為 `kage-engine` 專案的中文導覽，協助理解程式碼的用途、架構與慣例。
> 撰寫時間：2026-07-26。

## 1. 這個專案是做什麼的

`kage-engine` 是 **KAGE 字形引擎**（原始出處：[fonts.jp/engine](http://fonts.jp/engine/)）的個人修改版本，是一套用純 JavaScript 寫成、**沒有任何外部相依套件**的引擎，用途是：

> 把一串「筆畫資料字串」（描述一個漢字每一筆筆畫的類型、頭尾形狀、控制點座標）轉換成向量多邊形（polygon）輪廓，可以再輸出成 SVG、EPS，或直接畫到 HTML5 `<canvas>` / Flash 舞台上。

換句話說，這是一個「**參數化生成漢字字形外框**」的引擎，用來畫出明朝體（Mincho，類似襯線字體）或黑體（Gothic，類似無襯線字體）風格的漢字筆畫，包括：

- 鱗（うろこ，horizontal 筆畫尾端的三角形裝飾，類似襯線）
- 跳ね（hane，勾）
- 曲がり（mage，轉折/彎曲）
- 切り口（kirikuchi，斜切筆畫交叉處）
- 踵（kakato，某些曲線筆畫的「腳跟」形狀）

這套引擎是 **GlyphWiki**（一個協作式漢字字形 wiki 網站）背後的渲染核心，EPS 輸出裡甚至直接寫死 `%%Creator: GlyphWiki powered by KAGE system`。

> **注意**：本 repo（`frankslin/kage-engine`）是 **`kamichikoichi/kage-engine` 的 fork**，fork 當下與上游完全一致——既有 commit 均出自上游維護者 Koichi Kamichi 及被合併的貢獻者 Kurogoma（kurgm）、MihailJP。下面第 9 節「近期開發脈絡」描述的即是這段上游歷史。

## 2. 專案結構

專案是**完全扁平**的結構，沒有子目錄，也**沒有 `package.json`、沒有建置工具、沒有測試框架、沒有 lint 設定**：

```
kage-engine/
├── 2d.js         2D 幾何工具（線段/線段相交判斷）
├── buhin.js      「部品」(component/radical) 名稱 → 資料字串 的登錄表
├── curve.js      貝茲曲線數學（分割、取點+法線、offset curve 搜尋）
├── kage.js       Kage 類別：組字的最上層邏輯 + 明朝體專屬的筆畫位置微調啟發式
├── kagecd.js     核心笔畫外框繪製器（cdDrawCurveU 等），全專案最大檔案 (1235 行)
├── kagedf.js     依筆畫類型分派繪製 (dfDrawFont)，內部區分明朝/黑體兩套邏輯
├── polygon.js    Polygon 類別：單一封閉點列（含 on/off-curve 旗標，模仿 TrueType）
├── polygons.js   Polygons 類別：多個 Polygon 的集合，並提供 SVG/EPS 序列化輸出
├── sample.as     ActionScript(Flash) 範例
├── sample.html   瀏覽器 <canvas> 範例
├── sample.js     獨立 JS 引擎範例 (SpiderMonkey/Rhino)，輸出 SVG 到 stdout
└── COPYING       GNU GPL v3 全文（授權條款）
```

依賴順序（`sample.html`/`sample.js` 都是按此順序載入）：

```
2d.js → buhin.js → curve.js → kage.js → kagecd.js → kagedf.js → polygon.js → polygons.js
```

這個順序很重要：`kagecd.js` 用到 `Polygon`（在 `polygon.js`）與 `calculateBezier`（在 `curve.js`），必須先載入依賴檔案。

## 3. 核心資料格式：筆畫資料字串

這是整個引擎的「領域特定語言」。一個字的資料是用 `$` 分隔多筆「筆畫」，每筆筆畫再用 `:` 分隔多個欄位：

```
"1:0:2:40:37:143:37$4:22:5:143:37:12:169:170:169:175:171"
```

- **欄位 0 (`a1`)**：筆畫類型代碼。常見值：
  - `1` = 直線
  - `2` = 二次曲線
  - `3`/`4` = 複合「線+曲線」筆畫（例如「乙」型轉折）
  - `6` = 三次貝茲曲線
  - `7` = 線接曲線
  - `9`/`8` = 點/無操作
  - `99` = **部品參照**（不是實際筆畫，而是插入另一個已定義的部件/部首）
- **欄位 1、2 (`a2`, `a3`)**：分別編碼「起筆」與「收筆」的形狀（鱗、跳ね、切り口……等），常常用 `+100`、`+1000`、`+10000` 疊加多個旗標（例如 `kagecd.js` 裡常見 `Math.floor((ta1 % 10000) / 1000)` 這種「用十進位當作打包位元」的寫法）。
- **其餘欄位**：最多 4 組 (x, y) 控制點座標；若欄位 0 是 `99`（部品參照），格式則變成 `x1:y1:x2:y2:部品名稱:sx:sy:sx2:sy2`，代表把該部件的座標框重新映射（縮放/平移/鏡射）到目前這個範圍內。

所有座標都落在 **0–200 x 0–200 的固定 em 方格**內。

## 4. 主要流程（從呼叫端角度）

```js
var kage = new Kage();
var polygons = new Polygons();

// 註冊部品（可以是完整字或子部件）
kage.kBuhin.push("u6f22", "99:150:0:9:12:73:200:u6c35-07:0:-10:50$99:0:0:54:10:190:199:u26c29-07");
kage.kBuhin.push("u6c35-07", "2:7:8:...$2:7:8:...");
kage.kBuhin.push("u26c29-07", "1:0:0:...$...");

// 生成字形
kage.makeGlyph(polygons, "u6f22");

// 輸出
print(polygons.generateSVG(false));
```

呼叫鏈：

1. **`Kage.makeGlyph(polygons, buhinName)`**（`kage.js:3`）— 從 `kBuhin`（`Buhin` 實例）查出資料字串，交給 `makeGlyph2`。
2. **`makeGlyph2(polygons, data)`**（`kage.js:9`）—
   a. 用 `getEachStrokes` 把資料字串解析成每筆筆畫的數字陣列（欄位 0 為 `99` 時會遞迴展開部品，見 `getEachStrokesOfBuhin`，內含座標映射 `stretch()`）；
   b. 呼叫 `adjustStrokes`（**只有明朝體才會執行**，見下方第 5 節）；
   c. 對每一筆筆畫呼叫 `dfDrawFont`，把產生的 `Polygon` 累加進傳入的 `polygons`。
3. **`dfDrawFont`**（`kagedf.js:97`）— 依 `a1 % 100` 判斷筆畫種類（直線/曲線/複合/貝茲），並依 `kage.kShotai`（明朝 or 黑體）走不同分支，決定頭尾形狀該怎麼畫，最後委派給：
4. **`cdDrawLine` / `cdDrawCurve` / `cdDrawBezier`**（`kagecd.js:695`）— 都是 `cdDrawCurveU` 的薄包裝。
5. **`cdDrawCurveU`**（`kagecd.js:1`，整個引擎最核心的函式）— 真正的「筆畫轉外框多邊形」演算法：
   - 沿著筆畫中心線取樣，每個取樣點算出垂直於行進方向的偏移量（決定筆畫粗細）；
   - 依 `ta1`/`ta2`（起筆/收筆形狀碼）走大量 `switch` 分支，分別處理鱗、跳ね、切り口、踵……等具體形狀；
   - 若 `kage.kUseCurve` 開啟，改用貝茲曲線擬合平滑（`curve.js` 的 `calculateBezier`），否則用純折線。

另外還有 **`makeGlyph3(data)`**（`kage.js:30`），行為類似 `makeGlyph2`，但回傳「每一筆畫各自一個 `Polygons`」的陣列，方便逐筆檢視或動畫。

## 5. 明朝體專屬的「筆畫微調」啟發式（`kage.js` 的 `adjust*` 系列）

這是這個引擎最「藝術」也最難懂的部分：一組**只在 `kShotai == kMincho` 時執行**（黑體會跳過，這是 PR #7「fix-gothic」修的重點——舊版本這些調整誤用在黑體上導致輸出損壞）的函式，會分析**同一個字裡筆畫之間的幾何關係**，做出微調讓明朝體看起來更像手寫的書法：

- **`adjustHane`**（`kage.js:149`）— 偵測「跳ね」（勾）筆畫尾端若太靠近旁邊另一筆筆畫，就按比例縮小跳ね的突出程度。
- **`adjustUroko` / `adjustUroko2`**（`kage.js:184`）— 依水平筆畫長度、以及是否有其他筆畫從旁「擠壓」（用距離加權的「pressure」概念，`Math.pow(..., 1.1)`）調整鱗（serif 三角形）的大小/角度。
- **`adjustTate` / `adjustMage`** — 太靠近的直豎筆畫或轉折處會加粗，避免視覺上顯得太細。
- **`adjustKirikuchi`** — 偵測特定的「斜切線 vs 水平筆畫交叉」的模式，把筆畫類型重新編碼成 `132`（原本是 `32`）。
- **`adjustKakato`** — 依附近筆畫是否與探測框相交（用 `2d.js` 的 `isCrossBoxWithOthers`），調整某些曲線筆畫（類型 `13`/`23`）的「腳跟」形狀。

所有魔術數字常數（`kAdjustHaneLength`、`kAdjustUrokoX/Y/Length`、`kAdjustTateStep`、`kAdjustMageStep`、`kAdjustKakatoRangeX/Y` 等）都定義在 `Kage` 建構子（`kage.js:376`），依傳入的 `size` 參數有兩套預設值（小尺寸/一般尺寸）。

## 6. 貝茲曲線數學（`curve.js`）

- **`divide_curve`** — De Casteljau 式的曲線二分割，在 t=0.5 處把一條貝茲曲線切成兩段（用於例如需要在曲線中段插入跳ね的情況）。
- **`calculateBezier(x1,y1, sx1,sy1, sx2,sy2, x2,y2, t, width)`** — 給定 t，同時算出「該點座標」和「垂直於切線方向、按筆寬縮放的法向偏移量」；會自動判斷是二次（`sx1==sx2 && sy1==sy2`）還是三次貝茲。原本 `kagecd.js` 有一份重複程式碼，在 commit `38eacb8`（「ベジエ曲線計算のコードをさらに再利用する」）被整併到這裡共用。
- **`find_offcurve`** — 用網格搜尋（先粗後細）找出能最佳擬合一串取樣點的單一二次貝茲控制點（誤差平方最小化）。
- **`get_candidate`** — 沿著貝茲曲線中心線，以 `kage.kRate/1000` 為步進取樣 t，產生左右兩條「軌道」折線（之後會被反轉、串接成封閉的 `Polygon`）。

## 7. 幾何基礎與資料結構

- **`2d.js`** — 純幾何：兩線段交點 (`getCrossPoint`)、線段是否相交 (`isCross`)、探測框/線段是否與其他筆畫相交 (`isCrossBox` / `isCrossBoxWithOthers` / `isCrossWithOthers`)。是明朝體微調啟發式（鱗、踵）的底層依賴。
- **`buhin.js`** — 極簡的「名稱 → 資料字串」雜湊表（`push`/`set`/`search`），代表可重複使用的「部品」（部首、常見字元件）。
- **`polygon.js`** — `Polygon`：一串有序點 `{x, y, off}`（`off=1` 代表 off-curve 控制點，模仿 TrueType），座標統一 floor 到小數點後一位。
- **`polygons.js`** — `Polygons`：多個 `Polygon` 的集合。
  - `push(polygon)` 會先驗證（拒絕退化、NaN、零面積、點數過少的多邊形）才加入；
  - `generateSVG(curve)` 輸出固定 `viewBox="0 0 200 200"` 的 SVG（`curve=true` 時用 `Q` 二次貝茲路徑指令，否則用純 `<polygon>`）；
  - `generateEPS()` 輸出 PostScript/EPS（含 `GlyphWiki powered by KAGE system` 的 Creator 字串）。

## 8. 沒有建置/測試工具——如何驗證修改

這個專案**沒有 `package.json`、沒有 npm、沒有 TypeScript、沒有 lint、沒有自動化測試**。程式是老派 ES3/ES5 風格：全部用 `var`、建構子函式 + `Foo.prototype.method = ...` 手動掛方法、沒有模組系統（不是 ESM 也不是 CommonJS），單純靠 `<script>` 標籤或 `load()` 的載入順序運作。

驗證修改是否正確的**唯一方式是視覺檢查**：跑 `sample.js`（SpiderMonkey/Rhino）或用瀏覽器開 `sample.html`，把範例字（目前硬編碼 `u6f22`=漢、`u9ebb`=麻）畫出來，肉眼比對筆畫外框有沒有缺口、破圖、曲線扭曲。這也解釋了為什麼 commit 訊息常常是「欠け点の発生を改善」（改善缺點問題）、「ゴシック体の出力を修正」（修正黑體輸出損壞）這類描述視覺缺陷、而非「測試失敗」的用詞。

```bash
# SpiderMonkey
js sample.js > result.svg

# Rhino
java -jar js.jar sample.js > result.svg
```

## 9. 近期開發脈絡（上游 `kamichikoichi/kage-engine` 的歷史）

- 大部分是**非常針對性的 bug 修正**，commit 訊息直接引用具體的筆畫類型編號與書法術語（八屋根=hachi-yane、乙=otsu、鱗=uroko、跳ね=hane、かかと=kakato）。
- 偶爾有**去重複化的重構**（例如把明朝/黑體兩邊重複的幾何程式碼、或 `kagecd.js`/`curve.js` 重複的貝茲計算整併）。
- 最重要的一次結構性修正是 PR #7「fix-gothic」（`128534e`）：把原本誤用在黑體上的明朝體專屬微調邏輯隔離開來，並補上黑體版的旋轉/鏡射、乙筆畫、複曲線支援。
- Commit 訊息幾乎全是日文、簡短，並假設讀者已熟悉 KAGE 的筆畫代碼詞彙（不會另外解釋）。

## 10. 讀懂這份程式碼需要的書法詞彙對照

| 日文/羅馬拼音 | 意思 |
|---|---|
| 明朝體 (Mincho) | 類似襯線體的漢字字型風格 |
| ゴシック體 (Gothic) | 類似無襯線體的漢字字型風格 |
| 鱗 (uroko) | 水平筆畫尾端的三角形裝飾（類似襯線） |
| 跳ね (hane) | 筆畫尾端的勾 |
| 曲がり (mage) | 筆畫轉折/彎曲處 |
| 切り口 (kirikuchi) | 斜切筆畫與其他筆畫的交叉處理 |
| 踵 (kakato) | 某些曲線筆畫收尾的「腳跟」形狀 |
| 乙 (otsu) | 一種 S 形轉折筆畫（如「乙」字的筆畫） |
| 八屋根 (hachi-yane) | 筆畫頭部類型 27 號的俗稱 |
| 部品 (buhin) | 可重複使用的字元組件/部首 |
