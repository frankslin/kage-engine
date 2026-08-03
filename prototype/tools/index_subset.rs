//! 為指定的字形名清單算出 gwtegaki 特徵向量。
//!
//! 這支取代 gwtegaki 自己的 `build_index/src/main.rs`（它是掃全 dump、產 36 萬條），
//! 但**沿用同一份 `kage.rs`／`dump_reader.rs`**——也就是同一套「KAGE 資料 → 折線筆跡」
//! 的轉換與同一個 `strokes_to_feature_array`。索引側與查詢側共用特徵函數是關鍵：
//! 只要兩側一致，我們的向量表就自成一個空間，不需要跟上游後端的索引對齊。
//!
//! 用法（由 build-tegaki-index.sh 呼叫，不必手動跑）：
//!   cargo run --release -- <dump_newest_only.txt> <names.txt> > features.tsv
//!
//! names.txt 一行一個字形名；輸出每行是 `名稱\t逗號分隔的 f64`。
//! `99:` 參照要靠完整 dump 解，所以還是得讀整份 dump（約 332 MB）。

mod dump_reader;
mod glyph_name;
mod kage;

use std::io::{self, BufRead, Write};
use std::path::PathBuf;

use gwtegaki_model::{FEATURE_COLSIZE, MODEL_VERSION, strokes_to_feature_array};
use itertools::Itertools;

use crate::dump_reader::Dump;
use crate::kage::BuhinRecurser;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 3 {
        eprintln!("Usage: {} <dumpfilepath> <namesfilepath>", args[0]);
        std::process::exit(1);
    }
    if let Err(err) = run(PathBuf::from(&args[1]), PathBuf::from(&args[2])) {
        eprintln!("Application error: {}", err);
        std::process::exit(1);
    }
}

fn run(dumpfilepath: PathBuf, namesfilepath: PathBuf) -> Result<(), Box<dyn std::error::Error>> {
    eprintln!("reading dump...");
    let dump = Dump::read_from_file(&dumpfilepath)?;
    eprintln!("dump: {} glyphs", dump.len());

    let names: Vec<String> = io::BufReader::new(std::fs::File::open(&namesfilepath)?)
        .lines()
        .map_while(Result::ok)
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .collect();
    eprintln!("names: {}", names.len());

    let stdout = io::stdout();
    let mut out = io::BufWriter::new(stdout.lock());
    // 表頭：模型版本與維度，載入時要對版
    writeln!(&mut out, "{} {}", MODEL_VERSION, FEATURE_COLSIZE)?;

    let (mut ok, mut missing, mut empty, mut skipped) = (0usize, 0usize, 0usize, 0usize);
    for name in &names {
        // 沿用上游對「檢索對象」的定義：排除個人空間（含 `_`）、非漢字（我們的
        // 部件清單是按 `99:` 被參照次數統計的，會混進 u0020 空白這類東西）、hitsujun-
        if !glyph_name::is_target_glyph_name(name) {
            skipped += 1;
            continue;
        }
        let Some(data) = dump.get(name) else {
            eprintln!("missing in dump: {}", name);
            missing += 1;
            continue;
        };
        // 別名（單一 99: 全框參照）不特別處理——遞迴本來就會解開它
        let mut recurser = BuhinRecurser::new();
        let strokes = recurser.kage_data_to_strokes(data, &dump);
        if strokes.is_empty() {
            eprintln!("no strokes: {}", name);
            empty += 1;
            continue;
        }
        let feature = strokes_to_feature_array(&strokes);
        writeln!(&mut out, "{}\t{}", name, feature.iter().join(","))?;
        ok += 1;
    }
    out.flush()?;
    eprintln!(
        "done: {} ok, {} missing, {} empty, {} skipped (not a target glyph name)",
        ok, missing, empty, skipped
    );
    Ok(())
}
