# 구성 요소 라이선스

VNote 0.1.0에 사용한 구성 요소와 모델의 출처입니다. 모델 가중치는 DMG에 포함하지 않고 첫 실행 때 다운로드합니다. 아래 자동 목록은 빌드 도구와 선택적 의존성도 포함하는 보수적 목록입니다. 원문 고지는 `licenses/`에 보존합니다.

## 모델·주요 구성 요소

| 구성 요소 | 라이선스·출처 |
|---|---|
| Qwen3-ASR 1.7B / 0.6B | Apache-2.0 · [Qwen](https://huggingface.co/Qwen/Qwen3-ASR-1.7B) |
| MLX 양자화 ASR | Apache-2.0 · [1.7B 8bit](https://huggingface.co/moona3k/mlx-qwen3-asr-1.7b-8bit), [0.6B 4bit](https://huggingface.co/moona3k/mlx-qwen3-asr-0.6b-4bit). moona3k의 MLX 변환·양자화 모델 |
| Qwen3-ForcedAligner 0.6B | Apache-2.0 · [Qwen](https://huggingface.co/Qwen/Qwen3-ForcedAligner-0.6B) |
| FluidAudio | Apache-2.0 · [FluidInference](https://github.com/FluidInference/FluidAudio/blob/main/LICENSE) · [포함 원문](licenses/FluidAudio-LICENSE) |
| pyannote speaker-diarization-community-1 | CC-BY-4.0 · [원 모델](https://huggingface.co/pyannote/speaker-diarization-community-1), [라이선스 전문](https://creativecommons.org/licenses/by/4.0/legalcode) |
| Codex CLI | Apache-2.0 · [OpenAI](https://github.com/openai/codex/blob/main/LICENSE), [추가 고지](https://github.com/openai/codex/blob/main/NOTICE) |
| Python 3.12 | PSF-2.0 · [라이선스 전문](https://docs.python.org/3.12/license.html) |
| libsndfile (SoundFile 번들) | LGPL-2.1-or-later · [원문](https://github.com/libsndfile/libsndfile/blob/master/COPYING). 동적 라이브러리로 포함 |
| PDF.js 표준 폰트 | Foxit 고지 및 Liberation Fonts SIL OFL-1.1 · [PDF.js 고지](https://github.com/mozilla/pdf.js/tree/master/external/standard_fonts), [Liberation Fonts](https://github.com/liberationfonts/liberation-fonts/blob/main/LICENSE) |

**CC-BY 출처 표시:** pyannote community-1은 pyannote / Hervé Bredin 및 기여자가 제작했습니다. VNote는 FluidAudio가 CoreML로 변환한 segmentation·embedding 모델 및 VBx 화자 분리 파이프라인을 사용합니다. 원 모델 및 저작자: [pyannote 모델 카드](https://huggingface.co/pyannote/speaker-diarization-community-1). 변경: FluidAudio의 CoreML 변환·배포 형식 사용. 저작자가 VNote를 보증한다는 의미는 아닙니다.

- FluidAudio 내장 구성 요소: [JapaneseG2P-LICENSE](licenses/fluidaudio/JapaneseG2P-LICENSE.md)
- FluidAudio 내장 구성 요소: [KokoroAneSpanishFrenchG2P-LICENSE](licenses/fluidaudio/KokoroAneSpanishFrenchG2P-LICENSE.md)
- FluidAudio 내장 구성 요소: [NemoTextProcessing-LICENSE](licenses/fluidaudio/NemoTextProcessing-LICENSE.md)
- FluidAudio 내장 구성 요소: [fastcluster-LICENSE](licenses/fluidaudio/fastcluster-LICENSE.md)
- FluidAudio 내장 구성 요소: [vbx-LICENSE](licenses/fluidaudio/vbx-LICENSE.md)
## Python 환경

| 패키지·버전 | 라이선스 | 원문/출처 |
|---|---|---|
| altgraph 0.17.5 | MIT | [원문](licenses/python/altgraph/LICENSE) |
| anyio 4.15.1 | MIT | [원문](licenses/python/anyio/licenses/LICENSE) |
| cffi 2.1.1 | MIT-0 | [원문](licenses/python/cffi/licenses/LICENSE) |
| click 8.5.0 | BSD-3-Clause | [원문](licenses/python/click/licenses/LICENSE.txt) |
| cloudpickle 3.1.2 | BSD-3-Clause | [원문](licenses/python/cloudpickle/licenses/LICENSE) |
| Cython 3.3.0 | Apache-2.0 | [PyPI](https://pypi.org/project/Cython/3.3.0/) |
| dyNET38 2.2 | Apache 2.0 | [PyPI](https://pypi.org/project/dyNET38/2.2/) |
| filelock 4.0.12 | MIT | [원문](licenses/python/filelock/licenses/LICENSE) |
| fsspec 2026.9.0 | BSD-3-Clause | [원문](licenses/python/fsspec/licenses/LICENSE) |
| h11 0.16.0 | MIT | [원문](licenses/python/h11/licenses/LICENSE.txt) |
| hf-xet 1.6.0 | Apache-2.0 | [원문](licenses/python/hf-xet/licenses/LICENSE) |
| httpcore2 2.13.1 | BSD-3-Clause | [원문](licenses/python/httpcore2/licenses/LICENSE.md) |
| httpx2 2.13.1 | BSD-3-Clause | [원문](licenses/python/httpx2/licenses/LICENSE.md) |
| huggingface_hub 2.1.1 | Apache-2.0 | [원문](licenses/python/huggingface_hub/licenses/LICENSE) |
| idna 3.20 | BSD-3-Clause | [원문](licenses/python/idna/licenses/LICENSE.md) |
| iniconfig 2.3.0 | MIT | [원문](licenses/python/iniconfig/licenses/LICENSE) |
| joblib 1.6.0 | BSD-3-Clause | [원문](licenses/python/joblib/licenses/LICENSE.txt) |
| macholib 1.16.4 | MIT | [원문](licenses/python/macholib/LICENSE) |
| mlx 0.32.3 | MIT | [원문](licenses/python/mlx/licenses/LICENSE) |
| mlx-metal 0.32.3 | MIT | [원문](licenses/python/mlx-metal/licenses/LICENSE) |
| mlx-qwen3-asr 0.4.4 | Apache-2.0 | [원문](licenses/python/mlx-qwen3-asr/licenses/LICENSE) |
| nagisa 0.3.0 | MIT License | [원문](licenses/python/nagisa/licenses/LICENSE.txt) |
| narwhals 2.26.0 | MIT | [원문](licenses/python/narwhals/licenses/LICENSE.md) |
| numpy 2.5.3 | BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0 | [원문](licenses/python/numpy/licenses/LICENSE.txt), [원문](licenses/python/numpy/licenses/numpy/_core/include/numpy/libdivide/LICENSE.txt), [원문](licenses/python/numpy/licenses/numpy/_core/src/common/pythoncapi-compat/COPYING), [원문](licenses/python/numpy/licenses/numpy/_core/src/highway/LICENSE), [원문](licenses/python/numpy/licenses/numpy/_core/src/multiarray/dragon4_LICENSE.txt), [원문](licenses/python/numpy/licenses/numpy/_core/src/npysort/x86-simd-sort/LICENSE.md), [원문](licenses/python/numpy/licenses/numpy/_core/src/umath/svml/LICENSE), [원문](licenses/python/numpy/licenses/numpy/fft/pocketfft/LICENSE.md), [원문](licenses/python/numpy/licenses/numpy/linalg/lapack_lite/LICENSE.txt), [원문](licenses/python/numpy/licenses/numpy/ma/LICENSE), [원문](licenses/python/numpy/licenses/numpy/random/LICENSE.md), [원문](licenses/python/numpy/licenses/numpy/random/src/distributions/LICENSE.md), [원문](licenses/python/numpy/licenses/numpy/random/src/mt19937/LICENSE.md), [원문](licenses/python/numpy/licenses/numpy/random/src/pcg64/LICENSE.md), [원문](licenses/python/numpy/licenses/numpy/random/src/philox/LICENSE.md), [원문](licenses/python/numpy/licenses/numpy/random/src/sfc64/LICENSE.md), [원문](licenses/python/numpy/licenses/numpy/random/src/splitmix64/LICENSE.md) |
| packaging 26.3 | Apache-2.0 OR BSD-2-Clause | [원문](licenses/python/packaging/licenses/LICENSE), [원문](licenses/python/packaging/licenses/LICENSE.APACHE), [원문](licenses/python/packaging/licenses/LICENSE.BSD) |
| platformdirs 4.12.3 | MIT | [원문](licenses/python/platformdirs/licenses/LICENSE) |
| pluggy 1.6.0 | MIT | [원문](licenses/python/pluggy/licenses/LICENSE) |
| psutil 7.2.2 | BSD-3-Clause | [원문](licenses/python/psutil/LICENSE) |
| pycparser 3.0 | BSD-3-Clause | [원문](licenses/python/pycparser/licenses/LICENSE) |
| Pygments 2.21.0 | BSD-2-Clause | [원문](licenses/python/Pygments/licenses/AUTHORS), [원문](licenses/python/Pygments/licenses/LICENSE) |
| pyinstaller 6.22.3 | GPLv2-or-later with a special exception which allows to use PyInstaller to build and distribute non-free programs (including commercial ones) | [원문](licenses/python/pyinstaller/licenses/COPYING.txt) |
| pyinstaller-hooks-contrib 2026.8 | Apache Software License, GNU General Public License v2 (GPLv2) | [원문](licenses/python/pyinstaller-hooks-contrib/licenses/LICENSE) |
| pytest 9.1.1 | MIT | [원문](licenses/python/pytest/licenses/LICENSE) |
| PyYAML 6.0.3 | MIT | [원문](licenses/python/PyYAML/licenses/LICENSE) |
| regex 2026.9.29 | Apache-2.0 AND CNRI-Python | [원문](licenses/python/regex/licenses/LICENSE.txt) |
| scikit-learn 1.9.1 | BSD-3-Clause | [원문](licenses/python/scikit-learn/licenses/COPYING) |
| scipy 1.18.1 | 원문 참조 | [원문](licenses/python/scipy/LICENSE.txt) |
| setuptools 84.0.0 | MIT | [원문](licenses/python/setuptools/licenses/LICENSE), [원문](licenses/python/setuptools/LICENSE), [원문](licenses/python/setuptools/LICENSE), [원문](licenses/python/setuptools/licenses/LICENSE), [원문](licenses/python/setuptools/LICENSE), [원문](licenses/python/setuptools/licenses/LICENSE), [원문](licenses/python/setuptools/licenses/LICENSE), [원문](licenses/python/setuptools/licenses/LICENSE), [원문](licenses/python/setuptools/licenses/LICENSE), [원문](licenses/python/setuptools/licenses/LICENSE.APACHE), [원문](licenses/python/setuptools/licenses/LICENSE.BSD), [원문](licenses/python/setuptools/licenses/LICENSE), [원문](licenses/python/setuptools/licenses/LICENSE), [원문](licenses/python/setuptools/licenses/LICENSE.txt), [원문](licenses/python/setuptools/licenses/LICENSE) |
| six 1.17.0 | MIT | [원문](licenses/python/six/LICENSE) |
| soundfile 0.14.0 | BSD 3-Clause License | [원문](licenses/python/soundfile/LICENSE) |
| soynlp 0.0.493 | UNKNOWN | [PyPI](https://pypi.org/project/soynlp/0.0.493/) |
| threadpoolctl 3.7.0 | BSD-3-Clause | [원문](licenses/python/threadpoolctl/licenses/LICENSE) |
| tqdm 4.70.1 | MPL-2.0 AND MIT | [PyPI](https://pypi.org/project/tqdm/4.70.1/) |
| truststore 0.10.4 | MIT | [원문](licenses/python/truststore/licenses/LICENSE) |
| typing_extensions 4.16.0 | PSF-2.0 | [원문](licenses/python/typing_extensions/licenses/LICENSE) |

## JavaScript/npm 환경

| 패키지·버전 | 라이선스 | 출처 |
|---|---|---|
| @napi-rs/canvas 1.0.10 | MIT | [npm](https://www.npmjs.com/package/@napi-rs/canvas) |
| @napi-rs/canvas-android-arm64 1.0.10 | MIT | [npm](https://www.npmjs.com/package/@napi-rs/canvas-android-arm64) |
| @napi-rs/canvas-darwin-arm64 1.0.10 | MIT | [npm](https://www.npmjs.com/package/@napi-rs/canvas-darwin-arm64) |
| @napi-rs/canvas-darwin-x64 1.0.10 | MIT | [npm](https://www.npmjs.com/package/@napi-rs/canvas-darwin-x64) |
| @napi-rs/canvas-linux-arm-gnueabihf 1.0.10 | MIT | [npm](https://www.npmjs.com/package/@napi-rs/canvas-linux-arm-gnueabihf) |
| @napi-rs/canvas-linux-arm64-gnu 1.0.10 | MIT | [npm](https://www.npmjs.com/package/@napi-rs/canvas-linux-arm64-gnu) |
| @napi-rs/canvas-linux-arm64-musl 1.0.10 | MIT | [npm](https://www.npmjs.com/package/@napi-rs/canvas-linux-arm64-musl) |
| @napi-rs/canvas-linux-riscv64-gnu 1.0.10 | MIT | [npm](https://www.npmjs.com/package/@napi-rs/canvas-linux-riscv64-gnu) |
| @napi-rs/canvas-linux-x64-gnu 1.0.10 | MIT | [npm](https://www.npmjs.com/package/@napi-rs/canvas-linux-x64-gnu) |
| @napi-rs/canvas-linux-x64-musl 1.0.10 | MIT | [npm](https://www.npmjs.com/package/@napi-rs/canvas-linux-x64-musl) |
| @napi-rs/canvas-win32-arm64-msvc 1.0.10 | MIT | [npm](https://www.npmjs.com/package/@napi-rs/canvas-win32-arm64-msvc) |
| @napi-rs/canvas-win32-x64-msvc 1.0.10 | MIT | [npm](https://www.npmjs.com/package/@napi-rs/canvas-win32-x64-msvc) |
| @oxc-project/types 0.152.0 | MIT | [npm](https://www.npmjs.com/package/@oxc-project/types) |
| @rolldown/binding-android-arm-eabi 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-android-arm-eabi) |
| @rolldown/binding-android-arm64 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-android-arm64) |
| @rolldown/binding-darwin-arm64 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-darwin-arm64) |
| @rolldown/binding-darwin-x64 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-darwin-x64) |
| @rolldown/binding-freebsd-x64 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-freebsd-x64) |
| @rolldown/binding-linux-arm-gnueabihf 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-linux-arm-gnueabihf) |
| @rolldown/binding-linux-arm64-gnu 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-linux-arm64-gnu) |
| @rolldown/binding-linux-arm64-musl 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-linux-arm64-musl) |
| @rolldown/binding-linux-ppc64-gnu 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-linux-ppc64-gnu) |
| @rolldown/binding-linux-s390x-gnu 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-linux-s390x-gnu) |
| @rolldown/binding-linux-x64-gnu 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-linux-x64-gnu) |
| @rolldown/binding-linux-x64-musl 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-linux-x64-musl) |
| @rolldown/binding-openharmony-arm64 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-openharmony-arm64) |
| @rolldown/binding-win32-arm64-msvc 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-win32-arm64-msvc) |
| @rolldown/binding-win32-x64-msvc 1.2.12 | MIT | [npm](https://www.npmjs.com/package/@rolldown/binding-win32-x64-msvc) |
| @rolldown/pluginutils 1.0.1 | MIT | [npm](https://www.npmjs.com/package/@rolldown/pluginutils) |
| @tauri-apps/api 2.12.1 | Apache-2.0 OR MIT | [npm](https://www.npmjs.com/package/@tauri-apps/api) |
| @tauri-apps/cli 2.12.1 | Apache-2.0 OR MIT | [npm](https://www.npmjs.com/package/@tauri-apps/cli) |
| @tauri-apps/cli-darwin-arm64 2.12.1 | Apache-2.0 OR MIT | [npm](https://www.npmjs.com/package/@tauri-apps/cli-darwin-arm64) |
| @tauri-apps/cli-darwin-x64 2.12.1 | Apache-2.0 OR MIT | [npm](https://www.npmjs.com/package/@tauri-apps/cli-darwin-x64) |
| @tauri-apps/cli-linux-arm-gnueabihf 2.12.1 | Apache-2.0 OR MIT | [npm](https://www.npmjs.com/package/@tauri-apps/cli-linux-arm-gnueabihf) |
| @tauri-apps/cli-linux-arm64-gnu 2.12.1 | Apache-2.0 OR MIT | [npm](https://www.npmjs.com/package/@tauri-apps/cli-linux-arm64-gnu) |
| @tauri-apps/cli-linux-arm64-musl 2.12.1 | Apache-2.0 OR MIT | [npm](https://www.npmjs.com/package/@tauri-apps/cli-linux-arm64-musl) |
| @tauri-apps/cli-linux-riscv64-gnu 2.12.1 | Apache-2.0 OR MIT | [npm](https://www.npmjs.com/package/@tauri-apps/cli-linux-riscv64-gnu) |
| @tauri-apps/cli-linux-x64-gnu 2.12.1 | Apache-2.0 OR MIT | [npm](https://www.npmjs.com/package/@tauri-apps/cli-linux-x64-gnu) |
| @tauri-apps/cli-linux-x64-musl 2.12.1 | Apache-2.0 OR MIT | [npm](https://www.npmjs.com/package/@tauri-apps/cli-linux-x64-musl) |
| @tauri-apps/cli-win32-arm64-msvc 2.12.1 | Apache-2.0 OR MIT | [npm](https://www.npmjs.com/package/@tauri-apps/cli-win32-arm64-msvc) |
| @tauri-apps/cli-win32-ia32-msvc 2.12.1 | Apache-2.0 OR MIT | [npm](https://www.npmjs.com/package/@tauri-apps/cli-win32-ia32-msvc) |
| @tauri-apps/cli-win32-x64-msvc 2.12.1 | Apache-2.0 OR MIT | [npm](https://www.npmjs.com/package/@tauri-apps/cli-win32-x64-msvc) |
| @tauri-apps/plugin-dialog 2.8.1 | MIT OR Apache-2.0 | [npm](https://www.npmjs.com/package/@tauri-apps/plugin-dialog) |
| @tauri-apps/plugin-opener 2.7.0 | MIT OR Apache-2.0 | [npm](https://www.npmjs.com/package/@tauri-apps/plugin-opener) |
| @tauri-apps/plugin-shell 2.4.0 | MIT OR Apache-2.0 | [npm](https://www.npmjs.com/package/@tauri-apps/plugin-shell) |
| @types/debug 4.1.13 | MIT | [npm](https://www.npmjs.com/package/@types/debug) |
| @types/estree 1.0.9 | MIT | [npm](https://www.npmjs.com/package/@types/estree) |
| @types/estree-jsx 1.0.5 | MIT | [npm](https://www.npmjs.com/package/@types/estree-jsx) |
| @types/hast 3.0.5 | MIT | [npm](https://www.npmjs.com/package/@types/hast) |
| @types/mdast 4.0.4 | MIT | [npm](https://www.npmjs.com/package/@types/mdast) |
| @types/ms 2.1.0 | MIT | [npm](https://www.npmjs.com/package/@types/ms) |
| @types/react 19.3.0 | MIT | [npm](https://www.npmjs.com/package/@types/react) |
| @types/react-dom 19.3.0 | MIT | [npm](https://www.npmjs.com/package/@types/react-dom) |
| @types/unist 3.0.3 | MIT | [npm](https://www.npmjs.com/package/@types/unist) |
| @ungap/structured-clone 1.4.0 | ISC | [npm](https://www.npmjs.com/package/@ungap/structured-clone) |
| @vitejs/plugin-react 6.1.2 | MIT | [npm](https://www.npmjs.com/package/@vitejs/plugin-react) |
| bail 2.0.2 | MIT | [npm](https://www.npmjs.com/package/bail) |
| ccount 2.0.1 | MIT | [npm](https://www.npmjs.com/package/ccount) |
| character-entities 2.0.2 | MIT | [npm](https://www.npmjs.com/package/character-entities) |
| character-entities-html4 2.1.0 | MIT | [npm](https://www.npmjs.com/package/character-entities-html4) |
| character-entities-legacy 3.0.0 | MIT | [npm](https://www.npmjs.com/package/character-entities-legacy) |
| character-reference-invalid 2.0.1 | MIT | [npm](https://www.npmjs.com/package/character-reference-invalid) |
| comma-separated-tokens 2.0.3 | MIT | [npm](https://www.npmjs.com/package/comma-separated-tokens) |
| csstype 3.2.3 | MIT | [npm](https://www.npmjs.com/package/csstype) |
| debug 4.4.3 | MIT | [npm](https://www.npmjs.com/package/debug) |
| decode-named-character-reference 1.3.0 | MIT | [npm](https://www.npmjs.com/package/decode-named-character-reference) |
| dequal 2.0.3 | MIT | [npm](https://www.npmjs.com/package/dequal) |
| detect-libc 2.1.2 | Apache-2.0 | [npm](https://www.npmjs.com/package/detect-libc) |
| devlop 1.1.0 | MIT | [npm](https://www.npmjs.com/package/devlop) |
| estree-util-is-identifier-name 3.0.0 | MIT | [npm](https://www.npmjs.com/package/estree-util-is-identifier-name) |
| extend 3.0.2 | MIT | [npm](https://www.npmjs.com/package/extend) |
| fdir 6.5.0 | MIT | [npm](https://www.npmjs.com/package/fdir) |
| fsevents 2.3.3 | MIT | [npm](https://www.npmjs.com/package/fsevents) |
| hast-util-to-jsx-runtime 2.3.6 | MIT | [npm](https://www.npmjs.com/package/hast-util-to-jsx-runtime) |
| hast-util-whitespace 3.0.0 | MIT | [npm](https://www.npmjs.com/package/hast-util-whitespace) |
| html-url-attributes 3.0.1 | MIT | [npm](https://www.npmjs.com/package/html-url-attributes) |
| inline-style-parser 0.2.7 | MIT | [npm](https://www.npmjs.com/package/inline-style-parser) |
| is-alphabetical 2.0.1 | MIT | [npm](https://www.npmjs.com/package/is-alphabetical) |
| is-alphanumerical 2.0.1 | MIT | [npm](https://www.npmjs.com/package/is-alphanumerical) |
| is-decimal 2.0.1 | MIT | [npm](https://www.npmjs.com/package/is-decimal) |
| is-hexadecimal 2.0.1 | MIT | [npm](https://www.npmjs.com/package/is-hexadecimal) |
| is-plain-obj 4.1.0 | MIT | [npm](https://www.npmjs.com/package/is-plain-obj) |
| lightningcss 1.33.0 | MPL-2.0 | [npm](https://www.npmjs.com/package/lightningcss) |
| lightningcss-android-arm64 1.33.0 | MPL-2.0 | [npm](https://www.npmjs.com/package/lightningcss-android-arm64) |
| lightningcss-darwin-arm64 1.33.0 | MPL-2.0 | [npm](https://www.npmjs.com/package/lightningcss-darwin-arm64) |
| lightningcss-darwin-x64 1.33.0 | MPL-2.0 | [npm](https://www.npmjs.com/package/lightningcss-darwin-x64) |
| lightningcss-freebsd-x64 1.33.0 | MPL-2.0 | [npm](https://www.npmjs.com/package/lightningcss-freebsd-x64) |
| lightningcss-linux-arm-gnueabihf 1.33.0 | MPL-2.0 | [npm](https://www.npmjs.com/package/lightningcss-linux-arm-gnueabihf) |
| lightningcss-linux-arm64-gnu 1.33.0 | MPL-2.0 | [npm](https://www.npmjs.com/package/lightningcss-linux-arm64-gnu) |
| lightningcss-linux-arm64-musl 1.33.0 | MPL-2.0 | [npm](https://www.npmjs.com/package/lightningcss-linux-arm64-musl) |
| lightningcss-linux-x64-gnu 1.33.0 | MPL-2.0 | [npm](https://www.npmjs.com/package/lightningcss-linux-x64-gnu) |
| lightningcss-linux-x64-musl 1.33.0 | MPL-2.0 | [npm](https://www.npmjs.com/package/lightningcss-linux-x64-musl) |
| lightningcss-win32-arm64-msvc 1.33.0 | MPL-2.0 | [npm](https://www.npmjs.com/package/lightningcss-win32-arm64-msvc) |
| lightningcss-win32-x64-msvc 1.33.0 | MPL-2.0 | [npm](https://www.npmjs.com/package/lightningcss-win32-x64-msvc) |
| longest-streak 3.1.0 | MIT | [npm](https://www.npmjs.com/package/longest-streak) |
| mdast-util-from-markdown 2.1.0 | MIT | [npm](https://www.npmjs.com/package/mdast-util-from-markdown) |
| mdast-util-mdx-expression 2.0.1 | MIT | [npm](https://www.npmjs.com/package/mdast-util-mdx-expression) |
| mdast-util-mdx-jsx 3.2.0 | MIT | [npm](https://www.npmjs.com/package/mdast-util-mdx-jsx) |
| mdast-util-mdxjs-esm 2.0.1 | MIT | [npm](https://www.npmjs.com/package/mdast-util-mdxjs-esm) |
| mdast-util-phrasing 4.1.0 | MIT | [npm](https://www.npmjs.com/package/mdast-util-phrasing) |
| mdast-util-to-hast 13.2.1 | MIT | [npm](https://www.npmjs.com/package/mdast-util-to-hast) |
| mdast-util-to-markdown 2.2.0 | MIT | [npm](https://www.npmjs.com/package/mdast-util-to-markdown) |
| mdast-util-to-string 4.0.0 | MIT | [npm](https://www.npmjs.com/package/mdast-util-to-string) |
| micromark 4.0.3 | MIT | [npm](https://www.npmjs.com/package/micromark) |
| micromark-core-commonmark 2.0.4 | MIT | [npm](https://www.npmjs.com/package/micromark-core-commonmark) |
| micromark-factory-destination 2.0.1 | MIT | [npm](https://www.npmjs.com/package/micromark-factory-destination) |
| micromark-factory-label 2.0.1 | MIT | [npm](https://www.npmjs.com/package/micromark-factory-label) |
| micromark-factory-space 2.1.0 | MIT | [npm](https://www.npmjs.com/package/micromark-factory-space) |
| micromark-factory-title 2.0.1 | MIT | [npm](https://www.npmjs.com/package/micromark-factory-title) |
| micromark-factory-whitespace 2.0.1 | MIT | [npm](https://www.npmjs.com/package/micromark-factory-whitespace) |
| micromark-util-character 2.1.1 | MIT | [npm](https://www.npmjs.com/package/micromark-util-character) |
| micromark-util-chunked 2.0.1 | MIT | [npm](https://www.npmjs.com/package/micromark-util-chunked) |
| micromark-util-classify-character 2.0.1 | MIT | [npm](https://www.npmjs.com/package/micromark-util-classify-character) |
| micromark-util-combine-extensions 2.0.1 | MIT | [npm](https://www.npmjs.com/package/micromark-util-combine-extensions) |
| micromark-util-decode-numeric-character-reference 2.0.2 | MIT | [npm](https://www.npmjs.com/package/micromark-util-decode-numeric-character-reference) |
| micromark-util-decode-string 2.0.1 | MIT | [npm](https://www.npmjs.com/package/micromark-util-decode-string) |
| micromark-util-edit-map 1.0.0 | MIT | [npm](https://www.npmjs.com/package/micromark-util-edit-map) |
| micromark-util-encode 2.0.1 | MIT | [npm](https://www.npmjs.com/package/micromark-util-encode) |
| micromark-util-html-tag-name 2.0.1 | MIT | [npm](https://www.npmjs.com/package/micromark-util-html-tag-name) |
| micromark-util-normalize-identifier 2.0.1 | MIT | [npm](https://www.npmjs.com/package/micromark-util-normalize-identifier) |
| micromark-util-resolve-all 2.0.1 | MIT | [npm](https://www.npmjs.com/package/micromark-util-resolve-all) |
| micromark-util-sanitize-uri 2.0.1 | MIT | [npm](https://www.npmjs.com/package/micromark-util-sanitize-uri) |
| micromark-util-subtokenize 2.1.0 | MIT | [npm](https://www.npmjs.com/package/micromark-util-subtokenize) |
| micromark-util-symbol 2.0.1 | MIT | [npm](https://www.npmjs.com/package/micromark-util-symbol) |
| micromark-util-types 2.0.3 | MIT | [npm](https://www.npmjs.com/package/micromark-util-types) |
| ms 2.1.3 | MIT | [npm](https://www.npmjs.com/package/ms) |
| nanoid 3.3.20 | MIT | [npm](https://www.npmjs.com/package/nanoid) |
| parse-entities 4.0.2 | MIT | [npm](https://www.npmjs.com/package/parse-entities) |
| @types/unist 2.0.11 | MIT | [npm](https://www.npmjs.com/package/@types/unist) |
| pdfjs-dist 6.4.299 | Apache-2.0 | [npm](https://www.npmjs.com/package/pdfjs-dist) |
| picocolors 1.1.1 | ISC | [npm](https://www.npmjs.com/package/picocolors) |
| picomatch 4.0.7 | MIT | [npm](https://www.npmjs.com/package/picomatch) |
| postcss 8.5.29 | MIT | [npm](https://www.npmjs.com/package/postcss) |
| property-information 7.2.0 | MIT | [npm](https://www.npmjs.com/package/property-information) |
| react 19.3.0 | MIT | [npm](https://www.npmjs.com/package/react) |
| react-dom 19.3.0 | MIT | [npm](https://www.npmjs.com/package/react-dom) |
| react-markdown 10.1.0 | MIT | [npm](https://www.npmjs.com/package/react-markdown) |
| remark-parse 11.0.0 | MIT | [npm](https://www.npmjs.com/package/remark-parse) |
| remark-rehype 11.1.2 | MIT | [npm](https://www.npmjs.com/package/remark-rehype) |
| rolldown 1.2.12 | MIT | [npm](https://www.npmjs.com/package/rolldown) |
| scheduler 0.28.0 | MIT | [npm](https://www.npmjs.com/package/scheduler) |
| source-map-js 1.2.2 | BSD-3-Clause | [npm](https://www.npmjs.com/package/source-map-js) |
| space-separated-tokens 2.0.2 | MIT | [npm](https://www.npmjs.com/package/space-separated-tokens) |
| stringify-entities 4.0.4 | MIT | [npm](https://www.npmjs.com/package/stringify-entities) |
| style-to-js 1.1.21 | MIT | [npm](https://www.npmjs.com/package/style-to-js) |
| style-to-object 1.0.14 | MIT | [npm](https://www.npmjs.com/package/style-to-object) |
| tinyglobby 0.2.17 | MIT | [npm](https://www.npmjs.com/package/tinyglobby) |
| trim-lines 3.0.1 | MIT | [npm](https://www.npmjs.com/package/trim-lines) |
| trough 2.2.0 | MIT | [npm](https://www.npmjs.com/package/trough) |
| typescript 6.0.3 | Apache-2.0 | [npm](https://www.npmjs.com/package/typescript) |
| unified 11.0.5 | MIT | [npm](https://www.npmjs.com/package/unified) |
| unist-util-is 6.0.1 | MIT | [npm](https://www.npmjs.com/package/unist-util-is) |
| unist-util-position 5.0.0 | MIT | [npm](https://www.npmjs.com/package/unist-util-position) |
| unist-util-stringify-position 4.0.0 | MIT | [npm](https://www.npmjs.com/package/unist-util-stringify-position) |
| unist-util-visit 5.1.0 | MIT | [npm](https://www.npmjs.com/package/unist-util-visit) |
| unist-util-visit-parents 6.0.2 | MIT | [npm](https://www.npmjs.com/package/unist-util-visit-parents) |
| vfile 6.0.3 | MIT | [npm](https://www.npmjs.com/package/vfile) |
| vfile-message 4.0.3 | MIT | [npm](https://www.npmjs.com/package/vfile-message) |
| vite 8.3.3 | MIT | [npm](https://www.npmjs.com/package/vite) |
| zwitch 2.0.4 | MIT | [npm](https://www.npmjs.com/package/zwitch) |

## Rust/Cargo 환경

| crate·버전 | 라이선스 | 출처 |
|---|---|---|
| adler2 2.0.1 | 0BSD OR MIT OR Apache-2.0 | [원본](https://crates.io/crates/adler2/2.0.1) |
| aho-corasick 1.1.5 | Unlicense OR MIT | [원본](https://crates.io/crates/aho-corasick/1.1.5) |
| alloc-no-stdlib 3.0.0 | BSD-3-Clause | [원본](https://crates.io/crates/alloc-no-stdlib/3.0.0) |
| alloc-stdlib 0.3.0 | BSD-3-Clause | [원본](https://crates.io/crates/alloc-stdlib/0.3.0) |
| alsa 0.11.0 | 원문 참조 | [원본](https://crates.io/crates/alsa/0.11.0) |
| alsa-sys 0.4.0 | 원문 참조 | [원본](https://crates.io/crates/alsa-sys/0.4.0) |
| android_system_properties 0.1.6 | 원문 참조 | [원본](https://crates.io/crates/android_system_properties/0.1.6) |
| anyhow 1.0.104 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/anyhow/1.0.104) |
| async-broadcast 0.7.2 | 원문 참조 | [원본](https://crates.io/crates/async-broadcast/0.7.2) |
| async-channel 2.5.0 | 원문 참조 | [원본](https://crates.io/crates/async-channel/2.5.0) |
| async-executor 1.14.0 | 원문 참조 | [원본](https://crates.io/crates/async-executor/1.14.0) |
| async-io 2.6.0 | 원문 참조 | [원본](https://crates.io/crates/async-io/2.6.0) |
| async-lock 3.4.2 | 원문 참조 | [원본](https://crates.io/crates/async-lock/3.4.2) |
| async-process 2.5.0 | 원문 참조 | [원본](https://crates.io/crates/async-process/2.5.0) |
| async-recursion 1.2.0 | 원문 참조 | [원본](https://crates.io/crates/async-recursion/1.2.0) |
| async-signal 0.2.14 | 원문 참조 | [원본](https://crates.io/crates/async-signal/0.2.14) |
| async-task 4.7.1 | 원문 참조 | [원본](https://crates.io/crates/async-task/4.7.1) |
| async-trait 0.1.92 | 원문 참조 | [원본](https://crates.io/crates/async-trait/0.1.92) |
| atk 0.18.2 | 원문 참조 | [원본](https://crates.io/crates/atk/0.18.2) |
| atk-sys 0.18.2 | 원문 참조 | [원본](https://crates.io/crates/atk-sys/0.18.2) |
| atomic-waker 1.1.2 | 원문 참조 | [원본](https://crates.io/crates/atomic-waker/1.1.2) |
| autocfg 1.5.1 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/autocfg/1.5.1) |
| base64 0.21.7 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/base64/0.21.7) |
| base64 0.22.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/base64/0.22.1) |
| base64 0.23.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/base64/0.23.1) |
| bit-set 0.8.0 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/bit-set/0.8.0) |
| bit-vec 0.8.0 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/bit-vec/0.8.0) |
| bitflags 1.3.2 | MIT/Apache-2.0 | [원본](https://crates.io/crates/bitflags/1.3.2) |
| bitflags 2.13.2 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/bitflags/2.13.2) |
| block-buffer 0.10.4 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/block-buffer/0.10.4) |
| block2 0.6.2 | MIT | [원본](https://crates.io/crates/block2/0.6.2) |
| blocking 1.7.0 | 원문 참조 | [원본](https://crates.io/crates/blocking/1.7.0) |
| brotli 9.0.0 | BSD-3-Clause AND MIT | [원본](https://crates.io/crates/brotli/9.0.0) |
| brotli-decompressor 6.0.1 | BSD-3-Clause/MIT | [원본](https://crates.io/crates/brotli-decompressor/6.0.1) |
| bs58 0.5.1 | MIT/Apache-2.0 | [원본](https://crates.io/crates/bs58/0.5.1) |
| bumpalo 3.20.3 | 원문 참조 | [원본](https://crates.io/crates/bumpalo/3.20.3) |
| bytemuck 1.25.2 | 원문 참조 | [원본](https://crates.io/crates/bytemuck/1.25.2) |
| byteorder 1.5.0 | Unlicense OR MIT | [원본](https://crates.io/crates/byteorder/1.5.0) |
| bytes 1.12.1 | MIT | [원본](https://crates.io/crates/bytes/1.12.1) |
| cairo-rs 0.18.5 | 원문 참조 | [원본](https://crates.io/crates/cairo-rs/0.18.5) |
| cairo-sys-rs 0.18.2 | 원문 참조 | [원본](https://crates.io/crates/cairo-sys-rs/0.18.2) |
| camino 1.2.6 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/camino/1.2.6) |
| cargo-platform 0.1.9 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/cargo-platform/0.1.9) |
| cargo_metadata 0.19.2 | MIT | [원본](https://crates.io/crates/cargo_metadata/0.19.2) |
| cargo_toml 1.0.1 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/cargo_toml/1.0.1) |
| cc 1.6.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/cc/1.6.0) |
| cesu8 1.1.0 | 원문 참조 | [원본](https://crates.io/crates/cesu8/1.1.0) |
| cfb 0.14.0 | MIT | [원본](https://crates.io/crates/cfb/0.14.0) |
| cfg-expr 0.15.8 | 원문 참조 | [원본](https://crates.io/crates/cfg-expr/0.15.8) |
| cfg-if 1.0.5 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/cfg-if/1.0.5) |
| chrono 0.4.45 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/chrono/0.4.45) |
| combine 4.6.8 | 원문 참조 | [원본](https://crates.io/crates/combine/4.6.8) |
| concurrent-queue 2.5.0 | 원문 참조 | [원본](https://crates.io/crates/concurrent-queue/2.5.0) |
| cookie 0.18.2 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/cookie/0.18.2) |
| core-foundation 0.10.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/core-foundation/0.10.1) |
| core-foundation-sys 0.8.7 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/core-foundation-sys/0.8.7) |
| core-graphics 0.25.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/core-graphics/0.25.0) |
| core-graphics-types 0.2.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/core-graphics-types/0.2.0) |
| core_detect 1.0.0 | 원문 참조 | [원본](https://crates.io/crates/core_detect/1.0.0) |
| coreaudio-rs 0.14.2 | MIT/Apache-2.0 | [원본](https://crates.io/crates/coreaudio-rs/0.14.2) |
| cpal 0.18.2 | Apache-2.0 | [원본](https://crates.io/crates/cpal/0.18.2) |
| cpufeatures 0.2.17 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/cpufeatures/0.2.17) |
| crc32fast 1.5.2 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/crc32fast/1.5.2) |
| crossbeam-channel 0.5.17 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/crossbeam-channel/0.5.17) |
| crossbeam-utils 0.8.23 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/crossbeam-utils/0.8.23) |
| crypto-common 0.1.7 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/crypto-common/0.1.7) |
| cssparser 0.37.0 | MPL-2.0 | [원본](https://crates.io/crates/cssparser/0.37.0) |
| cssparser-macros 0.7.1 | MPL-2.0 | [원본](https://crates.io/crates/cssparser-macros/0.7.1) |
| ctor 1.0.13 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/ctor/1.0.13) |
| darling 0.24.1 | MIT | [원본](https://crates.io/crates/darling/0.24.1) |
| darling_core 0.24.1 | MIT | [원본](https://crates.io/crates/darling_core/0.24.1) |
| darling_macro 0.24.1 | MIT | [원본](https://crates.io/crates/darling_macro/0.24.1) |
| dasp_sample 0.11.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/dasp_sample/0.11.0) |
| dbus 0.9.12 | 원문 참조 | [원본](https://crates.io/crates/dbus/0.9.12) |
| defmt 1.1.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/defmt/1.1.1) |
| defmt-macros 1.1.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/defmt-macros/1.1.1) |
| defmt-parser 1.0.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/defmt-parser/1.0.0) |
| deranged 0.5.8 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/deranged/0.5.8) |
| derive_more 2.1.1 | MIT | [원본](https://crates.io/crates/derive_more/2.1.1) |
| derive_more-impl 2.1.1 | MIT | [원본](https://crates.io/crates/derive_more-impl/2.1.1) |
| digest 0.10.7 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/digest/0.10.7) |
| dirs 7.0.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/dirs/7.0.0) |
| dirs-sys 0.5.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/dirs-sys/0.5.0) |
| dispatch2 0.3.1 | Zlib OR Apache-2.0 OR MIT | [원본](https://crates.io/crates/dispatch2/0.3.1) |
| displaydoc 0.2.7 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/displaydoc/0.2.7) |
| dlopen2 0.8.2 | 원문 참조 | [원본](https://crates.io/crates/dlopen2/0.8.2) |
| dlopen2_derive 0.4.3 | 원문 참조 | [원본](https://crates.io/crates/dlopen2_derive/0.4.3) |
| dom_query 0.28.0 | MIT | [원본](https://crates.io/crates/dom_query/0.28.0) |
| dpi 0.1.2 | Apache-2.0 AND MIT | [원본](https://crates.io/crates/dpi/0.1.2) |
| dtoa 1.0.11 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/dtoa/1.0.11) |
| dtoa-short 0.3.5 | MPL-2.0 | [원본](https://crates.io/crates/dtoa-short/0.3.5) |
| dunce 1.0.5 | CC0-1.0 OR MIT-0 OR Apache-2.0 | [원본](https://crates.io/crates/dunce/1.0.5) |
| dyn-clone 1.0.20 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/dyn-clone/1.0.20) |
| embed-resource 3.0.11 | MIT | [원본](https://crates.io/crates/embed-resource/3.0.11) |
| embed_plist 1.2.2 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/embed_plist/1.2.2) |
| encoding_rs 0.8.42 | (Apache-2.0 OR MIT) AND BSD-3-Clause | [원본](https://crates.io/crates/encoding_rs/0.8.42) |
| endi 1.1.1 | 원문 참조 | [원본](https://crates.io/crates/endi/1.1.1) |
| enumflags2 0.7.12 | 원문 참조 | [원본](https://crates.io/crates/enumflags2/0.7.12) |
| enumflags2_derive 0.7.12 | 원문 참조 | [원본](https://crates.io/crates/enumflags2_derive/0.7.12) |
| equivalent 1.0.2 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/equivalent/1.0.2) |
| erased-serde 0.4.10 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/erased-serde/0.4.10) |
| errno 0.3.14 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/errno/0.3.14) |
| event-listener 5.4.2 | 원문 참조 | [원본](https://crates.io/crates/event-listener/5.4.2) |
| event-listener-strategy 0.5.4 | 원문 참조 | [원본](https://crates.io/crates/event-listener-strategy/0.5.4) |
| fastrand 2.5.0 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/fastrand/2.5.0) |
| fdeflate 0.3.7 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/fdeflate/0.3.7) |
| field-offset 0.3.6 | 원문 참조 | [원본](https://crates.io/crates/field-offset/0.3.6) |
| find-msvc-tools 0.1.14 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/find-msvc-tools/0.1.14) |
| flate2 1.1.10 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/flate2/1.1.10) |
| fnv 1.0.7 | Apache-2.0 / MIT | [원본](https://crates.io/crates/fnv/1.0.7) |
| foldhash 0.2.0 | Zlib | [원본](https://crates.io/crates/foldhash/0.2.0) |
| foreign-types 0.5.0 | MIT/Apache-2.0 | [원본](https://crates.io/crates/foreign-types/0.5.0) |
| foreign-types-macros 0.2.4 | MIT/Apache-2.0 | [원본](https://crates.io/crates/foreign-types-macros/0.2.4) |
| foreign-types-shared 0.3.1 | MIT/Apache-2.0 | [원본](https://crates.io/crates/foreign-types-shared/0.3.1) |
| form_urlencoded 1.2.2 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/form_urlencoded/1.2.2) |
| futures-channel 0.3.34 | 원문 참조 | [원본](https://crates.io/crates/futures-channel/0.3.34) |
| futures-core 0.3.34 | 원문 참조 | [원본](https://crates.io/crates/futures-core/0.3.34) |
| futures-executor 0.3.34 | 원문 참조 | [원본](https://crates.io/crates/futures-executor/0.3.34) |
| futures-io 0.3.34 | 원문 참조 | [원본](https://crates.io/crates/futures-io/0.3.34) |
| futures-lite 2.6.1 | 원문 참조 | [원본](https://crates.io/crates/futures-lite/2.6.1) |
| futures-macro 0.3.34 | 원문 참조 | [원본](https://crates.io/crates/futures-macro/0.3.34) |
| futures-sink 0.3.34 | 원문 참조 | [원본](https://crates.io/crates/futures-sink/0.3.34) |
| futures-task 0.3.34 | 원문 참조 | [원본](https://crates.io/crates/futures-task/0.3.34) |
| futures-util 0.3.34 | 원문 참조 | [원본](https://crates.io/crates/futures-util/0.3.34) |
| gdk 0.18.2 | 원문 참조 | [원본](https://crates.io/crates/gdk/0.18.2) |
| gdk-pixbuf 0.18.5 | 원문 참조 | [원본](https://crates.io/crates/gdk-pixbuf/0.18.5) |
| gdk-pixbuf-sys 0.18.0 | 원문 참조 | [원본](https://crates.io/crates/gdk-pixbuf-sys/0.18.0) |
| gdk-sys 0.18.2 | 원문 참조 | [원본](https://crates.io/crates/gdk-sys/0.18.2) |
| gdkwayland-sys 0.18.2 | 원문 참조 | [원본](https://crates.io/crates/gdkwayland-sys/0.18.2) |
| gdkx11 0.18.2 | 원문 참조 | [원본](https://crates.io/crates/gdkx11/0.18.2) |
| gdkx11-sys 0.18.2 | 원문 참조 | [원본](https://crates.io/crates/gdkx11-sys/0.18.2) |
| generic-array 0.14.7 | MIT | [원본](https://crates.io/crates/generic-array/0.14.7) |
| getrandom 0.3.4 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/getrandom/0.3.4) |
| getrandom 0.4.3 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/getrandom/0.4.3) |
| gio 0.18.4 | 원문 참조 | [원본](https://crates.io/crates/gio/0.18.4) |
| gio-sys 0.18.1 | 원문 참조 | [원본](https://crates.io/crates/gio-sys/0.18.1) |
| glib 0.18.5 | 원문 참조 | [원본](https://crates.io/crates/glib/0.18.5) |
| glib-macros 0.18.5 | 원문 참조 | [원본](https://crates.io/crates/glib-macros/0.18.5) |
| glib-sys 0.18.1 | 원문 참조 | [원본](https://crates.io/crates/glib-sys/0.18.1) |
| glob 0.3.4 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/glob/0.3.4) |
| gobject-sys 0.18.0 | 원문 참조 | [원본](https://crates.io/crates/gobject-sys/0.18.0) |
| gtk 0.18.2 | 원문 참조 | [원본](https://crates.io/crates/gtk/0.18.2) |
| gtk-sys 0.18.2 | 원문 참조 | [원본](https://crates.io/crates/gtk-sys/0.18.2) |
| gtk3-macros 0.18.2 | 원문 참조 | [원본](https://crates.io/crates/gtk3-macros/0.18.2) |
| hashbrown 0.12.3 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/hashbrown/0.12.3) |
| hashbrown 0.17.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/hashbrown/0.17.1) |
| heck 0.4.1 | 원문 참조 | [원본](https://crates.io/crates/heck/0.4.1) |
| heck 0.5.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/heck/0.5.0) |
| hermit-abi 0.5.3 | 원문 참조 | [원본](https://crates.io/crates/hermit-abi/0.5.3) |
| hex 0.4.3 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/hex/0.4.3) |
| hound 3.5.1 | Apache-2.0 | [원본](https://crates.io/crates/hound/3.5.1) |
| html5ever 0.39.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/html5ever/0.39.0) |
| http 1.5.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/http/1.5.0) |
| http-body 1.1.0 | 원문 참조 | [원본](https://crates.io/crates/http-body/1.1.0) |
| http-body-util 0.1.5 | 원문 참조 | [원본](https://crates.io/crates/http-body-util/0.1.5) |
| httparse 1.10.1 | 원문 참조 | [원본](https://crates.io/crates/httparse/1.10.1) |
| hyper 1.11.1 | 원문 참조 | [원본](https://crates.io/crates/hyper/1.11.1) |
| hyper-util 0.1.21 | 원문 참조 | [원본](https://crates.io/crates/hyper-util/0.1.21) |
| iana-time-zone 0.1.65 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/iana-time-zone/0.1.65) |
| iana-time-zone-haiku 0.1.2 | 원문 참조 | [원본](https://crates.io/crates/iana-time-zone-haiku/0.1.2) |
| ico 0.5.0 | MIT | [원본](https://crates.io/crates/ico/0.5.0) |
| icu_collections 2.3.0 | Unicode-3.0 | [원본](https://crates.io/crates/icu_collections/2.3.0) |
| icu_locale_core 2.3.0 | Unicode-3.0 | [원본](https://crates.io/crates/icu_locale_core/2.3.0) |
| icu_normalizer 2.3.0 | Unicode-3.0 | [원본](https://crates.io/crates/icu_normalizer/2.3.0) |
| icu_normalizer_data 2.3.0 | Unicode-3.0 | [원본](https://crates.io/crates/icu_normalizer_data/2.3.0) |
| icu_properties 2.3.0 | Unicode-3.0 | [원본](https://crates.io/crates/icu_properties/2.3.0) |
| icu_properties_data 2.3.0 | Unicode-3.0 | [원본](https://crates.io/crates/icu_properties_data/2.3.0) |
| icu_provider 2.3.1 | Unicode-3.0 | [원본](https://crates.io/crates/icu_provider/2.3.1) |
| ident_case 1.0.1 | MIT/Apache-2.0 | [원본](https://crates.io/crates/ident_case/1.0.1) |
| idna 1.1.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/idna/1.1.0) |
| idna_adapter 1.2.2 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/idna_adapter/1.2.2) |
| indexmap 1.9.3 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/indexmap/1.9.3) |
| indexmap 2.14.2 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/indexmap/2.14.2) |
| infer 0.22.0 | MIT | [원본](https://crates.io/crates/infer/0.22.0) |
| ipnet 2.12.2 | 원문 참조 | [원본](https://crates.io/crates/ipnet/2.12.2) |
| is-docker 0.2.0 | 원문 참조 | [원본](https://crates.io/crates/is-docker/0.2.0) |
| is-wsl 0.4.0 | 원문 참조 | [원본](https://crates.io/crates/is-wsl/0.4.0) |
| itoa 1.0.18 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/itoa/1.0.18) |
| javascriptcore-rs 1.1.2 | 원문 참조 | [원본](https://crates.io/crates/javascriptcore-rs/1.1.2) |
| javascriptcore-rs-sys 1.1.1 | 원문 참조 | [원본](https://crates.io/crates/javascriptcore-rs-sys/1.1.1) |
| jiff 0.2.37 | Unlicense OR MIT | [원본](https://crates.io/crates/jiff/0.2.37) |
| jiff-core 0.1.1 | Unlicense OR MIT | [원본](https://crates.io/crates/jiff-core/0.1.1) |
| jiff-static 0.2.37 | 원문 참조 | [원본](https://crates.io/crates/jiff-static/0.2.37) |
| jiff-tzdb 0.1.8 | 원문 참조 | [원본](https://crates.io/crates/jiff-tzdb/0.1.8) |
| jiff-tzdb-platform 0.1.3 | 원문 참조 | [원본](https://crates.io/crates/jiff-tzdb-platform/0.1.3) |
| jni 0.21.1 | 원문 참조 | [원본](https://crates.io/crates/jni/0.21.1) |
| jni 0.22.4 | 원문 참조 | [원본](https://crates.io/crates/jni/0.22.4) |
| jni-macros 0.22.4 | 원문 참조 | [원본](https://crates.io/crates/jni-macros/0.22.4) |
| jni-sys 0.3.1 | 원문 참조 | [원본](https://crates.io/crates/jni-sys/0.3.1) |
| jni-sys 0.4.1 | 원문 참조 | [원본](https://crates.io/crates/jni-sys/0.4.1) |
| jni-sys-macros 0.4.1 | 원문 참조 | [원본](https://crates.io/crates/jni-sys-macros/0.4.1) |
| js-sys 0.3.106 | 원문 참조 | [원본](https://crates.io/crates/js-sys/0.3.106) |
| json-patch 4.2.0 | MIT/Apache-2.0 | [원본](https://crates.io/crates/json-patch/4.2.0) |
| jsonptr 0.7.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/jsonptr/0.7.1) |
| keyboard-types 0.8.3 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/keyboard-types/0.8.3) |
| libappindicator 0.9.0 | 원문 참조 | [원본](https://crates.io/crates/libappindicator/0.9.0) |
| libappindicator-sys 0.9.0 | 원문 참조 | [원본](https://crates.io/crates/libappindicator-sys/0.9.0) |
| libc 0.2.190 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/libc/0.2.190) |
| libdbus-sys 0.2.7 | 원문 참조 | [원본](https://crates.io/crates/libdbus-sys/0.2.7) |
| libloading 0.7.4 | 원문 참조 | [원본](https://crates.io/crates/libloading/0.7.4) |
| libredox 0.1.25 | 원문 참조 | [원본](https://crates.io/crates/libredox/0.1.25) |
| linux-raw-sys 0.12.1 | 원문 참조 | [원본](https://crates.io/crates/linux-raw-sys/0.12.1) |
| litemap 0.8.3 | Unicode-3.0 | [원본](https://crates.io/crates/litemap/0.8.3) |
| lock_api 0.4.14 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/lock_api/0.4.14) |
| log 0.4.34 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/log/0.4.34) |
| mach2 0.6.0 | BSD-2-Clause OR MIT OR Apache-2.0 | [원본](https://crates.io/crates/mach2/0.6.0) |
| markup5ever 0.39.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/markup5ever/0.39.0) |
| memchr 2.8.3 | Unlicense OR MIT | [원본](https://crates.io/crates/memchr/2.8.3) |
| memoffset 0.9.1 | 원문 참조 | [원본](https://crates.io/crates/memoffset/0.9.1) |
| mime 0.3.17 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/mime/0.3.17) |
| miniz_oxide 0.8.9 | MIT OR Zlib OR Apache-2.0 | [원본](https://crates.io/crates/miniz_oxide/0.8.9) |
| miniz_oxide 0.9.1 | MIT OR Zlib OR Apache-2.0 | [원본](https://crates.io/crates/miniz_oxide/0.9.1) |
| mio 1.2.4 | MIT | [원본](https://crates.io/crates/mio/1.2.4) |
| muda 0.20.0 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/muda/0.20.0) |
| multiversion_no_op 1.0.0 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/multiversion_no_op/1.0.0) |
| ndk 0.9.0 | 원문 참조 | [원본](https://crates.io/crates/ndk/0.9.0) |
| ndk-context 0.1.1 | 원문 참조 | [원본](https://crates.io/crates/ndk-context/0.1.1) |
| ndk-sys 0.6.0+11769913 | 원문 참조 | [원본](https://crates.io/crates/ndk-sys/0.6.0+11769913) |
| new_debug_unreachable 1.0.6 | MIT | [원본](https://crates.io/crates/new_debug_unreachable/1.0.6) |
| num-conv 0.2.2 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/num-conv/0.2.2) |
| num-derive 0.4.2 | 원문 참조 | [원본](https://crates.io/crates/num-derive/0.4.2) |
| num-traits 0.2.19 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/num-traits/0.2.19) |
| num_enum 0.7.6 | 원문 참조 | [원본](https://crates.io/crates/num_enum/0.7.6) |
| num_enum_derive 0.7.6 | 원문 참조 | [원본](https://crates.io/crates/num_enum_derive/0.7.6) |
| objc2 0.6.5 | MIT | [원본](https://crates.io/crates/objc2/0.6.5) |
| objc2-app-kit 0.3.2 | Zlib OR Apache-2.0 OR MIT | [원본](https://crates.io/crates/objc2-app-kit/0.3.2) |
| objc2-audio-toolbox 0.3.2 | Zlib OR Apache-2.0 OR MIT | [원본](https://crates.io/crates/objc2-audio-toolbox/0.3.2) |
| objc2-avf-audio 0.3.2 | 원문 참조 | [원본](https://crates.io/crates/objc2-avf-audio/0.3.2) |
| objc2-cloud-kit 0.3.2 | 원문 참조 | [원본](https://crates.io/crates/objc2-cloud-kit/0.3.2) |
| objc2-core-audio 0.3.2 | Zlib OR Apache-2.0 OR MIT | [원본](https://crates.io/crates/objc2-core-audio/0.3.2) |
| objc2-core-audio-types 0.3.2 | Zlib OR Apache-2.0 OR MIT | [원본](https://crates.io/crates/objc2-core-audio-types/0.3.2) |
| objc2-core-data 0.3.2 | 원문 참조 | [원본](https://crates.io/crates/objc2-core-data/0.3.2) |
| objc2-core-foundation 0.3.2 | Zlib OR Apache-2.0 OR MIT | [원본](https://crates.io/crates/objc2-core-foundation/0.3.2) |
| objc2-core-graphics 0.3.2 | Zlib OR Apache-2.0 OR MIT | [원본](https://crates.io/crates/objc2-core-graphics/0.3.2) |
| objc2-core-image 0.3.2 | 원문 참조 | [원본](https://crates.io/crates/objc2-core-image/0.3.2) |
| objc2-core-location 0.3.2 | 원문 참조 | [원본](https://crates.io/crates/objc2-core-location/0.3.2) |
| objc2-core-text 0.3.2 | 원문 참조 | [원본](https://crates.io/crates/objc2-core-text/0.3.2) |
| objc2-encode 4.1.0 | MIT | [원본](https://crates.io/crates/objc2-encode/4.1.0) |
| objc2-exception-helper 0.1.1 | Zlib OR Apache-2.0 OR MIT | [원본](https://crates.io/crates/objc2-exception-helper/0.1.1) |
| objc2-foundation 0.3.2 | MIT | [원본](https://crates.io/crates/objc2-foundation/0.3.2) |
| objc2-io-surface 0.3.2 | Zlib OR Apache-2.0 OR MIT | [원본](https://crates.io/crates/objc2-io-surface/0.3.2) |
| objc2-quartz-core 0.3.2 | Zlib OR Apache-2.0 OR MIT | [원본](https://crates.io/crates/objc2-quartz-core/0.3.2) |
| objc2-ui-kit 0.3.2 | 원문 참조 | [원본](https://crates.io/crates/objc2-ui-kit/0.3.2) |
| objc2-user-notifications 0.3.2 | 원문 참조 | [원본](https://crates.io/crates/objc2-user-notifications/0.3.2) |
| objc2-web-kit 0.3.2 | Zlib OR Apache-2.0 OR MIT | [원본](https://crates.io/crates/objc2-web-kit/0.3.2) |
| once_cell 1.21.4 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/once_cell/1.21.4) |
| open 5.4.4 | MIT | [원본](https://crates.io/crates/open/5.4.4) |
| option-ext 0.2.0 | MPL-2.0 | [원본](https://crates.io/crates/option-ext/0.2.0) |
| ordered-stream 0.2.0 | 원문 참조 | [원본](https://crates.io/crates/ordered-stream/0.2.0) |
| os_pipe 1.2.3 | MIT | [원본](https://crates.io/crates/os_pipe/1.2.3) |
| pango 0.18.3 | 원문 참조 | [원본](https://crates.io/crates/pango/0.18.3) |
| pango-sys 0.18.0 | 원문 참조 | [원본](https://crates.io/crates/pango-sys/0.18.0) |
| parking 2.2.1 | 원문 참조 | [원본](https://crates.io/crates/parking/2.2.1) |
| parking_lot 0.12.5 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/parking_lot/0.12.5) |
| parking_lot_core 0.9.12 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/parking_lot_core/0.9.12) |
| percent-encoding 2.3.2 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/percent-encoding/2.3.2) |
| phf 0.13.1 | MIT | [원본](https://crates.io/crates/phf/0.13.1) |
| phf_codegen 0.13.1 | MIT | [원본](https://crates.io/crates/phf_codegen/0.13.1) |
| phf_generator 0.13.1 | MIT | [원본](https://crates.io/crates/phf_generator/0.13.1) |
| phf_macros 0.13.1 | MIT | [원본](https://crates.io/crates/phf_macros/0.13.1) |
| phf_shared 0.13.1 | MIT | [원본](https://crates.io/crates/phf_shared/0.13.1) |
| pin-project-lite 0.2.17 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/pin-project-lite/0.2.17) |
| piper 0.2.5 | 원문 참조 | [원본](https://crates.io/crates/piper/0.2.5) |
| pkg-config 0.3.34 | 원문 참조 | [원본](https://crates.io/crates/pkg-config/0.3.34) |
| plist 1.10.1 | MIT | [원본](https://crates.io/crates/plist/1.10.1) |
| png 0.17.16 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/png/0.17.16) |
| png 0.18.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/png/0.18.1) |
| polling 3.11.0 | 원문 참조 | [원본](https://crates.io/crates/polling/3.11.0) |
| portable-atomic 1.15.0 | 원문 참조 | [원본](https://crates.io/crates/portable-atomic/1.15.0) |
| portable-atomic-util 0.2.8 | 원문 참조 | [원본](https://crates.io/crates/portable-atomic-util/0.2.8) |
| potential_utf 0.1.6 | Unicode-3.0 | [원본](https://crates.io/crates/potential_utf/0.1.6) |
| powerfmt 0.2.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/powerfmt/0.2.1) |
| precomputed-hash 0.1.1 | MIT | [원본](https://crates.io/crates/precomputed-hash/0.1.1) |
| proc-macro-crate 1.3.1 | 원문 참조 | [원본](https://crates.io/crates/proc-macro-crate/1.3.1) |
| proc-macro-crate 2.0.2 | 원문 참조 | [원본](https://crates.io/crates/proc-macro-crate/2.0.2) |
| proc-macro-crate 3.5.0 | 원문 참조 | [원본](https://crates.io/crates/proc-macro-crate/3.5.0) |
| proc-macro-error 1.0.4 | 원문 참조 | [원본](https://crates.io/crates/proc-macro-error/1.0.4) |
| proc-macro-error-attr 1.0.4 | 원문 참조 | [원본](https://crates.io/crates/proc-macro-error-attr/1.0.4) |
| proc-macro2 1.0.107 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/proc-macro2/1.0.107) |
| quick-xml 0.42.0 | MIT | [원본](https://crates.io/crates/quick-xml/0.42.0) |
| quote 1.0.47 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/quote/1.0.47) |
| r-efi 5.3.0 | 원문 참조 | [원본](https://crates.io/crates/r-efi/5.3.0) |
| r-efi 6.0.0 | 원문 참조 | [원본](https://crates.io/crates/r-efi/6.0.0) |
| raw-window-handle 0.6.2 | MIT OR Apache-2.0 OR Zlib | [원본](https://crates.io/crates/raw-window-handle/0.6.2) |
| redox_syscall 0.5.18 | 원문 참조 | [원본](https://crates.io/crates/redox_syscall/0.5.18) |
| redox_users 0.5.3 | 원문 참조 | [원본](https://crates.io/crates/redox_users/0.5.3) |
| ref-cast 1.0.27 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/ref-cast/1.0.27) |
| ref-cast-impl 1.0.27 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/ref-cast-impl/1.0.27) |
| regex 1.13.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/regex/1.13.1) |
| regex-automata 0.4.18 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/regex-automata/0.4.18) |
| regex-syntax 0.8.11 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/regex-syntax/0.8.11) |
| reqwest 0.13.5 | 원문 참조 | [원본](https://crates.io/crates/reqwest/0.13.5) |
| rfd 0.16.0 | MIT | [원본](https://crates.io/crates/rfd/0.16.0) |
| rustc-hash 2.1.3 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/rustc-hash/2.1.3) |
| rustc_version 0.4.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/rustc_version/0.4.1) |
| rustix 1.1.5 | 원문 참조 | [원본](https://crates.io/crates/rustix/1.1.5) |
| rustversion 1.0.23 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/rustversion/1.0.23) |
| same-file 1.0.6 | Unlicense/MIT | [원본](https://crates.io/crates/same-file/1.0.6) |
| schemars 0.8.22 | MIT | [원본](https://crates.io/crates/schemars/0.8.22) |
| schemars 0.9.0 | MIT | [원본](https://crates.io/crates/schemars/0.9.0) |
| schemars 1.2.2 | MIT | [원본](https://crates.io/crates/schemars/1.2.2) |
| schemars_derive 0.8.22 | MIT | [원본](https://crates.io/crates/schemars_derive/0.8.22) |
| scopeguard 1.2.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/scopeguard/1.2.0) |
| selectors 0.38.0 | MPL-2.0 | [원본](https://crates.io/crates/selectors/0.38.0) |
| semver 1.0.28 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/semver/1.0.28) |
| serde 1.0.229 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/serde/1.0.229) |
| serde-untagged 0.1.9 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/serde-untagged/0.1.9) |
| serde_core 1.0.229 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/serde_core/1.0.229) |
| serde_derive 1.0.229 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/serde_derive/1.0.229) |
| serde_derive_internals 0.29.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/serde_derive_internals/0.29.1) |
| serde_json 1.0.151 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/serde_json/1.0.151) |
| serde_repr 0.1.21 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/serde_repr/0.1.21) |
| serde_spanned 0.6.9 | 원문 참조 | [원본](https://crates.io/crates/serde_spanned/0.6.9) |
| serde_spanned 1.1.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/serde_spanned/1.1.1) |
| serde_with 3.24.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/serde_with/3.24.0) |
| serde_with_macros 3.24.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/serde_with_macros/3.24.0) |
| serialize-to-javascript 0.1.2 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/serialize-to-javascript/0.1.2) |
| serialize-to-javascript-impl 0.1.2 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/serialize-to-javascript-impl/0.1.2) |
| servo_arc 0.4.3 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/servo_arc/0.4.3) |
| sha2 0.10.9 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/sha2/0.10.9) |
| shared_child 1.1.2 | MIT | [원본](https://crates.io/crates/shared_child/1.1.2) |
| shlex 2.0.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/shlex/2.0.1) |
| sigchld 0.2.5 | MIT | [원본](https://crates.io/crates/sigchld/0.2.5) |
| signal-hook 0.4.5 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/signal-hook/0.4.5) |
| signal-hook-registry 1.4.8 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/signal-hook-registry/1.4.8) |
| simd-adler32 0.3.10 | MIT | [원본](https://crates.io/crates/simd-adler32/0.3.10) |
| simd_cesu8 1.2.0 | 원문 참조 | [원본](https://crates.io/crates/simd_cesu8/1.2.0) |
| simdutf8 0.1.5 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/simdutf8/0.1.5) |
| siphasher 1.0.4 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/siphasher/1.0.4) |
| slab 0.4.12 | 원문 참조 | [원본](https://crates.io/crates/slab/0.4.12) |
| smallvec 1.16.2 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/smallvec/1.16.2) |
| socket2 0.6.5 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/socket2/0.6.5) |
| softbuffer 0.4.8 | 원문 참조 | [원본](https://crates.io/crates/softbuffer/0.4.8) |
| soup3 0.5.0 | 원문 참조 | [원본](https://crates.io/crates/soup3/0.5.0) |
| soup3-sys 0.5.0 | 원문 참조 | [원본](https://crates.io/crates/soup3-sys/0.5.0) |
| stable_deref_trait 1.2.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/stable_deref_trait/1.2.1) |
| string_cache 0.9.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/string_cache/0.9.0) |
| string_cache_codegen 0.6.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/string_cache_codegen/0.6.1) |
| strsim 0.11.1 | MIT | [원본](https://crates.io/crates/strsim/0.11.1) |
| swift-rs 1.0.8 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/swift-rs/1.0.8) |
| syn 1.0.109 | 원문 참조 | [원본](https://crates.io/crates/syn/1.0.109) |
| syn 2.0.119 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/syn/2.0.119) |
| syn 3.0.6 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/syn/3.0.6) |
| sync_wrapper 1.0.2 | 원문 참조 | [원본](https://crates.io/crates/sync_wrapper/1.0.2) |
| synstructure 0.14.0 | MIT | [원본](https://crates.io/crates/synstructure/0.14.0) |
| system-deps 6.2.2 | 원문 참조 | [원본](https://crates.io/crates/system-deps/6.2.2) |
| tao 0.37.1 | Apache-2.0 | [원본](https://crates.io/crates/tao/0.37.1) |
| tao-macros 0.1.4 | 원문 참조 | [원본](https://crates.io/crates/tao-macros/0.1.4) |
| target-lexicon 0.12.16 | 원문 참조 | [원본](https://crates.io/crates/target-lexicon/0.12.16) |
| tauri 2.12.1 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/tauri/2.12.1) |
| tauri-build 2.7.1 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/tauri-build/2.7.1) |
| tauri-codegen 2.7.1 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/tauri-codegen/2.7.1) |
| tauri-macros 2.7.1 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/tauri-macros/2.7.1) |
| tauri-plugin 2.7.1 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/tauri-plugin/2.7.1) |
| tauri-plugin-dialog 2.8.1 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/tauri-plugin-dialog/2.8.1) |
| tauri-plugin-fs 2.6.0 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/tauri-plugin-fs/2.6.0) |
| tauri-plugin-opener 2.7.0 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/tauri-plugin-opener/2.7.0) |
| tauri-plugin-shell 2.4.0 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/tauri-plugin-shell/2.4.0) |
| tauri-runtime 2.12.1 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/tauri-runtime/2.12.1) |
| tauri-runtime-wry 2.12.1 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/tauri-runtime-wry/2.12.1) |
| tauri-utils 2.10.1 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/tauri-utils/2.10.1) |
| tauri-winres 0.3.6 | MIT | [원본](https://crates.io/crates/tauri-winres/0.3.6) |
| tempfile 3.27.0 | 원문 참조 | [원본](https://crates.io/crates/tempfile/3.27.0) |
| tendril 0.5.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/tendril/0.5.1) |
| thiserror 1.0.69 | 원문 참조 | [원본](https://crates.io/crates/thiserror/1.0.69) |
| thiserror 2.0.21 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/thiserror/2.0.21) |
| thiserror-impl 1.0.69 | 원문 참조 | [원본](https://crates.io/crates/thiserror-impl/1.0.69) |
| thiserror-impl 2.0.21 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/thiserror-impl/2.0.21) |
| time 0.3.55 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/time/0.3.55) |
| time-core 0.1.9 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/time-core/0.1.9) |
| time-macros 0.2.32 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/time-macros/0.2.32) |
| tinystr 0.8.4 | Unicode-3.0 | [원본](https://crates.io/crates/tinystr/0.8.4) |
| tinyvec 1.13.3 | Zlib OR Apache-2.0 OR MIT | [원본](https://crates.io/crates/tinyvec/1.13.3) |
| tokio 1.53.2 | MIT | [원본](https://crates.io/crates/tokio/1.53.2) |
| tokio-util 0.7.19 | 원문 참조 | [원본](https://crates.io/crates/tokio-util/0.7.19) |
| toml 0.8.2 | 원문 참조 | [원본](https://crates.io/crates/toml/0.8.2) |
| toml 1.1.6+spec-1.1.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/toml/1.1.6+spec-1.1.0) |
| toml_datetime 0.6.3 | 원문 참조 | [원본](https://crates.io/crates/toml_datetime/0.6.3) |
| toml_datetime 1.1.1+spec-1.1.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/toml_datetime/1.1.1+spec-1.1.0) |
| toml_edit 0.19.15 | 원문 참조 | [원본](https://crates.io/crates/toml_edit/0.19.15) |
| toml_edit 0.20.2 | 원문 참조 | [원본](https://crates.io/crates/toml_edit/0.20.2) |
| toml_edit 0.25.15+spec-1.1.0 | 원문 참조 | [원본](https://crates.io/crates/toml_edit/0.25.15+spec-1.1.0) |
| toml_parser 1.1.3+spec-1.1.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/toml_parser/1.1.3+spec-1.1.0) |
| toml_writer 1.1.2+spec-1.1.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/toml_writer/1.1.2+spec-1.1.0) |
| tower 0.5.3 | 원문 참조 | [원본](https://crates.io/crates/tower/0.5.3) |
| tower-http 0.6.11 | 원문 참조 | [원본](https://crates.io/crates/tower-http/0.6.11) |
| tower-layer 0.3.3 | 원문 참조 | [원본](https://crates.io/crates/tower-layer/0.3.3) |
| tower-service 0.3.3 | 원문 참조 | [원본](https://crates.io/crates/tower-service/0.3.3) |
| tracing 0.1.44 | 원문 참조 | [원본](https://crates.io/crates/tracing/0.1.44) |
| tracing-attributes 0.1.31 | 원문 참조 | [원본](https://crates.io/crates/tracing-attributes/0.1.31) |
| tracing-core 0.1.36 | 원문 참조 | [원본](https://crates.io/crates/tracing-core/0.1.36) |
| tray-icon 0.25.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/tray-icon/0.25.1) |
| try-lock 0.2.5 | 원문 참조 | [원본](https://crates.io/crates/try-lock/0.2.5) |
| typeid 1.0.3 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/typeid/1.0.3) |
| typenum 1.20.1 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/typenum/1.20.1) |
| uds_windows 1.2.1 | 원문 참조 | [원본](https://crates.io/crates/uds_windows/1.2.1) |
| unicode-ident 1.0.26 | (MIT OR Apache-2.0) AND Unicode-3.0 | [원본](https://crates.io/crates/unicode-ident/1.0.26) |
| unicode-segmentation 1.13.3 | 원문 참조 | [원본](https://crates.io/crates/unicode-segmentation/1.13.3) |
| url 2.5.8 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/url/2.5.8) |
| urlpattern 0.6.0 | MIT | [원본](https://crates.io/crates/urlpattern/0.6.0) |
| utf8_iter 1.0.4 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/utf8_iter/1.0.4) |
| uuid 1.27.0 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/uuid/1.27.0) |
| version-compare 0.2.1 | 원문 참조 | [원본](https://crates.io/crates/version-compare/0.2.1) |
| version_check 0.9.5 | MIT/Apache-2.0 | [원본](https://crates.io/crates/version_check/0.9.5) |
| vswhom 0.1.0 | 원문 참조 | [원본](https://crates.io/crates/vswhom/0.1.0) |
| vswhom-sys 0.1.3 | 원문 참조 | [원본](https://crates.io/crates/vswhom-sys/0.1.3) |
| walkdir 2.5.0 | Unlicense/MIT | [원본](https://crates.io/crates/walkdir/2.5.0) |
| want 0.3.2 | 원문 참조 | [원본](https://crates.io/crates/want/0.3.2) |
| wasi 0.11.1+wasi-snapshot-preview1 | 원문 참조 | [원본](https://crates.io/crates/wasi/0.11.1+wasi-snapshot-preview1) |
| wasip2 1.0.4+wasi-0.2.12 | 원문 참조 | [원본](https://crates.io/crates/wasip2/1.0.4+wasi-0.2.12) |
| wasm-bindgen 0.2.129 | 원문 참조 | [원본](https://crates.io/crates/wasm-bindgen/0.2.129) |
| wasm-bindgen-futures 0.4.79 | 원문 참조 | [원본](https://crates.io/crates/wasm-bindgen-futures/0.4.79) |
| wasm-bindgen-macro 0.2.129 | 원문 참조 | [원본](https://crates.io/crates/wasm-bindgen-macro/0.2.129) |
| wasm-bindgen-macro-support 0.2.129 | 원문 참조 | [원본](https://crates.io/crates/wasm-bindgen-macro-support/0.2.129) |
| wasm-bindgen-shared 0.2.129 | 원문 참조 | [원본](https://crates.io/crates/wasm-bindgen-shared/0.2.129) |
| wasm-streams 0.5.0 | 원문 참조 | [원본](https://crates.io/crates/wasm-streams/0.5.0) |
| web-sys 0.3.106 | 원문 참조 | [원본](https://crates.io/crates/web-sys/0.3.106) |
| web-time 1.1.0 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/web-time/1.1.0) |
| web_atoms 0.2.6 | MIT OR Apache-2.0 | [원본](https://crates.io/crates/web_atoms/0.2.6) |
| webkit2gtk 2.0.2 | 원문 참조 | [원본](https://crates.io/crates/webkit2gtk/2.0.2) |
| webkit2gtk-sys 2.0.2 | 원문 참조 | [원본](https://crates.io/crates/webkit2gtk-sys/2.0.2) |
| webview2-com 0.39.1 | 원문 참조 | [원본](https://crates.io/crates/webview2-com/0.39.1) |
| webview2-com-macros 0.8.1 | 원문 참조 | [원본](https://crates.io/crates/webview2-com-macros/0.8.1) |
| webview2-com-sys 0.39.1 | 원문 참조 | [원본](https://crates.io/crates/webview2-com-sys/0.39.1) |
| winapi 0.3.9 | 원문 참조 | [원본](https://crates.io/crates/winapi/0.3.9) |
| winapi-i686-pc-windows-gnu 0.4.0 | 원문 참조 | [원본](https://crates.io/crates/winapi-i686-pc-windows-gnu/0.4.0) |
| winapi-util 0.1.11 | 원문 참조 | [원본](https://crates.io/crates/winapi-util/0.1.11) |
| winapi-x86_64-pc-windows-gnu 0.4.0 | 원문 참조 | [원본](https://crates.io/crates/winapi-x86_64-pc-windows-gnu/0.4.0) |
| window-vibrancy 0.8.1 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/window-vibrancy/0.8.1) |
| windows 0.62.2 | 원문 참조 | [원본](https://crates.io/crates/windows/0.62.2) |
| windows-collections 0.3.2 | 원문 참조 | [원본](https://crates.io/crates/windows-collections/0.3.2) |
| windows-core 0.62.2 | 원문 참조 | [원본](https://crates.io/crates/windows-core/0.62.2) |
| windows-future 0.3.2 | 원문 참조 | [원본](https://crates.io/crates/windows-future/0.3.2) |
| windows-implement 0.60.2 | 원문 참조 | [원본](https://crates.io/crates/windows-implement/0.60.2) |
| windows-interface 0.59.3 | 원문 참조 | [원본](https://crates.io/crates/windows-interface/0.59.3) |
| windows-link 0.2.1 | 원문 참조 | [원본](https://crates.io/crates/windows-link/0.2.1) |
| windows-numerics 0.3.1 | 원문 참조 | [원본](https://crates.io/crates/windows-numerics/0.3.1) |
| windows-result 0.4.1 | 원문 참조 | [원본](https://crates.io/crates/windows-result/0.4.1) |
| windows-strings 0.5.1 | 원문 참조 | [원본](https://crates.io/crates/windows-strings/0.5.1) |
| windows-sys 0.45.0 | 원문 참조 | [원본](https://crates.io/crates/windows-sys/0.45.0) |
| windows-sys 0.59.0 | 원문 참조 | [원본](https://crates.io/crates/windows-sys/0.59.0) |
| windows-sys 0.60.2 | 원문 참조 | [원본](https://crates.io/crates/windows-sys/0.60.2) |
| windows-sys 0.61.2 | 원문 참조 | [원본](https://crates.io/crates/windows-sys/0.61.2) |
| windows-targets 0.42.2 | 원문 참조 | [원본](https://crates.io/crates/windows-targets/0.42.2) |
| windows-targets 0.52.6 | 원문 참조 | [원본](https://crates.io/crates/windows-targets/0.52.6) |
| windows-targets 0.53.5 | 원문 참조 | [원본](https://crates.io/crates/windows-targets/0.53.5) |
| windows-threading 0.2.1 | 원문 참조 | [원본](https://crates.io/crates/windows-threading/0.2.1) |
| windows-version 0.1.7 | 원문 참조 | [원본](https://crates.io/crates/windows-version/0.1.7) |
| windows_aarch64_gnullvm 0.42.2 | 원문 참조 | [원본](https://crates.io/crates/windows_aarch64_gnullvm/0.42.2) |
| windows_aarch64_gnullvm 0.52.6 | 원문 참조 | [원본](https://crates.io/crates/windows_aarch64_gnullvm/0.52.6) |
| windows_aarch64_gnullvm 0.53.1 | 원문 참조 | [원본](https://crates.io/crates/windows_aarch64_gnullvm/0.53.1) |
| windows_aarch64_msvc 0.42.2 | 원문 참조 | [원본](https://crates.io/crates/windows_aarch64_msvc/0.42.2) |
| windows_aarch64_msvc 0.52.6 | 원문 참조 | [원본](https://crates.io/crates/windows_aarch64_msvc/0.52.6) |
| windows_aarch64_msvc 0.53.1 | 원문 참조 | [원본](https://crates.io/crates/windows_aarch64_msvc/0.53.1) |
| windows_i686_gnu 0.42.2 | 원문 참조 | [원본](https://crates.io/crates/windows_i686_gnu/0.42.2) |
| windows_i686_gnu 0.52.6 | 원문 참조 | [원본](https://crates.io/crates/windows_i686_gnu/0.52.6) |
| windows_i686_gnu 0.53.1 | 원문 참조 | [원본](https://crates.io/crates/windows_i686_gnu/0.53.1) |
| windows_i686_gnullvm 0.52.6 | 원문 참조 | [원본](https://crates.io/crates/windows_i686_gnullvm/0.52.6) |
| windows_i686_gnullvm 0.53.1 | 원문 참조 | [원본](https://crates.io/crates/windows_i686_gnullvm/0.53.1) |
| windows_i686_msvc 0.42.2 | 원문 참조 | [원본](https://crates.io/crates/windows_i686_msvc/0.42.2) |
| windows_i686_msvc 0.52.6 | 원문 참조 | [원본](https://crates.io/crates/windows_i686_msvc/0.52.6) |
| windows_i686_msvc 0.53.1 | 원문 참조 | [원본](https://crates.io/crates/windows_i686_msvc/0.53.1) |
| windows_x86_64_gnu 0.42.2 | 원문 참조 | [원본](https://crates.io/crates/windows_x86_64_gnu/0.42.2) |
| windows_x86_64_gnu 0.52.6 | 원문 참조 | [원본](https://crates.io/crates/windows_x86_64_gnu/0.52.6) |
| windows_x86_64_gnu 0.53.1 | 원문 참조 | [원본](https://crates.io/crates/windows_x86_64_gnu/0.53.1) |
| windows_x86_64_gnullvm 0.42.2 | 원문 참조 | [원본](https://crates.io/crates/windows_x86_64_gnullvm/0.42.2) |
| windows_x86_64_gnullvm 0.52.6 | 원문 참조 | [원본](https://crates.io/crates/windows_x86_64_gnullvm/0.52.6) |
| windows_x86_64_gnullvm 0.53.1 | 원문 참조 | [원본](https://crates.io/crates/windows_x86_64_gnullvm/0.53.1) |
| windows_x86_64_msvc 0.42.2 | 원문 참조 | [원본](https://crates.io/crates/windows_x86_64_msvc/0.42.2) |
| windows_x86_64_msvc 0.52.6 | 원문 참조 | [원본](https://crates.io/crates/windows_x86_64_msvc/0.52.6) |
| windows_x86_64_msvc 0.53.1 | 원문 참조 | [원본](https://crates.io/crates/windows_x86_64_msvc/0.53.1) |
| winnow 0.5.40 | 원문 참조 | [원본](https://crates.io/crates/winnow/0.5.40) |
| winnow 1.0.4 | MIT | [원본](https://crates.io/crates/winnow/1.0.4) |
| winreg 0.55.0 | 원문 참조 | [원본](https://crates.io/crates/winreg/0.55.0) |
| wit-bindgen 0.57.1 | 원문 참조 | [원본](https://crates.io/crates/wit-bindgen/0.57.1) |
| writeable 0.6.4 | Unicode-3.0 | [원본](https://crates.io/crates/writeable/0.6.4) |
| wry 0.57.0 | Apache-2.0 OR MIT | [원본](https://crates.io/crates/wry/0.57.0) |
| x11 2.21.0 | 원문 참조 | [원본](https://crates.io/crates/x11/2.21.0) |
| x11-dl 2.21.0 | 원문 참조 | [원본](https://crates.io/crates/x11-dl/2.21.0) |
| yoke 0.8.3 | Unicode-3.0 | [원본](https://crates.io/crates/yoke/0.8.3) |
| yoke-derive 0.8.4 | Unicode-3.0 | [원본](https://crates.io/crates/yoke-derive/0.8.4) |
| zbus 5.19.0 | 원문 참조 | [원본](https://crates.io/crates/zbus/5.19.0) |
| zbus_macros 5.19.0 | 원문 참조 | [원본](https://crates.io/crates/zbus_macros/5.19.0) |
| zbus_names 4.3.4 | 원문 참조 | [원본](https://crates.io/crates/zbus_names/4.3.4) |
| zcheapstr 1.1.0 | 원문 참조 | [원본](https://crates.io/crates/zcheapstr/1.1.0) |
| zerofrom 0.1.8 | Unicode-3.0 | [원본](https://crates.io/crates/zerofrom/0.1.8) |
| zerofrom-derive 0.1.8 | Unicode-3.0 | [원본](https://crates.io/crates/zerofrom-derive/0.1.8) |
| zerotrie 0.2.5 | Unicode-3.0 | [원본](https://crates.io/crates/zerotrie/0.2.5) |
| zerovec 0.11.8 | Unicode-3.0 | [원본](https://crates.io/crates/zerovec/0.11.8) |
| zerovec-derive 0.11.6 | Unicode-3.0 | [원본](https://crates.io/crates/zerovec-derive/0.11.6) |
| zlib-rs 0.6.8 | Zlib | [원본](https://crates.io/crates/zlib-rs/0.6.8) |
| zmij 1.0.23 | MIT | [원본](https://crates.io/crates/zmij/1.0.23) |
| zvariant 5.15.0 | 원문 참조 | [원본](https://crates.io/crates/zvariant/5.15.0) |
| zvariant_derive 5.15.0 | 원문 참조 | [원본](https://crates.io/crates/zvariant_derive/5.15.0) |
| zvariant_utils 4.2.0 | 원문 참조 | [원본](https://crates.io/crates/zvariant_utils/4.2.0) |

PyInstaller는 GPL-2.0-or-later와 bootloader 배포 예외를 사용합니다. 생성한 실행 파일에 대한 예외는 포함된 PyInstaller 원문을 참조하세요. VNote 자체 코드의 별도 공개 라이선스는 아직 지정하지 않았습니다.
