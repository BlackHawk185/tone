const { randomUUID } = require('crypto');
const { google } = require('googleapis');
const admin = require('firebase-admin');
const { env, getGoogleOAuthClient } = require('./googleAuth');

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.FIREBASE_PROJECT_ID || 'tone-b66eb',
  });
}

const DEFAULT_WATCH_TTL_SECONDS = 604800;
const DEFAULT_LOOKBACK_HOURS = 36;
const DEFAULT_LOOKAHEAD_HOURS = 36;

// Google Calendar colorId to ARGB mapping (Flutter format)
// Fetched directly from Google Calendar API colors endpoint
const GOOGLE_CALENDAR_COLOR_MAP = {
  '1': 0xFFa4bdfc,  // Blueberry
  '2': 0xFF7ae7bf,  // Peacock
  '3': 0xFFdbadff,  // Lavender
  '4': 0xFFff887c,  // Tomato
  '5': 0xFFfbd75b,  // Banana
  '6': 0xFFffb878,  // Tangerine
  '7': 0xFF46d6db,  // Cyan
  '8': 0xFFe1e1e1,  // Graphite
  '9': 0xFF5484ed,  // Blueberry (darker blue)
  '10': 0xFF51b749, // Sage
  '11': 0xFFdc2127, // Tomato (red)
};
const DEFAULT_EVENT_COLOR = 0xFF3949AB; // Indigo fallback

let _calendar = null;
let _userProfileCache = null;
const geocodingCache = new Map(); // address → {lat, lng}

function getGoogleCalendarColor(colorId) {
  if (!colorId) return DEFAULT_EVENT_COLOR;
  const argb = GOOGLE_CALENDAR_COLOR_MAP[String(colorId)];
  return argb || DEFAULT_EVENT_COLOR;
}

function getCalendarConfig() {
  return {
    calendarId: env('CALENDAR_ID') || 'primary',
    calendarAccountEmail: env('GOOGLE_ACCOUNT_EMAIL'),
    baseUrl: env('PUBLIC_BASE_URL').replace(/\/+$/, ''),
    pushSecret: env('PUSH_SECRET'),
    timeZone: env('CALENDAR_TIME_ZONE') || 'America/Denver',
    watchTtlSeconds: Number(env('CALENDAR_WATCH_TTL_SECONDS')) || DEFAULT_WATCH_TTL_SECONDS,
    lookbackHours: Number(env('SHIFT_LOOKBACK_HOURS')) || DEFAULT_LOOKBACK_HOURS,
    lookaheadHours: Number(env('SHIFT_LOOKAHEAD_HOURS')) || DEFAULT_LOOKAHEAD_HOURS,
  };
}

function getAuthClient() {
  return getGoogleOAuthClient({
    errorContext: 'Google OAuth credentials are not configured. Re-run setup-oauth.js with Calendar scope.',
  });
}

function getCalendar() {
  if (_calendar) return _calendar;
  _calendar = google.calendar({ version: 'v3', auth: getAuthClient() });
  return _calendar;
}

function getCalendarWebhookPath() {
  const { pushSecret } = getCalendarConfig();
  if (!pushSecret) throw new Error('PUSH_SECRET must be configured');
  return `/calendar-webhook/${pushSecret}`;
}

function getCalendarWebhookAddress() {
  const { baseUrl } = getCalendarConfig();
  if (!baseUrl) throw new Error('PUBLIC_BASE_URL must be configured for Calendar watch registration');
  return `${baseUrl}${getCalendarWebhookPath()}`;
}

async function registerCalendarWatch() {
  const calendar = getCalendar();
  const config = getCalendarConfig();
  const response = await calendar.events.watch({
    calendarId: config.calendarId,
    requestBody: {
      id: randomUUID(),
      type: 'web_hook',
      address: getCalendarWebhookAddress(),
      token: config.pushSecret,
      params: {
        ttl: String(Math.max(60, Math.floor(config.watchTtlSeconds))),
      },
    },
  });

  return {
    channelId: response.data.id,
    resourceId: response.data.resourceId,
    resourceUri: response.data.resourceUri,
    expiration: response.data.expiration
      ? new Date(Number(response.data.expiration)).toISOString()
      : null,
    calendarId: config.calendarId,
  };
}

