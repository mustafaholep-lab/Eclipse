"""Validate translation completeness and format arguments without Apple SDKs."""
import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FORMAT = re.compile(r"%(?:\d+\$)?(?:lld|ld|lu|zu|@|d|f|\.\d+f)")


def units(entry):
    if "stringUnit" in entry:
        yield entry["stringUnit"]
    for variation in entry.get("variations", {}).values():
        for value in variation.values():
            yield from units(value)


def check_catalog(path, require_complete):
    catalog = json.loads(path.read_text(encoding="utf-8"))
    assert catalog["sourceLanguage"] == "en", path
    translated = 0
    for key, entry in catalog["strings"].items():
        translation = entry.get("localizations", {}).get("tr")
        if not translation:
            assert not require_complete, f"Missing Turkish: {key}"
            continue
        for unit in units(translation):
            assert unit["state"] == "translated", key
            value = unit["value"]
            assert "\ufffd" not in value, f"Invalid UTF-8 replacement: {key}"
            source_formats = sorted(FORMAT.findall(key))
            target_formats = sorted(FORMAT.findall(value))
            assert source_formats == target_formats, f"Format arguments changed: {key}"
        translated += 1
    print(f"{path.relative_to(ROOT)}: {translated} Turkish entries validated")


if __name__ == "__main__":
    check_catalog(ROOT / "Eclipse/Localizable.xcstrings", require_complete=True)
    check_catalog(ROOT / "EclipseTV/Localizable.xcstrings", require_complete=False)
    info = plistlib.loads((ROOT / "Eclipse/Info.plist").read_bytes())
    assert info["CADisableMinimumFrameDurationOnPhone"] is True
    assert "audio" in info["UIBackgroundModes"]
    print("iOS plist parsed; ProMotion and playback background modes validated")
