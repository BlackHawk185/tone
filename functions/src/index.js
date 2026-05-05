const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

admin.initializeApp();

/**
 * Triggered when a new feed document is created in Firestore.
 * Sends a high-priority FCM push notification to the appropriate topic,
 * which app users subscribe to based on their channel settings.
 */
exports.onNewIncident = onDocumentCreated('feed/{eventId}', async (event) => {
  const incident = event.data.data();
  const incidentId = incident?.incidentId || event.params.eventId;

  if (!incident) {
    console.error('No incident data found in event');
    return;
  }

  const explicitType = String(incident.type || '').toUpperCase();
  const rawServiceType = String(
    incident.serviceType || incident.incidentCategory || incident.incidentType || '',
  ).toUpperCase();
  const isPriorityMessage =
    incident.isPriority === true || rawServiceType === 'PRIORITY TRAFFIC';
  const isMessage =
    explicitType === 'MESSAGE' || rawServiceType === 'MESSAGE' || isPriorityMessage;

  if (explicitType === 'EVENT') {
    console.log(`[FCM] Skipping calendar event ${incidentId}`);
    return;
  }

  const unitCodes = incident.unitCodes || [];
  const serviceType = isPriorityMessage
    ? 'PRIORITY TRAFFIC'
    : isMessage
      ? 'MESSAGE'
      : rawServiceType;
  const displayLabel = incident.displayLabel || incident.natureOfCall || incident.text || '';

  // Determine FCM topic prefix based on message type
  let topicPrefix;
  if (isMessage) {
    topicPrefix = 'messages';
  } else if (isPriorityMessage) {
    topicPrefix = 'priority';
  } else {
    topicPrefix = 'dispatch';
  }

  // Build list of unit-specific topics to fan out to.
  // For dispatches, each unit code gets its own topic (e.g. dispatch_21523).
  // For messages/priority sent from the app, unitCodes lists the target channels.
  const topics = unitCodes.length > 0
    ? unitCodes.map(code => `${topicPrefix}_${code}`)
    : [`${topicPrefix}_general`];

  // Build notification title/body for iOS APNS alert
  const title = isPriorityMessage
    ? `\u26a0 ${incident.address || displayLabel || 'Priority Traffic'}`
    : isMessage
      ? `${incident.address || incident.senderName || 'Message'}`
      : `TONE: ${displayLabel || serviceType}`;
  const body = (isMessage || isPriorityMessage)
    ? (incident.natureOfCall || incident.text || displayLabel || '')
    : (incident.address || '');

  // Data-only message (no top-level `notification` key) so Android always
  // delivers to DispatchMessagingService.onMessageReceived, even when
  // the app is backgrounded. iOS still shows via apns.payload.aps.alert.
  // Fan out to each unit-code topic.
  const results = await Promise.allSettled(
    topics.map(topic => {
      const message = {
        topic,
        data: {
          incidentId,
          incidentType: serviceType,
          serviceType,
          displayLabel,
          channel: topic,
          address: incident.address || '',
          units: JSON.stringify(incident.units || []),
          unitCodes: JSON.stringify(unitCodes),
          natureOfCall: incident.natureOfCall || '',
          dispatchTime: incident.dispatchTime || '',
          priority: incident.priority || '',
        },
        android: {
          priority: 'high',
        },
        apns: {
          headers: {
            'apns-priority': '10',
            'apns-push-type': 'alert',
          },
          payload: {
            aps: {
              alert: { title, body },
              sound: {
                critical: 1,
                name: 'default',
                volume: 1.0,
              },
              'content-available': 1,
              'interruption-level': 'critical',
            },
          },
        },
      };
      return admin.messaging().send(message);
    })
  );

  const succeeded = results.filter(r => r.status === 'fulfilled').length;
  const failed = results.filter(r => r.status === 'rejected');
  console.log(`[FCM] Sent ${succeeded}/${topics.length} notifications for incident ${incidentId} to topics: ${topics.join(', ')}`);
  for (const f of failed) {
    console.error(`[FCM] Failed:`, f.reason);
  }
});

