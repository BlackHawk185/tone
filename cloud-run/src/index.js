require('dotenv').config();
const http = require('http');
const { parseDispatchEmail } = require('./emailParser');
const { writeIncident } = require('./firestore');
const { registerWatch, fetchNewMessages } = require('./gmail');

const PORT = process.env.PORT || 8080;
const PUSH_SECRET = process.env.PUSH_SECRET || '';

/**
 * Convert raw MIME email source to clean plain text for parsing.
 */
function extractPlainText(raw) {
  let text = raw;
  text = text.replace(/=\r?\n/g, '');
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
  for (const { subject, raw } of messages) {
    console.log(`[Process] "${subject}"`);
    const body = extractPlainText(raw);
    const incident = parseDispatchEmail(subject, body);
    if (incident) {
      await writeIncident(incident);
      console.log(`[Firestore] ${incident.incidentId} written (final=${incident.isFinal})`);
    } else {
      console.log(`[Skip] "${subject}"`);
    }
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
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      // Ack immediately
      res.writeHead(204);
      res.end();

      // Extract historyId from Pub/Sub envelope
      let historyId = null;
      try {
        const envelope = JSON.parse(body);
        const data = envelope.message?.data
          ? JSON.parse(Buffer.from(envelope.message.data, 'base64').toString())
          : {};
        historyId = data.historyId;
      } catch (_) {}

      if (!historyId) {
        console.log('[Push] No historyId in notification, skipping.');
        return;
      }

      fetchNewMessages(historyId)
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
  // Register watch on startup to seed historyId — no message processing
  registerWatch().catch(err => console.error('[Watch] Startup error:', err.message));
});


