require('dotenv').config();
const http = require('http');
const { parseDispatchEmail } = require('./emailParser');
const { writeIncident } = require('./firestore');
const { registerWatch, fetchNewMessages, markAsRead } = require('./gmail');

const PORT = process.env.PORT || 8080;
const PUSH_SECRET = process.env.PUSH_SECRET || '';

/**
 * Convert raw MIME email source to clean plain text for parsing.
 */
function extractPlainText(raw) {
  let text = raw;
  // Decode quoted-printable: soft line breaks, then =XX hex sequences
  text = text.replace(/=\r?\n/g, '');
  text = text.replace(/=([0-9A-Fa-f]{2})/g, (_, hex) => {
    const byte = parseInt(hex, 16);
    // Only decode non-printable, high-byte, or '=' (0x3D) — these are the
    // bytes a valid QP encoder must encode. Printable ASCII (33-126 except 61)
    // is never QP-encoded, so sequences like =41 in URL params are left alone.
    if (byte === 0x3D || byte < 0x21 || byte > 0x7E) {
      return String.fromCharCode(byte);
    }
    return `=${hex}`;
  });
  if (/<html[\s>]/i.test(text)) {
    text = text
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/(?:p|div|tr|li|h[1-6]|blockquote)>/gi, '\n')
      .replace(/<[^>]+>/g, '');
  }
  text = text
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&nbsp;/g, ' ')
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)));
  return text;
}

/**
 * Process messages returned by Gmail history API.
 */
async function processMessages(messages) {
  try {
    for (const { subject, raw } of messages) {
      console.log(`[Process] "${subject}"`);
      const body = extractPlainText(raw);
      const incident = parseDispatchEmail(subject, body);
      if (incident) {
        await writeIncident(incident);
      } else {
        console.log(`[Skip] "${subject}"`);
      }
    }
  } finally {
    // Always mark as read — even if processing threw. Firestore writes are
    // idempotent so reprocessing on the next push is safe; leaving messages
    // unread causes infinite reprocessing loops.
    await markAsRead(messages.map(m => m.id));
  }
}

const server = http.createServer((req, res) => {
  // Health check
  if (req.method === 'GET' && req.url === '/') {
    res.writeHead(200);
    res.end('ok');
    return;
  }

  // Pub/Sub push — the ONE processing path
  if (req.method === 'POST' && req.url === `/pubsub/${PUSH_SECRET}`) {
    req.on('data', () => {}); // drain request body
    req.on('end', () => {
      // Ack immediately
      res.writeHead(204);
      res.end();

      console.log('[Push] Pub/Sub notification received, checking inbox.');

      fetchNewMessages()
        .then(msgs => {
          if (!msgs.length) {
            console.log('[Push] No new inbox messages in history.');
            return;
          }
          return processMessages(msgs);
        })
        .catch(err => console.error('[Push] Error:', err.message));
    });
    return;
  }

  // Watch renewal — called by Cloud Scheduler every 6 days
  if (req.method === 'POST' && req.url === '/renew-watch') {
    res.writeHead(200);
    res.end();
    registerWatch().catch(err => console.error('[Watch] Renewal error:', err.message));
    return;
  }

  res.writeHead(404);
  res.end();
});

server.listen(PORT, () => {
  console.log(`[HTTP] Listening on :${PORT}`);
});


