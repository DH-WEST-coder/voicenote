# 재현 가능한 Apple Silicon onedir 엔진. 루트에서 build_engine.sh로 실행.
from pathlib import Path
import importlib.metadata as metadata
import sysconfig
from packaging.requirements import Requirement
from PyInstaller.utils.hooks import collect_data_files, collect_dynamic_libs, copy_metadata

root = Path(SPECPATH).parent
binaries, datas, hiddenimports = [], [], []
# collect_all의 런타임 import는 GPU 없는 빌드 호스트에서 MLX를 초기화한다.
# 같은 모듈·데이터·동적 라이브러리를 정적으로 수집한다.
site = Path(sysconfig.get_paths()['purelib'])


def distribution_closure():
    """Installed runtime dependencies for mlx-qwen3-asr[aligner], without imports."""
    seen = set()
    pending = [('mlx-qwen3-asr', 'aligner')]
    while pending:
        name, extra = pending.pop()
        normalized = name.lower().replace('_', '-')
        if normalized in seen:
            continue
        try:
            dist = metadata.distribution(name)
        except metadata.PackageNotFoundError:
            # Dependency may be platform-optional; collect packages available in
            # this build environment and let the bundle selftest catch omissions.
            continue
        seen.add(normalized)
        yield dist
        for raw in dist.requires or ():
            req = Requirement(raw)
            if req.marker is None or req.marker.evaluate({'extra': extra}):
                pending.append((req.name, ''))


def import_roots(dist):
    raw = dist.read_text('top_level.txt') or ''
    roots = [line.strip() for line in raw.splitlines() if line.strip()]
    if not roots:
        roots = [dist.metadata['Name'].replace('-', '_').lower()]
    return roots


runtime_dists = list(distribution_closure())
non_runtime_paths = {'tests', 'test', 'testing', '__pycache__'}
for dist in runtime_dists:
    for package in import_roots(dist):
        folder = site / package
        if not folder.exists():
            # Top-level extension modules (e.g. nagisa_utils) live as a file.
            if (site / (package + '.py')).is_file():
                hiddenimports.append(package)
            for file in site.glob(package + '*.so'):
                binaries.append((str(file), '.'))
                hiddenimports.append(package)
            continue
        datas += collect_data_files(
            package,
            excludes=['**/tests/**', '**/test/**', '**/testing/**',
                      '**/conftest.py', '**/test_*.py', '**/*_test.py'],
        )
        binaries += collect_dynamic_libs(package)
        for file in folder.rglob('*.py'):
            relative = file.relative_to(site)
            if non_runtime_paths.intersection(relative.parts[:-1]):
                continue
            if relative.name == 'conftest.py' or relative.name.startswith('test_') or relative.name.endswith('_test.py'):
                continue
            parts = list(relative.with_suffix('').parts)
            if parts[-1] == '__init__':
                parts.pop()
            if parts:
                hiddenimports.append('.'.join(parts))
        for file in folder.rglob('*.so'):
            relative = file.relative_to(site)
            hiddenimports.append('.'.join(relative.parent.parts + (file.name.split('.')[0],)))
    # RECORD also lists extension modules outside their package directory.
    for file in dist.files or ():
        if str(file).endswith('.so'):
            source = Path(dist.locate_file(file))
            if source.exists():
                binaries.append((str(source), '.'))
    datas += copy_metadata(dist.metadata['Name'])

# soundfile is used by the engine and may be included through a runtime dependency
# closure on some versions; ensure its module/data is always collected.
datas += collect_data_files('soundfile')
a = Analysis([str(root / 'voicenote.py')], pathex=[str(root)],
             binaries=binaries, datas=datas,
             hiddenimports=hiddenimports + ['engine.models', 'engine.backends.mac'],
             hookspath=[], hooksconfig={}, runtime_hooks=[], excludes=[], noarchive=False)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name='vnote-engine',
          debug=False, bootloader_ignore_signals=False, strip=False, upx=False,
          console=True, target_arch='arm64', codesign_identity=None, entitlements_file=None)
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False, name='vnote-engine')