/**
 * Sync on-call shifts from WhenIWork API every 10 minutes.
 *
 * Reads config/wheniwork for the W-Token and user mapping,
 * fetches current shifts, and writes active on-call responders
 * to config/onCall. Also sends FCM notifications on shift transitions.
 *
 * TODO: Replace demo stub with real WhenIWork API calls once W-Token is obtained.
 */
exports.syncOnCall = onSchedule('every 10 minutes', async (_event) => {
  const db = admin.firestore();

  // Check for WhenIWork config
  const configDoc = await db.collection('config').doc('wheniwork').get();
  if (!configDoc.exists || !configDoc.data().wToken) {
    console.log('[WhenIWork] No API token configured — skipping sync. Using demo data.');
    return;
  }

  const config = configDoc.data();
  const wToken = config.wToken;
  const userMap = config.userMap || {}; // { wiwUserId: firebaseUid }

  // Fetch current shifts from WhenIWork
  const now = new Date().toISOString();
  const threeHoursLater = new Date(Date.now() + 3 * 60 * 60 * 1000).toISOString();

  try {
    const https = require('https');
    const shiftsData = await new Promise((resolve, reject) => {
      const req = https.request({
        hostname: 'api.wheniwork.com',
        path: `/2/shifts?start=${encodeURIComponent(now)}&end=${encodeURIComponent(threeHoursLater)}`,
        method: 'GET',
        headers: { 'W-Token': wToken },
      }, (res) => {
        let raw = '';
        res.on('data', c => raw += c);
        res.on('end', () => {
          try { resolve(JSON.parse(raw)); }
          catch (e) { reject(new Error('Failed to parse WhenIWork response')); }
        });
      });
      req.on('error', reject);
      req.end();
    });

    if (!shiftsData.shifts || !Array.isArray(shiftsData.shifts)) {
      console.warn('[WhenIWork] Unexpected response shape:', JSON.stringify(shiftsData).substring(0, 200));
      return;
    }

    // Build on-call list from active shifts
    const activeUsers = [];
    for (const shift of shiftsData.shifts) {
      if (!shift.user_id || shift.user_id === 0) continue; // Skip open shifts
      const firebaseUid = userMap[String(shift.user_id)];
      if (!firebaseUid) {
        console.warn(`[WhenIWork] No Firebase UID mapped for WhenIWork user ${shift.user_id}`);
        continue;
      }

      // Look up display name from Firebase Auth
      let displayName = `User ${shift.user_id}`;
      try {
        const userRecord = await admin.auth().getUser(firebaseUid);
        displayName = userRecord.displayName || userRecord.email || displayName;
      } catch (_) { /* use fallback */ }

      activeUsers.push({
        uid: firebaseUid,
        displayName,
        shiftStart: shift.start_time,
        shiftEnd: shift.end_time,
        wiwUserId: shift.user_id,
      });
    }

    // Detect shift transitions for push notifications
    const prevDoc = await db.collection('config').doc('onCall').get();
    const prevUids = new Set((prevDoc.data()?.users || []).map(u => u.uid));
    const newUids = new Set(activeUsers.map(u => u.uid));

    // Notify users whose shift just started
    for (const user of activeUsers) {
      if (!prevUids.has(user.uid)) {
        try {
          await admin.messaging().send({
            topic: 'dispatch',
            notification: {
              title: 'Shift Started',
              body: `${user.displayName} is now on call until ${user.shiftEnd}`,
            },
          });
          console.log(`[WhenIWork] Notified shift start for ${user.displayName}`);
        } catch (e) {
          console.error(`[WhenIWork] FCM error for shift start:`, e);
        }
      }
    }

    // Write updated on-call list
    await db.collection('config').doc('onCall').set({
      users: activeUsers,
      lastSynced: now,
    });

    console.log(`[WhenIWork] Synced ${activeUsers.length} on-call responders`);
  } catch (err) {
    console.error('[WhenIWork] Sync failed:', err);
  }
});
