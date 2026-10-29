#!/usr/bin/env python3
"""
Mishkat Mushaf Layout Metadata Extractor (Phase Q2)

Extracts Ayah layout and geometry metadata from the 604 SVG Mushaf pages
into a compact, deterministic JSON asset for sub-millisecond runtime hit-testing.

Validation guarantees:
- 604 pages (1..604)
- 6,236 Ayahs (1..6236)
- 11,386 segments (11,378 axis-aligned rectangles, 8 polygon segments on pages 1-2)
- 100% agreement with assets/data/quran.json (surah and ayah numbers)
- 100% agreement with assets/data/hafs-kfqc-manifest.json (page numbers)
- ViewBox boundary containment
- Exactly one source Ayah-number center within every Ayah's geometry
"""

import glob
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '../..'))
SVG_DIR = os.path.join(BASE_DIR, 'assets/mushaf/pages')
QURAN_JSON_PATH = os.path.join(BASE_DIR, 'assets/data/quran.json')
MANIFEST_JSON_PATH = os.path.join(BASE_DIR, 'assets/data/hafs-kfqc-manifest.json')
OUTPUT_JSON_PATH = os.path.join(BASE_DIR, 'assets/data/mushaf-layout.json')


def clean_num(n):
    """Format float cleanly: drop unnecessary trailing .0 if integer."""
    rounded = round(float(n), 4)
    if rounded == int(rounded):
        return int(rounded)
    # round to 2 decimal places if 2 decimals is enough
    r2 = round(rounded, 2)
    if abs(rounded - r2) < 1e-5:
        return int(r2) if r2 == int(r2) else r2
    return rounded


def parse_subpaths(d_str):
    """Splits SVG path 'd' attribute by Z/z into subpaths."""
    return [s.strip() for s in re.split(r'[Zz]', d_str) if s.strip()]


def parse_coords(subpath_str):
    """Extracts numeric coordinates from a subpath."""
    raw_nums = re.findall(r'[-+]?(?:\d*\.\d+|\d+)', subpath_str)
    coords = [clean_num(x) for x in raw_nums]
    return coords


def polygon_contains(coords, x, y):
    """Ray-cast in SVG viewBox coordinates, including concave opening-page paths."""
    points = list(zip(coords[0::2], coords[1::2]))
    inside = False
    for i, (x1, y1) in enumerate(points):
        x2, y2 = points[i - 1]
        if ((y1 > y) != (y2 > y)
                and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1):
            inside = not inside
    return inside


def ayah_contains(ayah, point):
    x, y = point
    return (any(left <= x <= right and top <= y <= bottom
                for left, top, right, bottom in ayah['r'])
            or any(polygon_contains(poly, x, y) for poly in ayah.get('p', [])))


