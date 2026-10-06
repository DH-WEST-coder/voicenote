"""기준/새 출력 비교. 실행: .venv/bin/python tests/compare_regression.py"""
import difflib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "out/dist-test"


def read_events(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def diff(name, before, after):
    return ''.join(difflib.unified_diff(before, after, fromfile=f"baseline/{name}",
                                      tofile=f"after/{name}")) or "차이 없음\n"


def compare():
    report = []
    passed = True
    for stem in ['clip_ko_3min', 'clip_en_2min']:
        baseline = next((ROOT / 'baseline').glob(f'* {stem}.md'))
        after = next((ROOT / 'after').glob(f'* {stem}.md'), None)
        if after is None:
            report.append(f"{stem}.md: 새 대본 없음. date:/source: 제외 본문 diff 불가.\n")
            passed = False
        else:
            normalize = lambda path: [line + '\n' for line in path.read_text().splitlines()
                                     if not line.startswith(('date:', 'source:'))]
            before, actual = normalize(baseline), normalize(after)
            report.append(diff(baseline.name, before, actual))
            passed &= before == actual
        name = f'{stem}.progress.jsonl'
        # 진행 값/출력 경로와 별개로 종류와 순서를 비교한다.
        normalize = lambda path: [f"{e['stage']}/{e.get('status', '-')}\n" for e in read_events(path)]
        before, actual = normalize(ROOT / 'baseline' / name), normalize(ROOT / 'after' / name)
        report.append(diff(name, before, actual))
        passed &= before == actual
    name = 'live_ko_30s.jsonl'
    normalize = lambda path: [json.dumps({key: e[key] for key in ('type', 'text')
                                        if key in e and (key != 'text' or e['type'] == 'commit')},
                                       ensure_ascii=False) + '\n' for e in read_events(path)]
    before, actual = normalize(ROOT / 'baseline' / name), normalize(ROOT / 'after' / name)
    report.append(diff(name, before, actual))
    passed &= before == actual
    output = ''.join(report)
    (ROOT / 'after/regression.diff').write_text(output)
    print(output, end='')
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(compare())
