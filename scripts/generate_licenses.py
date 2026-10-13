#!/usr/bin/env python3
"""설치된 로컬 metadata·라이선스로 배포 고지를 만든다(네트워크 없음)."""
import importlib.metadata as metadata
import json
from pathlib import Path
import shutil
import tomllib

ROOT = Path(__file__).resolve().parents[1]
RELEASE = ROOT / 'release'
NOTICES = RELEASE / 'licenses'
NOTICES.mkdir(parents=True, exist_ok=True)
lines = ['# 구성 요소 라이선스', '',
         'VNote 0.1.2에 사용한 구성 요소와 모델의 출처입니다. 모델 가중치는 DMG에 포함하지 않고 첫 실행 때 다운로드합니다. '
         '아래 자동 목록은 빌드 도구와 선택적 의존성도 포함하는 보수적 목록입니다. 원문 고지는 `licenses/`에 보존합니다.', '',
         '## 모델·주요 구성 요소', '',
         '| 구성 요소 | 라이선스·출처 |', '|---|---|',
         '| Qwen3-ASR 1.7B / 0.6B | Apache-2.0 · [Qwen](https://huggingface.co/Qwen/Qwen3-ASR-1.7B) |',
         '| MLX 양자화 ASR | Apache-2.0 · [1.7B 8bit](https://huggingface.co/moona3k/mlx-qwen3-asr-1.7b-8bit), [0.6B 4bit](https://huggingface.co/moona3k/mlx-qwen3-asr-0.6b-4bit). moona3k의 MLX 변환·양자화 모델 |',
         '| Qwen3-ForcedAligner 0.6B | Apache-2.0 · [Qwen](https://huggingface.co/Qwen/Qwen3-ForcedAligner-0.6B) |',
         '| FluidAudio | Apache-2.0 · [FluidInference](https://github.com/FluidInference/FluidAudio/blob/main/LICENSE) · [포함 원문](licenses/FluidAudio-LICENSE) |',
         '| pyannote speaker-diarization-community-1 | CC-BY-4.0 · [원 모델](https://huggingface.co/pyannote/speaker-diarization-community-1), [라이선스 전문](https://creativecommons.org/licenses/by/4.0/legalcode) |',
         '| Codex CLI | Apache-2.0 · [OpenAI](https://github.com/openai/codex/blob/main/LICENSE), [추가 고지](https://github.com/openai/codex/blob/main/NOTICE) |',
         '| Python 3.12 | PSF-2.0 · [라이선스 전문](https://docs.python.org/3.12/license.html) |',
         '| libsndfile (SoundFile 번들) | LGPL-2.1-or-later · [원문](https://github.com/libsndfile/libsndfile/blob/master/COPYING). 동적 라이브러리로 포함 |',
         '| PDF.js 표준 폰트 | Foxit 고지 및 Liberation Fonts SIL OFL-1.1 · [PDF.js 고지](https://github.com/mozilla/pdf.js/tree/master/external/standard_fonts), [Liberation Fonts](https://github.com/liberationfonts/liberation-fonts/blob/main/LICENSE) |', '',
         '**CC-BY 출처 표시:** pyannote community-1은 pyannote / Hervé Bredin 및 기여자가 제작했습니다. '
         'VNote는 FluidAudio가 CoreML로 변환한 segmentation·embedding 모델 및 VBx 화자 분리 파이프라인을 사용합니다. '
         '원 모델 및 저작자: [pyannote 모델 카드](https://huggingface.co/pyannote/speaker-diarization-community-1). '
         '변경: FluidAudio의 CoreML 변환·배포 형식 사용. 저작자가 VNote를 보증한다는 의미는 아닙니다.', '',
         '## Python 환경', '', '| 패키지·버전 | 라이선스 | 원문/출처 |', '|---|---|---|']