def main():
    print("=" * 60)
    print("Mishkat Mushaf Layout Metadata Extraction — Phase Q2")
    print("=" * 60)

    # 1. Load Quran and Manifest for cross-validation
    with open(QURAN_JSON_PATH, 'r', encoding='utf-8') as f:
        quran_data = json.load(f)
    with open(MANIFEST_JSON_PATH, 'r', encoding='utf-8') as f:
        manifest_data = json.load(f)

    expected_verse_pages = manifest_data.get('versePages', [])
    assert len(expected_verse_pages) == 6236, f"Expected 6236 versePages, got {len(expected_verse_pages)}"

    expected_quran_verses = {}
    g = 1
    for surah_obj in quran_data.get('surahs', []):
        s_num = surah_obj['n']
        ayahs = surah_obj['ayahs']
        for a_idx in range(1, len(ayahs) + 1):
            expected_quran_verses[g] = (s_num, a_idx)
            g += 1
    assert len(expected_quran_verses) == 6236, f"Expected 6236 quran verses, got {len(expected_quran_verses)}"

    # 2. Extract SVG metadata page by page
    pages_output = []
    global_ayah_seen = {}
    total_segments = 0
    total_rects = 0
    total_polys = 0

    for page_num in range(1, 605):
        svg_filename = f"{page_num:03d}.svg"
        svg_path = os.path.join(SVG_DIR, svg_filename)
        if not os.path.isfile(svg_path):
            print(f"ERROR: Missing SVG file {svg_path}")
            sys.exit(1)

        tree = ET.parse(svg_path)
        root = tree.getroot()
        vb_raw = root.attrib.get('viewBox', '')
        if not vb_raw:
            print(f"ERROR: Page {page_num} missing viewBox")
            sys.exit(1)

        vb_parts = [clean_num(x) for x in vb_raw.split()]
        vx, vy, vw, vh = vb_parts
        v_right = vx + vw
        v_bottom = vy + vh

        page_ayahs = []

        for elem in root.iter():
            cls = elem.attrib.get('class', '')
            elem_id = elem.attrib.get('id', '')
            if 'ayahPolygon' in cls or elem_id.startswith('verse-'):
                gid_str = elem_id.replace('verse-', '')
                if not gid_str.isdigit():
                    continue
                gid = int(gid_str)
                surah = int(elem.attrib.get('surah'))
                ayah = int(elem.attrib.get('ayah'))

                # Cross-validation with manifest & quran.json
                expected_page = expected_verse_pages[gid - 1]
                if expected_page != page_num:
                    print(f"ERROR: Verse {gid} on page {page_num}, expected {expected_page} in manifest!")
                    sys.exit(1)

                exp_s, exp_a = expected_quran_verses[gid]
                if (surah, ayah) != (exp_s, exp_a):
                    print(f"ERROR: Verse {gid} has (surah={surah}, ayah={ayah}), expected ({exp_s}, {exp_a}) in quran.json!")
                    sys.exit(1)

                if gid in global_ayah_seen:
                    print(f"ERROR: Duplicate verse {gid} found on page {page_num} and {global_ayah_seen[gid]}!")
                    sys.exit(1)
                global_ayah_seen[gid] = page_num

                d_str = elem.attrib.get('d', '')
                subpaths = parse_subpaths(d_str)

                rects = []
                polys = []
                all_xs = []
                all_ys = []

                for sp in subpaths:
                    coords = parse_coords(sp)
                    pts = list(zip(coords[0::2], coords[1::2]))
                    xs = [p[0] for p in pts]
                    ys = [p[1] for p in pts]
                    all_xs.extend(xs)
                    all_ys.extend(ys)

                    total_segments += 1

                    # Check for axis-aligned rectangle
                    is_rect = (len(pts) == 4 and len(set(xs)) == 2 and len(set(ys)) == 2)
                    if is_rect:
                        min_x, max_x = min(xs), max(xs)
                        min_y, max_y = min(ys), max(ys)
                        rects.append([clean_num(min_x), clean_num(min_y), clean_num(max_x), clean_num(max_y)])
                        total_rects += 1
                    else:
                        polys.append(coords)
                        total_polys += 1

                # Bounds check against viewBox
                min_ax, max_ax = min(all_xs), max(all_xs)
                min_ay, max_ay = min(all_ys), max(all_ys)
                if min_ax < vx - 0.5 or max_ax > v_right + 0.5 or min_ay < vy - 0.5 or max_ay > v_bottom + 0.5:
                    print(f"ERROR: Verse {gid} on page {page_num} exceeds viewBox [{vx}, {vy}, {vw}, {vh}]: [{min_ax}, {min_ay}, {max_ax}, {max_ay}]")
                    sys.exit(1)

                ayah_dict = {
                    'g': gid,
                    's': surah,
                    'a': ayah,
                    'b': [clean_num(min_ax), clean_num(min_ay), clean_num(max_ax), clean_num(max_ay)],
                    'r': rects
                }
                if polys:
                    ayah_dict['p'] = polys

                page_ayahs.append(ayah_dict)

        # Sort ayahs strictly by globalAyah
        page_ayahs.sort(key=lambda x: x['g'])

        # SVG digits carry exact medallion centers in viewBox coordinates.
        # Use containment, since marker XML order is reversed on some pages.
        namespace = '{https://quranpedia.net}'
        centers = [
            (clean_num(elem.get(namespace + 'x')),
             clean_num(elem.get(namespace + 'y')))
            for elem in root.iter()
            if elem.get(namespace + 'x') is not None
            and elem.get(namespace + 'y') is not None
        ]
        assert len(centers) == len(page_ayahs), f'Number count mismatch on page {page_num}'
        assigned = set()
        for ayah in page_ayahs:
            matches = [center for center in centers if ayah_contains(ayah, center)]
            assert len(matches) == 1, f"Ambiguous/missing number for Ayah {ayah['g']}: {matches}"
            center = matches[0]
            assert center not in assigned, f'Duplicate number center on page {page_num}'
            assigned.add(center)
            ayah['n'] = list(center)

        pages_output.append({
            'p': page_num,
            'vb': vb_parts,
            'ay': page_ayahs
        })

    # 3. Overall sanity verification
    print(f"Extracted {len(pages_output)} pages.")
    print(f"Extracted {len(global_ayah_seen)} unique global Ayahs.")
    print(f"Total segments: {total_segments} ({total_rects} rects, {total_polys} polys).")

    assert len(pages_output) == 604, f"Expected 604 pages, got {len(pages_output)}"
    assert len(global_ayah_seen) == 6236, f"Expected 6236 Ayahs, got {len(global_ayah_seen)}"
    assert total_segments == 11386, f"Expected 11,386 segments, got {total_segments}"
    assert total_rects == 11378, f"Expected 11,378 rects, got {total_rects}"
    assert total_polys == 8, f"Expected 8 polys, got {total_polys}"

    # Verify no gap in globalAyah 1..6236
    for i in range(1, 6237):
        if i not in global_ayah_seen:
            print(f"ERROR: Global Ayah {i} missing from extraction!")
            sys.exit(1)

    # 4. Write output JSON
    output_data = {
        'version': 1,
        'coordinateSystem': 'svg_viewbox',
        'totalPages': len(pages_output),
        'totalAyahs': len(global_ayah_seen),
        'totalSegments': total_segments,
        'totalRectSegments': total_rects,
        'totalPolySegments': total_polys,
        'pages': pages_output
    }

    output_str = json.dumps(output_data, separators=(',', ':'), ensure_ascii=False)
    with open(OUTPUT_JSON_PATH, 'w', encoding='utf-8') as f:
        f.write(output_str)

    size_kb = len(output_str.encode('utf-8')) / 1024
    print(f"Successfully generated {OUTPUT_JSON_PATH}")
    print(f"JSON file size: {size_kb:.2f} KB")
    print("=" * 60)
    print("EXTRACTION COMPLETE & VERIFIED!")
    print("=" * 60)


if __name__ == '__main__':
    main()
