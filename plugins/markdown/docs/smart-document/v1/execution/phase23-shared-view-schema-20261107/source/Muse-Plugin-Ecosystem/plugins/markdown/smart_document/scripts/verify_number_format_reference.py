#!/usr/bin/env python3
"""Check the exact original money formatter package and the bounded reuse patch."""
from pathlib import Path
import hashlib
import json
import tarfile
ROOT = Path(__file__).resolve().parents[1]
V = ROOT / 'vendor/number_format_reference'
pin = json.loads((V / 'upstream-files.json').read_text())
assert (pin['package'], pin['version']) == ('rusty-money', '0.4.1')
crate = V / 'rusty-money-0.4.1.crate'
assert hashlib.sha256(crate.read_bytes()).hexdigest() == pin['crateSha256'] == '5b28f881005eac7ad8d46b6f075da5f322bd7f4f83a38720fc069694ddadd683'
with tarfile.open(crate) as archive:
    for item in pin['files']:
        data = (V / item['path']).read_bytes()
        assert hashlib.sha256(data).hexdigest() == item['sha256']
        assert archive.extractfile(item['path']).read() == data
runtime = (ROOT / 'vendor/appflowy_database/src/fields/type_option/number_type_option.rs').read_text()
assert 'Formatter::money(&money, params)' in runtime and 'pattern.iter().sum::<usize>() < 29' in runtime
assert 'LocalFormat::from_locale(currency.locale())' in runtime
print('P21: original money 0.4.1 checksum, formatter/locale/license and bounded pattern reuse verified')
