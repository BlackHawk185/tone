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
 * Write dispatch fields to Firestore. Uses set-with-merge so a single code path
 * handles both creation and update. Fields we don't send (e.g. responders) are
 * never touched.
 */
async function writeIncident(incident) {
  const docRef = db.collection('incidents').doc(incident.incidentId);

  const data = {
    incidentId:       incident.incidentId,
    incidentType:     incident.incidentType,
    incidentCategory: incident.incidentCategory || 'FIRE',
    address:          incident.address,
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

module.exports = { writeIncident };
