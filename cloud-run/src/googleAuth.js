const { google } = require('googleapis');

const authClientCache = new Map();

function env(...names) {
  for (const name of names) {
    const value = String(process.env[name] || '').trim();
    if (value) return value;
  }
  return '';
}

function getGoogleAuthConfig() {
  return {
    clientId: env('GOOGLE_CLIENT_ID'),
    clientSecret: env('GOOGLE_CLIENT_SECRET'),
    refreshToken: env('GOOGLE_REFRESH_TOKEN'),
  };
}

function getGoogleOAuthClient({
  cacheKey = 'google',
  errorContext = 'Google OAuth credentials are not configured',
} = {}) {
  if (authClientCache.has(cacheKey)) return authClientCache.get(cacheKey);

  const config = getGoogleAuthConfig();

  if (!config.clientId || !config.clientSecret || !config.refreshToken) {
    throw new Error(errorContext);
  }

  const client = new google.auth.OAuth2(config.clientId, config.clientSecret);
  client.setCredentials({ refresh_token: config.refreshToken });
  authClientCache.set(cacheKey, client);
  return client;
}

module.exports = {
  env,
  getGoogleAuthConfig,
  getGoogleOAuthClient,
};