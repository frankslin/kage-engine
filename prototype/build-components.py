#!/usr/bin/env python3
"""從 GlyphWiki dump 生成 components.js（常用部件清單 + 字元對應）。

用法:
    python3 build-components.py <dump_newest_only.txt 路徑> [vt.json 路徑]

- dump 取自 https://glyphwiki.org/dump.tar.gz 內的 dump_newest_only.txt
- vt.json（可選）取自 char-components 專案 web/data/vt.json：
  單向異體映射表 {"變體": "正字", ...}，用來把「木」連到「朩/𣎳」等
  已驗證方向安全的異體字，供替換候選使用。

收錄規則：被其他字形以 99: 參照 ≥ MIN_REFS 次，排除個人空間（名稱含 _），
只保留 u+碼位 / cdp- / u2ff(IDS) 命名。輸出為 JS 檔（非 JSON），
讓 prototype/index.html 以 <script> 載入、file:// 雙擊也能用。
"""
import collections
import json
import re
import sys

MIN_REFS = 50

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    dump_path = sys.argv[1]
    vt_path = sys.argv[2] if len(sys.argv) > 2 else None

    ref_count = collections.Counter()
    names = set()
    with open(dump_path, encoding='utf-8', errors='replace') as f:
        for line in f:
            parts = line.split('|')
            if len(parts) < 3:
                continue
            name = parts[0].strip()
            data = parts[2].strip()
            if not name or name == 'name':
                continue
            names.add(name)
            for row in data.split('$'):
                cols = row.split(':')
                if len(cols) > 7 and cols[0] == '99' and cols[7]:
                    ref_count[cols[7]] += 1

    keep = re.compile(r'^(u[0-9a-f]{4,6}(-|$)|u2ff|cdp-)')
    used = [
        (n, c) for n, c in ref_count.items()
        if c >= MIN_REFS and n in names and '_' not in n and keep.match(n)
    ]
    used.sort(key=lambda x: -x[1])

    # 依「字元」歸戶：u6728-01 → 木。IDS(u2ff*) 與 cdp- 無單一字元，歸入 others
    chars = collections.defaultdict(list)
    others = []
    codepoint = re.compile(r'^u([0-9a-f]{4,6})(-.*)?$')
    for n, c in used:
        m = codepoint.match(n)
        if m and not n.startswith('u2ff'):
            chars[chr(int(m.group(1), 16))].append([n, c])
        else:
            others.append([n, c])

    out = {
        'minRefs': MIN_REFS,
        'total': len(used),
        'chars': dict(chars),   # 字元 → [[部件名, 被參照次數], ...] 按次數降冪
        'others': others,       # cdp-/IDS 等無單一字元者
    }

    if vt_path:
        vt = json.load(open(vt_path, encoding='utf-8'))
        vt_rev = collections.defaultdict(list)
        for variant, canonical in vt.items():
            vt_rev[canonical].append(variant)
        out['vt'] = vt            # 變體 → 正字
        out['vtRev'] = dict(vt_rev)  # 正字 → [變體...]

    with open('components.js', 'w', encoding='utf-8') as f:
        f.write('// 由 build-components.py 生成，資料來源見該腳本開頭註解\n')
        f.write('var GW_COMPONENTS = ')
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
        f.write(';\n')

    print(f'components.js: {len(used)} 個部件（{len(chars)} 個字元 + {len(others)} 個其他）'
          + (f'，vt 映射 {len(out["vt"])} 筆' if vt_path else ''))

if __name__ == '__main__':
    main()
