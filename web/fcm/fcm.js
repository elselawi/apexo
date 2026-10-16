import { firebaseConfig, vapidKey, relayServer } from "./constants.js";
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
import { getMessaging, onMessage, getToken } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging.js";
import { PushData } from "./push_data.js";

const RTL_LANGS = new Set(["ar", "fa", "ku", "ur"]);

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
        this._isListening = false;

        this.translations = {
            en: {
                title: "Enable Notifications",
                subtitle: "Never miss an important update. Please allow notifications for Apexo.",
                enable: "Enable",
                later: "Not Now"
            },
            ar: {
                title: "تفعيل الإشعارات",
                subtitle: "لا تفوت أي تحديث مهم. يرجى السماح بإشعارات Apexo.",
                enable: "تفعيل",
                later: "ليس الآن"
            },
            es: {
                title: "Activar notificaciones",
                subtitle: "Nunca te pierdas una actualización importante. Por favor, permite las notificaciones de Apexo.",
                enable: "Activar",
                later: "Ahora no"
            },
            el: {
                title: "Ενεργοποίηση ειδοποιήσεων",
                subtitle: "Μην χάσετε καμία σημαντική ενημέρωση. Επιτρέψτε τις ειδοποιήσεις για το Apexo.",
                enable: "Ενεργοποίηση",
                later: "Όχι τώρα"
            },
            fa: {
                title: "فعال کردن اعلان‌ها",
                subtitle: "هیچ به‌روزرسانی مهمی را از دست ندهید. لطفاً اعلان‌های Apexo را مجاز کنید.",
                enable: "فعال کردن",
                later: "فعلاً نه"
            },
            ku: {
                title: "چالاککردنی ئاگادارکردنەوەکان",
                subtitle: "هیچ نوێکارییەکی گرنگ لەدەست مەدە. تکایە ڕێگە بە ئاگادارکردنەوەکانی Apexo بدە.",
                enable: "چالاککردن",
                later: "ئێستا نا"
            },
            fr: {
                title: "Activer les notifications",
                subtitle: "Ne manquez aucune mise à jour importante. Veuillez autoriser les notifications pour Apexo.",
                enable: "Activer",
                later: "Pas maintenant"
            },
            tr: {
                title: "Bildirimleri Etkinleştir",
                subtitle: "Önemli hiçbir güncellemeyi kaçırmayın. Lütfen Apexo için bildirimlere izin verin.",
                enable: "Etkinleştir",
                later: "Şimdi Değil"
            },
            it: {
                title: "Abilita le notifiche",
                subtitle: "Non perdere nessun aggiornamento importante. Consenti le notifiche per Apexo.",
                enable: "Abilita",
                later: "Non ora"
            },
            ur: {
                title: "اطلاعات فعال کریں",
                subtitle: "کوئی بھی اہم اپ ڈیٹ مس نہ کریں۔ براہ کرم Apexo کے لیے اطلاعات کی اجازت دیں۔",
                enable: "فعال کریں",
                later: "ابھی نہیں"
            }
        };

        this.registerServiceWorker();
        this.setupGlobalsForDart();
        this.bindEvents();
    }

    postToServiceWorker(message) {
        const sw = this.registration?.active || this.registration?.waiting || this.registration?.installing || navigator.serviceWorker?.controller;
        if (sw) {
            try {
                sw.postMessage(message);
            } catch (e) {
                console.warn("Could not postMessage to service worker:", e);
            }
        }
    }

    syncStateToServiceWorker() {
        this.postToServiceWorker({
            type: "LANG_CHANGED",
            lang: this.config.lang || "en",
        });
        this.postToServiceWorker({
            type: "SAVE_CURRENT_ACCOUNT_ID",
            currentAccountID: this.config.accountId || "",
        });
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
                this.config.lang = value || "en";
                self.lang = this.config.lang;
                this.postToServiceWorker({
                    type: "LANG_CHANGED",
                    lang: this.config.lang,
                });
                const el = document.getElementById('fcm-custom-container');
                if (el && el.style.display === 'block') {
                    this.localize();
                }
            }
        });

        // intercept changes to accountId so logout or login immediately updates both window and SW
        Object.defineProperty(window, 'accountId', {
            get: () => this.config.accountId,
            set: (value) => {
                this.config.accountId = value || "";
                window.currentAccountID = this.config.accountId;
                self.currentAccountID = this.config.accountId;
                this.postToServiceWorker({
                    type: "SAVE_CURRENT_ACCOUNT_ID",
                    currentAccountID: this.config.accountId,
                });
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
                    window.currentAccountID = this.config.accountId;
                    self.currentAccountID = this.config.accountId;
                    self.lang = this.config.lang;

                    // send current account id & lang to service worker
                    this.syncStateToServiceWorker();

                    try {
                        const supported = "Notification" in window && typeof window.Notification !== "undefined";
                        const legacySafari = !supported && "safari" in window && "pushNotification" in window.safari;

                        if (supported) {
                            if (window.Notification.permission !== "granted") {
                                // Asked once, ever. The prompt used to come back on
                                // every login (and every page load while logins
                                // were not persisted), which read as a modal the
                                // user could not get rid of. "Not now" is a
                                // decision, so it is remembered.
                                if (this.promptDismissed()) {
                                    this.setup();
                                } else {
                                    this.showPrompt();
                                }
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
                    } catch (notifErr) {
                        console.warn("Notification API unavailable or restricted in this environment:", notifErr.message);
                    }
                }
            }
        });
    }

    async registerServiceWorker() {
        try {
            if (!("serviceWorker" in navigator)) return;
            this.registration = await navigator.serviceWorker.register('/firebase-messaging-sw.js', {
                type: "module",
                scope: "/firebase-cloud-messaging-push-scope",
            });
            console.log("Service Worker registered");
            this.syncStateToServiceWorker();
            if (!this.registration.active) {
                const pending = this.registration.installing || this.registration.waiting;
                if (pending) {
                    pending.addEventListener('statechange', () => {
                        if (this.registration?.active) {
                            this.syncStateToServiceWorker();
                        }
                    });
                }
            }
        } catch (err) {
            console.error("Service Worker registration failed:", err);
        }
    }

    bindEvents() {
        document.getElementById('btn-grant-fcm')?.addEventListener('click', () => this.requestPermission());
        document.getElementById('btn-later-fcm')?.addEventListener('click', () => this.rememberPromptDismissed());
    }

    localize() {
        const lang = this.config.lang || 'en';
        const texts = this.translations[lang] || this.translations['en'];
        const isRtl = RTL_LANGS.has(lang);

        const titleEl = document.getElementById('fcm-lbl-title');
        const subtitleEl = document.getElementById('fcm-lbl-subtitle');
        const btnGrant = document.getElementById('btn-grant-fcm');
        const btnLater = document.getElementById('btn-later-fcm');
        const dialogBox = document.getElementById('fcm-dialog-box');

        if (titleEl) titleEl.innerText = texts.title;
        if (subtitleEl) subtitleEl.innerText = texts.subtitle;
        if (btnGrant) btnGrant.innerText = texts.enable;
        if (btnLater) btnLater.innerText = texts.later;

        // Ensure correct layout direction for all RTL languages (ar, fa, ku, ur)
        if (dialogBox) {
            dialogBox.style.direction = isRtl ? 'rtl' : 'ltr';
            dialogBox.style.textAlign = isRtl ? 'right' : 'left';

            const buttonsContainer = dialogBox.querySelector('.fcm-buttons');
            if (buttonsContainer) {
                buttonsContainer.style.justifyContent = isRtl ? 'flex-start' : 'flex-end';
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

    // Whether the user has already answered the prompt with "Not now".
    promptDismissed() {
        try {
            return window.localStorage.getItem('apexo-fcm-prompt-dismissed') === '1';
        } catch (e) {
            return false;
        }
    }

    // Records "Not now" so the prompt is never shown again on this device.
    rememberPromptDismissed() {
        try {
            window.localStorage.setItem('apexo-fcm-prompt-dismissed', '1');
        } catch (e) {
            // Private mode / storage disabled: the prompt is simply asked again.
        }
        this.hidePrompt();
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

        const permission = await window.Notification.requestPermission();
        if (permission === 'granted') {
            await this.setup();
        } else {
            // A refusal cannot be undone from inside the app, so asking again on
            // the next login would only be noise.
            console.warn("Permission denied");
            this.rememberPromptDismissed();
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

            console.log("Device token retrieved");
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
        if (this._isListening) return;
        this._isListening = true;
        onMessage(this.messaging, async (payload) => {
            if (!this.config.accountId) return;
            try {
                const rawPayload = payload?.data?.payload;
                if (typeof rawPayload !== "string" || !rawPayload) return;
                const pushData = PushData.fromJson(JSON.parse(rawPayload));
                const displayTuple = pushData.displayTuple();

                if (!this.registration && "serviceWorker" in navigator) {
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