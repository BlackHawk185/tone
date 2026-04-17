/**
 * IAR (I Am Responding) Rip & Run Email Parser
 *
 * Parses LCFD full "Rip & Run" dispatch emails.
 *
 * Sample format: see cloud-run/test-parser.js
 */

/**
 * Parse an M/D/YYYY H:mm:ss timestamp into an ISO string. Returns null on failure.
 */
/**
 * Parse a timestamp from IAR dispatch emails. These are always in
 * America/Denver (Mountain Time). We compute the UTC offset manually
 * using US DST rules (Mar 2nd Sun 2:00 → Nov 1st Sun 2:00).
 */
function parseTimestamp(raw) {
  if (!raw) return null;
  const match = raw.match(/(\d{1,2})\/(\d{1,2})\/(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})/);
  if (!match) return null;
  const [, month, day, year, hour, min, sec] = match.map(Number);

  // Determine if Mountain Daylight Time is in effect (UTC-6) or MST (UTC-7).
  // US DST: starts 2nd Sunday of March at 2:00, ends 1st Sunday of November at 2:00.
  const isDST = (() => {
    if (month > 3 && month < 11) return true;
    if (month < 3 || month > 11) return false;
    // Find the relevant Sunday
    const d = new Date(Date.UTC(year, month - 1, 1));
    const firstDayOfWeek = d.getUTCDay();
    if (month === 3) {
      const secondSunday = firstDayOfWeek === 0 ? 8 : 15 - firstDayOfWeek;
      return day > secondSunday || (day === secondSunday && hour >= 2);
    }
    // November — 1st Sunday
    const firstSunday = firstDayOfWeek === 0 ? 1 : 8 - firstDayOfWeek;
    return day < firstSunday || (day === firstSunday && hour < 2);
  })();

  const offsetHours = isDST ? 6 : 7;
  const dt = new Date(Date.UTC(year, month - 1, day, hour + offsetHours, min, sec));
  return dt.toISOString();
}

function isFireUnitCode(code) {
  return /^215\d+$/.test(code);
}

function isEmsUnitCode(code) {
  return code === 'PBAMB' || code === 'AMR' || /(?:EMS|AMB)/.test(code);
}

function deriveServiceType(unitCodes) {
  const hasFire = unitCodes.some(isFireUnitCode);
  const hasEms = unitCodes.some(isEmsUnitCode);

  if (hasFire && hasEms) return 'BOTH';
  if (hasEms) return 'EMS';
  if (hasFire) return 'FIRE';
  return 'UNKNOWN';
}

/**
 * @param {string} subject - Email subject line
 * @param {string} body    - Full email body (plain text)
 * @returns {object|null}  - Parsed incident object or null if not a dispatch email
 */
