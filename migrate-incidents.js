/**
 * migrate-incidents.js
 *
 * Migrates both legacy Firestore collections into the unified `feed/` collection:
 *
 *   incidents/ → feed/  (type: DISPATCH or MESSAGE, adds `time` Timestamp)
 *   events/    → feed/  (type: EVENT, time Timestamp already present)
 *
 * Run from the repo root:
 *   node migrate-incidents.js [--dry-run]
 *
 * Requires Application Default Credentials:
 *   firebase login  OR  gcloud auth application-default login
 */

const admin = require('firebase-admin');

const DRY_RUN = process.argv.includes('--dry-run');

admin.initializeApp({ projectId: 'tone-b66eb' });
const db = admin.firestore();

function deriveType(data) {
  const svc = (data.serviceType || data.incidentCategory || data.incidentType || '').toUpperCase();
  if (svc === 'MESSAGE' || svc === 'PRIORITY TRAFFIC') return 'MESSAGE';
  return 'DISPATCH';
}

function toTimestamp(isoString) {
  if (!isoString) return admin.firestore.Timestamp.now();
  return admin.firestore.Timestamp.fromDate(new Date(isoString));
}

async function commitBatch(batch, count, label) {
  if (!DRY_RUN && count > 0) {
    await batch.commit();
    console.log(`  → Committed ${count} ${label} doc(s).`);
  }
}

async function migrateIncidents() {
  const snap = await db.collection('incidents').get();
  console.log(`incidents/: ${snap.size} docs`);

  let written = 0, skipped = 0, batchCount = 0;
  let batch = db.batch();

  for (const doc of snap.docs) {
    const data = doc.data();

    // Check if already migrated
    const existing = await db.collection('feed').doc(doc.id).get();
    if (existing.exists && existing.data().type) {
      skipped++;
      continue;
    }

    const type = deriveType(data);
    const isPriority = (data.serviceType || '').toUpperCase() === 'PRIORITY TRAFFIC';
    const timeTs = data.dispatchTime ? toTimestamp(data.dispatchTime) : admin.firestore.Timestamp.now();

    const feedDoc = {
      ...data,
      type,
      time: timeTs,
      ...(type === 'MESSAGE' ? {
        isPriority,
        text: data.displayLabel || data.natureOfCall || '',
        senderName: data.address || 'Unknown',
      } : {}),
    };

    console.log(`  [${doc.id}] incidents → feed (type=${type})`);

    if (!DRY_RUN) {
      batch.set(db.collection('feed').doc(doc.id), feedDoc);
      batchCount++;
      if (batchCount === 499) {
        await commitBatch(batch, batchCount, 'incident');
        batch = db.batch();
        batchCount = 0;
      }
    }
    written++;
  }

  await commitBatch(batch, batchCount, 'incident');
  console.log(`incidents/: written=${written}, skipped=${skipped}\n`);
}

async function migrateEvents() {
  const snap = await db.collection('events').get();
  console.log(`events/: ${snap.size} docs`);

  let written = 0, skipped = 0, batchCount = 0;
  let batch = db.batch();

  for (const doc of snap.docs) {
    const data = doc.data();

    const existing = await db.collection('feed').doc(doc.id).get();
    if (existing.exists && existing.data().type) {
      skipped++;
      continue;
    }

    const feedDoc = { ...data, type: 'EVENT' };

    console.log(`  [${doc.id}] events → feed (type=EVENT)`);

    if (!DRY_RUN) {
      batch.set(db.collection('feed').doc(doc.id), feedDoc);
      batchCount++;
      if (batchCount === 499) {
        await commitBatch(batch, batchCount, 'event');
        batch = db.batch();
        batchCount = 0;
      }
    }
    written++;
  }

  await commitBatch(batch, batchCount, 'event');
  console.log(`events/: written=${written}, skipped=${skipped}\n`);
}

async function main() {
  console.log(`Mode: ${DRY_RUN ? 'DRY RUN (no writes)' : 'LIVE'}\n`);
  await migrateIncidents();
  await migrateEvents();
  console.log('Migration complete.');
}

main().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});

