const admin = require('firebase-admin');

// Initialize Admin SDK using Application Default Credentials
// (automatically works in Cloud Run via the service account attached to the container)
if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.FIREBASE_PROJECT_ID || 'tone-b66eb',
  });
}

const db = admin.firestore();
const calendarStateDocRef = db.collection('serviceState').doc('calendarSync');
const onCallDocRef = db.collection('config').doc('onCall');
const usersCollectionRef = db.collection('users');

/**
 * Write dispatch fields to Firestore. Uses set-with-merge so a single code path
 * handles both creation and update. Fields we don't send (e.g. responders) are
 * never touched.
 */
async function writeIncident(incident) {
  const docRef = db.collection('feed').doc(incident.incidentId);

  const dispatchDate = new Date(incident.dispatchTime);
  const data = {
    type:             'DISPATCH',
    incidentId:       incident.incidentId,
    incidentType:     incident.incidentType,
    incidentCategory: incident.incidentCategory || 'FIRE',
    serviceType:      incident.serviceType || incident.incidentCategory || incident.incidentType,
    displayLabel:     incident.displayLabel || incident.natureOfCall || '',
    address:          incident.address,
    crossStreets:  incident.crossStreets  || null,
    fireQuadrant:  incident.fireQuadrant  || null,
    emsDistrict:   incident.emsDistrict   || null,
    units:         incident.units,
    unitCodes:     incident.unitCodes  || [],
    priority:      incident.priority,
    time:          admin.firestore.Timestamp.fromDate(dispatchDate),
    dispatchTime:  incident.dispatchTime,
    natureOfCall:  incident.natureOfCall  || null,
    narrative:     incident.narrative     || [],
    lat:           incident.lat           || null,
    lng:           incident.lng           || null,
    updatedAt:     admin.firestore.FieldValue.serverTimestamp(),
  };

  // Only set status when we have a reason to — active on first write, inactive on final
  const existing = await docRef.get();
  if (!existing.exists) {
    data.status = incident.isFinal ? 'inactive' : 'active';
    data.createdAt = admin.firestore.FieldValue.serverTimestamp();
  } else if (incident.isFinal) {
    data.status = 'inactive';
  }

  await docRef.set(data, { merge: true });
  console.log(`[Firestore] ${incident.incidentId} written (final=${incident.isFinal}, new=${!existing.exists}).`);
}

async function writeCalendarStatusProjection(users, metadata = {}) {
  const managedSnapshot = await usersCollectionRef
    .where('statusManagedBy', '==', 'google_calendar')
    .get();
  const managedDocsById = new Map(
    managedSnapshot.docs.map((doc) => [doc.id, doc]),
  );
  const activeUserIds = new Set(users.map((user) => user.uid));
  const batch = db.batch();

  for (const user of users) {
    const docRef = usersCollectionRef.doc(user.uid);
    const existingSnapshot = managedDocsById.get(user.uid) || await docRef.get();
    const existing = existingSnapshot.data() || {};

    const patch = {
      displayName: user.displayName,
      ...(user.email ? { email: user.email } : {}),
      customStatus: 'On Call',
      statusExpiresAt: user.shiftEnd,
      statusManagedBy: 'google_calendar',
      statusRole: user.role || admin.firestore.FieldValue.delete(),
      statusManagedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (existing.statusManagedBy !== 'google_calendar') {
      patch.calendarPreviousStatus = typeof existing.customStatus === 'string'
        ? existing.customStatus
        : admin.firestore.FieldValue.delete();
      patch.calendarPreviousStatusExpiresAt = typeof existing.statusExpiresAt === 'string'
        ? existing.statusExpiresAt
        : admin.firestore.FieldValue.delete();
      patch.calendarPreviousStatusRole = typeof existing.statusRole === 'string'
        ? existing.statusRole
        : admin.firestore.FieldValue.delete();
    }

    batch.set(docRef, patch, { merge: true });
  }

  for (const doc of managedSnapshot.docs) {
    if (activeUserIds.has(doc.id)) continue;
    const existing = doc.data();
    const patch = {
      statusManagedBy: admin.firestore.FieldValue.delete(),
      statusManagedAt: admin.firestore.FieldValue.delete(),
      statusRole: admin.firestore.FieldValue.delete(),
      calendarPreviousStatus: admin.firestore.FieldValue.delete(),
      calendarPreviousStatusExpiresAt: admin.firestore.FieldValue.delete(),
      calendarPreviousStatusRole: admin.firestore.FieldValue.delete(),
    };

    if (typeof existing.calendarPreviousStatus === 'string') {
      patch.customStatus = existing.calendarPreviousStatus;
      if (typeof existing.calendarPreviousStatusExpiresAt === 'string') {
        patch.statusExpiresAt = existing.calendarPreviousStatusExpiresAt;
      } else {
        patch.statusExpiresAt = admin.firestore.FieldValue.delete();
      }
      if (typeof existing.calendarPreviousStatusRole === 'string' && existing.calendarPreviousStatusRole) {
        patch.statusRole = existing.calendarPreviousStatusRole;
      }
    } else {
      patch.customStatus = admin.firestore.FieldValue.delete();
      patch.statusExpiresAt = admin.firestore.FieldValue.delete();
    }

    batch.set(doc.ref, patch, { merge: true });
  }

  await batch.commit();

  await onCallDocRef.delete().catch((err) => {
    if (err.code !== 5) {
      console.warn(`[Firestore] Failed to delete legacy config/onCall doc: ${err.message}`);
    }
  });

  await mergeCalendarSyncState({
    activeUsers: users.length,
    activeUserIds: Array.from(activeUserIds),
    lastProjectionSource: metadata.source || 'google_calendar',
    lastProjectionReason: metadata.reason || 'manual',
    lastProjectionAt: metadata.syncedAt || new Date().toISOString(),
  });
}

async function getCalendarSyncState() {
  const snapshot = await calendarStateDocRef.get();
  return snapshot.exists ? snapshot.data() : {};
}

async function mergeCalendarSyncState(patch) {
  await calendarStateDocRef.set({
    ...patch,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

/**
 * Write a calendar event to the `feed/` collection.
 * Uses set-with-merge so we can upsert calendar events that are modified in Google Calendar.
 */
async function writeCalendarEvent(event) {
  const docRef = db.collection('feed').doc(event.id);

  const data = {
    type: 'EVENT',
    title: event.title,
    time: admin.firestore.Timestamp.fromDate(new Date(event.time)),
    color: event.color || 0xFF3949AB, // default indigo
    durationMin: event.durationMin || 30,
    location: event.location || null,
    lat: event.lat || null,
    lng: event.lng || null,
    notes: event.notes || null,
    createdBy: event.createdBy,
    status: event.status || 'active',
    channel: event.channel || 'PBAMB', // Default to PBAMB if not specified
    attendees: event.attendees || {},
    notifyUnitCodes: event.notifyUnitCodes || [],
    calendarEventId: event.calendarEventId || event.id,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Only set createdAt on first write
  const existing = await docRef.get();
  if (!existing.exists) {
    data.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }

  await docRef.set(data, { merge: true });
  console.log(`[Firestore] Calendar event ${event.id} written (title="${event.title}", new=${!existing.exists}).`);
}

module.exports = {
  getCalendarSyncState,
  mergeCalendarSyncState,
  writeIncident,
  writeCalendarStatusProjection,
  writeCalendarEvent,
};
