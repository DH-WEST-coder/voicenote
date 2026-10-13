import { useState,useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { getVersion } from '@tauri-apps/api/app';
import { ko } from '../i18n/ko';
import { ChatModel,Settings } from '../types';
import { ChatModelSelect } from './ChatModelSelect';
import { ModelProgress } from './ModelProgress';

const precise='moona3k/mlx-qwen3-asr-1.7b-8bit';
const light='moona3k/mlx-qwen3-asr-0.6b-4bit';
type ModelProgressValue = { busy:boolean; text:string; done:boolean; modelSet:string; error?:boolean; status?:string; model?:string; downloadedBytes?:number; totalBytes?:number; bytesPerSec?:number; progress?:number; lastByteAt?:number };

export function SettingsView({ settings,change,close,connected,login,logout,download,retryDownload,progress,onError,onModels }: {
    settings:Settings; change:(s:Settings)=>void; close:()=>void; connected:boolean; login:()=>void; logout:()=>void;
    download:(asr:string,live:string)=>void; retryDownload:()=>void; progress:ModelProgressValue; onError:(e:unknown)=>void;
    onModels:(models:ChatModel[])=>void;
}) {
    const [licenses,setLicenses]=useState(false);
    const [version,setVersion]=useState('');
    const [models,setModels]=useState<{id:string;downloaded:boolean;size_bytes:number}[]>([]);
    const [chatModels,setChatModels]=useState<ChatModel[]>([]);
    useEffect(() => {
        getVersion().then(setVersion).catch(onError);
        invoke<{models:typeof models}>('models_status').then(v => setModels(v.models)).catch(onError);
        invoke<ChatModel[]>('chat_models').then(v => { setChatModels(v); onModels(v); }).catch(onError);
    },[progress.busy]);
    const folder=async (logs:boolean) => { try { await invoke('open_data_folder',{logs}); } catch(e) { onError(e); } };
    const item=(id:string) => models.find(m => m.id===id);
    const modelChoice=(kind:'asr'|'live',id:string,label:string,size:string) => {
        const selected=kind==='asr'?settings.asrModel===id:settings.liveModel===id;
        const update=() => change(kind==='asr'?{...settings,asrModel:id}:{...settings,liveModel:id});
        return <label className="model-choice" key={`${kind}-${id}`}>
            <input type="radio" name={`${kind}-model`} checked={selected} onChange={update}/>
            {label} · {size} · {item(id)?.downloaded?ko.modelReceived:ko.modelMissing}
            {item(id)?.size_bytes?` (${(item(id)!.size_bytes/2**30).toFixed(2)} GB 저장됨)`:''}
        </label>;
    };
    return <div className="overlay"><section className="modal">
        <h2>{ko.settings}<button onClick={close}>{ko.close}</button></h2>
        <h3>{ko.asrModel}</h3>
        {modelChoice('asr',precise,ko.preciseModel,'약 2.2 GB')}
        {modelChoice('asr',light,ko.lightModel,'약 0.5 GB')}
        <h3>{ko.liveModel}</h3>
        {modelChoice('live',light,ko.lightModel,'약 0.5 GB · 배터리 절약')}
        {modelChoice('live',precise,ko.preciseModel,'약 2.2 GB · 정확도 높음')}
        <button disabled={progress.busy} onClick={() => download(settings.asrModel,settings.liveModel)}>{ko.download}</button>
        <ModelProgress value={progress} retry={retryDownload}/>
        <h3>{ko.requiredModels}</h3>
        {models.filter(m => m.id==='Qwen/Qwen3-ForcedAligner-0.6B'||m.id==='FluidAudio').map(m => <p key={m.id}>{m.id}: {m.downloaded?ko.modelReceived:ko.modelMissing} · {m.size_bytes?`${(m.size_bytes/2**30).toFixed(2)} GB`:ko.modelSizePending}</p>)}
        <label><input type="checkbox" checked={settings.liveEnabled} onChange={e => change({...settings,liveEnabled:e.target.checked})}/>{ko.live}</label>
        <label>{ko.theme}<select value={settings.theme} onChange={e => change({...settings,theme:e.target.value})}>{['system','light','dark'].map(t => <option key={t} value={t}>{ko[t as 'system'|'light'|'dark']}</option>)}</select></label>
        <label>{ko.chatProvider}<select value={settings.chatProvider||'chatgpt'} onChange={e => change({...settings,chatProvider:e.target.value as Settings['chatProvider'],chatModel:''})}><option value="chatgpt">{ko.chatgpt}</option><option value="claude">{ko.claude}</option></select></label>
        <ChatModelSelect settings={settings} change={change} models={chatModels}/>
        <p>{connected?ko.connected:ko.disconnected}</p><button onClick={connected?logout:login}>{connected?ko.logout:settings.chatProvider==='claude'?ko.claudeLogin:ko.login}</button>
        <p>{settings.chatProvider==='claude'?ko.privacyClaude:ko.privacy}</p>
        <div className="toolbar"><button onClick={() => void folder(false)}>{ko.dataFolder}</button><button onClick={() => void folder(true)}>{ko.logsFolder}</button><button onClick={() => setLicenses(!licenses)}>{ko.licenses}</button></div>
        {licenses&&ko.licenseItems.map(([name,license,url]) => <p key={name}><b>{name}</b> · {license}<br/><span className="source">{url}</span></p>)}
        <small>{ko.version} {version}</small>
    </section></div>;
}
