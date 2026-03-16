import { PushData } from "./fcm/push_data.js";
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
import { getMessaging, onBackgroundMessage } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-sw.js";
import { firebaseConfig } from "./fcm/constants.js";

const app = initializeApp(firebaseConfig);
const messaging = getMessaging(app);

// default language
self.lang = "en";

// intercept messages from the main thread to update the language
self.addEventListener('message', (event) => {
    console.log("Message received in SW:", event.data);
    if (event.data.type === "LANG_CHANGED") {
        console.log("Language changed to:", event.data.lang);
        self.lang = event.data.lang;
    }

    if (event.data.type === "SAVE_CURRENT_ACCOUNT_ID") {
        console.log("Current account ID saved:", event.data.currentAccountID);
        self.currentAccountID = event.data.currentAccountID;
    }
});

// intercept background messages
onBackgroundMessage(messaging, (payload) => {
    try {
        const pushData = PushData.fromJson(JSON.parse(payload.data.payload));
        const displayTuple = pushData.displayTuple();
        if (self.registration) {
            self.registration.showNotification(displayTuple[0], {
                body: displayTuple[1],
                icon: '/icons/Icon-192.png',
                badge: '/icons/Icon-192.png',
            });
        }
    } catch (err) {
        console.error("Error processing background message:", err);
    }
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