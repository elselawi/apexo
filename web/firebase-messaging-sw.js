import { PushData } from "./fcm/push_data.js";
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
import { getMessaging, onBackgroundMessage } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-sw.js";
import { firebaseConfig } from "./fcm/constants.js";

const app = initializeApp(firebaseConfig);
const messaging = getMessaging(app);
onBackgroundMessage(messaging, (payload) => {
    let notificationTitle = "New Message";
    let notificationOptions = {
        body: "You have a new message.",
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        data: payload.data?.payload || null,
    };

    try {
        if (payload?.data?.payload) {
            const pushData = PushData.fromJson(JSON.parse(payload.data.payload));
            const displayTuple = pushData.displayTuple();
            notificationTitle = displayTuple[0];
            notificationOptions.body = displayTuple[1];
        }
    } catch (err) {
        console.error("Error parsing background message payload:", err);
    }

    return self.registration.showNotification(notificationTitle, notificationOptions);
});

self.addEventListener('notificationclick', (event) => {
    event.notification.close();

    event.waitUntil(
        clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
            if (clientList.length > 0) {
                return clientList[0].focus();
            }
            return clients.openWindow('/');
        })
    );
});