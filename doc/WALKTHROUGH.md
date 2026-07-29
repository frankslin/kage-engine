# kage-engine 程式碼導覽（walkthrough）

> 本文件為 `kage-engine` 專案的中文導覽，協助理解程式碼的用途、架構與慣例。
> 初版 2026-07-26（當時引擎為上游的純 JS 版本）；2026-07-29 隨引擎改以
> `kurgm/kage-engine` 為基礎（TypeScript）全面改寫。

## 1. 這個專案是做什麼的

`kage-engine` 是 **KAGE 字形引擎**（原始出處：[fonts.jp/engine](http://fonts.jp/engine/)），
用途是：

> 把一串「筆畫資料字串」（描述一個漢字每一筆筆畫的類型、頭尾形狀、控制點座標）轉換成向量多邊形（polygon）輪廓，可以再輸出成 SVG、EPS，或直接畫到 HTML5 `<canvas>` 上。

換句話說，這是一個「**參數化生成漢字字形外框**」的引擎，用來畫出明朝體（Mincho，類似襯線字體）或黑體（Gothic，類似無襯線字體）風格的漢字筆畫，包括：

- 鱗（うろこ，horizontal 筆畫尾端的三角形裝飾，類似襯線）
- 跳ね（hane，勾）
- 曲がり（mage，轉折/彎曲）
- 切り口（kirikuchi，斜切筆畫交叉處）
- 踵（kakato，某些曲線筆畫的「腳跟」形狀）

這套引擎是 **GlyphWiki**（一個協作式漢字字形 wiki 網站）背後的渲染核心，EPS 輸出裡甚至直接寫死 `%%Creator: GlyphWiki powered by KAGE system`。

> **上游關係**：`kamichikoichi/kage-engine`（GlyphWiki 官方）→ `kurgm/kage-engine` → 本 repo。
> 本 repo 原本是官方上游的鏡像，2026-07-29 改為合併 `kurgm/kage-engine`——它包含官方上游
> 的全部歷史且零落後，官方 repo 自 2017 年起的外部 PR（#4/#5/#6/#7）皆出自 kurgm。
> 選型的實測依據見 [`AGENTS.md`](../AGENTS.md)。

## 2. 專案結構

TypeScript 原始碼在 `src/`，建置產物 `lib/`（ESM + CJS）與 `dist/`（瀏覽器 bundle）皆被 gitignore：

```
kage-engine/
├── src/
│   ├── index.ts          對外匯出：Kage / Polygons / Buhin / KShotai
│   ├── browser.ts        瀏覽器 bundle 的進入點（只 re-export default）
│   ├── kage.ts           Kage 類別：組字最上層邏輯（makeGlyph 系列、部品展開）
│   ├── stroke.ts         Stroke 類別：一筆筆畫的資料封裝（欄位解包、座標、相交判斷）
│   ├── pen.ts            Pen 類別：以「筆的位置＋朝向」把區域座標換算成全域座標
│   ├── curve.ts          貝茲曲線數學（分割、offset curve 搜尋、加粗曲線生成）
│   ├── util.ts           數值工具（貝茲取值/微分、三分搜尋、normalize、round）
│   ├── 2d.ts             2D 幾何（線段相交 isCross / isCrossBox）
│   ├── buhin.ts          「部品」名稱 → 資料字串 的登錄表
│   ├── polygon.ts        Polygon：單一封閉點列（含 on/off-curve 旗標）
│   ├── polygons.ts       Polygons：Polygon 集合 + SVG/EPS 序列化
│   └── font/
│       ├── index.ts      FontInterface、字體選擇（select）
│       ├── shotai.ts     KShotai 列舉（kMincho / kGothic）
│       ├── mincho/
│       │   ├── index.ts  Mincho 類別：字體參數、adjust* 微調啟發式、dfDrawFont 分派
│       │   └── cd.ts     明朝體的筆畫外框繪製器（cdDrawCurveU 等）
│       └── gothic/
│           ├── index.ts  Gothic 類別 + dfDrawFont 分派
│           └── cd.ts     黑體的筆畫外框繪製器
├── samples/              範例（sample.js 輸出 SVG、sample.html 瀏覽器版）
├── test/index.js         測試（`npm test`）
├── docs/                 typedoc 產生的 API 文件
├── prototype/            本 fork 的拼字法造字工具（見 prototype/README.md）
├── doc/                  本 fork 的中文文件
└── COPYING               GNU GPL v3
```

**沒有「載入順序」的概念了**——模組相依由 ESM `import` 表達，不再靠 `<script>` 標籤的先後。

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
- **欄位 1、2 (`a2`, `a3`)**：分別編碼「起筆」與「收筆」的形狀（鱗、跳ね、切り口……等），常常用 `+100`、`+1000`、`+10000` 疊加多個旗標。**這種「用十進位當作打包位元」的解包在新版集中在 `Stroke` 建構子**（`src/stroke.ts`），欄位被拆成具名屬性 `a2_100` / `a2_opt_1` / `a2_opt_2` / `a2_opt_3` 等，繪製端直接讀這些屬性，不再各自寫 `Math.floor((ta1 % 10000) / 1000)`。
- **其餘欄位**：最多 4 組 (x, y) 控制點座標；若欄位 0 是 `99`（部品參照），格式則變成 `x1:y1:x2:y2:部品名稱:sx:sy:sx2:sy2`，代表把該部件的座標框重新映射（縮放/平移/鏡射）到目前這個範圍內。

所有座標都落在 **0–200 x 0–200 的固定 em 方格**內。

完整的欄位編碼表另見 [`doc/KAGE資料格式.md`](./KAGE資料格式.md)。

## 4. 主要流程（從呼叫端角度）

```js
import { Kage, Polygons } from "@kurgm/kage-engine";  // 或 lib/esm/index.js

const kage = new Kage();
const polygons = new Polygons();

// 註冊部品（可以是完整字或子部件）
kage.kBuhin.push("u6f22", "99:150:0:9:12:73:200:u6c35-07:0:-10:50$99:0:0:54:10:190:199:u26c29-07");
kage.kBuhin.push("u6c35-07", "2:7:8:...$2:7:8:...");
kage.kBuhin.push("u26c29-07", "1:0:0:...$...");

// 生成字形
kage.makeGlyph(polygons, "u6f22");

// 輸出
console.log(polygons.generateSVG(false));
```

呼叫鏈：

1. **`Kage.makeGlyph(polygons, buhinName)`**（`src/kage.ts:106`）— 從 `kBuhin`（`Buhin` 實例）查出資料字串，交給 `makeGlyph2`。
2. **`makeGlyph2(polygons, data)`**（`src/kage.ts:124`）—
   a. 用 `getEachStrokes` 把資料字串解析成 `Stroke` 陣列（欄位 0 為 `99` 時會遞迴展開部品，見 `getEachStrokesOfBuhin`，內含座標映射 `Stroke.stretch()`）；
   b. 呼叫 `this.kFont.getDrawers(strokes)` 取得每筆筆畫的繪製函式，逐一套用到 `polygons`。
3. **`Mincho.getDrawers`**（`src/font/mincho/index.ts:356`）— 先跑 `adjustStrokes`（**明朝體專屬**，見第 5 節），再對每筆呼叫 `dfDrawFont`。
   黑體版在 `src/font/gothic/index.ts`，**不含任何 adjust\* 步驟**——兩種字體是各自獨立的類別，
   不再靠一個 `if (kShotai == kMincho)` 分支隔離（這是舊版 PR #7「fix-gothic」踩過的坑，
   新結構從型別層面就不會再犯）。
4. **`dfDrawFont`**（`src/font/mincho/index.ts:75`、`src/font/gothic/index.ts:10`）— 依筆畫種類（直線/曲線/複合/貝茲）決定要畫幾段、頭尾形狀怎麼配，委派給：
5. **`cdDrawLine` / `cdDrawCurve` / `cdDrawBezier`**（`src/font/*/cd.ts` 檔尾）— 都是 `cdDrawCurveU` 的薄包裝。
6. **`cdDrawCurveU`**（`src/font/mincho/cd.ts:8`，整個引擎最核心的函式）— 真正的「筆畫轉外框多邊形」演算法。新版把它拆成三段：
   - **`drawCurveHead`**（`cd.ts:279`）— 起筆形狀（切り口、細入り、屋根……）
   - **`drawCurveBody`**（`cd.ts:124`）— 筆身：沿中心線取樣，每點算垂直於行進方向的偏移量決定粗細
   - **`drawCurveTail`**（`cd.ts:390`）— 收筆形狀（鱗、跳ね、踵、止め……）

   若 `kage.kUseCurve` 開啟，筆身改用貝茲曲線擬合平滑（`src/curve.ts` 的 `find_offcurve`），否則用純折線。

另外還有 **`makeGlyph3(data)`**（`src/kage.ts:147`），回傳「每一筆畫各自一個 `Polygons`」的陣列，
方便逐筆檢視或做互動選取——`prototype/` 的部件點選就是靠它。
以及 **`makeGlyphSeparated(data)`**（`src/kage.ts:181`，kurgm 為 kage-editor 新增）。

### 4.1 `Pen`：新版最重要的抽象

舊版 `kagecd.js` 裡「水平時 / 垂直時 / 斜向時」三套幾乎相同的座標計算，在新版收斂成
**`Pen`**（`src/pen.ts`）：一支「筆」記住自己的位置 `(x, y)` 與朝向（`cos_theta`/`sin_theta`），
`setLeft` / `setRight` / `setUp` / `setDown` 用另一個點來設定朝向，
`getPoint(localX, localY)` / `getPolygon(localPoints)` 則把**以筆為原點的區域座標**換算成全域座標。

於是「在筆尖右側 `kMinWidthT`、前方 `kMage` 處放一個點」這種描述可以直接寫成區域座標，
不必為每個角度各寫一份三角函數。讀 `cd.ts` 時抓住這一點，大量看似複雜的座標運算就會變得直白。

## 5. 明朝體專屬的「筆畫微調」啟發式（`src/font/mincho/index.ts`）

這是這個引擎最「藝術」也最難懂的部分：一組會分析**同一個字裡筆畫之間的幾何關係**、
做出微調讓明朝體更像手寫書法的函式。它們是 `Mincho` 類別的 protected 方法，
黑體（`Gothic`）根本沒有這些方法：

- **`adjustHane`**（`index.ts:395`）— 偵測「跳ね」（勾）筆畫尾端若太靠近旁邊另一筆筆畫，就按比例縮小跳ね的突出程度。
- **`adjustMage`**（`index.ts:442`）— 轉折處太靠近其他筆畫時調整。
- **`adjustTate`**（`index.ts:483`）— 太靠近的直豎筆畫會加粗，避免視覺上顯得太細。
- **`adjustKakato`**（`index.ts:513`）— 依附近筆畫是否與探測框相交（`Stroke.isCrossBox`），調整某些曲線筆畫的「腳跟」形狀。
- **`adjustUroko` / `adjustUroko2`**（`index.ts:538`）— 依水平筆畫長度、以及是否有其他筆畫從旁「擠壓」（用距離加權的 pressure 概念）調整鱗的大小/角度。
- **`adjustKirikuchi`**（`index.ts:611`）— 偵測特定的「斜切線 vs 水平筆畫交叉」模式。

各步驟的調整量不再塞回筆畫類型編號（舊版把 `32` 改寫成 `132` 那種），而是掛在
`MinchoAdjustedStroke` 上的具名欄位（`tateAdjustment`、`haneAdjustment`、`urokoAdjustment`……），
一路傳到 `cdDrawCurveU` 的具名參數。**改這一塊時不要再去猜編號的十進位旗標**。

所有魔術數字常數（`kAdjustHaneLength`、`kAdjustUrokoX/Y/Length`、`kAdjustTateStep`、
`kAdjustMageStep`、`kAdjustKakatoRangeX/Y` 等）定義在 `Mincho.setSize()`（`index.ts:303`），
依傳入的 `size` 參數有兩套預設值（小尺寸/一般尺寸）。

## 6. 貝茲曲線數學（`src/curve.ts`、`src/util.ts`）

- **`divide_curve`**（`curve.ts:4`）— De Casteljau 式的曲線二分割，把一條貝茲曲線切成兩段。
- **`find_offcurve`**（`curve.ts:27`）— 找出能最佳擬合一串取樣點的單一二次貝茲控制點（誤差平方最小化，用 `util.ts` 的 `ternarySearchMin`）。
- **`generateFattenCurve`**（`curve.ts:53`）— 沿貝茲曲線中心線取樣，產生左右兩條「軌道」，之後串接成封閉 `Polygon`。
- **`util.ts`** — `quadraticBezier` / `cubicBezier` 及其微分、`ternarySearchMin/Max`、`normalize`、`round`。舊版散落在 `kagecd.js` 與 `curve.js` 的重複貝茲計算已整併於此。

## 7. 幾何基礎與資料結構

- **`src/2d.ts`** — 純幾何：線段是否相交 (`isCross`)、探測框與線段是否相交 (`isCrossBox`)。是明朝體微調啟發式（鱗、踵）的底層依賴。舊版的 `isCrossWithOthers` / `isCrossBoxWithOthers` 移到 `Stroke` 上成為方法。
- **`src/stroke.ts`** — `Stroke`：一筆筆畫的封裝。建構子解包欄位旗標；`getControlSegments()`、`isCross()`、`isCrossBox()`、`stretch()`、`getBox()`。
- **`src/buhin.ts`** — 「名稱 → 資料字串」的登錄表（`push`/`set`/`search`）。kurgm 另加了 `onMissing` callback：查不到的名稱可以攔截（預設 `null`，維持原本靜默回傳 `""` 的行為）——對本 fork 的造字工具很有用，可用來偵測缺件而不是默默畫出殘字。
- **`src/polygon.ts`** — `Polygon`：一串有序點 `{x, y, off}`（`off` 代表 off-curve 控制點，模仿 TrueType），座標統一 round 到小數點後一位。另有 `translate` / `reflectX` / `reflectY` / `rotate90|180|270`。
- **`src/polygons.ts`** — `Polygons`：多個 `Polygon` 的集合。
  - `push(polygon)` 會先驗證（拒絕退化、NaN、零面積、點數過少的多邊形）才加入；
  - `generateSVG(curve)` 輸出固定 `viewBox="0 0 200 200"` 的 SVG（`curve=true` 時用 `Q` 二次貝茲路徑指令，否則用純 `<polygon>`）；
  - `generateEPS()` 輸出 PostScript/EPS。

## 8. 如何驗證修改

現在**有**工具鏈了：

```bash
npm install
npm run build      # build:lib（tsc → lib/esm + lib/cjs）+ build:dist（rollup → dist/）
npm test           # test/index.js
npm run lint       # eslint
```

`npm test` 目前只跑 `test/index.js`：三個手寫字形逐點比對內嵌的多邊形座標。
它的範圍比看起來窄——實際只觸及 10 組筆畫類型／頭形／尾形組合，全為明朝體，
黑體從未渲染過；而且通過時靜默，`npm test` 的輸出看不出它跑過。

它只能回答「輸出有沒有變」，不能回答「字形對不對」。
改動 `src/font/**` 之後，`npm test` 通過**不代表**字形沒有畫壞，仍然必須**視覺檢查**：

```bash
node samples/sample.js > result.svg     # 需先 npm run build:lib
# 或用瀏覽器開 samples/sample.html
```

範例字硬編碼 `u6f22`（漢）。如果修改涉及特定筆畫類型，最好額外加一個包含該筆畫類型的字。

**更廣的回歸測試已提到上游**：一份 7,614 個 case 的矩陣測試（筆畫類型 × 頭形 × 尾形
× 四種幾何 × 明朝/黑體 × `kUseCurve`，比對指紋而非座標）見
[kurgm/kage-engine#19](https://github.com/kurgm/kage-engine/pull/19)。若被合併，
`git merge kurgm/master` 就會帶進來（見 `AGENTS.md` 的「跟進上游」）。
kurgm 自己另外維護了一套跨版本的輸出比對腳本
[`kage-engine-compare`](https://github.com/kurgm/kage-engine-compare)，做的是同一件事。

這也解釋了為什麼上游 commit 訊息常常是「欠け点の発生を改善」（改善缺點問題）、
「ゴシック体の出力を修正」這類描述視覺缺陷、而非「測試失敗」的用詞。

## 9. 開發脈絡

**官方上游（`kamichikoichi`）**：24 個 commit，大部分是**非常針對性的 bug 修正**，
commit 訊息直接引用具體的筆畫類型編號與書法術語（八屋根=hachi-yane、乙=otsu、鱗=uroko、
跳ね=hane、かかと=kakato），幾乎全是日文、簡短，假設讀者已熟悉 KAGE 的筆畫代碼詞彙。

**kurgm**：354 個 commit，持續維護中。除了整體 TypeScript 化與上述的去重複重構之外，
還做了官方上游沒有的：黑體支援筆畫類型 4（乙）與 6（複曲線）、黑體的旋轉/鏡射、
修正黑體有時缺左跳/上跳的 bug、`Mincho`/`Gothic` 類別拆分、`makeGlyphSeparated`、
雙格式打包（ESM + CJS）。重構過程中發現的一批「疑似 bug 但刻意不改」的行為
（怕影響非漢字字形）列在根目錄 `README.md` 的「改変したところ」一節，值得一讀。

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
