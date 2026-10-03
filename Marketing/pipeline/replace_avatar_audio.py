#!/usr/bin/env python3
"""Replace an avatar demo's soundtrack with audio from Marketing/assets/audio."""

import argparse
import json
from pathlib import Path
import subprocess


def probe(path):
    return json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-show_format",
        "-of", "json", str(path),
    ]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("audio", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    audio_root = Path(__file__).resolve().parents[1] / "assets" / "audio"
    if not args.audio.resolve().is_relative_to(audio_root.resolve()):
        parser.error("Audio must come from Marketing/assets/audio/")
    if args.output.resolve() in (args.source.resolve(), args.audio.resolve()):
        parser.error("Output must not overwrite an input")
    video = next(s for s in probe(args.source)["streams"] if s["codec_type"] == "video")
    if not any(s["codec_type"] == "audio" for s in probe(args.audio)["streams"]):
        parser.error("Selected audio asset has no audio stream")
    duration = float(video["duration"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        "ffmpeg", "-n", "-v", "error", "-i", str(args.source),
        "-stream_loop", "-1", "-i", str(args.audio),
        "-map", "0:v:0", "-map", "1:a:0",
        "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
        "-af", (f"asetpts=PTS-STARTPTS,atrim=duration={duration:.6f},"
                f"afade=t=out:st={max(0, duration - 0.25):.6f}:d=0.25"),
        "-t", str(duration), "-map_metadata", "-1", "-map_chapters", "-1",
        "-movflags", "+faststart", str(args.output),
    ], check=True)
    result = probe(args.output)
    streams = result["streams"]
    if [s["codec_type"] for s in streams] != ["video", "audio"]:
        raise RuntimeError("Output must have exactly one video and one replacement audio stream")
    if abs(float(streams[0]["duration"]) - duration) > 0.001:
        raise RuntimeError("Video duration changed")
    if abs(float(result["format"]["duration"]) - duration) > 0.001:
        raise RuntimeError("Audio extends beyond the video")
    print(json.dumps({"output": str(args.output), "audio": str(args.audio),
                      "video_duration": duration, "original_audio_removed": True}))


if __name__ == "__main__":
    main()
