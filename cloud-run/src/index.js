require('dotenv').config();
const http = require('http');
const { parseDispatchEmail } = require('./emailParser');
const {
  getCalendarSyncState,
  mergeCalendarSyncState,
  writeIncident,
  writeCalendarStatusProjection,
  writeCalendarEvent,
} = require('./firestore');
const {
  buildActiveShiftEntries,
  buildCalendarEvents,
  getCalendarWebhookPath,
  registerCalendarWatch,
  stopCalendarWatch,
  validateAndDeclineInvalidShifts,
} = require('./calendar');
const { registerWatch, fetchNewMessages, markAsRead } = require('./gmail');

const PORT = process.env.PORT || 8080;
const PUSH_SECRET = process.env.PUSH_SECRET || '';
const CALENDAR_WEBHOOK_PATH = PUSH_SECRET ? getCalendarWebhookPath() : '';

let calendarRefreshInFlight = null;

function headerValue(headers, name) {
  return String(headers[name] || '').trim();
}

function readCalendarWebhookHeaders(req) {
  return {
    channelId: headerValue(req.headers, 'x-goog-channel-id'),
    channelToken: headerValue(req.headers, 'x-goog-channel-token'),
    expiration: headerValue(req.headers, 'x-goog-channel-expiration'),
    resourceId: headerValue(req.headers, 'x-goog-resource-id'),
    resourceState: headerValue(req.headers, 'x-goog-resource-state'),
    resourceUri: headerValue(req.headers, 'x-goog-resource-uri'),
    messageNumber: headerValue(req.headers, 'x-goog-message-number'),
  };
}

function queueCalendarRefresh(reason, extraState = {}) {
  if (calendarRefreshInFlight) {
    console.log(`[Calendar] Refresh already running, coalescing ${reason}.`);
    return calendarRefreshInFlight;
  }

  calendarRefreshInFlight = (async () => {
    try {
      // Process both shifts and events in parallel
      const [users, events] = await Promise.all([
        buildActiveShiftEntries(),
        buildCalendarEvents(),
      ]);

      // Write shifts to user status projections
      await writeCalendarStatusProjection(users, {
        source: 'google_calendar',
        reason,
        syncedAt: new Date().toISOString(),
      });

      // Write events to feed collection
      for (const event of events) {
        await writeCalendarEvent(event);
      }

      await mergeCalendarSyncState({
        ...extraState,
        activeUsers: users.length,
        activeEvents: events.length,
        lastRefreshAt: new Date().toISOString(),
        lastRefreshReason: reason,
        lastRefreshError: null,
        lastRefreshErrorAt: null,
      });
      console.log(`[Calendar] Projected ${users.length} active shift(s) and ${events.length} event(s) (${reason}).`);
      return { users, events };
    } catch (err) {
      await mergeCalendarSyncState({
        ...extraState,
        lastRefreshAt: new Date().toISOString(),
        lastRefreshReason: reason,
        lastRefreshError: err.message,
        lastRefreshErrorAt: new Date().toISOString(),
      });
      throw err;
    } finally {
      calendarRefreshInFlight = null;
    }
  })();

  return calendarRefreshInFlight;
}

async function renewCalendarWatch() {
  const currentState = await getCalendarSyncState();
  if (currentState?.watch?.channelId && currentState?.watch?.resourceId) {
    try {
      await stopCalendarWatch(currentState.watch);
      console.log(`[Calendar] Stopped previous watch ${currentState.watch.channelId}.`);
    } catch (err) {
      console.warn(`[Calendar] Failed to stop previous watch: ${err.message}`);
    }
  }

  const watch = await registerCalendarWatch();
  await mergeCalendarSyncState({
    watch,
    lastWatchRenewalAt: new Date().toISOString(),
    lastWatchRenewalError: null,
  });
  console.log(`[Calendar] Watch registered. expires=${watch.expiration || 'unknown'}`);
  await queueCalendarRefresh('calendar_watch_renewal');
  return watch;
}

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

  if (CALENDAR_WEBHOOK_PATH && req.method === 'POST' && req.url === CALENDAR_WEBHOOK_PATH) {
    const headers = readCalendarWebhookHeaders(req);
    req.on('data', () => {});
    req.on('end', () => {
      res.writeHead(204);
      res.end();

      if (headers.channelToken && headers.channelToken !== PUSH_SECRET) {
        console.warn('[Calendar] Ignoring webhook with unexpected channel token.');
        return;
      }

      const syncState = {
        lastWebhookAt: new Date().toISOString(),
        lastWebhookChannelId: headers.channelId || null,
        lastWebhookMessageNumber: headers.messageNumber || null,
        lastWebhookResourceId: headers.resourceId || null,
        lastWebhookResourceState: headers.resourceState || null,
        lastWebhookResourceUri: headers.resourceUri || null,
        lastWebhookExpiration: headers.expiration || null,
      };

      mergeCalendarSyncState(syncState).catch((err) => {
        console.error('[Calendar] Failed to persist webhook metadata:', err.message);
      });

      if (!headers.resourceState || headers.resourceState === 'sync' || headers.resourceState === 'exists') {
        // Validate and decline any invalid shifts (past-dated invites)
        validateAndDeclineInvalidShifts()
          .catch((err) => console.error('[Calendar] Validation error:', err.message));

        // Then refresh active shifts and events
        queueCalendarRefresh(`calendar_webhook:${headers.resourceState || 'unknown'}`, syncState)
          .catch((err) => console.error('[Calendar] Refresh error:', err.message));
      }
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

  if (req.method === 'POST' && req.url === '/renew-calendar-watch') {
    res.writeHead(200);
    res.end();
    renewCalendarWatch().catch(async (err) => {
      console.error('[Calendar] Watch renewal error:', err.message);
      await mergeCalendarSyncState({
        lastWatchRenewalAt: new Date().toISOString(),
        lastWatchRenewalError: err.message,
      });
    });
    return;
  }

  if (req.method === 'POST' && req.url === '/refresh-calendar-shifts') {
    res.writeHead(202);
    res.end();
    queueCalendarRefresh('calendar_scheduler_reconcile')
      .catch((err) => console.error('[Calendar] Scheduled reconcile error:', err.message));
    return;
  }

  res.writeHead(404);
  res.end();
});

server.listen(PORT, () => {
  console.log(`[HTTP] Listening on :${PORT}`);
});


