export interface Project {
    id: string;
    name: string;
    language: string;
    terms: string[];
}
export interface Material {
    id: string;
    name: string;
    path: string;
    text: string;
}
export interface Note {
    id: string;
    projectId: string;
    title: string;
    createdAt: string;
    recordingIds: string[];
    materials: Material[];
    terms: string[];
    speakerNames: Record<string, string>;
}
export interface Recording {
    id: string;
    noteId: string;
    path: string;
    status: string;
    transcript: string | null;
    live: string | null;
    duration: number;
    error: string | null;
}
export interface Settings {
    onboardingDone: boolean;
    liveEnabled: boolean;
    modelSet: string;
    theme: string;
    chatModel: string;
    updateChecked: string;
}
export interface Data {
    projects: Project[];
    notes: Note[];
    recordings: Recording[];
    settings: Settings;
}
export interface Line {
    time: number;
    localTime: number;
    recordingId: string;
    speaker: string;
    text: string;
}
export interface Message {
    role: string;
    text: string;
    id: string;
    error?: boolean;
}
export interface Detail {
    text: string;
    messages: Message[];
    lines: Line[];
}
export const time = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
