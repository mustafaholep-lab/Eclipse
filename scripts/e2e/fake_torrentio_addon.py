"""Local Stremio addon that mirrors Torrentio + TorBox stream responses.

The iPhone stream-flow UI test installs this addon, opens a movie, picks a
stream and starts playback against media files served from this process. The
stream entries copy the shape of real Torrentio responses (multi-line titles
with emoji, behaviorHints.filename/videoSize/bingeGroup, TorBox resolve URLs
that redirect to a CDN file) so the picker, labels and player see the same
kind of data as on a device. No real key or private link is involved.

Usage: python3 -I fake_torrentio_addon.py --port 8765 --media DIR --log FILE
"""

import argparse
import json
import os
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

IMDB_ID = "tt1375666"
FAKE_KEY = "e2e-not-a-real-key"

# (infoHash, media file served, Torrentio filename, display size, name line,
#  title line). Hashes are 40 hex chars like real Torrentio entries.
STREAMS = [
    ("2849211f150e966ef7924f43aec22727a644e10d", "h264-aac.mkv",
     "Inception.2010.PROPER.Bluray.2160p.AV1.HDR10.OPUS.5.1-UH.mkv", 9_567_000_000,
     "Torrentio\n4k HDR",
     "Inception 2010 PROPER Bluray 2160p AV1 HDR10 EN/ITA/FR/ES/DE OPUS 5.1-UH [UserHEVC]\n"
     "\U0001F464 293 \U0001F4BE 8.91 GB ⚙️ 1337x\n"
     "\U0001F1EC\U0001F1E7 / \U0001F1EE\U0001F1F9 / \U0001F1EA\U0001F1F8 / \U0001F1EB\U0001F1F7 / \U0001F1E9\U0001F1EA"),
    ("fa4a45aa220a6b0343817965a47d85f2d192e9b4", "h264-aac.mp4",
     "Inception (2010).mp4", 27_090_000_000,
     "Torrentio\n4k DV | HDR",
     "Inception 2010 UHD BluRay 2160p HDR10 DV HEVC DTS-HD MA 5.1 x265-E\n"
     "\U0001F464 45 \U0001F4BE 25.23 GB ⚙️ 1337x"),
    ("9625c8f0e88a8c120dd137b3e37357389f0fc4f3", "hevc-aac.mkv",
     "Начало.2010.UHD.Blu-Ray.Remux.2160p.[by arxivariys].mkv", 83_090_000_000,
     "Torrentio\n4k DV | HDR10+ | HDR",
     "Начало / Inception [2010 UHD BDRemux 2160p HDR10 HDR10+ Dolby Vision] "
     "[Hybrid] Dub + 3x DVO + Original (Eng) + Sub (Rus Ukr Eng)\n"
     "\U0001F464 43 \U0001F4BE 77.38 GB ⚙️ Rutracker\n"
     "\U0001F1EC\U0001F1E7 / \U0001F1F7\U0001F1FA / \U0001F1FA\U0001F1E6"),
    ("c3f1a9e2b7d84e6f9a0b1c2d3e4f5a6b7c8d9e0f", "h264-aac.avi",
     "Inception.2010.1080p.BluRay.x264.YIFY.avi", 1_890_000_000,
     "Torrentio\n1080p",
     "Inception.2010.1080p.BluRay.x264.YIFY\n"
     "\U0001F464 1204 \U0001F4BE 1.76 GB ⚙️ YTS"),
    ("d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8091a2b3c4d", "h264-aac.mp4",
     "Inception 2010 720p BRRip [Dual Audio] [Hindi-English].mp4", 1_100_000_000,
     "Torrentio\n720p",
     "Inception 2010 720p BRRip [Dual Audio] [Hindi-English]\n"
     "\U0001F464 88 \U0001F4BE 1.02 GB ⚙️ TorrentGalaxy\n"
     "Multi Audio"),
]

MEDIA_TYPES = {
    ".mp4": "video/mp4",
    ".mkv": "video/x-matroska",
    ".avi": "video/x-msvideo",
}


def manifest():
    return {
        "id": "org.eclipse.e2e.torrentio",
        "version": "0.0.1",
        "name": "Torrentio",
        "description": "Local Torrentio + TorBox shaped fixture for Eclipse UI tests",
        "resources": ["stream"],
        "types": ["movie", "series"],
        "idPrefixes": ["tt"],
        "catalogs": [],
        "behaviorHints": {"configurable": True, "configurationRequired": False},
    }


def streams(base):
    result = []
    for info_hash, _media, filename, size, name, title in STREAMS:
        result.append({
            "name": name,
            "title": title,
            "url": f"{base}/resolve/torbox/{FAKE_KEY}/{info_hash}/null/0/{filename}",
            "behaviorHints": {
                "bingeGroup": "torrentio|" + name.split("\n", 1)[-1].replace(" ", ""),
                "filename": filename,
                "videoSize": size,
            },
        })
    return {"streams": result}


class Handler(BaseHTTPRequestHandler):
    server_version = "EclipseE2EAddon/1"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        line = "%s %s\n" % (self.log_date_time_string(), fmt % args)
        with self.server.log_lock:
            self.server.log_file.write(line)
            self.server.log_file.flush()

    def _send_json(self, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _not_found(self):
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = unquote(urlparse(self.path).path)
        base = f"http://127.0.0.1:{self.server.server_address[1]}"
        if path == "/manifest.json":
            return self._send_json(manifest())
        if re.fullmatch(rf"/stream/movie/{IMDB_ID}(?::[^/]*)?\.json", path):
            return self._send_json(streams(base))
        if path.startswith("/stream/"):
            return self._send_json({"streams": []})
        match = re.fullmatch(r"/resolve/torbox/[^/]+/([0-9a-f]{40})/null/\d+/.+", path)
        if match:
            media = next((s[1] for s in STREAMS if s[0] == match.group(1)), None)
            if media is None:
                return self._not_found()
            # TorBox resolve links answer with a redirect to the CDN file.
            self.send_response(302)
            self.send_header("Location", f"{base}/dld/{media}")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if path.startswith("/dld/"):
            return self._send_media(os.path.basename(path))
        return self._not_found()

    def _send_media(self, name):
        file_path = os.path.join(self.server.media_dir, name)
        if not os.path.isfile(file_path):
            return self._not_found()
        size = os.path.getsize(file_path)
        start, end = 0, size - 1
        status = 200
        header = self.headers.get("Range")
        if header:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", header.strip())
            if not match or (match.group(1) == "" and match.group(2) == ""):
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if match.group(1) == "":
                start = max(0, size - int(match.group(2)))
            else:
                start = int(match.group(1))
                if match.group(2):
                    end = min(end, int(match.group(2)))
            if start > end or start >= size:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            status = 206
        length = end - start + 1
        self.send_response(status)
        self.send_header("Content-Type", MEDIA_TYPES.get(os.path.splitext(name)[1], "application/octet-stream"))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if self.command == "HEAD":
            return
        with open(file_path, "rb") as handle:
            handle.seek(start)
            remaining = length
            try:
                while remaining > 0:
                    chunk = handle.read(min(256 * 1024, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--media", required=True)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()
    missing = sorted({s[1] for s in STREAMS} - set(os.listdir(args.media)))
    if missing:
        sys.exit(f"missing fixture media: {', '.join(missing)}")
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.daemon_threads = True
    server.media_dir = args.media
    server.log_lock = threading.Lock()
    server.log_file = open(args.log, "a", encoding="utf-8")
    print(f"fake Torrentio addon on http://127.0.0.1:{args.port}/manifest.json", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