function parseDispatchEmail(subject, body) {
  const text = `${subject}\n${body}`;

  // Detect dispatch emails: match "Rip & Run" (with HTML entity variants), LCFD dispatch headers,
  // or the older "R&R Notification" subject format
  if (!/rip\s*(?:&amp;|&)?\s*run|LCFD\s*#?\d|R&R\s+Notification/i.test(text)) return null;

  // --- Incident ID & Unit Codes ---
  // Parse ALL [incidentNumber unitCode] pairs from the Incident Number(s) line.
  // unitCodes drive per-unit FCM topic subscriptions (e.g. dispatch_21523, dispatch_PBAMB).
  let incidentId = null;
  const unitCodes = [];
  const idSection = text.match(/Incident\s+Number\(s\)\s*:\s*((?:\[[^\]]+\][\s,]*)+)/i);
  if (idSection) {
    const pairs = [...idSection[1].matchAll(/\[(\S+)\s+(\S+)\]/g)];
    for (const p of pairs) {
      if (!unitCodes.includes(p[2])) unitCodes.push(p[2]);
    }
    // Pick the incident ID: prefer FD5 (21523), then PBAMB, then first listed
    const fd5   = pairs.find(p => p[2] === '21523');
    const pbems = pairs.find(p => p[2] === 'PBAMB');
    const chosen = fd5 || pbems || pairs[0];
    if (chosen) incidentId = chosen[1];
  }
  if (!incidentId) incidentId = `TONE-${Date.now()}`;

  // --- Priority ---
  // No 's' flag: each regex must match on a single line so EMS doesn't bleed
  // into the Fire line (or vice-versa) when one side has no priority number.
  const emsP  = text.match(/EMS\s+Incident\s+Info.*?Call\s+Priority\s*:\s*(\d+)/i);
  const fireP = text.match(/Fire\s+Incident\s+Info.*?Call\s+Priority\s*:\s*(\d+)/i);
  const priorities = [];
  if (emsP)  priorities.push(parseInt(emsP[1],  10));
  if (fireP) priorities.push(parseInt(fireP[1], 10));
  const priority = priorities.length ? String(Math.min(...priorities)) : null;

  // --- Address ---
  const addrMatch = text.match(/Incident\s+Location\s*:\s*(.+?)(?=\s*Cross\s+Streets|\n)/im);
  const address = addrMatch ? addrMatch[1].trim() : 'Unknown';

  // --- Cross Streets ---
  const xMatch = text.match(/Cross\s+Streets\s*:\s*(.+?)(?=\n|$)/im);
  const crossStreets = (xMatch && xMatch[1].trim()) ? xMatch[1].trim() : null;

  // --- Fire Quadrant / EMS District ---
  const quadrantMatch = text.match(/Fire\s+Quadrant\s*:\s*(\S+)/i);
  const districtMatch = text.match(/EMS\s+District\s*:\s*(\S+)/i);
  const fireQuadrant = quadrantMatch ? quadrantMatch[1] : null;
  const emsDistrict  = districtMatch ? districtMatch[1] : null;

  // --- Lat/Lng ---
  let lat = null, lng = null;
  const coordMatch = text.match(/[?&]query=([-\d.]+),([-\d.]+)/);
  if (coordMatch) {
    lat = parseFloat(coordMatch[1]);
    lng = parseFloat(coordMatch[2]);
  }

  // --- Nature of Call ---
  const nocMatch = text.match(/Nature\s+of\s+Call\s*:\s*(.+?)(?=\n|$)/im);
  const natureOfCall = (nocMatch && nocMatch[1].trim()) ? nocMatch[1].trim() : null;

  // --- Service Type / Display Label ---
  // Canonical dispatch type comes from unit codes only.
  const serviceType = deriveServiceType(unitCodes);
  const incidentType = serviceType;
  const incidentCategory = serviceType;
  const displayLabel = natureOfCall ? natureOfCall.trim() : '';

  // --- Narrative (structured: [{time, author, text}]) ---
  // Section runs from "Narrative:" to "First Unit Dispatched:"
  // Date header appears as ***M/D/YYYY*** within the section
  const narrative = [];
  const narrativeSection = text.match(/Narrative\s*:\s*([\s\S]*?)(?=First\s+Unit\s+Dispatched|$)/i);
  if (narrativeSection) {
    const block = narrativeSection[1];
    const dateTag = block.match(/\*{3}(\d{1,2}\/\d{1,2}\/\d{4})\*{3}/);
    const dateStr = dateTag ? dateTag[1] : null;
    for (const line of block.split('\n')) {
      const m = line.trim().match(/^(\d{2}:\d{2}:\d{2})\s+(.+?)\s+-\s+(.+)$/);
      if (!m) continue;
      const [, time, author, entryText] = m;
      narrative.push({
        time:   dateStr ? (parseTimestamp(`${dateStr} ${time}`) || time) : time,
        author,
        text:   entryText.trim(),
      });
    }
  }

  // --- Units ---
  // The summary line immediately before "Unit Status Times:" is the cleanest source:
  // e.g. "FD3, FD5, PineEMS, PD3, WHP"
  const units = [];
  const summaryMatch = text.match(/([\w]+(?:,\s*[\w]+)+)\s*[\r\n]+Unit\s+Status\s+Times/i);
  if (summaryMatch) {
    summaryMatch[1].split(/,\s*/).forEach(u => {
      const trimmed = u.trim();
      if (trimmed) units.push(trimmed);
    });
  }
  // Fall back to "Unit: XXX" lines in Unit Status Times section
  if (units.length === 0) {
    const statusSection = text.match(/Unit\s+Status\s+Times\s*:\s*([\s\S]*?)(?=For\s+questions|$)/i);
    if (statusSection) {
      for (const m of statusSection[1].matchAll(/^Unit\s*:\s*(.+)$/gim)) {
        const code = m[1].trim();
        if (code && !units.includes(code)) units.push(code);
      }
    }
  }

  // --- Dispatch Time ---
  const dtMatch = text.match(/First\s+Unit\s+Dispatched\s*:\s*([\d/]+\s+[\d:]+)/i);
  const dispatchTime = parseTimestamp(dtMatch ? dtMatch[1] : null) || new Date().toISOString();

  // --- Is Final ---
  // A "Final" Rip & Run can appear as:
  //   - "Report Time: M/D/YYYY H:mm:ss Final" in the body
  //   - "Final" in the subject line (e.g. "LCFD #5 Rip & Run Final")
  const isFinal = /Report\s+Time\s*:.*\bFinal\b/i.test(text)
    || /\bFinal\b/i.test(subject);

  return {
    incidentId,
    incidentType,
    incidentCategory,
    serviceType,
    displayLabel,
    address,
    crossStreets,
    fireQuadrant,
    emsDistrict,
    units,
    unitCodes,
    priority,
    dispatchTime,
    natureOfCall,
    narrative,
    lat,
    lng,
    isFinal,
  };
}

module.exports = { parseDispatchEmail };
