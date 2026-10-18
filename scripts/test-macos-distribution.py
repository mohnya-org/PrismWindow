"""Offline regression tests: no credentials, Apple services or keychain mutation."""
import base64
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('distribution', Path(__file__).with_name('macos-distribution.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
DUMMY = {name: 'test-only-value' for name in m.REQUIRED_SECRETS}
DUMMY.update(APPLE_CERT_BASE64=base64.b64encode(b'fixture certificate').decode(),
             APPLE_TEAM_ID='TESTTEAM01', APPLE_API_PRIVATE_KEY='-----BEGIN PRIVATE KEY-----\nfixture',
             SPARKLE_PUBLIC_ED_KEY=base64.b64encode(bytes(32)).decode())


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.app = self.root / 'Prism Window.app'
        self.app.mkdir()

    def macho(self, path):
        p = self.app / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(b'\xcf\xfa\xed\xfe' + b'fixture')
        return p

    def test_preflight_lists_missing_names_not_values(self):
        with self.assertRaises(m.ReleaseError) as error:
            m.preflight({'APPLE_CERT_PASSWORD': 'never-print-this'})
        self.assertIn('APPLE_TEAM_ID', str(error.exception))
        self.assertIn('APPLE_API_PRIVATE_KEY', str(error.exception))
        self.assertNotIn('never-print-this', str(error.exception))
        m.preflight(DUMMY)

    def test_preflight_rejects_bad_base64_and_team(self):
        for name, value in [('APPLE_CERT_BASE64', '!'), ('SPARKLE_PUBLIC_ED_KEY', 'YQ=='),
                            ('APPLE_TEAM_ID', 'invalid'), ('APPLE_API_PRIVATE_KEY', 'invalid')]:
            with self.subTest(name=name), self.assertRaises(m.ReleaseError) as error:
                m.preflight(dict(DUMMY, **{name: value}))
            self.assertIn(name, str(error.exception))
            self.assertNotIn(value if len(value) > 10 else 'never-print-this', str(error.exception))

    def test_nested_signing_order_and_no_deep_sign(self):
        self.macho('Contents/MacOS/PrismWindow')
        self.macho('Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle')
        self.macho('Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader')
        self.macho('Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater')
        framework = self.app / 'Contents/Frameworks/Sparkle.framework'
        (framework / 'Versions/Current').symlink_to('B')
        (framework / 'Sparkle').symlink_to('Versions/Current/Sparkle')
        with patch.object(m, 'run', return_value=b'') as run:
            m.sign_app(self.app, 'identity', '/isolated.keychain-db')
        calls = [c.args[0] for c in run.call_args_list]
        signs = [c for c in calls if '--sign' in c]
        targets = [c[-1] for c in signs]
        self.assertEqual(targets[-1], self.app)
        self.assertEqual(len(targets), len(set(targets)))
        for call in signs:
            self.assertNotIn('--deep', call)
            self.assertIn('--timestamp', call)
            self.assertIn('runtime', call)
            self.assertIn('--keychain', call)
            self.assertNotIn('--preserve-metadata=entitlements', call)
        for target in targets:
            for parent in target.parents:
                if parent in targets:
                    self.assertLess(targets.index(target), targets.index(parent))
        self.assertIn('--deep', calls[-1])
        self.assertIn('--strict', calls[-1])

    def test_team_comes_from_certificate_ou_not_identity_label(self):
        fingerprint = hashlib.sha1(b'der').hexdigest().upper()
        def response(args, *_a, **_k):
            if args[1] == 'find-identity':
                return f'1) {fingerprint} "Developer ID Application: Fixture (TESTTEAM01)"'.encode()
            if args[1] == 'find-certificate':
                return b'-----BEGIN CERTIFICATE-----\nfixture\n-----END CERTIFICATE-----'
            if '-outform' in args:
                return b'der'
            return b'subject=\n CN=Developer ID Application: Fixture\n OU=WRONGTEAM1\n'
        with patch.object(m, 'run', side_effect=response):
            with self.assertRaises(m.ReleaseError):
                m.signing_identity('keychain', 'TESTTEAM01')
            self.assertEqual(m.signing_identity('keychain', 'WRONGTEAM1'), fingerprint)

    def test_reject_appledouble_and_zip_traversal(self):
        for path in ['Prism Window.app/Contents/Frameworks/._Sparkle', '__MACOSX/metadata', '../escape', '/escape']:
            archive = self.root / 'app.zip'
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr(path, b'fixture')
            with self.subTest(path=path), self.assertRaises(m.ReleaseError):
                m.check_zip(archive)

    def test_both_archive_commands_disable_metadata(self):
        archive = self.root / 'app.zip'
        with patch.object(m, 'run') as run, patch.object(m, 'check_zip'):
            m.archive_app(self.app, archive)
        args = run.call_args.args[0]
        self.assertIn('--norsrc', args)
        self.assertIn('--noextattr', args)
        self.assertEqual(run.call_args.kwargs['env']['COPYFILE_DISABLE'], '1')

    def release_fixture(self, fail_stage=None, status='Accepted', verification_error=False):
        stages, cleaned = [], []
        def run(_args, stage, **_kwargs):
            stages.append(stage)
            if stage == fail_stage:
                raise m.ReleaseError('simulated failure')
            return json.dumps({'status': status}).encode()
        original_cleanup = m.cleanup
        def cleanup(path):
            cleaned.append(Path(path))
            original_cleanup(path)
        env = dict(DUMMY, RUNNER_TEMP=str(self.root), GITHUB_ENV=str(self.root / 'env'))
        with patch.dict(os.environ, env), patch.object(m, 'run', side_effect=run), \
             patch.object(m, 'signing_identity', return_value='fixture'), \
             patch.object(m, 'sign_app'), patch.object(m, 'verify_app'), \
             patch.object(m, 'archive_app') as archive, \
             patch.object(m, 'verify_archive', side_effect=m.ReleaseError('verification failed') if verification_error else None) as verify, \
             patch.object(m, 'cleanup', side_effect=cleanup), contextlib.redirect_stdout(io.StringIO()):
            error = None
            try:
                m.release(self.app, self.root / 'final.zip')
            except m.ReleaseError as caught:
                error = caught
        self.assertEqual(len(cleaned), 1)
        self.assertFalse(cleaned[0].exists())
        self.assertIn('SIGNING_TEMP_DIR=', (self.root / 'env').read_text())
        return stages, archive.call_count, verify.call_count, error

    def test_cleanup_on_import_signing_and_notary_failures(self):
        for stage in ['Temporary keychain creation', 'Certificate import', 'Notarization submission', 'Ticket stapling']:
            with self.subTest(stage=stage):
                _, _, _, error = self.release_fixture(fail_stage=stage)
                self.assertIsNotNone(error)

    def test_notary_invalid_never_staples_or_verifies(self):
        stages, archives, verifies, error = self.release_fixture(status='Invalid')
        self.assertIsNotNone(error)
        self.assertNotIn('Ticket stapling', stages)
        self.assertEqual(archives, 1)
        self.assertEqual(verifies, 0)

    def test_final_verification_failure_blocks_success(self):
        _, archives, verifies, error = self.release_fixture(verification_error=True)
        self.assertIsNotNone(error)
        self.assertEqual(archives, 2)
        self.assertEqual(verifies, 1)

    def test_success_verifies_recreated_archive_and_cleans_credentials(self):
        stages, archives, verifies, error = self.release_fixture()
        self.assertIsNone(error)
        self.assertEqual(archives, 2)
        self.assertEqual(verifies, 1)
        self.assertLess(stages.index('Notarization submission'), stages.index('Ticket stapling'))

    def test_tool_failure_does_not_echo_secret_arguments_or_output(self):
        result = type('Result', (), dict(returncode=1, stdout=b'secret-output', stderr=b'secret-output'))()
        with patch.object(m.subprocess, 'run', return_value=result), self.assertRaises(m.ReleaseError) as error:
            m.run(['tool', 'secret-argument'], 'Test stage')
        self.assertEqual(str(error.exception), 'Test stage failed')

    def test_no_global_keychain_settings_mutations(self):
        source = Path(m.__file__).read_text()
        self.assertNotIn("'default-keychain'", source)
        self.assertNotIn("'list-keychains'", source)

    def test_verification_rejects_wrong_team_missing_runtime_timestamp_and_entitlements(self):
        binary = self.macho('Contents/MacOS/PrismWindow')
        good = 'TeamIdentifier=TESTTEAM01\nAuthority=Developer ID Application: Fixture\nflags=0x10000(runtime)\nTimestamp=fixture\n'
        for metadata, entitlements in [
            (good.replace('TESTTEAM01', 'WRONGTEAM1'), b''),
            (good.replace('(runtime)', ''), b''),
            (good.replace('Timestamp=', 'Signed Time='), b''),
            (good.replace('Developer ID Application:', 'Apple Development:'), b''),
            (good, m.plistlib.dumps({'com.apple.security.get-task-allow': True})),
        ]:
            result = type('Result', (), dict(returncode=0, stderr=metadata.encode()))()
            with patch.object(m, 'code_targets', return_value=[binary]), \
                 patch.object(m.subprocess, 'run', return_value=result), \
                 patch.object(m, 'run', return_value=entitlements), self.assertRaises(m.ReleaseError):
                m.verify_app(self.app, 'TESTTEAM01')

    def test_verification_requires_codesign_stapler_and_gatekeeper(self):
        for failed_stage in ['Strict signature verification', 'Stapled ticket validation', 'Gatekeeper assessment']:
            def run(_args, stage, **_kwargs):
                if stage == failed_stage:
                    raise m.ReleaseError('simulated verification failure')
                return b''
            with patch.object(m, 'code_targets', return_value=[]), \
                 patch.object(m, 'run', side_effect=run), self.assertRaises(m.ReleaseError):
                m.verify_app(self.app, 'TESTTEAM01')

    def test_cleanup_deletes_keys_even_when_keychain_delete_fails_then_retries(self):
        directory = self.root / 'prism-signing-fixture'
        directory.mkdir()
        for name in ['signing.keychain-db', 'certificate.p12', 'AuthKey.p8']:
            (directory / name).write_text('fixture')
        failure = type('Result', (), dict(returncode=1))()
        with patch.object(m.subprocess, 'run', return_value=failure), self.assertRaises(m.ReleaseError):
            m.cleanup(directory)
        self.assertFalse((directory / 'AuthKey.p8').exists())
        self.assertFalse((directory / 'certificate.p12').exists())
        self.assertTrue((directory / 'signing.keychain-db').exists())
        success = type('Result', (), dict(returncode=0))()
        with patch.object(m.subprocess, 'run', return_value=success):
            m.cleanup(directory)
        self.assertFalse(directory.exists())


if __name__ == '__main__':
    unittest.main()
