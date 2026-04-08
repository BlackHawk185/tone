/**
 * One-time OAuth2 setup script — run locally to get a Gmail refresh token.
 *
 * Prerequisites:
 *   1. Set GMAIL_CLIENT_ID and GMAIL_CLIENT_SECRET in .env (or env vars)
 *   2. In GCP Console, add http://localhost:3000/oauth2callback as an
 *      Authorized Redirect URI on your OAuth2 client.
 *
 * Usage:
 *   node setup-oauth.js
 *   Open the printed URL in your browser, sign in, grant access.
 *   The refresh token will be printed to the console.
 */
require('dotenv').config();
const http = require('http');
const url = require('url');
const { google } = require('googleapis');

const CLIENT_ID     = process.env.GMAIL_CLIENT_ID;
const CLIENT_SECRET = process.env.GMAIL_CLIENT_SECRET;
const REDIRECT_URI  = 'http://localhost:3000/oauth2callback';
const SCOPES        = ['https://www.googleapis.com/auth/gmail.modify'];

if (!CLIENT_ID || !CLIENT_SECRET) {
  console.error('Error: GMAIL_CLIENT_ID and GMAIL_CLIENT_SECRET must be set in .env');
  process.exit(1);
}

const oauth2Client = new google.auth.OAuth2(CLIENT_ID, CLIENT_SECRET, REDIRECT_URI);

const authUrl = oauth2Client.generateAuthUrl({
  access_type: 'offline',
  scope: SCOPES,
  prompt: 'consent', // always return refresh_token
});

console.log('\nOpen this URL in your browser:\n');
console.log(authUrl);
console.log('\nWaiting for OAuth callback on http://localhost:3000 ...\n');

const server = http.createServer(async (req, res) => {
  const query = url.parse(req.url, true).query;
  if (!query.code) {
    res.end('No code received.');
    return;
  }

  try {
    const { tokens } = await oauth2Client.getToken(query.code);
    res.end('Authentication successful — you can close this tab.');
    server.close();

    console.log('\n✓ Refresh token obtained.\n');
    console.log('Run this to store it in Secret Manager:');
    console.log(`\n  echo -n "${tokens.refresh_token}" | gcloud secrets create gmail-refresh-token --data-file=- --project tone-b66eb\n`);
    console.log('Or if the secret already exists:');
    console.log(`\n  echo -n "${tokens.refresh_token}" | gcloud secrets versions add gmail-refresh-token --data-file=- --project tone-b66eb\n`);
  } catch (err) {
    console.error('Error exchanging code for tokens:', err.message);
    res.end('Error — check console.');
    server.close();
  }
});

server.listen(3000);
