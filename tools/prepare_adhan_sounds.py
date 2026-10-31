#!/usr/bin/env python3
"""Build offline opening-takbir clips for Android/iOS from the bundled sources.

Requires ffmpeg and ffprobe. Endpoints are pauses between phrases, not a hard
29-second cut. Run from any directory after changing a bundled recording.
"""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / 'android/app/src/main/res/raw'
IOS = ROOT / 'ios/Runner/Sounds'
# First source has been trimmed to remove its original 9 seconds of silence.
CLIPS = {'adhan1': (0, 17.8), 'adhan2': (0.15, 21.85), 'adhan4': (0.25, 23.25)}
for name, (start, duration) in CLIPS.items():
    source = RAW / f'{name}.mp3'
    for output, codec in [
        (RAW / f'{name}_short.mp3', ['-c:a', 'libmp3lame', '-b:a', '128k']),
        (IOS / f'{name}.caf', ['-c:a', 'pcm_s16le']),
    ]:
        subprocess.run([
            'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', str(start),
            '-i', str(source), '-t', str(duration), '-map_metadata', '-1',
            '-af', f'afade=t=out:st={duration - .2}:d=0.2',
            '-ar', '22050', '-ac', '1', *codec, str(output),
        ], check=True)
        probe = json.loads(subprocess.check_output([
            'ffprobe', '-v', 'error', '-show_format', '-of', 'json', str(output),
        ]))
        assert 0 < float(probe['format']['duration']) < 30, output
        print(f'{output.relative_to(ROOT)}: {probe["format"]["duration"]}s')
