#!/usr/bin/env python3
"""Build and mount a real DMG to verify a signed app survives packaging.

Run with the DMG requirements installed and a locally signed app argument.
No Developer ID credentials or notarization service are used.
"""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location('dmg', Path(__file__).with_name('macos-dmg.py'))
dmg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dmg)


def check(*args):
    subprocess.run(list(map(str, args)), check=True)


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: test-dmg-signature.py <signed.app>')
    app = Path(sys.argv[1]).resolve()
    check('codesign', '--verify', '--deep', '--strict', app)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    with tempfile.TemporaryDirectory(prefix='prism-dmg-signature-') as directory:
        root = Path(directory)
        image = root / 'test.dmg'
        dmg.build_image(app, image)
        mount = root / 'mount'
        mount.mkdir()
        check('hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, image)
        try:
            check('codesign', '--verify', '--deep', '--strict', mount / app.name)
            dmg.verify_layout(mount, app.name, info)
            dmg.verify_design(mount, app.name)
        finally:
            check('hdiutil', 'detach', mount)
    print('Real DMG preserves app signature and installation layout')


if __name__ == '__main__':
    main()
