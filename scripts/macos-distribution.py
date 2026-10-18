#!/usr/bin/env python3
"""Fail-closed Developer ID distribution. Never print credentials or tool output."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
import zipfile

APPLE_SECRETS = (
    'APPLE_CERT_BASE64', 'APPLE_CERT_PASSWORD', 'APPLE_TEAM_ID',
    'APPLE_API_ISSUER_ID', 'APPLE_API_KEY_ID', 'APPLE_API_PRIVATE_KEY',
)
REQUIRED_SECRETS = APPLE_SECRETS + ('SPARKLE_PRIVATE_KEY', 'SPARKLE_PUBLIC_ED_KEY')
MACHO_MAGIC = {
    b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
    b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca',
    b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca',
}


class ReleaseError(Exception):
    pass


def signing_error(stderr):
    # Emit ONLY fixed known error labels, never raw diagnostics: codesign can
    # include the signing certificate's name/team and absolute keychain paths.
    markers = (
        'errSecInternalComponent', 'errSecInteractionNotAllowed',
        'User interaction is not allowed', 'unable to build chain to self-signed root',
        'The specified item could not be found in the keychain',
        'no identity found', 'The user name or passphrase you entered is not correct',
        'resource fork, Finder information, or similar detritus not allowed',
        'bundle format unrecognized, invalid, or unsuitable',
        'code object is not signed at all', 'a sealed resource is missing or invalid',
        'timestamp service is not available', 'A timestamp was expected but was not found',
        'CSSMERR_TP_CERT_EXPIRED', 'CSSMERR_TP_NOT_TRUSTED',
        'errSecAuthFailed', 'errSecNotAvailable', 'errSecCSInternalError',
    )
    output = stderr.decode(errors='replace')
    return '; '.join(marker for marker in markers if marker.lower() in output.lower()) or 'unclassified codesign error (raw output suppressed)'


def run(args, stage, **kwargs):
    # In particular, security/notarytool may echo credentials in diagnostics.
    # Do not print argv, stderr, stdout, or CalledProcessError.
    try:
        result = subprocess.run([str(a) for a in args], capture_output=True,
                                check=False, **kwargs)
    except (OSError, subprocess.TimeoutExpired):
        raise ReleaseError(f'{stage} failed') from None
    if result.returncode:
        if str(args[0]) == 'codesign':
            raise ReleaseError(f'{stage} failed (exit {result.returncode}): {signing_error(result.stderr)}')
        raise ReleaseError(f'{stage} failed')
    return result.stdout


def preflight(env=os.environ):
    missing = [name for name in REQUIRED_SECRETS if not env.get(name, '').strip()]
    if missing:
        raise ReleaseError('Missing secrets: ' + ', '.join(missing))
    for name in ('APPLE_CERT_BASE64', 'SPARKLE_PUBLIC_ED_KEY'):
        try:
            data = base64.b64decode(''.join(env[name].split()), validate=True)
            if not data or (name == 'SPARKLE_PUBLIC_ED_KEY' and len(data) != 32):
                raise ValueError()
        except ValueError:
            raise ReleaseError('Invalid secret: ' + name) from None
    if not re.fullmatch(r'[A-Z0-9]{10}', env['APPLE_TEAM_ID']):
        raise ReleaseError('Invalid secret: APPLE_TEAM_ID')
    if '-----BEGIN PRIVATE KEY-----' not in env['APPLE_API_PRIVATE_KEY']:
        raise ReleaseError('Invalid secret: APPLE_API_PRIVATE_KEY')


def code_targets(app):
    """Physical Mach-O files first, then enclosing bundles, deepest first.

    Do not follow framework symlinks or sign the same executable via an alias.
    Resource-only bundles are sealed by their parent and need no signature.
    """
    app = Path(app)
    binaries, bundles = [], []
    for root, dirs, files in os.walk(app, followlinks=False):
        dirs[:] = [d for d in dirs if not (Path(root) / d).is_symlink()]
        path = Path(root)
        if path.suffix in ('.app', '.xpc', '.framework'):
            bundles.append(path)
        elif path.suffix == '.bundle':
            info = path / 'Contents/Info.plist'
            if info.is_file() and plistlib.loads(info.read_bytes()).get('CFBundleExecutable'):
                bundles.append(path)
        for name in files:
            target = path / name
            if not target.is_symlink():
                with target.open('rb') as stream:
                    if stream.read(4) in MACHO_MAGIC:
                        binaries.append(target)
    if not binaries or app not in bundles:
        raise ReleaseError('App has no signable executable')
    depth = lambda p: (-len(p.parts), str(p))
    return sorted(binaries, key=depth) + sorted(bundles, key=depth)


def sign_app(app, identity, keychain=None):
    args = ['codesign', '--force', '--sign', identity]
    if identity != '-':
        if not keychain:
            raise ReleaseError('An isolated signing keychain is required')
        args += ['--keychain', keychain, '--options', 'runtime', '--timestamp']
    # Swift/AppKit and the pinned Sparkle binaries need no entitlements.
    # Do not preserve development entitlements or add JIT/library-validation exceptions.
    for target in code_targets(app):
        component = str(target.relative_to(app)) if target != Path(app) else 'host app'
        print(f'Signing component: {component}', flush=True)
        run(args + [target], f'Code signing [{component}]')
    run(['codesign', '--verify', '--deep', '--strict', app], 'Signature verification')


def signing_identity(keychain, team):
    identities = run(['security', 'find-identity', '-v', '-p', 'codesigning', keychain],
                     'Identity lookup').decode()
    valid = set(re.findall(r'\b([A-Fa-f0-9]{40})\b', identities))
    pem = run(['security', 'find-certificate', '-a', '-p', keychain], 'Certificate lookup')
    matches = []
    for cert in re.findall(rb'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', pem, re.S):
        der = run(['openssl', 'x509', '-outform', 'DER'], 'Certificate decoding', input=cert)
        fingerprint = hashlib.sha1(der).hexdigest().upper()
        if fingerprint not in {value.upper() for value in valid}:
            continue
        subject = run(['openssl', 'x509', '-noout', '-subject', '-nameopt', 'sep_multiline,sname'],
                      'Certificate subject lookup', input=cert).decode()
        fields = dict(re.findall(r'^\s*(CN|OU)\s*=\s*(.*?)\s*$', subject, re.M))
        if fields.get('CN', '').startswith('Developer ID Application:') and fields.get('OU') == team:
            matches.append(fingerprint)
    if len(matches) != 1:
        raise ReleaseError('Expected exactly one valid Developer ID Application identity matching APPLE_TEAM_ID')
    return matches[0]


def verify_app(app, team, notarized=True):
    run(['codesign', '--verify', '--deep', '--strict', app], 'Strict signature verification')
    # Verify every physical executable as well as the outer bundle.
    for target in code_targets(app):
        result = subprocess.run(['codesign', '-dvvv', str(target)], capture_output=True)
        metadata = result.stderr.decode(errors='replace')
        if result.returncode or f'TeamIdentifier={team}\n' not in metadata:
            raise ReleaseError('Signature team does not match APPLE_TEAM_ID')
        if 'Authority=Developer ID Application:' not in metadata:
            raise ReleaseError('Non-Developer ID signature found')
        if '(runtime)' not in metadata or 'Timestamp=' not in metadata:
            raise ReleaseError('Hardened Runtime or secure timestamp missing')
        entitlements = run(['codesign', '-d', '--entitlements', ':-', target], 'Entitlements verification')
        if entitlements.strip() and plistlib.loads(entitlements):
            raise ReleaseError('Unexpected entitlements in Swift/AppKit distribution')
    if notarized:
        run(['xcrun', 'stapler', 'validate', app], 'Stapled ticket validation', timeout=120)
        run(['spctl', '--assess', '--type', 'execute', '--verbose=2', app],
            'Gatekeeper assessment', timeout=120)


def check_zip(archive):
    with zipfile.ZipFile(archive) as source:
        for entry in source.infolist():
            parts = Path(entry.filename).parts
            if (entry.filename.startswith('/') or '..' in parts or
                    any(p.startswith('._') or p == '__MACOSX' for p in parts)):
                raise ReleaseError('Unsafe path or AppleDouble metadata in archive')


def archive_app(app, archive):
    # Both the notarization upload and the FINAL stapled archive use these flags.
    Path(archive).unlink(missing_ok=True)
    run(['ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent', app, archive],
        'ZIP creation', env=dict(os.environ, COPYFILE_DISABLE='1'))
    check_zip(archive)


def verify_archive(archive, team):
    check_zip(archive)
    with tempfile.TemporaryDirectory(prefix='prism-verify-') as directory:
        run(['ditto', '-x', '-k', '--norsrc', '--noextattr', archive, directory], 'ZIP extraction')
        app = Path(directory) / 'Prism Window.app'
        if not app.is_dir():
            raise ReleaseError('Expected app missing from final archive')
        verify_app(app, team)


def cleanup(directory):
    directory = Path(directory)
    if not directory.name.startswith('prism-signing-'):
        raise ReleaseError('Refusing to clean an unrelated directory')
    if not directory.exists():
        return
    keychain = directory / 'signing.keychain-db'
    failed = False
    if keychain.exists():
        result = subprocess.run(['security', 'delete-keychain', str(keychain)], capture_output=True)
        failed = result.returncode != 0
    # Remove certificate/API key even if the keychain service fails. Retain the
    # keychain for the workflow's always() retry instead of silently forgetting it.
    for path in directory.iterdir():
        if not failed or not path.name.startswith('signing.keychain'):
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()
    if failed:
        raise ReleaseError('Temporary keychain cleanup failed; workflow cleanup must retry')
    directory.rmdir()


def release(app, archive):
    preflight()
    app, archive = Path(app).resolve(), Path(archive).resolve()
    temp = Path(tempfile.mkdtemp(prefix='prism-signing-', dir=os.environ.get('RUNNER_TEMP')))
    os.chmod(temp, 0o700)
    # Register before creating any credentials so always() can clean after termination.
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'], 'a') as stream:
            stream.write(f'SIGNING_TEMP_DIR={temp}\n')
    keychain = temp / 'signing.keychain-db'
    try:
        cert, api_key = temp / 'certificate.p12', temp / 'AuthKey.p8'
        cert.write_bytes(base64.b64decode(''.join(os.environ['APPLE_CERT_BASE64'].split()), validate=True))
        api_key.write_text(os.environ['APPLE_API_PRIVATE_KEY'])
        cert.chmod(0o600)
        api_key.chmod(0o600)
        password = secrets.token_urlsafe(32)
        run(['security', 'create-keychain', '-p', password, keychain], 'Temporary keychain creation')
        run(['security', 'set-keychain-settings', '-lut', '21600', keychain], 'Keychain configuration')
        run(['security', 'unlock-keychain', '-p', password, keychain], 'Keychain unlock')
        run(['security', 'import', cert, '-k', keychain, '-P', os.environ['APPLE_CERT_PASSWORD'],
             '-T', '/usr/bin/codesign', '-T', '/usr/bin/security'], 'Certificate import')
        run(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, keychain],
            'Signing key access configuration')
        identity = signing_identity(keychain, os.environ['APPLE_TEAM_ID'])
        cert.unlink()
        # Never change the default keychain or replace the user's search list.
        # codesign is given this job's unique keychain explicitly.
        print('Developer ID certificate team verified', flush=True)
        for path in sorted(app.rglob('*'), key=lambda p: -len(p.parts)):
            if path.name.startswith('._') or path.name == '__MACOSX':
                if path.is_dir() and not path.is_symlink():
                    shutil.rmtree(path)
                else:
                    path.unlink()
        run(['xattr', '-cr', app], 'Pre-signing metadata cleanup')
        sign_app(app, identity, keychain)
        verify_app(app, os.environ['APPLE_TEAM_ID'], notarized=False)
        archive_app(app, archive)
        response = run(['xcrun', 'notarytool', 'submit', archive,
                        '--key', api_key, '--key-id', os.environ['APPLE_API_KEY_ID'],
                        '--issuer', os.environ['APPLE_API_ISSUER_ID'],
                        '--wait', '--timeout', '20m', '--output-format', 'json'],
                       'Notarization submission', timeout=1260)
        if json.loads(response).get('status') != 'Accepted':
            raise ReleaseError('Notarization was not Accepted; publication blocked')
        print('Notarization Accepted')
        run(['xcrun', 'stapler', 'staple', app], 'Ticket stapling', timeout=120)
        # Stapling is the only permitted post-signing mutation.
        archive_app(app, archive)
        verify_archive(archive, os.environ['APPLE_TEAM_ID'])
        print('Final ZIP passed signature, team, runtime, ticket and Gatekeeper checks')
    finally:
        cleanup(temp)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['preflight', 'release', 'sign-local', 'verify-archive', 'cleanup'])
    parser.add_argument('paths', nargs='*')
    args = parser.parse_args()
    if args.command == 'preflight' and not args.paths:
        preflight()
    elif args.command == 'release' and len(args.paths) == 2:
        release(*args.paths)
    elif args.command == 'sign-local' and len(args.paths) == 1:
        sign_app(args.paths[0], '-')
    elif args.command == 'verify-archive' and len(args.paths) == 1:
        team = os.environ.get('APPLE_TEAM_ID', '')
        if not team:
            raise ReleaseError('Missing secrets: APPLE_TEAM_ID')
        verify_archive(args.paths[0], team)
    elif args.command == 'cleanup' and len(args.paths) == 1:
        cleanup(args.paths[0])
    else:
        parser.error('Incorrect number of paths')


if __name__ == '__main__':
    def interrupted(_signum, _frame):
        raise ReleaseError('Distribution interrupted')
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        main()
    except (ReleaseError, ValueError, OSError):
        # Never include exception text from parsers/tools handling secret material.
        error = sys.exc_info()[1]
        print(str(error) if isinstance(error, ReleaseError) else 'Distribution input or file operation failed', file=sys.stderr)
        sys.exit(1)
