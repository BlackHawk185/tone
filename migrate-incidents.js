/**
 * migrate-incidents.js
 *
 * One-shot migration that adapts legacy incident documents to the current schema
 * expected by DispatchEvent.fromFirestore():
 *
 *   serviceType   — derived from incidentCategory || incidentType if missing
 *   displayLabel  — derived from natureOfCall if missing
 *   unitCodes     — defaulted to [] if missing
 *
 * Run from the repo root:
 *   node migrate-incidents.js [--dry-run]
 *
 * Requires GOOGLE_APPLICATION_CREDENTIALS or Application Default Credentials
 * (i.e. `firebase login` / `gcloud auth application-default login`).
 */

const admin = require('firebase-admin');

const DRY_RUN = process.argv.includes('--dry-run');

admin.initializeApp({ projectId: 'tone-b66eb' });
const db = admin.firestore();

/**
 * Derives serviceType using the same logic as cloud-run/src/firestore.js:
 *   incident.serviceType || incident.incidentCategory || incident.incidentType
 *
 * Normalises to one of: FIRE | EMS | BOTH | MESSAGE | PRIORITY TRAFFIC | UNKNOWN
 */
function deriveServiceType(data) {
  const raw = (
    data.serviceType ||
    data.incidentCategory ||
    data.incidentType ||
    ''
  ).trim().toUpperCase();

  if (!raw) return 'UNKNOWN';

  // Normalise legacy category values that map to known service types
  if (raw === 'FIRE' || raw === 'EMS' || raw === 'BOTH') return raw;
  if (raw === 'MESSAGE' || raw === 'PRIORITY TRAFFIC') return raw;

  // Legacy free-text incidentType that implies a service type
  if (/\bfire\b|structure|wildland|vehicle fire|brush/i.test(raw)) return 'FIRE';
  if (/\bems\b|medical|trauma|cardiac|respiratory/i.test(raw)) return 'EMS';

  // Keep whatever the raw value was — better than UNKNOWN
  return raw;
}

async function migrate() {
  console.log(`Mode: ${DRY_RUN ? 'DRY RUN (no writes)' : 'LIVE'}\n`);

  const snapshot = await db.collection('incidents').get();
  console.log(`Found ${snapshot.size} incident(s) to inspect.\n`);

  let updated = 0;
  let skipped = 0;
  const batch = db.batch();
  let batchCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const patch = {};

    // ── serviceType ──────────────────────────────────────────────────────────
    if (!data.serviceType) {
      patch.serviceType = deriveServiceType(data);
    }

    // ── displayLabel ─────────────────────────────────────────────────────────
    if (data.displayLabel === undefined || data.displayLabel === null) {
      patch.displayLabel = (data.natureOfCall || '').trim();
    }

    // ── unitCodes ─────────────────────────────────────────────────────────────
    if (!Array.isArray(data.unitCodes)) {
      patch.unitCodes = [];
    }

    if (Object.keys(patch).length === 0) {
      skipped++;
      continue;
    }

    console.log(`[${doc.id}] patching:`, patch);

    if (!DRY_RUN) {
      batch.set(doc.ref, patch, { merge: true });
      batchCount++;

      // Firestore batches are capped at 500 operations
      if (batchCount === 499) {
        await batch.commit();
        console.log('  → Committed batch of 499.');
        batchCount = 0;
      }
    }

    updated++;
  }

  if (!DRY_RUN && batchCount > 0) {
    await batch.commit();
    console.log(`  → Committed final batch of ${batchCount}.`);
  }

  console.log(`\nDone. Updated: ${updated}  |  Already current: ${skipped}`);
}

migrate().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});
