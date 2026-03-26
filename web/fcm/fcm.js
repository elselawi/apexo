import { firebaseConfig, vapidKey, relayServer } from "./constants.js";
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
import { getMessaging, onMessage, getToken } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging.js";
import { PushData } from "./push_data.js";

class FCMManager {
    constructor() {
        this.config = {
            clinicServer: "",
            clinicKey: "",
            accountId: "",
            lang: "en",
        };

        this.app = initializeApp(firebaseConfig);
        this.messaging = getMessaging(this.app);
        this.registration = null;

        this.translations = {
            en: {
                title: "Enable Notifications",
                subtitle: "Never miss an important update. Please allow notifications for Apexo.",
                enable: "Enable",
                later: "Not Now"
            },
            es: {
                title: "Activar notificaciones",
                subtitle: "Nunca te pierdas una actualización importante. Por favor, permite las notificaciones de Apexo.",
                enable: "Activar",
                later: "Ahora no"
            },
            ar: {
                title: "تفعيل الإشعارات",
                subtitle: "لا تفوت أي تحديث مهم. يرجى السماح بإشعارات Apexo.",
                enable: "تفعيل",
                later: "ليس الآن"
            }
        };

        this.registerServiceWorker();
        this.setupGlobalsForDart();
        this.bindEvents();
    }

    setupGlobalsForDart() {
        // Expose configuration variables for Dart to populate
        window.clinicServer = "";
        window.clinicKey = "";
        window.accountId = "";
        window.lang = "en";

        // intercept changes to lang
        Object.defineProperty(window, 'lang', {
            get: () => this.config.lang,
            set: (value) => {
                this.config.lang = value;
                if (this.registration) {
                    this.registration.active.postMessage({
                        type: "LANG_CHANGED",
                        lang: value,
                    });
                }
            }
        });

        // Intercept changes to shouldShowPrompt
        let _shouldShowPrompt = "no";
        Object.defineProperty(window, 'shouldShowPrompt', {
            get: () => _shouldShowPrompt,
            set: (value) => {
                _shouldShowPrompt = value;
                if (value === "yes") {
                    _shouldShowPrompt = "no"; // Auto-reset instantly

                    // Sync dart variables to our internal config
                    this.config.clinicServer = window.clinicServer;
                    this.config.clinicKey = window.clinicKey;
                    this.config.accountId = window.accountId;
                    this.config.lang = window.lang;

                    // set current account id (push_data access from window)
                    window.currentAccountID = window.accountId;

                    // send current account id to service worker (push_data access from sw)
                    this.registration.active.postMessage({
                        type: "SAVE_CURRENT_ACCOUNT_ID",
                        currentAccountID: window.accountId,
                    });


                    const supported = "Notification" in window;
                    const legacySafari = !supported && "safari" in window && "pushNotification" in window.safari;

                    if (supported) {
                        if (Notification.permission !== "granted") {
                            this.showPrompt();
                        } else {
                            this.setup();
                        }
                    } else if (legacySafari) {
                        // Legacy Safari Push API support could be added here if needed
                        console.log("Legacy Safari Push Notification API detected");
                        // For now, we just avoid the crash
                    } else {
                        console.warn("Notifications are not supported in this browser environment.");
                        // On iOS, explain PWA requirement
                        const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream;
                        if (isIOS && !window.navigator.standalone) {
                            console.info("On iOS, Web Push requires the app to be 'Added to Home Screen'.");
                        }
                    }
                }
            }
        });
    }

    async registerServiceWorker() {
        try {
            this.registration = await navigator.serviceWorker.register('/firebase-messaging-sw.js', {
                type: "module",
                scope: "/firebase-cloud-messaging-push-scope",
            });
            console.log("Service Worker registered");
        } catch (err) {
            console.error("Service Worker registration failed:", err);
        }
    }

    bindEvents() {
        document.getElementById('btn-grant-fcm')?.addEventListener('click', () => this.requestPermission());
        document.getElementById('btn-later-fcm')?.addEventListener('click', () => this.hidePrompt());
    }

