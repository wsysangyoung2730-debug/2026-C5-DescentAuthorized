"""Verify release metadata in an actual app bundle, not only build settings."""
import argparse
import plistlib
from pathlib import Path


def validate(app):
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    privacy = plistlib.loads((app / 'PrivacyInfo.xcprivacy').read_bytes())
    reasons = {x['NSPrivacyAccessedAPIType']: x['NSPrivacyAccessedAPITypeReasons']
               for x in privacy['NSPrivacyAccessedAPITypes']}
    checks = {
        'Korean bundle language': info.get('CFBundleDevelopmentRegion') == 'ko',
        'iPad only': info.get('UIDeviceFamily') == [2],
        'Legacy fullscreen': info.get('UIRequiresFullScreen') is True,
        'Modern window support': info.get('UIRequiresFullScreenIgnoredStartingWithVersion') == '26.0',
        'Single shared game session': info.get('UIApplicationSceneManifest', {}).get('UIApplicationSupportsMultipleScenes') is False,
        'Four iPad orientations': set(info.get('UISupportedInterfaceOrientations~ipad', [])) == {
            'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
            'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'},
        'Elapsed-time API reason': reasons.get('NSPrivacyAccessedAPICategorySystemBootTime') == ['35F9.1'],
        'Local preferences API reason': reasons.get('NSPrivacyAccessedAPICategoryUserDefaults') == ['CA92.1'],
    }
    for name, passed in checks.items():
        print(f'{"PASS" if passed else "FAIL"}: {name}')
    return all(checks.values())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    raise SystemExit(0 if validate(args.app) else 1)