async function stopCalendarWatch(watch) {
  if (!watch?.channelId || !watch?.resourceId) return false;
  await getCalendar().channels.stop({
    requestBody: {
      id: watch.channelId,
      resourceId: watch.resourceId,
    },
  });
  return true;
}

function toDateTime(dateValue) {
  if (!dateValue?.dateTime) return null;
  
  // If timezone is UTC or missing, the dateTime string should be interpreted as local time
  // (Google Calendar defaults to UTC but user meant their local timezone)
  const isDefaultUTC = !dateValue.timeZone || dateValue.timeZone === 'UTC';
  
  if (isDefaultUTC) {
    const config = getCalendarConfig();
    const localTimeZone = config.timeZone;
    
    // Extract date and time components from the string
    const match = String(dateValue.dateTime).match(/(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/);
    if (!match) return null;
    
    const [, yearStr, monthStr, dayStr, hourStr, minuteStr, secondStr] = match;
    const year = parseInt(yearStr);
    const month = parseInt(monthStr) - 1;
    const day = parseInt(dayStr);
    const hour = parseInt(hourStr);
    const minute = parseInt(minuteStr);
    const second = parseInt(secondStr);
    
    // Create UTC date from the components (treating them as UTC for now)
    const utcDate = new Date(Date.UTC(year, month, day, hour, minute, second));
    
    // Format this UTC date as it appears in the local timezone using formatToParts
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: localTimeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    });
    
    const parts = formatter.formatToParts(utcDate);
    const values = Object.fromEntries(
      parts.filter(p => p.type !== 'literal').map(p => [p.type, parseInt(p.value)])
    );
    
    // Calculate offset: how much the UTC date differs from its local timezone representation
    const localUTC = new Date(Date.UTC(values.year, values.month - 1, values.day, values.hour, values.minute, values.second));
    const offsetMs = utcDate.getTime() - localUTC.getTime();
    
    // Apply offset: ADD it because the time was interpreted as UTC when it should be local
    // If 18:30 UTC looks like 12:30 in Denver, but user meant 18:30 local,
    // then correct UTC = 18:30 + 6 hours = 00:30 next day UTC
    const corrected = new Date(utcDate.getTime() + offsetMs);
    
    return corrected;
  }
  
  // Explicit timezone set, parse normally as UTC
  const parsed = new Date(dateValue.dateTime);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function localDateKey(date, timeZone) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const values = Object.fromEntries(
    parts
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, part.value]),
  );
  return `${values.year}-${values.month}-${values.day}`;
}

function resolveEventWindow(event, now, timeZone) {
  const start = toDateTime(event.start);
  const end = toDateTime(event.end);
  if (start && end) {
    return {
      isActive: start <= now && end > now,
      shiftStart: start.toISOString(),
      shiftEnd: end.toISOString(),
    };
  }

  if (event.start?.date && event.end?.date) {
    const todayKey = localDateKey(now, timeZone);
    return {
      isActive: event.start.date <= todayKey && todayKey < event.end.date,
      shiftStart: `${event.start.date}T00:00:00`,
      shiftEnd: `${event.end.date}T00:00:00`,
    };
  }

  return null;
}

