#!/usr/bin/env python3
"""Build the offline expansion from pinned, hash-verified MIT-licensed lexicons.

No generated combinations: every added answer has an upstream row. Downloads are
build-time only; the iOS app loads the checked-in TSV without network access.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import unicodedata
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
RESOURCE_DIR = ROOT / "Sources/Core/Resources"
HAN = re.compile(r"[\u4e00-\u9fff]{2,8}\Z")
ALLOWED_POS = {"n", "v", "a", "i", "l", "vn"}
TOTAL = 50_000


def key(word: str) -> str:
    return "".join(unicodedata.normalize("NFKC", word).split()).casefold()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=ROOT / "build/wordbank-upstream")
    parser.add_argument("--offline", action="store_true", help="Fail if a pinned source is missing")
    args = parser.parse_args()
    manifest = json.loads((ROOT / "scripts/wordbank_sources.json").read_text())
    rules = json.loads((ROOT / "scripts/wordbank_exclusions.json").read_text())
    exact = set(rules["exact"])
    fragments = tuple(rules["contains"])
    category_exclusions = rules["category_exclusions"]
    sources: dict[tuple[str, str], str] = {}
    for entry in manifest:
        path = args.source_dir / entry["source"] / entry["path"]
        if not path.exists():
            if args.offline:
                raise SystemExit(f"Missing pinned source: {path}")
            path.parent.mkdir(parents=True, exist_ok=True)
            request = Request(entry["url"], headers={"User-Agent": "TwoSides-wordbank-builder/1"})
            with urlopen(request, timeout=60) as response:
                data = response.read()
            if hashlib.sha256(data).hexdigest() != entry["sha256"]:
                raise SystemExit(f"Source hash mismatch: {entry['url']}")
            path.write_bytes(data)
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise SystemExit(f"Source hash mismatch: {path}")
        sources[(entry["source"], entry["path"])] = data.decode("utf-8-sig")

    classic_source = (ROOT / "Sources/Core/WordBank.swift").read_text()
    classic: dict[str, str] = {}
    for category, body in re.findall(r"\(\.(\w+),\s*\[(.*?)\]\)", classic_source, re.S):
        for word in re.findall(r'"([^"\n]+)"', body):
            classic[word] = category
    if len(classic) != 240:
        raise SystemExit(f"Expected 240 baseline words; found {len(classic)}. Update baseline parser explicitly.")
    seen = {key(word) for word in classic}
    added: list[tuple[str, str, str, int, str]] = []
    filtered = Counter()

    def acceptable(word: str) -> bool:
        return bool(HAN.fullmatch(word)) and word not in exact and not any(part in word for part in fragments)

    def add(word: str, category: str, source: str, frequency: int, pos: str = "") -> None:
        normalized = key(word)
        if not acceptable(word):
            filtered["format_or_exclusion"] += 1
        elif normalized in seen:
            filtered["duplicate"] += 1
        else:
            seen.add(normalized)
            added.append((category, word, source, frequency, pos))

    # Curated original categories take precedence; upstream themed lexicons follow.
    for upstream, category in [("animal", "animals"), ("food", "food"), ("chengyu", "idioms")]:
        source_path = f"data/THUOCL_{upstream}.txt"
        candidates = []
        for line in sources[("thuocl", source_path)].splitlines():
            parts = line.split()
            if len(parts) != 2 or not parts[1].isdigit():
                filtered["malformed_upstream"] += 1
                continue
            word, frequency = parts[0], int(parts[1])
            if frequency < 100:
                continue
            if word in category_exclusions.get(category, []):
                filtered["category_mismatch"] += 1
                continue
            candidates.append((word, frequency))
        for word, frequency in sorted(candidates, key=lambda row: (-row[1], row[0])):
            add(word, category, f"thuocl:{upstream}", frequency)

    candidates = []
    for line in sources[("jieba", "jieba/dict.txt")].splitlines():
        parts = line.split()
        if len(parts) != 3 or not parts[1].isdigit():
            filtered["malformed_upstream"] += 1
            continue
        word, frequency, pos = parts[0], int(parts[1]), parts[2]
        if pos in ALLOWED_POS and frequency >= 10 and acceptable(word):
            candidates.append((word, frequency, pos))
    for word, frequency, pos in sorted(candidates, key=lambda row: (-row[1], row[0], row[2])):
        if len(classic) + len(added) >= TOTAL:
            break
        add(word, "general", "jieba", frequency, pos)
    if len(classic) + len(added) != TOTAL:
        raise SystemExit(f"Not enough unique entries: {len(classic) + len(added)}")

    RESOURCE_DIR.mkdir(parents=True, exist_ok=True)
    data_dir = ROOT / "Data"
    data_dir.mkdir(exist_ok=True)
    tsv = "".join(f"{category}\t{word}\n" for category, word, *_ in added)
    (RESOURCE_DIR / "ExpandedWords.tsv").write_text(tsv, encoding="utf-8")
    provenance = "category\tanswer\tsource\tfrequency\tpos\n" + "".join(
        f"{category}\t{word}\t{source}\t{frequency}\t{pos}\n"
        for category, word, source, frequency, pos in added
    )
    (data_dir / "wordbank-provenance.tsv").write_text(provenance, encoding="utf-8")
    counts = Counter(classic.values()) + Counter(row[0] for row in added)
    report = {
        "total": TOTAL,
        "classic": len(classic),
        "expanded": len(added),
        "categories": dict(sorted(counts.items())),
        "sources": dict(sorted(Counter(row[2] for row in added).items())),
        "expanded_sha256": hashlib.sha256(tsv.encode()).hexdigest(),
        "source_manifest": "scripts/wordbank_sources.json",
        "filter_rules": "scripts/wordbank_exclusions.json",
        "filter_counts": dict(sorted(filtered.items())),
        "minimum_selected_jieba_frequency": min(row[3] for row in added if row[2] == "jieba"),
        "quality_note": "按格式、词性、频率和有限排除表初筛；尚未逐条人工审核，不保证全部易猜或分类准确。",
    }
    (data_dir / "wordbank-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    notices = f"""两面猜 · 词库来源与说明

内置 {TOTAL:,} 个不重复的词：原有 240 个基础词，加上 49,760 个扩展词。
所有词都可离线使用。扩展词来自真实词典条目，没有通过拼接组合凑数量。

来源
• jieba 中文分词词典，作者 Sun Junyi，MIT 许可证。
  https://github.com/fxsjy/jieba
• THUOCL 清华大学开放中文词库，作者 THUNLP，MIT 许可证。
  https://github.com/thunlp/THUOCL
  使用其动物、饮食、成语分类词表。

词条经过字数、词性、频率和有限排除表筛选，含生僻词、抽象词及专业词汇。
尚未逐条人工审核，也不代表每个词都适合比划；遇到不熟悉的词可以跳过。
上游类别标注也可能存在歧义。更适合日常暖场的原有词条仍保留在各自分类中。

抽词规则
每次开局只洗牌一次，整局内两队、多个回合都不会重复答案。
答对、跳过，以及已展示但未作答的词，都视为用过。
所选词全部用完时提前结束本局并保留比分。另开一局会重新洗牌，可能遇到以前玩过的词。
不把不同别称、繁简体或近义词当作同一个概念。

完整版本、哈希和筛选规则见项目 WORD_BANK.md 与 scripts/wordbank_sources.json。

第三方许可原文

jieba
{sources[("jieba", "LICENSE")].strip()}

THUOCL
{sources[("thuocl", "LICENSE")].strip()}
"""
    (RESOURCE_DIR / "WordSources.txt").write_text(notices, encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