    localize() {
        const lang = this.config.lang || 'en';
        const texts = this.translations[lang] || this.translations['en'];

        const titleEl = document.getElementById('fcm-lbl-title');
        const subtitleEl = document.getElementById('fcm-lbl-subtitle');
        const btnGrant = document.getElementById('btn-grant-fcm');
        const btnLater = document.getElementById('btn-later-fcm');
        const dialogBox = document.getElementById('fcm-dialog-box');

        if (titleEl) titleEl.innerText = texts.title;
        if (subtitleEl) subtitleEl.innerText = texts.subtitle;
        if (btnGrant) btnGrant.innerText = texts.enable;
        if (btnLater) btnLater.innerText = texts.later;

        // Ensure correct layout direction for Arabic
        if (dialogBox) {
            dialogBox.style.direction = lang === 'ar' ? 'rtl' : 'ltr';
            dialogBox.style.textAlign = lang === 'ar' ? 'right' : 'left';

            const buttonsContainer = dialogBox.querySelector('.fcm-buttons');
            if (buttonsContainer) {
                buttonsContainer.style.justifyContent = lang === 'ar' ? 'flex-start' : 'flex-end';
            }
        }
    }

    showPrompt() {
        this.localize();
        const el = document.getElementById('fcm-custom-container');
        if (el) el.style.display = 'block';
    }

    hidePrompt() {
        const el = document.getElementById('fcm-custom-container');
        if (el) el.style.display = 'none';
    }

    async requestPermission() {
        this.hidePrompt();

        if (!("Notification" in window)) {
            const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream;
            if (isIOS && !window.navigator.standalone) {
                alert("To enable notifications on iOS, please add this app to your Home Screen (Tap Share > Add to Home Screen).");
            } else {
                alert("This browser does not support notifications.");
            }
            return;
        }

        const permission = await Notification.requestPermission();
        if (permission === 'granted') {
            await this.setup();
        } else {
            console.warn("Permission denied");
        }
    }

    async getDeviceToken() {
        try {
            if (!this.registration) {
                this.registration = await navigator.serviceWorker.ready;
            }

            const token = await getToken(this.messaging, {
                vapidKey: vapidKey,
                serviceWorkerRegistration: this.registration
            });

            console.log("Token retrieved:", token);
            return token;
        } catch (e) {
            console.error("Token error:", e);
            return null;
        }
    }

    async sendTokenToRelay(deviceToken) {
        try {
            const res = await fetch(relayServer + "/put-device", {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    clinicServer: this.config.clinicServer,
                    clinicKey: this.config.clinicKey,
                    accountId: this.config.accountId,
                    deviceToken,
                }),
            });

            if (res.ok) {
                const response = await res.text();
                if (response === "ok") {
                    console.log("Device token sent successfully");
                } else {
                    console.warn("Relay server returned unexpected text:", response);
                }
            } else {
                console.error(`Relay server error: ${res.status} ${res.statusText}`);
            }
        } catch (err) {
            console.error("Relay server request failed:", err);
        }
    }

    listenForMessages() {
        onMessage(this.messaging, async (payload) => {
            if (!this.config.accountId) return;
            try {
                const pushData = PushData.fromJson(JSON.parse(payload.data.payload));
                const displayTuple = pushData.displayTuple();

                if (!this.registration) {
                    this.registration = await navigator.serviceWorker.ready;
                }

                if (this.registration) {
                    this.registration.showNotification(displayTuple[0], {
                        body: displayTuple[1],
                        icon: '/icons/Icon-192.png',
                        badge: '/icons/Icon-192.png',
                    });
                }
            } catch (err) {
                console.error("Error processing foreground message:", err);
            }
        });
    }

    async setup() {
        const deviceToken = await this.getDeviceToken();
        if (!deviceToken) return;

        await this.sendTokenToRelay(deviceToken);
        this.listenForMessages();
    }
}

// Instantiate the manager globally
window.fcmManager = new FCMManager();