export interface AccessToken {
  applicationId?: string;
  declinedPermissions?: string[];
  expires?: string;
  isExpired?: boolean;
  lastRefresh?: string;
  permissions?: string[];
  token: string;
  userId?: string;
}

export interface FacebookLoginResponse {
  accessToken: AccessToken | null;
  recentlyGrantedPermissions?: string[];
  recentlyDeniedPermissions?: string[];
}

export interface FacebookCurrentAccessTokenResponse {
  accessToken: AccessToken | null;
}

/**
 * Deferred deep-link data supplied by a native platform.
 *
 * All fields are optional because a platform can return partial attribution data,
 * or no deferred link at all.
 */
export interface FacebookDeferredDeepLinkResponse {
  uri?: string;
  promotionCode?: string;
  arguments?: Record<string, unknown>;
}

export interface FacebookLoginPlugin {
  initialize(options: Partial<FacebookConfiguration>): Promise<void>;
  login(options: {
    permissions: string[];
    /**
     * Limited Login: iOS Only.
     * https://developers.facebook.com/docs/facebook-login/limited-login/ios/
     */
    tracking?: 'limited' | 'enabled';
    /**
     * A random string used to verify the identity of the person who is logging in.
     * This requires raw string, not sha256 hash.
     */
    nonce?: string;
  }): Promise<FacebookLoginResponse>;
  logout(): Promise<void>;
  reauthorize(): Promise<FacebookLoginResponse>;
  getCurrentAccessToken(): Promise<FacebookCurrentAccessTokenResponse>;
  getProfile<T extends Record<string, unknown>>(options: { fields: readonly string[] }): Promise<T>;
  logEvent(options: { eventName: string }): Promise<void>;
  setAutoLogAppEventsEnabled(options: { enabled: boolean }): Promise<void>;
  setAdvertiserTrackingEnabled(options: { enabled: boolean }): Promise<void>;
  setAdvertiserIDCollectionEnabled(options: { enabled: boolean }): Promise<void>;
  /**
   * Retrieves deferred deep-link data, when the native platform provides it.
   *
   * Android makes one immediate request and then up to five retries, spaced two
   * seconds apart; it rejects when no data is available after those attempts.
   * iOS and web resolve an empty object when no URI is available. iOS rejects
   * configuration and SDK errors.
   */
  getDeferredDeepLink(): Promise<FacebookDeferredDeepLinkResponse>;
}

export interface FacebookGetLoginStatusResponse {
  status: 'connected';
  authResponse: {
    accessToken: string;
    expiresIn: number;
    reauthorize_required_in: number;
    signedRequest: string;
    userID: string;
  };
}

export interface FacebookError {
  message: string;
  type: string;
  code: number;
}

export interface FacebookGetProfileResponse {
  error: FacebookError | null;
}

export interface FacebookConfiguration {
  appId: string;
  autoLogAppEvents: boolean;
  xfbml: boolean;
  version: string;
  locale: string;
}
