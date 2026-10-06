# 재현 가능한 Apple Silicon onedir 엔진. 루트에서 build_engine.sh로 실행.
from pathlib import Path
import sysconfig
from PyInstaller.utils.hooks import collect_data_files, collect_dynamic_libs, copy_metadata

root = Path(SPECPATH).parent
binaries, datas, hiddenimports = [], [], []
# collect_all의 런타임 import는 GPU 없는 빌드 호스트에서 MLX를 초기화한다.
# 같은 모듈·데이터·동적 라이브러리를 정적으로 수집한다.
site = Path(sysconfig.get_paths()['purelib'])
for package in ('mlx', 'mlx_qwen3_asr', 'huggingface_hub'):
    folder = site / package
    datas += collect_data_files(package)
    binaries += collect_dynamic_libs(package)
    for file in folder.rglob('*.py'):
        parts = list(file.relative_to(site).with_suffix('').parts)
        if parts[-1] == '__init__':
            parts.pop()
        hiddenimports.append('.'.join(parts))
    for file in folder.rglob('*.so'):
        relative = file.relative_to(site)
        hiddenimports.append('.'.join(relative.parent.parts + (file.name.split('.')[0],)))
datas += collect_data_files('soundfile')
datas += copy_metadata('mlx-qwen3-asr')
datas += copy_metadata('huggingface-hub')
a = Analysis([str(root / 'voicenote.py')], pathex=[str(root)],
             binaries=binaries, datas=datas,
             hiddenimports=hiddenimports + ['engine.models', 'engine.backends.mac'],
             hookspath=[], hooksconfig={}, runtime_hooks=[], excludes=[], noarchive=False)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name='vnote-engine',
          debug=False, bootloader_ignore_signals=False, strip=False, upx=False,
          console=True, target_arch='arm64', codesign_identity=None, entitlements_file=None)
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False, name='vnote-engine')
