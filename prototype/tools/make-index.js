// features.tsv（index_subset.rs 的輸出）→ tegaki-index.js（頁面載入的索引）
//
// 量化成逐維尺度的 int8：實測 top-20 與 f32 重合 97.7%、top-1 相同 97/100，
// 而體積是 f32 的四分之一（base64+gzip 0.71 MB vs 3.84 MB）。用全域尺度只有
// 94/100，因為值域偏斜（多數維度在 0〜7，最大到 20.6），逐維才不浪費精度。
//
// 用法：node tools/make-index.js <features.tsv> > tegaki-index.js

// 根目錄的 package.json 是 "type": "module"，所以這裡用 ESM 寫法
import { readFileSync } from "node:fs";
import { Buffer } from "node:buffer";
import process from "node:process";

const path = process.argv[2];
if (!path) {
	process.stderr.write("Usage: node tools/make-index.js <features.tsv> > tegaki-index.js\n");
	process.exit(1);
}

const lines = readFileSync(path, "utf8").trim().split("\n");
const [version, dim] = lines[0].split(" ");
const D = Number(dim);
const N = lines.length - 1;

const names = [];
const f32 = new Float32Array(N * D);
for (let i = 0; i < N; i++) {
	const tab = lines[i + 1].indexOf("\t");
	names.push(lines[i + 1].slice(0, tab));
	const cells = lines[i + 1].slice(tab + 1).split(",");
	if (cells.length !== D) throw new Error(`${names[i]}: 維度 ${cells.length} ≠ ${D}`);
	for (let j = 0; j < D; j++) f32[i * D + j] = Number(cells[j]);
}

// 逐維尺度：以該維在整份索引裡的最大值對映到 127
const scale = new Float32Array(D);
for (let j = 0; j < D; j++) {
	let max = 0;
	for (let i = 0; i < N; i++) if (f32[i * D + j] > max) max = f32[i * D + j];
	scale[j] = (max || 1) / 127;
}
const q = new Int8Array(N * D);
for (let i = 0; i < N; i++) {
	for (let j = 0; j < D; j++) {
		const v = Math.round(f32[i * D + j] / scale[j]);
		q[i * D + j] = Math.max(-127, Math.min(127, v));
	}
}

const b64 = (typed) => Buffer.from(typed.buffer, typed.byteOffset, typed.byteLength).toString("base64");

process.stdout.write(
	"// 手寫搜尋的本地索引：由 build-tegaki-index.sh 產生，請勿手改。\n" +
	`// ${N} 個常用部件 × ${D} 維特徵，逐維尺度量化成 int8。\n` +
	"// 特徵函數與查詢端是同一個（vendor/gwtegaki 的 wasm），所以兩側自洽；\n" +
	"// v 必須等於 wasm 的 model_version()，對不上就代表索引該重建了。\n" +
	"var GWTEGAKI_INDEX = {\n" +
	`  v: ${JSON.stringify(version)},\n` +
	`  dim: ${D},\n` +
	`  count: ${N},\n` +
	`  names: ${JSON.stringify(names)},\n` +
	`  scale: ${JSON.stringify(b64(scale))},\n` +
	`  data: ${JSON.stringify(b64(q))}\n` +
	"};\n"
);

process.stderr.write(`${N} 條 × ${D} 維 → int8 ${(N * D / 1048576).toFixed(2)} MB\n`);
