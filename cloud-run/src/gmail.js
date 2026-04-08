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

  // Log which account we're using
  try {
    const profile = await gmail.users.getProfile({ userId: 'me' });
    console.log(`[Gmail] Authenticated as: ${profile.data.emailAddress}`);
  } catch (e) {
    console.log(`[Gmail] Could not get profile: ${e.message}`);
  }

  const list = await gmail.users.messages.list({
    userId: 'me',
    q: 'is:unread in:inbox',
    maxResults: 20,
  });

  if (!list.data.messages?.length) {
    // Debug: show recent inbox messages
    try {
      const recent = await gmail.users.messages.list({
        userId: 'me',
        q: 'in:inbox',
        maxResults: 5,
      });
      if (recent.data.messages?.length) {
        for (const { id } of recent.data.messages.slice(0, 3)) {
          const m = await gmail.users.messages.get({ userId: 'me', id, format: 'metadata', metadataHeaders: ['Subject'] });
          const subj = m.data.payload?.headers?.find(h => h.name === 'Subject')?.value || '(no subject)';
          const labels = (m.data.labelIds || []).join(',');
          console.log(`[Gmail] Recent msg: "${subj}" [${labels}]`);
        }
      } else {
        console.log('[Gmail] Inbox is completely empty.');
      }
    } catch (e) {
      console.log(`[Gmail] Debug listing error: ${e.message}`);
    }
    return [];
  }

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
