import { useState,useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { getVersion } from '@tauri-apps/api/app';
import { ko } from '../i18n/ko';
import { Settings } from '../types';
const precise='moona3k/mlx-qwen3-asr-1.7b-8bit';
const light='moona3k/mlx-qwen3-asr-0.6b-4bit';
export function SettingsView({ settings,change,close,connected,login,logout,download,progress,onError }: {
    settings: Settings; change: (s: Settings) => void; close: () => void;
    connected: boolean; login: () => void; logout: () => void;
    download: (id: string,type: string) => void;
    progress: { busy: boolean; text: string }; onError: (e: unknown) => void;
}) {
    const [licenses,setLicenses]=useState(false);
    const [version,setVersion]=useState('');
    const [models,setModels]=useState<{id:string;downloaded:boolean;size_bytes:number}[]>([]);
    useEffect(() => {
        getVersion().then(setVersion).catch(onError);
        invoke<{models:typeof models}>('models_status').then(v => setModels(v.models)).catch(onError);
    },[progress.busy]);
    const folder=async (logs: boolean) => { try { await invoke('open_data_folder',{ logs }); } catch(e) { onError(e); } };
    const modelRow=(kind:'asr'|'live',id:string,label:string,size:string) => {
        const item=models.find(m => m.id===id);
        const selected=kind==='asr'?settings.asrModel===id:settings.liveModel===id;
        const update=(next:string) => change(kind==='asr'?{...settings,asrModel:next}:{...settings,liveModel:next});
        return <div className="model-choice" key={`${kind}-${id}`}>
            <label><input type="radio" name={`${kind}-model`} checked={selected} onChange={() => update(id)} />{label} · {size}</label>
            <span>{item?.downloaded?ko.modelReceived:ko.modelMissing}</span>
            {selected&&!item?.downloaded&&<button disabled={progress.busy} onClick={() => download(id,kind)}>{ko.download}</button>}
        </div>;
    };
    return <div className="overlay"><section className="modal">
        <h2>{ko.settings}<button onClick={close}>{ko.close}</button></h2>
        <h3>{ko.asrModel}</h3>
        {modelRow('asr',precise,ko.preciseModel,'약 2.2 GB')}
        {modelRow('asr',light,ko.lightModel,'약 0.5 GB')}
        <h3>{ko.liveModel}</h3>
        {modelRow('live',light,ko.lightModel,'약 0.5 GB · 배터리 절약')}
        {modelRow('live',precise,ko.preciseModel,'약 2.2 GB · 정확도 높음')}
        <h3>{ko.requiredModels}</h3>
        {models.filter(m => m.id==='Qwen/Qwen3-ForcedAligner-0.6B'||m.id==='FluidAudio').map(m => <p key={m.id}>{m.id}: {m.downloaded?ko.modelReceived:ko.modelMissing} · {m.size_bytes?`${(m.size_bytes/2**30).toFixed(2)} GB`:ko.modelSizePending}</p>)}
        <p>{progress.text}</p>
        <label><input type="checkbox" checked={settings.liveEnabled} onChange={e => change({...settings,liveEnabled:e.target.checked})} />{ko.live}</label>
        <label>{ko.theme}<select value={settings.theme} onChange={e => change({...settings,theme:e.target.value})}>{['system','light','dark'].map(t => <option key={t} value={t}>{ko[t as 'system'|'light'|'dark']}</option>)}</select></label>
        <label>{ko.model}<input value={settings.chatModel} onChange={e => change({...settings,chatModel:e.target.value})} /></label>
        <p>{connected?ko.connected:ko.disconnected}</p><button onClick={connected?logout:login}>{connected?ko.logout:ko.login}</button>
        <p>{ko.privacy}</p><div className="toolbar"><button onClick={() => void folder(false)}>{ko.dataFolder}</button><button onClick={() => void folder(true)}>{ko.logsFolder}</button><button onClick={() => setLicenses(!licenses)}>{ko.licenses}</button></div>
        {licenses&&ko.licenseItems.map(([name,license,url]) => <p key={name}><b>{name}</b> · {license}<br /><span className="source">{url}</span></p>)}
        <small>{ko.version} {version}</small>
    </section></div>;
}
