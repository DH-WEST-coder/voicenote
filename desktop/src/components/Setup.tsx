import { useEffect,useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { openUrl } from '@tauri-apps/plugin-opener';
import { ko } from '../i18n/ko';
import { Settings } from '../types';
import { ModelProgress } from './ModelProgress';

const precise='moona3k/mlx-qwen3-asr-1.7b-8bit';
const light='moona3k/mlx-qwen3-asr-0.6b-4bit';
interface Device { appleSilicon:boolean; memoryBytes:number; freeBytes:number; recommended:string; }
type ModelProgressValue = { busy:boolean; done:boolean; modelSet:string; text:string; error?:boolean; status?:string; model?:string; downloadedBytes?:number; totalBytes?:number; bytesPerSec?:number; progress?:number; lastByteAt?:number };

export function Setup({ settings,onSettings,connected,login,modelProgress,download,onError,testRecording }: {
    testRecording:()=>void; settings:Settings; onSettings:(s:Settings)=>void; connected:boolean; login:()=>void;
    modelProgress:ModelProgressValue; download:(asr:string,live:string)=>void; onError:(e:unknown)=>void;
}) {
    const [step,setStep]=useState(0);
    const [mic,setMic]=useState(false);
    const [device,setDevice]=useState<Device>();
    const [detail,setDetail]=useState(false);
    const [asr,setAsr]=useState(settings.asrModel||precise);
    const [live,setLive]=useState(settings.liveModel||light);
    const selection=`${asr},${live}`;
    useEffect(() => { invoke<Device>('device_info').then(d => { setDevice(d); if(!settings.asrModel) setAsr(d.recommended==='lite'?light:precise); }).catch(onError); },[]);
    useEffect(() => { if(modelProgress.done) onSettings({...settings,asrModel:asr,liveModel:live}); },[modelProgress.done]);
    return <div className="overlay"><section className="modal setup">
        <small>{step+1} / 5</small><h1>{[ko.welcome,ko.microphone,ko.device,ko.login,ko.app][step]}</h1>
        {step===0&&<><p>{ko.privacy}</p><p>{ko.consent}</p></>}
        {step===1&&<><p>{ko.micHelp}</p><button onClick={() => invoke('microphone_check').then(() => setMic(true)).catch(onError)}>{mic?ko.micReady:ko.allowMic}</button><button onClick={() => openUrl(ko.microphoneUrl).catch(onError)}>{ko.openMic}</button></>}
        {step===2&&<>
            <label>{ko.chatProvider}<select value={settings.chatProvider||'chatgpt'} onChange={e => onSettings({...settings,chatProvider:e.target.value as Settings['chatProvider'],chatModel:''})}><option value="chatgpt">{ko.chatgpt}</option><option value="claude">{ko.claude}</option></select></label>
            <p>{ko.silicon}: {device?.appleSilicon?'✓':ko.unsupported}</p>
            <p>{ko.memory}: {((device?.memoryBytes||0)/2**30).toFixed(1)} GB · {ko.disk}: {((device?.freeBytes||0)/2**30).toFixed(1)} GB</p>
            <p>{ko.recommend}: {device?.recommended}</p>
            {detail&&<div>
                <h3>{ko.asrModel}</h3>
                <label><input type="radio" name="setup-asr" checked={asr===precise} onChange={() => setAsr(precise)}/>{ko.preciseModel} · 약 2.2 GB</label>
                <label><input type="radio" name="setup-asr" checked={asr===light} onChange={() => setAsr(light)}/>{ko.lightModel} · 약 0.5 GB</label>
                <h3>{ko.liveModel}</h3>
                <label><input type="radio" name="setup-live" checked={live===light} onChange={() => setLive(light)}/>{ko.lightModel} · 약 0.5 GB · 배터리 절약</label>
                <label><input type="radio" name="setup-live" checked={live===precise} onChange={() => setLive(precise)}/>{ko.preciseModel} · 약 2.2 GB · 전력 더 사용</label>
            </div>}
            <button onClick={() => setDetail(!detail)}>{detail?ko.less:ko.more}</button>
            <button disabled={modelProgress.busy||!device?.appleSilicon} onClick={() => download(asr,live)}>{modelProgress.busy?ko.downloading:ko.download}</button>
            <ModelProgress value={modelProgress} retry={() => download(asr,live)}/>
        </>}
        {step===3&&<><p>{settings.chatProvider==='claude'?ko.privacyClaude:ko.privacy}</p><p>{connected?ko.connected:settings.chatProvider==='claude'?ko.claudeHint:ko.disconnected}</p><button onClick={login}>{settings.chatProvider==='claude'?ko.claudeLogin:ko.login}</button></>}
        {step===4&&<><p>{ko.onboardDone}</p><button onClick={testRecording}>{ko.testRecord}</button></>}
        <footer>{step>0&&<button onClick={() => setStep(step-1)}>{ko.back}</button>}{step===3&&(!connected||settings.chatProvider==='claude')&&<button onClick={() => setStep(4)}>{ko.skip}</button>}
            {step<4?<button disabled={(step===1&&!mic)||(step===2&&(!modelProgress.done||modelProgress.modelSet!==selection))||(step===3&&!connected&&settings.chatProvider==='chatgpt')} onClick={() => setStep(step+1)}>{ko.next}</button>:<button onClick={() => onSettings({...settings,onboardingDone:true,asrModel:asr,liveModel:live})}>{ko.finish}</button>}</footer>
    </section></div>;
}
