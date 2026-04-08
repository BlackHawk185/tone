const { google } = require('googleapis');

function createOAuth2Client() {
  const client = new google.auth.OAuth2(
    (process.env.GMAIL_CLIENT_ID || '').trim(),
    (process.env.GMAIL_CLIENT_SECRET || '').trim(),
  );
  client.setCredentials({
    refresh_token: (process.env.GMAIL_REFRESH_TOKEN || '').trim(),
  });
  return client;
}

/**
 * Fetch all unread INBOX messages, mark them as read, return raw RFC 2822 strings.
 */
async function fetchAndMarkUnread() {
  const auth = createOAuth2Client();
  const gmail = google.gmail({ version: 'v1', auth });

  const list = await gmail.users.messages.list({
    userId: 'me',
    q: 'is:unread in:inbox',
    maxResults: 20,
  });

  if (!list.data.messages?.length) return [];

  const results = [];
  for (const { id } of list.data.messages) {
    const msg = await gmail.users.messages.get({
      userId: 'me',
      id,
      format: 'raw',
    });

    // Decode base64url → raw RFC 2822
    const raw = Buffer.from(msg.data.raw, 'base64url').toString('utf-8');

    // Extract subject from headers for logging
    const subjectMatch = raw.match(/^Subject:\s*(.+)$/im);
    const subject = subjectMatch ? subjectMatch[1].trim() : '(no subject)';

    // Mark as read immediately so reconnects don't reprocess
    await gmail.users.messages.modify({
      userId: 'me',
      id,
      requestBody: { removeLabelIds: ['UNREAD'] },
    });

    results.push({ id, subject, raw });
  }

  return results;
}

/**
 * Register Gmail push notifications to the configured Pub/Sub topic.
 * Must be called on startup and renewed every ≤7 days.
 */
async function registerWatch() {
  const auth = createOAuth2Client();
  const gmail = google.gmail({ version: 'v1', auth });

  const response = await gmail.users.watch({
    userId: 'me',
    requestBody: {
      labelIds: ['INBOX'],
      topicName: process.env.PUBSUB_TOPIC,
    },
  });

  const expiry = new Date(Number(response.data.expiration)).toISOString();
  console.log(`[Gmail] Watch registered. Expires: ${expiry}`);
  return response.data;
}

module.exports = { fetchAndMarkUnread, registerWatch };
