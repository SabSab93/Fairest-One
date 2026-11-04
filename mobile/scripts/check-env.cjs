const value = process.env.EXPO_PUBLIC_API_URL;
let valid = false;
try { const url = new URL(value); valid = url.protocol === 'https:' && url.pathname.endsWith('/api/') && !url.username && !url.password && !url.search && !url.hash && !url.hostname.includes('VOTRE-'); } catch {}
if (!valid) { console.error('Définissez EXPO_PUBLIC_API_URL avec l’URL HTTPS de l’API de test terminée par /api/.'); process.exit(1); }