function formatNameFromEmail(email) {
  const localPart = String(email || '').split('@')[0];
  if (!localPart) return 'Unknown';
  return localPart
    .replace(/[._-]+/g, ' ')
    .split(' ')
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

function normalizeIdentity(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');
}

function deriveRole(summary) {
  const text = String(summary || '').toLowerCase();
  if (/\b(driver|rig)\b/.test(text)) return 'driver';
  if (/\b(pcp|emt|medic)\b/.test(text)) return 'pcp';
  return '';
}

function getExplicitToneUid(event) {
  const privateUid = String(event.extendedProperties?.private?.toneUid || '').trim();
  if (privateUid) return privateUid;
  const sharedUid = String(event.extendedProperties?.shared?.toneUid || '').trim();
  if (sharedUid) return sharedUid;
  const description = String(event.description || '');
  const match = description.match(/(?:^|\b)tone_uid\s*:\s*([A-Za-z0-9:_-]+)/i);
  return match ? match[1].trim() : '';
}

function candidateEmails(event) {
  const config = getCalendarConfig();
  const ignored = new Set(
    [config.calendarAccountEmail, config.calendarId === 'primary' ? '' : config.calendarId]
      .map((value) => String(value || '').trim().toLowerCase())
      .filter(Boolean),
  );

  const candidates = [
    event.organizer?.email,
    event.creator?.email,
    ...((event.attendees || []).map((attendee) => attendee?.email)),
  ];

  const seen = new Set();
  return candidates
    .map((value) => String(value || '').trim().toLowerCase())
    .filter((value) => value && !ignored.has(value) && !seen.has(value) && seen.add(value));
}

const authEmailCache = new Map();

async function getUserByEmail(email) {
  const key = String(email || '').trim().toLowerCase();
  if (!key) return null;
  if (authEmailCache.has(key)) return authEmailCache.get(key);

  try {
    const record = await admin.auth().getUserByEmail(key);
    const resolved = {
      uid: record.uid,
      displayName: record.displayName || formatNameFromEmail(record.email || key),
      email: record.email || key,
    };
    authEmailCache.set(key, resolved);
    return resolved;
  } catch (err) {
    if (err.code === 'auth/user-not-found') {
      authEmailCache.set(key, null);
      return null;
    }
    throw err;
  }
}

async function getUserByUid(uid) {
  const key = String(uid || '').trim();
  if (!key) return null;

  try {
    const record = await admin.auth().getUser(key);
    return {
      uid: record.uid,
      displayName: record.displayName || formatNameFromEmail(record.email || record.uid),
      email: record.email || '',
    };
  } catch (err) {
    if (err.code === 'auth/user-not-found') return null;
    throw err;
  }
}

async function getUserProfiles() {
  if (_userProfileCache) return _userProfileCache;

  const snapshot = await admin.firestore().collection('users').get();
  _userProfileCache = snapshot.docs.map((doc) => {
    const data = doc.data() || {};
    return {
      uid: doc.id,
      displayName: String(data.displayName || '').trim(),
      email: String(data.email || '').trim().toLowerCase(),
    };
  });
  return _userProfileCache;
}

function getCandidateIdentityKeys(event, emails) {
  const keys = new Set();
  const push = (value) => {
    const normalized = normalizeIdentity(value);
    if (normalized) keys.add(normalized);
  };

  for (const email of emails) {
    push(email);
    push(email.split('@')[0]);
  }

  push(event.organizer?.displayName);
  push(event.creator?.displayName);
  for (const attendee of event.attendees || []) {
    push(attendee?.displayName);
  }

  return Array.from(keys);
}

function profileMatchesIdentity(profile, identityKeys) {
  const displayKey = normalizeIdentity(profile.displayName);
  const emailKey = normalizeIdentity(profile.email);

  return identityKeys.some((key) => {
    if (!key) return false;
    if (emailKey && emailKey === key) return true;
    if (displayKey && displayKey === key) return true;
    if (displayKey && key.startsWith(displayKey)) return true;
    if (displayKey && displayKey.startsWith(key)) return true;
    return false;
  });
}

async function resolveShiftOwnerFromProfiles(event, emails) {
  const identityKeys = getCandidateIdentityKeys(event, emails);
  if (!identityKeys.length) return null;

  const profiles = await getUserProfiles();
  const matches = profiles.filter((profile) => profileMatchesIdentity(profile, identityKeys));

  if (matches.length === 1) {
    const resolved = await getUserByUid(matches[0].uid);
    if (resolved) {
      return {
        ...resolved,
        email: resolved.email || matches[0].email || (emails[0] || ''),
      };
    }
    return {
      uid: matches[0].uid,
      displayName: matches[0].displayName || formatNameFromEmail(emails[0] || ''),
      email: matches[0].email || (emails[0] || ''),
    };
  }

  if (matches.length > 1) {
    console.warn(
      `[Calendar] Ambiguous user match for event attendee(s): ${emails.join(', ')} -> ${matches
        .map((profile) => profile.uid)
        .join(', ')}`,
    );
  }

  return null;
}

async function resolveShiftOwner(event) {
  const explicitUid = getExplicitToneUid(event);
  if (explicitUid) {
    const user = await getUserByUid(explicitUid);
    if (user) return user;
  }

  const emails = candidateEmails(event);
  for (const email of emails) {
    const user = await getUserByEmail(email);
    if (user) return user;
  }

  const resolvedFromProfiles = await resolveShiftOwnerFromProfiles(event, emails);
  if (resolvedFromProfiles) return resolvedFromProfiles;

  if (emails.length) {
    console.warn(`[Calendar] No Firebase user found for event attendee(s): ${emails.join(', ')}`);
  }
  return null;
}

function mergeShiftEntry(existing, next) {
  if (!existing) return next;
  const existingStartMs = Date.parse(existing.shiftStart);
  const nextStartMs = Date.parse(next.shiftStart);
  const existingEndMs = Date.parse(existing.shiftEnd);
  const nextEndMs = Date.parse(next.shiftEnd);
  return {
    ...existing,
    role: existing.role || next.role,
    shiftStart:
      Number.isFinite(existingStartMs) && Number.isFinite(nextStartMs)
        ? (existingStartMs <= nextStartMs ? existing.shiftStart : next.shiftStart)
        : (existing.shiftStart < next.shiftStart ? existing.shiftStart : next.shiftStart),
    shiftEnd:
      Number.isFinite(existingEndMs) && Number.isFinite(nextEndMs)
        ? (existingEndMs >= nextEndMs ? existing.shiftEnd : next.shiftEnd)
        : (existing.shiftEnd > next.shiftEnd ? existing.shiftEnd : next.shiftEnd),
  };
}

async function buildActiveShiftEntries(now = new Date()) {
  const calendar = getCalendar();
  const config = getCalendarConfig();
  const lowerBound = new Date(now.getTime() - config.lookbackHours * 60 * 60 * 1000).toISOString();
  const upperBound = new Date(now.getTime() + config.lookaheadHours * 60 * 60 * 1000).toISOString();

  const events = [];
  let pageToken;
  do {
    const response = await calendar.events.list({
      calendarId: config.calendarId,
      timeMin: lowerBound,
      timeMax: upperBound,
      singleEvents: true,
      orderBy: 'startTime',
      showDeleted: false,
      maxResults: 2500,
      pageToken,
    });
    events.push(...(response.data.items || []));
    pageToken = response.data.nextPageToken;
  } while (pageToken);

  const byUid = new Map();
  for (const event of events) {
    if (event.status === 'cancelled') continue;
    const eventWindow = resolveEventWindow(event, now, config.timeZone);
    if (!eventWindow?.isActive) continue;

    const owner = await resolveShiftOwner(event);
    if (!owner) continue;

    const entry = {
      uid: owner.uid,
      displayName: owner.displayName,
      email: owner.email || '',
      role: deriveRole(event.summary),
      shiftStart: eventWindow.shiftStart,
      shiftEnd: eventWindow.shiftEnd,
      source: 'google_calendar',
      calendarEventId: event.id || '',
      calendarSummary: String(event.summary || '').trim(),
    };
    byUid.set(owner.uid, mergeShiftEntry(byUid.get(owner.uid), entry));
  }

  return Array.from(byUid.values()).sort((left, right) => {
    return left.displayName.localeCompare(right.displayName);
  });
}

/**
 * Geocode an address to lat/lng using Google Maps Geocoding API.
 * Results are cached to avoid repeated API calls.
 * If geocoding fails or the address is empty, returns null.
 */
async function geocodeAddress(address) {
  if (!address) return null;

  const cacheKey = String(address).toLowerCase().trim();
  if (geocodingCache.has(cacheKey)) {
    return geocodingCache.get(cacheKey);
  }

  try {
    const authClient = getAuthClient();
    const mapsClient = google.maps({ version: 'v1', auth: authClient });
    
    const response = await mapsClient.geocode({
      address: cacheKey,
      region: 'us', // Default to US (Pine Bluffs, WY)
    });

    if (response.data?.results?.length > 0) {
      const location = response.data.results[0].geometry?.location;
      if (location?.lat && location?.lng) {
        const result = { lat: location.lat, lng: location.lng };
        geocodingCache.set(cacheKey, result);
        console.log(`[Geocode] "${address}" → (${location.lat}, ${location.lng})`);
        return result;
      }
    }

    // Cache null result to avoid retrying
    geocodingCache.set(cacheKey, null);
    console.warn(`[Geocode] No results for address: "${address}"`);
    return null;
  } catch (err) {
    console.error(`[Geocode] Error geocoding "${address}": ${err.message}`);
    // Don't cache errors, allow retry on next sync
    return null;
  }
}

async function buildCalendarEvents(now = new Date()) {
  const calendar = getCalendar();
  const config = getCalendarConfig();
  const calendarAccountEmail = String(config.calendarAccountEmail || '').trim().toLowerCase();

  const lowerBound = new Date(now.getTime() - config.lookbackHours * 60 * 60 * 1000).toISOString();
  const upperBound = new Date(now.getTime() + config.lookaheadHours * 60 * 60 * 1000).toISOString();

  const events = [];
  let pageToken;
  do {
    const response = await calendar.events.list({
      calendarId: config.calendarId,
      timeMin: lowerBound,
      timeMax: upperBound,
      singleEvents: true,
      orderBy: 'startTime',
      showDeleted: false,
      maxResults: 2500,
      pageToken,
    });
    events.push(...(response.data.items || []));
    pageToken = response.data.nextPageToken;
  } while (pageToken);

  const result = [];
  for (const event of events) {
    if (event.status === 'cancelled') continue;

    // Negative parsing: A shift has attendees OTHER than the calendar admin account.
    // Events are created by the admin with no external attendees invited.
    const externalAttendees = (event.attendees || []).filter((attendee) => {
      const email = String(attendee.email || '').trim().toLowerCase();
      return email && email !== calendarAccountEmail;
    });

    if (externalAttendees.length > 0) continue; // This is a shift, skip it

    const eventWindow = resolveEventWindow(event, now, config.timeZone);
    if (!eventWindow) continue; // Skip events without valid time

    // For calendar events, use a fixed system UID for createdBy (admin doesn't exist as a user)
    const adminUid = env('CALENDAR_EVENT_ADMIN_UID') || 'calendar_admin';

    // Parse optional unit codes from description (format: notifyUnits: CODE1,CODE2)
    const notifyUnitCodes = [];
    const description = String(event.description || '');
    const unitsMatch = description.match(/notifyUnits\s*:\s*([A-Z0-9,\s]+)/i);
    if (unitsMatch) {
      notifyUnitCodes.push(
        ...unitsMatch[1]
          .split(',')
          .map((code) => code.trim())
          .filter(Boolean),
      );
    }

    // Calculate duration: minimum 30 minutes
    const startTime = new Date(eventWindow.shiftStart);
    const endTime = new Date(eventWindow.shiftEnd);
    const durationMin = Math.max(30, Math.round((endTime - startTime) / (1000 * 60)));

    // Geocode location if present
    let lat = null;
    let lng = null;
    if (event.location) {
      const geocoded = await geocodeAddress(event.location);
      if (geocoded) {
        lat = geocoded.lat;
        lng = geocoded.lng;
      }
    }

    // Resolve all attendees (including admin) to UIDs for the app
    const attendeesMap = {};
    if (event.attendees && event.attendees.length > 0) {
      for (const attendee of event.attendees) {
        const email = String(attendee.email || '').trim().toLowerCase();
        if (!email) continue;

        // Skip calendar admin account itself
        if (email === calendarAccountEmail) continue;

        const user = await getUserByEmail(email);
        if (user) {
          // Default status to 'maybe' for invited attendees; they can change it in the app
          attendeesMap[user.uid] = 'maybe';
        } else {
          console.warn(`[Calendar] Attendee email not found in Firebase Auth: ${email}`);
        }
      }
    }

    // Determine channel: use first notifyUnitCode if available, otherwise default to PBAMB
    const channel = notifyUnitCodes.length > 0 ? notifyUnitCodes[0] : 'PBAMB';

    const eventColor = getGoogleCalendarColor(event.colorId);

    result.push({
      id: event.id || randomUUID(), // Use calendar event ID if available
      title: String(event.summary || '').trim(),
      location: event.location ? String(event.location).trim() : null,
      lat,
      lng,
      time: eventWindow.shiftStart,
      endTime: eventWindow.shiftEnd,
      durationMin,
      notes: description ? String(description).trim() : null,
      createdBy: adminUid,
      createdByName: 'Calendar',
      status: 'active',
      channel,
      attendees: attendeesMap,
      notifyUnitCodes,
      calendarEventId: event.id || '',
      color: eventColor,
    });
  }

  return result;
}

/**
 * Validate and decline shift invites with past start times.
 * Called when calendar webhook fires to catch invalid shifts immediately.
 *
 * Flow:
 * 1. Personnel creates shift with past-dated start time and invites tone.pinebluffsems@gmail.com
 * 2. Google sends webhook notification
 * 3. This function checks: is Tone invited? Is start time in past?
 * 4. If both true: update Tone's attendee RSVP to "declined"
 * 5. Log action to audit trail
 *
 * @param {Date} now - Current time (default: now)
 * @returns {Promise<Array>} Array of declined events with metadata
 */
async function validateAndDeclineInvalidShifts(now = new Date()) {
  const calendar = getCalendar();
  const config = getCalendarConfig();
  const toneEmail = String(config.calendarAccountEmail || '').trim().toLowerCase();

  if (!toneEmail) {
    console.warn('[Calendar] TONE_EMAIL not configured, skipping invalid shift validation');
    return [];
  }

  // Query events modified in the past 12 hours to catch recently created shifts
  const observationStart = new Date(now.getTime() - 12 * 60 * 60 * 1000);

  const events = [];
  let pageToken;
  try {
    do {
      const response = await calendar.events.list({
        calendarId: config.calendarId,
        updatedMin: observationStart.toISOString(),
        singleEvents: true,
        showDeleted: false,
        maxResults: 2500,
        pageToken,
      });
      events.push(...(response.data.items || []));
      pageToken = response.data.nextPageToken;
    } while (pageToken);
  } catch (err) {
    console.error(`[Calendar] Failed to query events for validation: ${err.message}`);
    return [];
  }

  const declined = [];

  for (const event of events) {
    if (event.status === 'cancelled') continue;

    // Check if Tone is invited to this event
    const attendees = event.attendees || [];
    const toneAttendee = attendees.find(
      (a) => String(a.email || '').toLowerCase() === toneEmail
    );
    if (!toneAttendee) continue;

    // Check if event start time is in the past
    const eventStart = toDateTime(event.start);
    if (!eventStart || eventStart >= now) continue; // Valid: future event

    // Invalid: event has past start time and Tone was invited
    // Verify event was created recently (within 12-hour observation window)
    const createdTime = event.created ? new Date(event.created) : null;
    if (!createdTime || createdTime < observationStart) continue; // Event too old, skip

    // Decline Tone's RSVP status
    try {
      toneAttendee.responseStatus = 'declined';
      await calendar.events.patch({
        calendarId: config.calendarId,
        eventId: event.id,
        requestBody: { attendees },
      });

      declined.push({
        eventId: event.id,
        summary: event.summary || '(no title)',
        startTime: eventStart.toISOString(),
        createdTime: createdTime.toISOString(),
        declinedAt: new Date().toISOString(),
      });

      console.log(
        `[Calendar] Declined invalid shift: "${event.summary}" ` +
          `(start=${eventStart.toISOString()}, created=${createdTime.toISOString()})`
      );
    } catch (err) {
      console.error(
        `[Calendar] Failed to decline event ${event.id} ("${event.summary}"): ${err.message}`
      );
    }
  }

  if (declined.length > 0) {
    console.log(`[Calendar] Validation: declined ${declined.length} invalid shift(s)`);
  }

  return declined;
}

module.exports = {
  buildActiveShiftEntries,
  buildCalendarEvents,
  geocodeAddress,
  getCalendarConfig,
  getCalendarWebhookPath,
  registerCalendarWatch,
  stopCalendarWatch,
  validateAndDeclineInvalidShifts,
};