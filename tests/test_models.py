import json
import os
import subprocess
import pytest
from pathlib import Path
from types import SimpleNamespace
from engine import models


def test_distribution_isolation(work_dir):
    script = '''from engine.core import *
import json
print(json.dumps([str(CONFIG), str(DEFAULT_OUT), load_profiles(), load_config(), default_asr_model(), default_live_model(), resolve_wiki_dir("/wiki", "/vault")]))'''
    (work_dir / 'config.json').write_text(json.dumps({'vault': '/private', 'asr_model': models.LIVE_MODEL, 'live_model': models.ASR_MODEL}))
    result = subprocess.run([__import__('sys').executable, '-c', script], env={**os.environ, 'VNOTE_DATA_DIR': str(work_dir)}, capture_output=True, text=True)
    assert result.returncode == 0
    data = json.loads(result.stdout)
    assert data == [str(work_dir / 'config.json'), str(work_dir / 'transcripts'), {}, {'vault': '', 'semester': ''}, models.LIVE_MODEL, models.ASR_MODEL, None]


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
    assert json.loads(models.CONFIG.read_text()) == {'other': 1, 'asr_model': models.LIVE_MODEL, 'live_model': models.LIVE_MODEL}
    assert json.loads(capsys.readouterr().out.splitlines()[-1])['status'] == 'done'


def test_download_selected_models_only(work_dir, monkeypatch, capsys):
    monkeypatch.setenv('HF_HOME', str(work_dir))
    monkeypatch.setenv('VNOTE_DATA_DIR', str(work_dir))
    monkeypatch.setattr(models, 'CONFIG', work_dir / 'config.json')
    models.CONFIG.write_text('{}')
    called = []
    monkeypatch.setattr('huggingface_hub.snapshot_download', lambda repo, **kw: called.append(repo))
    monkeypatch.setattr(models, 'warm_fluid', lambda emit: called.append('fluid'))
    selected = models.ASR_MODEL
    assert models.run_models(SimpleNamespace(model_action='download', models=selected, set=None, json=True)) == 0
    assert called == [selected, models.ALIGNER, 'fluid']
    assert json.loads(models.CONFIG.read_text()) == {'asr_model': selected, 'live_model': models.LIVE_MODEL}
    assert json.loads(capsys.readouterr().out.splitlines()[-1])['models'] == [selected]


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
        return SimpleNamespace(returncode=0, stderr="")
    monkeypatch.setattr(models.subprocess, 'run', run)
    monkeypatch.setattr(models, "fluid_complete", lambda: True)
    events = []
    models.warm_fluid(lambda kind, **data: events.append(data))
    assert [e['progress'] for e in events] == [0, 1]


@pytest.mark.parametrize('model,files', [
    (models.ASR_MODEL, 'README.md config.json merges.txt quantization_config.json tokenizer_config.json vocab.json weights.safetensors'),
    (models.LIVE_MODEL, 'README.md config.json merges.txt quantization_config.json tokenizer_config.json vocab.json weights.safetensors'),
    (models.ALIGNER, 'README.md chat_template.json config.json generation_config.json merges.txt model.safetensors preprocessor_config.json tokenizer_config.json vocab.json'),
])
def test_real_snapshot_layout(work_dir, monkeypatch, model, files):
    monkeypatch.setenv('HF_HOME', str(work_dir))
    snap = work_dir / 'hub' / ('models--' + model.replace('/', '--')) / 'snapshots/revision'
    snap.mkdir(parents=True)
    for name in files.split():
        (snap / name).write_bytes(b'content')
    assert models.model_status(model)['downloaded']
    weight = next(snap.glob('*.safetensors'))
    weight.write_bytes(b'')
    assert not models.snapshot_complete(snap)
    weight.write_bytes(b'weight')
    (snap / 'merges.txt').unlink()
    assert not models.snapshot_complete(snap)


def fake_fluid(work_dir, monkeypatch, complete, exit_code):
    monkeypatch.setenv('VNOTE_DATA_DIR', str(work_dir))
    monkeypatch.setattr(models, 'CONFIG', work_dir / 'config.json')
    binary = work_dir / 'fluidaudiocli'
    binary.write_text("#!/bin/sh\n" + (
        'root="$CFFIXED_USER_HOME/Library/Application Support/FluidAudio/Models/repo"\n'
        'mkdir -p "$root"\n'
        'for name in Segmentation Embedding FBank PldaRho; do mkdir -p "$root/$name.mlmodelc"; done\n'
        'printf "{}" > "$root/plda-parameters.json"\n' if complete else '') +
        'echo "preparing" >&2\necho "noSpeechDetected" >&2\n' + f'exit {exit_code}\n')
    binary.chmod(0o755)
    monkeypatch.setenv('VNOTE_FLUID_BIN', str(binary))


@pytest.mark.parametrize('model_set,chosen', [('full', models.ASR_MODEL), ('lite', models.LIVE_MODEL)])
def test_download_saves_after_no_speech(work_dir, monkeypatch, capfd, model_set, chosen):
    fake_fluid(work_dir, monkeypatch, True, 1)
    monkeypatch.setenv('HF_HOME', str(work_dir / 'models'))
    models.CONFIG.write_text('{"other": 1}')
    monkeypatch.setattr('huggingface_hub.snapshot_download', lambda *a, **kw: None)
    assert models.run_models(SimpleNamespace(model_action='download', set=model_set, json=True)) == 0
    assert json.loads(models.CONFIG.read_text()) == {'other': 1, 'asr_model': chosen, 'live_model': models.LIVE_MODEL}
    assert json.loads(capfd.readouterr().out.splitlines()[-1])['status'] == 'done'


@pytest.mark.parametrize('exit_code', [0, 1])
def test_missing_fluid_models_fail_with_last_stderr(work_dir, monkeypatch, capfd, exit_code):
    fake_fluid(work_dir, monkeypatch, False, exit_code)
    monkeypatch.setenv('HF_HOME', str(work_dir / 'models'))
    models.CONFIG.write_text('{"asr_model": "old"}')
    monkeypatch.setattr('huggingface_hub.snapshot_download', lambda *a, **kw: None)
    assert models.run_models(SimpleNamespace(model_action='download', set='full', json=True)) == 1
    assert json.loads(models.CONFIG.read_text()) == {'asr_model': 'old'}
    message = json.loads(capfd.readouterr().out.splitlines()[-1])['message']
    assert message == f'FluidAudio 모델 준비 실패: {exit_code}: noSpeechDetected'
