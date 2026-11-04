import { Platform } from 'react-native';
import { ApiClient } from './api';
import { PhoneFlow } from './phone';
import { MirrorFlow } from './mirror';
import { accessStore, NativeMirror, phoneReader } from '../adapters/hardware';
export const api = new ApiClient(() => process.env.EXPO_PUBLIC_API_URL);
export const phone = new PhoneFlow(api, phoneReader, accessStore);
export const mirror = new MirrorFlow(api, new NativeMirror());
// iPhone uses the same signed RC522 reader for all card operations.
export const usesMirrorReader = Platform.OS === 'ios';
export const cardReader = usesMirrorReader ? mirror : phone;
export const stopHardware = (message?: string) => { phone.stop(message); mirror.stop(message); };
