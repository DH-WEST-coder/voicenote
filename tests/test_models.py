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
    (snap / 'tokenizer.json').write_text('{}')
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


def test_download_failure_keeps_selected_model(work_dir, monkeypatch, capsys):
    monkeypatch.setenv('VNOTE_DATA_DIR', str(work_dir))
    monkeypatch.setattr(models, 'CONFIG', work_dir / 'config.json')
    models.CONFIG.write_text('{"asr_model": "old"}')
    def fail(*args, **kwargs):
        raise RuntimeError('offline')
    monkeypatch.setattr('huggingface_hub.snapshot_download', fail)
    assert models.run_models(SimpleNamespace(model_action='download', set='full', json=True)) == 1
    assert json.loads(models.CONFIG.read_text())['asr_model'] == 'old'
    assert json.loads(capsys.readouterr().out.splitlines()[-1])['status'] == 'error'


def test_fluid_home_is_distribution_local(work_dir, monkeypatch):
    monkeypatch.setenv('VNOTE_DATA_DIR', str(work_dir))
    assert models.fluid_env()['CFFIXED_USER_HOME'] == str(work_dir / 'models/fluid-home')
    assert models.fluid_root() == work_dir / 'models/fluid-home/Library/Application Support/FluidAudio/Models'


def test_partial_snapshot_is_not_ready(work_dir):
    (work_dir / 'config.json').write_text('{}')
    (work_dir / 'tokenizer.json').write_text('{}')
    (work_dir / 'model-00001.safetensors').write_bytes(b'weight')
    (work_dir / 'model.safetensors.index.json').write_text(json.dumps({
        'weight_map': {'a': 'model-00001.safetensors', 'b': 'model-00002.safetensors'}}))
    assert not models.snapshot_complete(work_dir)
    (work_dir / 'model-00002.safetensors').write_bytes(b'weight')
    assert models.snapshot_complete(work_dir)
    (work_dir / 'tokenizer.json').unlink()
    assert not models.snapshot_complete(work_dir)


def test_fluid_requires_all_offline_models(work_dir, monkeypatch):
    monkeypatch.setenv('HF_HOME', str(work_dir))
    monkeypatch.setattr(models, 'fluid_root', lambda: work_dir / 'fluid')
    root = work_dir / 'fluid/repo'
    root.mkdir(parents=True)
    (root / 'plda-parameters.json').write_text('{}')
    assert not models.status()['models'][-1]['downloaded']
    for name in ('Segmentation', 'Embedding', 'FBank', 'PldaRho'):
        model = root / (name + '.mlmodelc')
        model.mkdir()
        (model / 'weights.bin').write_bytes(b'weight')
    assert models.status()['models'][-1]['downloaded']


def test_warm_fluid_invocation_is_isolated(work_dir, monkeypatch):
    monkeypatch.setenv('VNOTE_DATA_DIR', str(work_dir))
    binary = work_dir / 'fluidaudiocli'
    binary.touch()
    monkeypatch.setenv('VNOTE_FLUID_BIN', str(binary))
    monkeypatch.setattr(models, 'CONFIG', work_dir / 'config.json')
    def run(command, **kwargs):
        import wave
        with wave.open(command[2]) as wav:
            assert (wav.getnchannels(), wav.getframerate(), wav.getnframes()) == (1, 16000, 48000)
        assert kwargs['env']['CFFIXED_USER_HOME'].startswith(str(work_dir))
        assert command[3:5] == ['--mode', 'offline']
        return SimpleNamespace(returncode=0)
    monkeypatch.setattr(models.subprocess, 'run', run)
    events = []
    models.warm_fluid(lambda kind, **data: events.append(data))
    assert [e['progress'] for e in events] == [0, 1]
