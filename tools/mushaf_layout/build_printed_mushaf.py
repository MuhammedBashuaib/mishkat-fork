#!/usr/bin/env python3
"""Build a verified, offline Madinah line map from the QUL SQLite exports.

Usage:
  python3 tools/mushaf_layout/build_printed_mushaf.py \
    --words-db /path/qpc-hafs-word-by-word.db \
    --layout-db /path/qpc-v2-15-lines.db

No network access is performed. The source IDs include verse end markers, so
their printed positions are preserved instead of inferred from verse lengths.
The application's canonical text and recitation word indices are not changed.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import sqlite3


ROOT = Path(__file__).resolve().parents[2]
COMMIT = "dad9cf67588ab66c914c155924d8a3699704a03d"
SOURCE_BASE = (
    "https://media.githubusercontent.com/media/manaf/"
    f"KFGQPC-Madinah-Mushaf/{COMMIT}/qul-data/"
)
SOURCE_HASHES = {
    "words": "e1cf266ed47a56e58100c08f69499f635f84c97233318cc53daf17200fb9048e",
    "layout": "e4df98f35dd3b8927ff096337c8739e0f0b12c8ba622834c345eaa4c3e28dd8c",
}
ARABIC_LETTER = re.compile(r"[ء-يٱ-ۓۺ-ۿ]")
MARKS = re.compile(
    r"[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u08D3-\u08FF\u0640]"
)
IGNORABLE = re.compile(r"[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF\s]")
TRANSLATION = str.maketrans("أإآٱٲٳٵىئیؤةک", "ااااااايييوهك")

# These are drawing-script differences, not acceptable ASR spelling changes.
# Exact location AND both original spellings must match; no fuzzy matching is
# used in the corpus import. Ordinals here are zero based.
ORTHOGRAPHY = {
    (2, 72, 3): ("فَٱدَّٰرَْٰٔتُمْ", "فَٱدَّٰرَٰءۡتُمۡ"),
    (12, 39, 0): ("يَٰصَىٰحِبَىِ", "يَٰصَٰحِبَيِ"),
    (12, 41, 0): ("يَٰصَىٰحِبَىِ", "يَٰصَٰحِبَيِ"),
}
EXPECTED_SPLITS = {(2, 181, 2), (8, 6, 3), (13, 37, 7)}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def normalized(text: str) -> str:
    """The existing QuranRecitationText.normalize orthographic equivalence."""
    text = re.sub(r"[ﻵﻶﻷﻸﻹﻺﻻﻼ]", "لا", text)
    return IGNORABLE.sub("", MARKS.sub("", text).replace("ءا", "ا").translate(TRANSLATION))


def arabic_number(number: int) -> str:
    return str(number).translate(str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩"))


def open_verified(path: Path, expected_hash: str) -> sqlite3.Connection:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    require(digest == expected_hash, f"Unexpected SQLite source: {path} ({digest})")
    db = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    return db


def build(words_path: Path, layout_path: Path, quran_path: Path, geometry_path: Path) -> dict:
    quran = json.loads(quran_path.read_text())
    geometry = json.loads(geometry_path.read_text())
    canonical: dict[tuple[int, int], tuple[int, list[str]]] = {}
    for surah in quran["surahs"]:
        for offset, text in enumerate(surah["ayahs"]):
            canonical[(surah["n"], offset + 1)] = (
                surah["start"] + offset,
                [part for part in text.split() if ARABIC_LETTER.search(part)],
            )
    require(len(canonical) == 6236, "Canonical verse count changed")
    canonical_count = sum(len(words) for _, words in canonical.values())
    require(canonical_count == 77430, "Canonical word count changed")
    verse_pages = {
        verse["g"]: page["p"] for page in geometry["pages"] for verse in page["ay"]
    }
    require(len(verse_pages) == 6236, "Canonical page boundaries are incomplete")

    words_db = open_verified(words_path, SOURCE_HASHES["words"])
    layout_db = open_verified(layout_path, SOURCE_HASHES["layout"])
    try:
        source_rows = list(words_db.execute("SELECT * FROM words ORDER BY id"))
        line_rows = list(layout_db.execute("SELECT * FROM pages ORDER BY page_number,line_number"))
        info = dict(layout_db.execute("SELECT * FROM info").fetchone())
    finally:
        words_db.close()
        layout_db.close()
    require(info["number_of_pages"] == 604 and info["lines_per_page"] == 15, "Unexpected printed edition")
    require([row["id"] for row in source_rows] == list(range(1, 83669)), "Source IDs are incomplete")
    by_verse: dict[tuple[int, int], list] = defaultdict(list)
    for row in source_rows:
        by_verse[(row["surah"], row["ayah"])].append(row)
    require(set(by_verse) == set(canonical), "Source verse set differs from the canonical text")

    mapped: dict[int, list[list]] = defaultdict(list)
    split_locations = set()
    joined_locations = set()
    orthography_locations = set()
    for location, source in by_verse.items():
        surah, ayah = location
        global_ayah, words = canonical[location]
        require([r["word"] for r in source] == list(range(1, len(source) + 1)), f"Broken source ordinals at {location}")
        marker = source[-1]
        require(marker["text"] == arabic_number(ayah), f"Missing verse end marker at {location}")
        mapped[marker["id"]] = [[global_ayah, -1, marker["text"], 1, ayah]]
        parts = []
        for row in source[:-1]:
            text = row["text"]
            lexical_parts = [part for part in text.split() if ARABIC_LETTER.search(part)]
            require(lexical_parts, f"Unexpected non-word {row['location']}")
            if len(lexical_parts) > 1:
                # The QUL token إِلۡ يَاسِينَ contains two canonical words. Both
                # remain on the same source line but reveal independently.
                require((surah, ayah, row["word"]) == (37, 130, 3), "Unexpected joined source token")
                require(text == "إِلۡ يَاسِينَ", "Changed joined source spelling")
                joined_locations.add((surah, ayah, row["word"]))
                parts.extend((row["id"], part) for part in lexical_parts)
            else:
                # Keep attached pause and rub-el-hizb marks with their word.
                parts.append((row["id"], text))
        cursor = 0
        for ordinal, word in enumerate(words):
            require(cursor < len(parts), f"Too few printed words at {location}:{ordinal}")
            source_id, printed = parts[cursor]
            exact_location = (surah, ayah, ordinal)
            same = normalized(word) == normalized(printed)
            if not same and ORTHOGRAPHY.get(exact_location) == (word, printed):
                orthography_locations.add(exact_location)
                same = True
            if same:
                mapped[source_id].append([global_ayah, ordinal, printed, 0, ayah])
                cursor += 1
                continue
            if cursor + 1 < len(parts) and normalized(word) == normalized(printed + parts[cursor + 1][1]):
                require(exact_location in EXPECTED_SPLITS, f"Unexpected split canonical word at {exact_location}")
                split_locations.add(exact_location)
                for source_id, printed in parts[cursor:cursor + 2]:
                    mapped[source_id].append([global_ayah, ordinal, printed, 0, ayah])
                cursor += 2
                continue
            raise ValueError(f"Word mismatch at {surah}:{ayah}:{ordinal + 1}: {word!r} / {printed!r}")
        require(cursor == len(parts), f"Unmapped printed words at {location}")
    require(split_locations == EXPECTED_SPLITS, "Canonical split mappings changed")
    require(joined_locations == {(37, 130, 3)}, "Joined source mapping changed")
    require(orthography_locations == set(ORTHOGRAPHY), "Script differences changed")
    require(set(mapped) == set(range(1, 83669)), "Some source tokens were not mapped")

    pages = [{"p": page, "l": []} for page in range(1, 605)]
    seen_ids = set()
    seen_words = set()
    seen_markers = set()
    painted_count = 0
    current_surah = None
    for row in line_rows:
        page, line = row["page_number"], row["line_number"]
        require(1 <= page <= 604 and 1 <= line <= 15, "Invalid page/line")
        kind = {"ayah": 0, "surah_name": 1, "basmallah": 2}[row["line_type"]]
        if kind == 1:
            current_surah = int(row["surah_number"])
        content = []
        if kind == 0:
            first, last = int(row["first_word_id"]), int(row["last_word_id"])
            require(first <= last, f"Empty printed line {page}:{line}")
            for source_id in range(first, last + 1):
                require(source_id not in seen_ids, f"Repeated source token {source_id}")
                seen_ids.add(source_id)
                for word in mapped[source_id]:
                    global_ayah, ordinal, _, marker, _ = word
                    require(verse_pages[global_ayah] == page, f"Page boundary mismatch for verse {global_ayah}: {page}/{verse_pages[global_ayah]}")
                    if marker:
                        require(global_ayah not in seen_markers, "Duplicate verse marker")
                        seen_markers.add(global_ayah)
                    else:
                        painted_count += 1
                        seen_words.add((global_ayah, ordinal))
                    content.append(word)
        pages[page - 1]["l"].append({"n": line, "k": kind, "s": current_surah, "c": int(row["is_centered"]), "w": content})
    require(seen_ids == set(mapped), "Some words are missing from printed pages")
    require(len(seen_words) == canonical_count, "Canonical word coverage is incomplete")
    require(len(seen_markers) == 6236, "Verse end marker coverage is incomplete")
    require(painted_count == 77433, "Unexpected number of printed word parts")
    for page in pages:
        expected_lines = 8 if page["p"] <= 2 else 15
        require([line["n"] for line in page["l"]] == list(range(1, expected_lines + 1)), f"Printed lines incomplete on page {page['p']}")
    return {
        "version": 1,
        "edition": "QCF V2 (1421H print), QPC Hafs Unicode",
        "canonicalWordCount": canonical_count,
        "sourceWordCount": 77432,
        "printedWordCount": painted_count,
        "sources": {
            "layout": {"url": SOURCE_BASE + "qpc-v2-15-lines.db.zip", "sqliteSha256": SOURCE_HASHES["layout"]},
            "words": {"url": SOURCE_BASE + "qpc-hafs-word-by-word.db.zip", "sqliteSha256": SOURCE_HASHES["words"]},
        },
        "mappingNotes": {
            "canonicalWordPrintedInTwoParts": [[s, a, n] for s, a, n in sorted(split_locations)],
            "sourceTokenPrintedAsTwoCanonicalWords": [[37, 130, 3]],
            "exactOrthographyExceptions": [
                {"location": list(key), "canonical": texts[0], "printed": texts[1]}
                for key, texts in sorted(ORTHOGRAPHY.items())
            ],
        },
        "pages": pages,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--words-db", type=Path, required=True)
    parser.add_argument("--layout-db", type=Path, required=True)
    parser.add_argument("--quran", type=Path, default=ROOT / "assets/data/quran.json")
    parser.add_argument("--geometry", type=Path, default=ROOT / "assets/data/mushaf-layout.json")
    parser.add_argument("--output", type=Path, default=ROOT / "assets/data/printed-mushaf.json")
    args = parser.parse_args()
    data = build(args.words_db, args.layout_db, args.quran, args.geometry)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"Verified 604 pages, 6236 ayahs, {data['canonicalWordCount']} canonical words, {data['printedWordCount']} printed parts; wrote {args.output.stat().st_size} bytes.")


if __name__ == "__main__":
    main()
