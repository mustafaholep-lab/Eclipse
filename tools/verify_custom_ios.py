"""Validate shipped localization and preserve the custom build's identity."""
import json
import plistlib
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
subprocess.run(['git', 'merge-base', '--is-ancestor', '1189cacac52da32656c3beb6f60103ce859c286b', 'HEAD'], cwd=root, check=True)
catalog = json.loads((root / 'Eclipse/Localizable.xcstrings').read_text(encoding='utf-8'))
# A printf conversion. The space flag is left out on purpose: literal text such
# as "85% apply" is not a format argument.
specifier = re.compile(r"%(?:(\d+)\$)?[-+#0']*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOcCfFeEgGaAsSp%])")
def argument_types(text):
    """Map each argument position to the type Foundation reads for it.

    Comparing sorted specifier lists is not enough: '%@ \u2026 %lld \u2026 %@' translated
    as '%@ \u2026 %@ \u2026 %lld' has the same specifiers, yet reads the Int64 argument as
    an object pointer and crashes. Reordered translations must use n$ positions.
    """
    types, sequential, styles = {}, 0, set()
    for match in specifier.finditer(text):
        position, length, conversion = match.groups()
        if conversion == '%':
            continue
        styles.add(bool(position))
        if position:
            index = int(position)
        else:
            sequential += 1
            index = sequential
        if conversion == '@':
            kind = 'object'
        elif conversion in 'cC':
            kind = 'character'
        elif conversion in 'dDiuUxXoO':
            kind = 'int64' if length in ('ll', 'l', 'q', 'z', 't', 'j') else 'int32'
        elif conversion in 'fFeEgGaA':
            kind = 'double'
        else:
            kind = conversion
        assert types.setdefault(index, kind) == kind, f'argument {index} is read as two types in {text!r}'
    assert len(styles) < 2, f'mixes positional and sequential arguments: {text!r}'
    return types
def units(value):
    if 'stringUnit' in value:
        yield value['stringUnit']
    for category in value.get('variations', {}).values():
        for variation in category.values():
            yield from units(variation)
def verify_catalog(path, data):
    for key, entry in data['strings'].items():
        assert 'tr' in entry.get('localizations', {}), key
        expected = argument_types(key)
        for unit in units(entry['localizations']['tr']):
            assert unit['state'] == 'translated', key
            assert '\ufffd' not in unit['value'], key
            actual = argument_types(unit['value'])
            assert actual == expected, f'{path}: {key!r} -> {unit["value"]!r} reads {actual}, key passes {expected}'
verify_catalog('Eclipse/Localizable.xcstrings', catalog)
verify_catalog('EclipseTV/Localizable.xcstrings', json.loads((root / 'EclipseTV/Localizable.xcstrings').read_text(encoding='utf-8')))
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
