'use strict';

var core = require('@capacitor/core');

const FacebookLogin = core.registerPlugin('FacebookLogin', {
    web: () => Promise.resolve().then(function () { return web; }).then((m) => new m.FacebookLoginWeb()),
});

class FacebookLoginWeb extends core.WebPlugin {
    async initialize(options) {
        const defaultOptions = { version: 'v26.0' };
        await this.loadScript(options.locale);
        return FB.init(Object.assign(Object.assign({}, defaultOptions), options));
    }
    loadScript(locale) {
        if (typeof document === 'undefined') {
            return Promise.reject('document global not found');
        }
        const scriptId = 'fb';
        const scriptEl = document.getElementById(scriptId);
        if (scriptEl) {
            // already loaded
            return Promise.resolve();
        }
        const head = document.getElementsByTagName('head')[0];
        const script = document.createElement('script');
        return new Promise((resolve) => {
            script.onload = () => resolve();
            script.defer = true;
            script.async = true;
            script.id = scriptId;
            script.src = `https://connect.facebook.net/${locale !== null && locale !== void 0 ? locale : 'en_US'}/sdk.js`;
            head.appendChild(script);
        });
    }
    async login(options) {
        return new Promise((resolve, reject) => {
            const resolveWithAccessToken = (response) => {
                var _a;
                const token = (_a = response.authResponse) === null || _a === void 0 ? void 0 : _a.accessToken;
                if (response.status !== 'connected' || !token) {
                    return false;
                }
                resolve({
                    accessToken: {
                        token,
                    },
                });
                return true;
            };
            FB.login((response) => {
                if (resolveWithAccessToken(response)) {
                    return;
                }
                FB.getLoginStatus((statusResponse) => {
                    if (!resolveWithAccessToken(statusResponse)) {
                        reject('Facebook login did not return an access token.');
                    }
                });
            }, { scope: options.permissions.join(',') });
        });
    }
    async logout() {
        return new Promise((resolve) => FB.logout(() => resolve()));
    }
    async reauthorize() {
        return new Promise((resolve) => FB.reauthorize((it) => resolve(it)));
    }
    async getCurrentAccessToken() {
        return new Promise((resolve, reject) => {
            FB.getLoginStatus((response) => {
                if (response.status === 'connected') {
                    const result = {
                        accessToken: {
                            applicationId: undefined,
                            declinedPermissions: [],
                            expires: undefined,
                            isExpired: undefined,
                            lastRefresh: undefined,
                            permissions: [],
                            token: response.authResponse.accessToken,
                            userId: response.authResponse.userID,
                        },
                    };
                    resolve(result);
                }
                else {
                    reject({
                        accessToken: {
                            token: null,
                        },
                    });
                }
            });
        });
    }
    async getProfile(options) {
        const fields = options.fields.join(',');
        return new Promise((resolve, reject) => {
            FB.api('/me', { fields }, (response) => {
                if (response.error) {
                    reject(response.error.message);
                    return;
                }
                resolve(response);
            });
        });
    }
    async logEvent(options) {
        FB.AppEvents.logEvent(options.eventName, undefined, options.parameters);
    }
    async setAutoLogAppEventsEnabled() {
        return Promise.resolve();
    }
    async setAdvertiserTrackingEnabled() {
        return Promise.resolve();
    }
    async setAdvertiserIDCollectionEnabled() {
        return Promise.resolve();
    }
    async getDeferredDeepLink() {
        return Promise.resolve({});
    }
}

var web = /*#__PURE__*/Object.freeze({
    __proto__: null,
    FacebookLoginWeb: FacebookLoginWeb
});

exports.FacebookLogin = FacebookLogin;
//# sourceMappingURL=plugin.cjs.js.map
