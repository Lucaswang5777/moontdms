"""Release metadata regression tests; no Git history or network required."""
from pathlib import Path
import tempfile
import unittest

from audit import read_manifest


class ManifestTests(unittest.TestCase):
    def read(self, text):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'moon.mod'
            path.write_text(text, encoding='utf-8')
            return read_manifest(path)

    def test_release_versions_are_read_from_manifest(self):
        for name, version in [('Lucaswang5777/moontdms', '0.2.1'),
                              ('Lucaswang5777/moontdms', '0.2.2'),
                              ('example/another-module', '1.0.0-rc.1')]:
            with self.subTest(name=name, version=version):
                result = self.read(f'name = "{name}"\nversion = "{version}"\n'
                                   f'repository = "https://github.com/{name}"\n')
                self.assertEqual(result['name'], name)
                self.assertEqual(result['version'], version)

    def test_missing_empty_or_wrong_type_fields_are_rejected(self):
        good = {'name': 'Lucaswang5777/moontdms', 'version': '0.2.2',
                'repository': 'https://github.com/Lucaswang5777/moontdms'}
        for field in good:
            for bad in [None, '', '  ', 22]:
                with self.subTest(field=field, value=bad):
                    values = dict(good)
                    values[field] = bad
                    text = ''.join(f'{key} = {value!r}\n' for key, value in values.items()
                                   if value is not None)
                    with self.assertRaises(ValueError):
                        self.read(text)

    def test_repository_mismatch_is_rejected(self):
        with self.assertRaises(ValueError):
            self.read('name = "Lucaswang5777/moontdms"\nversion = "0.2.2"\n'
                      'repository = "https://github.com/example/wrong"\n')


if __name__ == '__main__':
    unittest.main()
