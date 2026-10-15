"""Validate shipped localization and preserve the custom build's identity."""
import json
import plistlib
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
subprocess.run(['git', 'merge-base', '--is-ancestor', '1189cacac52da32656c3beb6f60103ce859c286b', 'HEAD'], cwd=root, check=True)
catalog = json.loads((root / 'Eclipse/Localizable.xcstrings').read_text(encoding='utf-8'))
pattern = re.compile(r'%(?:\d+\$)?(?:lld|ld|lu|zu|@|d|f|\.\d+f)')
def units(value):
    if 'stringUnit' in value:
        yield value['stringUnit']
    for category in value.get('variations', {}).values():
        for variation in category.values():
            yield from units(variation)
for key, entry in catalog['strings'].items():
    assert 'tr' in entry.get('localizations', {}), key
    for unit in units(entry['localizations']['tr']):
        assert unit['state'] == 'translated', key
        assert '\ufffd' not in unit['value'], key
        assert sorted(pattern.findall(key)) == sorted(pattern.findall(unit['value'])), key
info = plistlib.loads((root / 'Eclipse/Info.plist').read_bytes())
assert info['CADisableMinimumFrameDurationOnPhone'] is True
assert info['ECLIPSE_SYNC_SERVER_URL'] == '$(ECLIPSE_SYNC_SERVER_URL)'
assert 'audio' in info['UIBackgroundModes']
for name in ['EclipseSyncCoordinator', 'EclipseSyncTransport', 'EclipseSyncProtocol', 'EclipseSyncPlayerAdapter', 'PlaybackLifecycleRecoveryPolicy']:
    assert (root / f'Eclipse/Player/{name}.swift').is_file(), name
project = (root / 'Eclipse.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
source_phases = re.findall(r'isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);', project, re.S)
ios_sources = next(phase for phase in source_phases if 'SoraApp.swift in Sources' in phase)
for name in ['DisplayRefreshSettings', 'DownloadBackgroundExecution', 'HLSBackgroundTransport']:
    assert f'{name}.swift in Sources' in ios_sources, f'{name} missing from iOS target'
print(f'Custom Eclipse ancestry, Sync configuration, and {len(catalog["strings"])} Turkish catalog entries verified')
