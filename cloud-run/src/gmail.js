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

// In-memory last-seen historyId. Seeded on first watch registration.
let lastHistoryId = null;

/**
 * Register Gmail push notifications. Returns the current historyId
 * which seeds our tracking so we only process *new* changes.
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
  lastHistoryId = res.data.historyId;
  const expiry = new Date(Number(res.data.expiration)).toISOString();
  console.log(`[Watch] Registered. historyId=${lastHistoryId}, expires=${expiry}`);
  return res.data;
}

/**
 * Given a historyId from a Pub/Sub push, fetch only the messages that
 * were added to the INBOX since our last checkpoint.
 * Returns raw RFC 2822 strings for each new message.
 */
async function fetchNewMessages(pushHistoryId) {
  const gmail = getGmail();

  // Use whichever is older: our tracked id or the one from the push
  const startId = lastHistoryId || pushHistoryId;

  let history;
  try {
    const res = await gmail.users.history.list({
      userId: 'me',
      startHistoryId: startId,
      historyTypes: ['messageAdded'],
      labelId: 'INBOX',
    });
    history = res.data.history || [];
  } catch (err) {
    if (err.code === 404) {
      // historyId too old — Gmail expired it. Fall back to unread scan.
      console.log('[Gmail] historyId expired, falling back to unread scan.');
      return fetchUnread();
    }
    throw err;
  }

  // Advance our checkpoint
  lastHistoryId = pushHistoryId;

  // Collect unique message IDs that were added
  const seen = new Set();
  const messageIds = [];
  for (const entry of history) {
    for (const added of entry.messagesAdded || []) {
      if (!seen.has(added.message.id)) {
        seen.add(added.message.id);
        messageIds.push(added.message.id);
      }
    }
  }

  if (!messageIds.length) return [];

  return fetchByIds(messageIds);
}

/**
 * Fallback: fetch unread inbox messages (used when historyId expires).
 */
async function fetchUnread() {
  const gmail = getGmail();
  const list = await gmail.users.messages.list({
    userId: 'me',
    q: 'is:unread in:inbox',
    maxResults: 20,
  });
  if (!list.data.messages?.length) return [];
  return fetchByIds(list.data.messages.map(m => m.id));
}

/**
 * Fetch full raw content for a list of message IDs.
 */
async function fetchByIds(ids) {
  const gmail = getGmail();
  const results = [];
  for (const id of ids) {
    const msg = await gmail.users.messages.get({
      userId: 'me',
      id,
      format: 'raw',
    });
    const raw = Buffer.from(msg.data.raw, 'base64url').toString('utf-8');
    const subjectMatch = raw.match(/^Subject:\s*(.+)$/im);
    const subject = subjectMatch ? subjectMatch[1].trim() : '(no subject)';
    results.push({ id, subject, raw });
  }
  return results;
}

module.exports = { registerWatch, fetchNewMessages };
