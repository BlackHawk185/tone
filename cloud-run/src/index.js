require('dotenv').config();
const http = require('http');
const { parseDispatchEmail } = require('./emailParser');
const { writeIncident } = require('./firestore');
const { fetchAndMarkUnread, registerWatch } = require('./gmail');

const PORT = process.env.PORT || 8080;
const PUSH_SECRET = process.env.PUSH_SECRET || '';

/**
 * Convert raw MIME email source to clean plain text for parsing.
 * Handles HTML emails (br → newline, strip tags, decode entities)
 * and quoted-printable soft line breaks.
 */
function extractPlainText(raw) {
  let text = raw;

  // Decode quoted-printable soft line breaks (=\r\n or =\n)
  text = text.replace(/=\r?\n/g, '');

  // If it contains HTML, convert structure to newlines then strip all tags
  if (/<html[\s>]/i.test(text)) {
    text = text
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/(?:p|div|tr|li|h[1-6]|blockquote)>/gi, '\n')
      .replace(/<[^>]+>/g, '');
  }

  // Decode common HTML entities
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

async function processNewMessages() {
  const messages = await fetchAndMarkUnread();
  if (!messages.length) {
    console.log('[Gmail] No unread messages.');
    return;
  }
  for (const { subject, raw } of messages) {
    console.log(`[Gmail] Processing message: "${subject}"`);
    const body = extractPlainText(raw);
    const incident = parseDispatchEmail(subject, body);
    if (incident) {
      await writeIncident(incident);
      console.log(`[Firestore] Incident written: ${incident.incidentId}`);
    } else {
      console.log(`[Parser] Skipped. Subject: "${subject}"`);
      console.log(`[Parser] Body preview: ${body.slice(0, 300).replace(/\n/g, ' ')}`);
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

  // Pub/Sub push — secret in path prevents random callers from triggering it
  if (req.method === 'POST' && req.url === `/pubsub/${PUSH_SECRET}`) {
    // Acknowledge immediately — Pub/Sub retries if we don't respond within ~10s
    res.writeHead(204);
    res.end();
    processNewMessages().catch(err => console.error('[Push] Error:', err.message));
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
  // Register watch on startup
  registerWatch().catch(err => console.error('[Watch] Startup error:', err.message));
  // Process anything unread that arrived while we were offline/deploying
  // Delay startup processing to avoid racing with deployment health checks
  setTimeout(() => {
    processNewMessages().catch(err => console.error('[Startup] Error:', err.message));
  }, 5000);
});


