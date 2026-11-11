#!/usr/bin/env python3
"""Extract a compact RMS waveform from an audio source using ffmpeg."""

import array
import json
import math
import shutil
import subprocess
import sys
from urllib.parse import unquote, urlparse


SAMPLE_RATE = 4000
MIN_BUCKETS = 128
MAX_BUCKETS = 1024


def local_or_remote_source(value):
    parsed = urlparse(value)
    if parsed.scheme == "file":
        return unquote(parsed.path)
    return value


def get_duration(source):
    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            source,
        ],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    duration = float(result.stdout.strip())
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError("the audio duration could not be determined")
    return duration


def analyze(source):
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        raise RuntimeError("ffmpeg and ffprobe are required for audio waveforms")

    duration = get_duration(source)
    bucket_count = max(MIN_BUCKETS, min(MAX_BUCKETS, round(duration * 4)))
    estimated_samples = max(1, round(duration * SAMPLE_RATE))
    sums = [0.0] * bucket_count
    peaks = [0.0] * bucket_count
    counts = [0] * bucket_count

    process = subprocess.Popen(
        [
            "ffmpeg",
            "-v",
            "error",
            "-nostdin",
            "-i",
            source,
            "-vn",
            "-ac",
            "1",
            "-ar",
            str(SAMPLE_RATE),
            "-f",
            "s16le",
            "pipe:1",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )

    sample_index = 0
    remainder = b""
    try:
        while True:
            chunk = process.stdout.read(16384)
            if not chunk:
                break

            data = remainder + chunk
            if len(data) % 2:
                remainder = data[-1:]
                data = data[:-1]
            else:
                remainder = b""

            samples = array.array("h")
            samples.frombytes(data)
            if sys.byteorder != "little":
                samples.byteswap()

            for sample in samples:
                level = abs(sample) / 32768.0
                bucket = min(
                    bucket_count - 1,
                    sample_index * bucket_count // estimated_samples,
                )
                sums[bucket] += level * level
                peaks[bucket] = max(peaks[bucket], level)
                counts[bucket] += 1
                sample_index += 1
    finally:
        process.stdout.close()

    exit_code = process.wait()
    if exit_code != 0:
        raise RuntimeError("ffmpeg could not decode this audio source")
    if sample_index == 0:
        raise RuntimeError("ffmpeg returned no audio samples")

    levels = []
    for total, peak, count in zip(sums, peaks, counts):
        rms = math.sqrt(total / count) if count else 0.0
        levels.append(0.7 * rms + 0.3 * peak)

    maximum = max(levels) or 1.0
    normalized = [
        round(max(0.025, min(1.0, math.sqrt(level / maximum))), 4)
        for level in levels
    ]
    return {"duration": duration, "samples": normalized}


def main():
    if len(sys.argv) != 2 or not sys.argv[1].strip():
        print("an audio source path is required", file=sys.stderr)
        return 2

    source = local_or_remote_source(sys.argv[1].strip())
    try:
        result = analyze(source)
    except (OSError, ValueError, subprocess.SubprocessError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        return 1

    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
