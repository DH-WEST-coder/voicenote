import json
import os
import subprocess
from pathlib import Path
from types import SimpleNamespace
from engine import models


def test_distribution_isolation(work_dir):
    script = '''from engine.core import *
import json
print(json.dumps([str(CONFIG), str(DEFAULT_OUT), load_profiles(), load_config(), default_asr_model(), resolve_wiki_dir("/wiki", "/vault")]))'''
    (work_dir / 'config.json').write_text(json.dumps({'vault': '/private', 'asr_model': models.LIVE_MODEL}))
    result = subprocess.run([__import__('sys').executable, '-c', script], env={**os.environ, 'VNOTE_DATA_DIR': str(work_dir)}, capture_output=True, text=True)
    assert result.returncode == 0
    data = json.loads(result.stdout)
    assert data == [str(work_dir / 'config.json'), str(work_dir / 'transcripts'), {}, {'vault': '', 'semester': ''}, models.LIVE_MODEL, None]


def test_status_without_loading_models(work_dir, monkeypatch):
    monkeypatch.setenv('HF_HOME', str(work_dir))
    monkeypatch.setattr(models, 'fluid_root', lambda: work_dir / 'fluid')
    assert not any(m['downloaded'] for m in models.status()['models'])
    base = work_dir / 'hub' / ('models--' + models.LIVE_MODEL.replace('/', '--'))
    snap = base / 'snapshots/revision'
    snap.mkdir(parents=True)
    (snap / 'config.json').write_text('{}')
    (snap / 'weights.safetensors').write_bytes(b'weights')
    assert models.model_status(models.LIVE_MODEL)['downloaded']


def test_download_lite_and_preserve_config(work_dir, monkeypatch, capsys):
    monkeypatch.setenv('HF_HOME', str(work_dir))
    monkeypatch.setattr(models, 'CONFIG', work_dir / 'config.json')
    models.CONFIG.write_text('{"other": 1}')
    called = []
    monkeypatch.setattr('huggingface_hub.snapshot_download', lambda repo, **kw: called.append(repo))
    monkeypatch.setattr(models, 'warm_fluid', lambda emit: called.append('fluid'))
    assert models.run_models(SimpleNamespace(model_action='download', set='lite', json=True)) == 0
    assert called == [models.LIVE_MODEL, models.ALIGNER, 'fluid']
    assert json.loads(models.CONFIG.read_text()) == {'other': 1, 'asr_model': models.LIVE_MODEL}
    assert json.loads(capsys.readouterr().out.splitlines()[-1])['status'] == 'done'
