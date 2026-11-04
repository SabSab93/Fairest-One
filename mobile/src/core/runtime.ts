import { ApiClient } from './api';
import { PhoneFlow } from './phone';
import { MirrorFlow } from './mirror';
import { accessStore, NativeMirror, phoneReader } from '../adapters/hardware';
export const api = new ApiClient(() => process.env.EXPO_PUBLIC_API_URL);
export const phone = new PhoneFlow(api, phoneReader, accessStore);
export const mirror = new MirrorFlow(api, new NativeMirror());
export const stopHardware = () => { phone.stop(); mirror.stop(); };
