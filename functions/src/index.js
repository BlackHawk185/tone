const { onDocumentCreated } = require('firebase-functions/v2/firestore');
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

// Active/inactive state for events is computed client-side from
// event.time + event.durationMin — no scheduled status write-back needed.
