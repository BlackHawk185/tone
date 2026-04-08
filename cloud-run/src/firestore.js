const admin = require('firebase-admin');

// Initialize Admin SDK using Application Default Credentials
// (automatically works in Cloud Run via the service account attached to the container)
if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.FIREBASE_PROJECT_ID || 'tone-b66eb',
  });
}

const db = admin.firestore();

/**
 * Writes or updates a parsed incident in the Firestore `incidents` collection.
 * Uses incidentId as the document ID.
 *
 * New incidents are created with status 'active' and a createdAt timestamp.
 * Existing incidents have all dispatch fields overwritten (address changes, unit
 * updates, narrative additions, etc.) while preserving responder data, createdAt,
 * and any manual status override — UNLESS the incoming email is marked Final,
 * in which case status is forced to 'inactive'.
 *
 * @param {object} incident - Parsed incident from emailParser
 */
async function writeIncident(incident) {
  const docRef = db.collection('incidents').doc(incident.incidentId);

  const existing = await docRef.get();

  const dispatchFields = {
    incidentId:    incident.incidentId,
    incidentType:  incident.incidentType,
    address:       incident.address,
    crossStreets:  incident.crossStreets  || null,
    fireQuadrant:  incident.fireQuadrant  || null,
    emsDistrict:   incident.emsDistrict   || null,
    units:         incident.units,
    priority:      incident.priority,
    dispatchTime:  incident.dispatchTime,
    natureOfCall:  incident.natureOfCall  || null,
    narrative:     incident.narrative     || [],
    lat:           incident.lat           || null,
    lng:           incident.lng           || null,
    updatedAt:     admin.firestore.FieldValue.serverTimestamp(),
  };

  if (!existing.exists) {
    // First time we've seen this incident — create it
    await docRef.set({
      ...dispatchFields,
      status:    incident.isFinal ? 'inactive' : 'active',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`[Firestore] Incident ${incident.incidentId} created${incident.isFinal ? ' (Final)' : ''}.`);
  } else {
    // Update all dispatch fields; preserve responders and createdAt.
    // If this is a Final Rip & Run, force status to 'inactive'.
    const update = { ...dispatchFields };
    if (incident.isFinal) {
      update.status = 'inactive';
      console.log(`[Firestore] Incident ${incident.incidentId} marked inactive (Final).`);
    } else {
      console.log(`[Firestore] Incident ${incident.incidentId} updated.`);
    }
    await docRef.update(update);
  }
}

module.exports = { writeIncident };
