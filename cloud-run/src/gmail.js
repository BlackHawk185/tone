const { google } = require('googleapis');

let _gmail = null;

function getGmail() {
  if (_gmail) return _gmail;
  const client = new google.auth.OAuth2(
    (process.env.GMAIL_CLIENT_ID || '').trim(),
    (process.env.GMAIL_CLIENT_SECRET || '').trim(),
  );
  client.setCredentials({
    refresh_token: (process.env.GMAIL_REFRESH_TOKEN || '').trim(),
  });
  _gmail = google.gmail({ version: 'v1', auth: client });
  return _gmail;
}

/**
 * Register Gmail push notifications (called by Cloud Scheduler).
 */
async function registerWatch() {
  const gmail = getGmail();
  const res = await gmail.users.watch({
    userId: 'me',
    requestBody: {
      labelIds: ['INBOX'],
      topicName: process.env.PUBSUB_TOPIC,
    },
  });
  const expiry = new Date(Number(res.data.expiration)).toISOString();
  console.log(`[Watch] Registered. expires=${expiry}`);
  return res.data;
}

/**
 * Fetch recent unread inbox messages. Firestore writes are idempotent
 * (keyed on incidentId), so reprocessing is harmless.
 */
async function fetchNewMessages() {
  const gmail = getGmail();
  const list = await gmail.users.messages.list({
    userId: 'me',
    q: 'is:unread in:inbox',
    maxResults: 20,
  });
  if (!list.data.messages?.length) return [];

  // Fetch all messages in parallel
  const results = await Promise.all(
    list.data.messages.map(async ({ id }) => {
      const msg = await gmail.users.messages.get({
        userId: 'me',
        id,
        format: 'raw',
      });
      const raw = Buffer.from(msg.data.raw, 'base64url').toString('utf-8');
      const subjectMatch = raw.match(/^Subject:\s*(.+)$/im);
      const subject = subjectMatch ? subjectMatch[1].trim() : '(no subject)';
      return { id, subject, raw };
    }),
  );
  return results;
}

/**
 * Mark messages as read so they aren't reprocessed on the next push.
 */
async function markAsRead(messageIds) {
  const gmail = getGmail();
  await gmail.users.messages.batchModify({
    userId: 'me',
    requestBody: {
      ids: messageIds,
      removeLabelIds: ['UNREAD'],
    },
  });
  console.log(`[Gmail] Marked ${messageIds.length} message(s) as read.`);
}

module.exports = { registerWatch, fetchNewMessages, markAsRead };
