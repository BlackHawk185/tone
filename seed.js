const admin = require('firebase-admin');

// Initialize with application default credentials or service account
admin.initializeApp({
  projectId: 'tone-b66eb',
});

const db = admin.firestore();

async function run() {
  const incidentId = `TEST-${Date.now()}`;
  const now = new Date().toISOString();

  console.log(`Writing incident ${incidentId}...`);
  await db.collection('incidents').doc(incidentId).set({
    incidentId,
    incidentType: 'STRUCTURE FIRE',
    address: '123 Main St, Anytown',
    units: ['E1', 'E3', 'M2'],
    priority: '1',
    dispatchTime: now,
    status: 'active',
    lat: 40.9312,
    lng: -74.3654,
  });
  console.log(`✓ Incident written: ${incidentId}`);

  // Seed on-call demo data
  console.log('Writing on-call demo data...');
  const shiftStart = new Date();
  shiftStart.setHours(shiftStart.getHours() - 2);
  const shiftEnd = new Date();
  shiftEnd.setHours(shiftEnd.getHours() + 10);

  await db.collection('config').doc('onCall').set({
    users: [
      {
        uid: 'demo-user-1',
        displayName: 'Smith',
        role: 'PCP',
        shiftStart: shiftStart.toISOString(),
        shiftEnd: shiftEnd.toISOString(),
        wiwUserId: 101,
      },
      {
        uid: 'demo-user-2',
        displayName: 'Jones',
        role: 'Driver',
        shiftStart: shiftStart.toISOString(),
        shiftEnd: shiftEnd.toISOString(),
        wiwUserId: 102,
      },
    ],
    lastSynced: now,
  });
  console.log('✓ On-call demo data written (Smith, Jones on shift)');
  console.log('  Check your app — banner should appear on the home screen.');
}

run().catch(console.error);
