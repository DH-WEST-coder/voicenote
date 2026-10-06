import { useState,useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { getVersion } from '@tauri-apps/api/app';
import { ko } from '../i18n/ko';
import { Settings } from '../types';
import { ModelProgress } from './ModelProgress';
export function SettingsView({ settings,change,close,connected,login,logout,download,retryDownload,progress,onError }: {
    settings: Settings;
    change: (s: Settings) => void;
    close: () => void;
    connected: boolean;
    login: () => void;
    logout: () => void;
    download: (s: string) => void;
    retryDownload: () => void;
    progress: {
        busy: boolean;
        text: string;
        done: boolean;
        modelSet: string;
        error?: boolean;
        status?: string;
        model?: string;
        downloadedBytes?: number;
        totalBytes?: number;
        bytesPerSec?: number;
        progress?: number;
        lastByteAt?: number;
    };
    onError: (e: unknown) => void;
}) {
    const [licenses,setLicenses]=useState(false);
    const [modelSet,chooseModelSet]=useState(settings.modelSet);
    const [version,setVersion]=useState('');
    const [models,setModels]=useState<{
        id: string;
        downloaded: boolean;
        size_bytes: number;
    }[]>([]);
    useEffect(() => {
        getVersion().then(setVersion).catch(onError); invoke<{
            models: typeof models;
        }>('models_status').then(v => setModels(v.models)).catch(onError);
    },[progress.busy]);
    const folder=async (logs: boolean) => {
        try {
            await invoke('open_data_folder',{ logs });
        }
        catch(e) {
            onError(e);
        }
    };
    return <div className="overlay">
        <section className="modal">
            <h2>
                {ko.settings}
                <button onClick={close}>
                    {ko.close}
                </button>
            </h2>
            <label>
                {ko.modelSet}
                <select value={modelSet} onChange={e => chooseModelSet(e.target.value)}>
                    <option value="full">
                        {ko.full}
                    </option>
                    <option value="lite">
                        {ko.lite}
                    </option>
                </select>
            </label>
            <button disabled={progress.busy} onClick={() => download(modelSet)}>
                {ko.download}
            </button>
            <ModelProgress value={progress} retry={retryDownload}/>
            {models.map(m => <p key={m.id}>
                {m.id}: {m.downloaded? '✓':'—'} · {(m.size_bytes/2**30).toFixed(2)} GB</p>)}
            <label>
                <input type="checkbox" checked={settings.liveEnabled} onChange={e => change({ ...settings,liveEnabled: e.target.checked })} />
                {ko.live}
            </label>
            <label>
                {ko.theme}
                <select value={settings.theme} onChange={e => change({ ...settings,theme: e.target.value })}>
                    {['system','light','dark'].map(t => <option key={t} value={t}>
                        {ko[t as 'system'|'light'|'dark']}
                    </option>)}
                </select>
            </label>
            <label>
                {ko.model}
                <input value={settings.chatModel} onChange={e => change({ ...settings,chatModel: e.target.value })} />
            </label>
            <p>
                {connected? ko.connected:ko.disconnected}
            </p>
            <button onClick={connected? logout:login}>
                {connected? ko.logout:ko.login}
            </button>
            <p>
                {ko.privacy}
            </p>
            <div className="toolbar">
                <button onClick={() => void folder(false)}>
                    {ko.dataFolder}
                </button>
                <button onClick={() => void folder(true)}>
                    {ko.logsFolder}
                </button>
                <button onClick={() => setLicenses(!licenses)}>
                    {ko.licenses}
                </button>
            </div>
            {licenses&&ko.licenseItems.map(([name,license,url]) => <p key={name}>
                <b>
                    {name}
                </b> · {license}
                <br />
                <span className="source">
                    {url}
                </span>
            </p>)}
            <small>
                {ko.version} {version}
            </small>
        </section>
    </div>;
}
