import { Cancelled, errorMessage } from './async';
import type { FlowState, Stage } from './types';

export abstract class Flow {
  private listeners = new Set<() => void>();
  private current: FlowState = { busy: false, stage: 'idle', message: 'Lecteur prêt' };
  protected controller: AbortController | null = null;
  getSnapshot = () => this.current;
  subscribe = (listener: () => void) => { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; };
  protected publish(message: string, stage: Stage) {
    this.current = { busy: this.controller !== null, message, stage };
    this.listeners.forEach(listener => listener());
  }
  protected async run<T>(work: (signal: AbortSignal) => Promise<T>): Promise<T> {
    if (this.controller) throw new Error('Une lecture est déjà en cours.');
    this.controller = new AbortController();
    try { return await work(this.controller.signal); }
    catch (error) { this.publish(errorMessage(error), error instanceof Cancelled ? 'idle' : 'error'); throw error; }
    finally { this.controller = null; this.current = { ...this.current, busy: false }; this.listeners.forEach(l => l()); }
  }
  stop(message?: string) { this.controller?.abort(new Cancelled(message)); }
}
