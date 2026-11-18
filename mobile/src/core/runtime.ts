import { Platform } from 'react-native';
import { ApiClient } from './api';
import { PhoneFlow } from './phone';
import { MirrorFlow } from './mirror';
import { accessStore, mirrorAddressStore, NativeMirror, phoneReader } from '../adapters/hardware';
import { WifiMirror, mirrorAddress } from '../adapters/wifi-mirror';

const defaultWifiAddress = '172.20.10.8';
export const getWifiAddress = async () => (await mirrorAddressStore.read()) ?? defaultWifiAddress;
export const setWifiAddress = (address: string) => mirrorAddressStore.save(mirrorAddress(address));
export const api = new ApiClient(() => process.env.EXPO_PUBLIC_API_URL);
export const phone = new PhoneFlow(api, phoneReader, accessStore);
export const mirror = new MirrorFlow(api, Platform.OS === 'ios' ? new WifiMirror(getWifiAddress) : new NativeMirror());
// iPhone uses the same signed RC522 reader for all card operations.
export const usesMirrorReader = Platform.OS === 'ios';
export const cardReader = usesMirrorReader ? mirror : phone;
export const stopHardware = (message?: string) => { phone.stop(message); mirror.stop(message); };
