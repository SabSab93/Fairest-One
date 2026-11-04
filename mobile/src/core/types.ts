export type Purpose = 'registration' | 'recovery';
export interface ClientRecord {
  id: string;
  email: string;
  card_uid: string | null;
  created_at: string;
  photo_count: number;
  messages: string[];
}
export interface FlowResult {
  state: string;
  uid?: string;
  code?: string;
  token?: string;
  session_id?: string;
  client?: ClientRecord;
}
export interface Api {
  post(body: Record<string, unknown>, signal?: AbortSignal): Promise<FlowResult>;
  clients(password: string, signal?: AbortSignal): Promise<ClientRecord[]>;
}
export interface PhoneReader { readUid(signal: AbortSignal): Promise<string> }
export interface AccessStore {
  read(): Promise<string | null>;
  save(value: string): Promise<void>;
  generate(): Promise<string>;
}
export interface BleEvent {
  type: string;
  token: string;
  uid?: string;
  proof?: string;
  code?: string;
}
export interface MirrorTransport {
  connect(signal: AbortSignal): Promise<void>;
  send(command: Record<string, unknown>, signal?: AbortSignal): Promise<void>;
  subscribe(listener: (event: BleEvent | Error) => void): () => void;
  disconnect(): Promise<void>;
}
export type Stage = 'idle' | 'reading' | 'checking' | 'countdown' | 'saved' | 'error';
export interface FlowState { busy: boolean; stage: Stage; message: string }