shutil.copyfile(ROOT / 'vendor/FluidAudio/LICENSE', NOTICES / 'FluidAudio-LICENSE')
for source in sorted((ROOT / 'vendor/FluidAudio/ThirdPartyLicenses').glob('*LICENSE*')):
    dest = NOTICES / 'fluidaudio' / source.name
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, dest)
    lines.insert(lines.index('## Python 환경'), f'- FluidAudio 내장 구성 요소: [{source.stem}]({dest.relative_to(RELEASE).as_posix()})')
for dist in sorted(metadata.distributions(), key=lambda d: d.metadata['Name'].lower()):
    name, version = dist.metadata['Name'], dist.version
    license_name = dist.metadata.get('License-Expression') or dist.metadata.get('License') or ', '.join(
        c.split(' :: ')[-1] for c in dist.metadata.get_all('Classifier', []) if c.startswith('License ::')) or '원문 참조'
    if len(license_name) > 150:
        license_name = '원문 참조'
    copied = []
    for file in dist.files or []:
        if '.dist-info/' in str(file) and any(x in file.name.lower() for x in ('license', 'copying', 'notice', 'authors')):
            source = Path(dist.locate_file(file))
            if source.is_file():
                dest = NOTICES / 'python' / name / str(file).split('.dist-info/', 1)[1]
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, dest)
                copied.append(f'[원문]({dest.relative_to(RELEASE).as_posix()})')
    links = copied or [f'[PyPI](https://pypi.org/project/{name}/{version}/)']
    lines.append(f'| {name} {version} | {license_name.replace(chr(10), " ").replace("|", "/")} | {", ".join(links)} |')
lines += ['', '## JavaScript/npm 환경', '', '| 패키지·버전 | 라이선스 | 출처 |', '|---|---|---|']
lock = json.loads((ROOT / 'desktop/package-lock.json').read_text())
for path, data in sorted(lock['packages'].items()):
    if not path:
        continue
    name = path.split('node_modules/')[-1]
    folder = ROOT / 'desktop' / path
    for source in folder.iterdir() if folder.is_dir() else []:
        if source.is_file() and source.name.lower().startswith(('license', 'notice', 'copying')):
            dest = NOTICES / 'npm' / name / source.name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, dest)
    lines.append(f'| {name} {data.get("version", "")} | {data.get("license", "원문 참조")} | [npm](https://www.npmjs.com/package/{name}) |')
lines += ['', '## Rust/Cargo 환경', '', '| crate·버전 | 라이선스 | 출처 |', '|---|---|---|']
lock = tomllib.loads((ROOT / 'desktop/src-tauri/Cargo.lock').read_text())
registry = Path.home() / '.cargo/registry/src'
for package in sorted(lock['package'], key=lambda p:(p['name'], p['version'])):
    if not package.get('source', '').startswith('registry+'):
        continue
    name, version = package['name'], package['version']
    folders = list(registry.glob(f'*/{name}-{version}'))
    license_name = '원문 참조'
    if folders:
        folder = folders[0]
        meta = tomllib.loads((folder / 'Cargo.toml').read_text())['package']
        license_name = meta.get('license', '원문 참조')
        for source in folder.iterdir():
            if source.is_file() and source.name.lower().startswith(('license', 'notice', 'copying')):
                dest = NOTICES / 'cargo' / f'{name}-{version}' / source.name
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, dest)
    lines.append(f'| {name} {version} | {license_name} | [원본](https://crates.io/crates/{name}/{version}) |')
lines += ['', 'PyInstaller는 GPL-2.0-or-later와 bootloader 배포 예외를 사용합니다. 생성한 실행 파일에 대한 '
          '예외는 포함된 PyInstaller 원문을 참조하세요. VNote 자체 코드의 별도 공개 라이선스는 아직 지정하지 않았습니다.', '']
(RELEASE / 'LICENSES.md').write_text('\n'.join(lines))
print('작성:', RELEASE / 'LICENSES.md')
