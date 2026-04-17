// Firebase Cloud Messaging service worker — required for background push on web.
// Must live at the root of the web app so the browser can register it.
// Uses the compat SDK because ES module imports are not supported in service workers.

importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyCAQuDVjIuYz5u_HgrrLuGKSDRWQukciV8',
  authDomain: 'tone-b66eb.firebaseapp.com',
  projectId: 'tone-b66eb',
  storageBucket: 'tone-b66eb.firebasestorage.app',
  messagingSenderId: '323826101860',
  appId: '1:323826101860:web:da0bfd2c06d33712e97971',
});

const messaging = firebase.messaging();

// Handle background/closed-tab messages and show a notification.
messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title ?? 'Tone Alert';
  const body = payload.notification?.body ?? '';
  return self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data ?? {},
    // Keep the notification visible until the user interacts.
    requireInteraction: true,
  });
});
