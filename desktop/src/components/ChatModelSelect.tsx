import { ChatModel,Settings } from '../types';
import { ko } from '../i18n/ko';

export function ChatModelSelect({ settings,change,models }: {
    settings: Settings;
    change: (s: Settings) => void;
    models: ChatModel[];
}) {
    const cached=models.some(m => m.id===settings.chatModel);
    return <>
        <label>
            {ko.model}
            <select value={settings.chatModel} onChange={e => change({ ...settings,chatModel: e.target.value })}>
                <option value="">{ko.defaultModel}</option>
                {!cached&&settings.chatModel&&<option value={settings.chatModel}>{ko.unknownModel}: {settings.chatModel}</option>}
                {models.map(m => <option key={m.id} value={m.id}>{m.label}</option>)}
            </select>
        </label>
        <label>
            {ko.effort}
            <select value={settings.chatReasoningEffort||'low'} onChange={e => change({ ...settings,chatReasoningEffort: e.target.value })}>
                {(['low','medium','high'] as const).map(effort => <option key={effort} value={effort}>{ko[effort]}</option>)}
            </select>
        </label>
    </>;
}
