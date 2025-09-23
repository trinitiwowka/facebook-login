import Foundation
import Capacitor
import FBSDKLoginKit
import FBSDKCoreKit

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitor.ionicframework.com/docs/plugins/ios
 */
@objc(FacebookLogin)
public class FacebookLogin: CAPPlugin {
    private let loginManager = LoginManager()
    private let dateFormatter = ISO8601DateFormatter()
    private let domainConfigurationDefaultsKey = "com.facebook.sdk:domainConfiguration"
    private let domainConfigurationRequestTimeout: TimeInterval = 20

    override public func load() {
        if #available(iOS 11.2, *) {
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        } else {
            dateFormatter.formatOptions = [.withInternetDateTime]
        }

    }

    private func dateToJS(_ date: Date) -> String {
        return dateFormatter.string(from: date)
    }

    @objc func initialize(_ call: CAPPluginCall) {
        call.resolve()
    }

    @objc func login(_ call: CAPPluginCall) {
        guard let permissions = call.getArray("permissions", String.self) else {
            call.reject("Missing permissions argument")
            return
        }

        DispatchQueue.main.async {
            self.loginManager.logIn(permissions: permissions, from: self.bridge?.viewController) { result, error in
                if let error = error {
                    print(error)
                    call.reject("LoginManager.logIn failed: \(error.localizedDescription)", nil, error)
                } else if let result = result, result.isCancelled {
                    print("User cancelled login")
                    call.resolve()
                } else {
                    print("Logged in")
                    return self.getCurrentAccessToken(call)
                }
            }
        }
    }

    @objc func limitedLogin(_ call: CAPPluginCall) {
        guard let permissions = call.getArray("permissions", String.self) else {
            call.reject("Missing permissions argument")
            return
        }

        let nonce = call.getString("nonce") ?? ""
        let tracking = call.getString("tracking") ?? "limited"

        let configuration: LoginConfiguration
        if nonce != "" {
            guard let config = LoginConfiguration(
                permissions: permissions,
                tracking: tracking == "limited" ? .limited : .enabled,
                nonce: nonce
            ) else {
                return
            }
            configuration = config
        } else {
            guard let config = LoginConfiguration(
                permissions: permissions,
                tracking: tracking == "limited" ? .limited : .enabled
            ) else {
                return
            }
            configuration = config
        }

        DispatchQueue.main.async {
            self.loginManager.logIn(configuration: configuration) { result in
                switch result {
                case .cancelled:
                    print("User cancelled login")
                    call.resolve()
                case .failed:
                    call.reject("LoginManager.logIn failed")
                case .success:
                    print("Logged in")
                    return self.getAuthToken(call)
                }
            }
        }
    }

    @objc func logout(_ call: CAPPluginCall) {
        loginManager.logOut()

        call.resolve()
    }

    @objc func reauthorize(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if let token = AccessToken.current, !token.isDataAccessExpired {
                return self.getCurrentAccessToken(call)
            } else {
                self.loginManager.reauthorizeDataAccess(from: (self.bridge?.viewController)!) { (loginResult, error) in
                    if (loginResult?.token) != nil {
                        return self.getCurrentAccessToken(call)
                    } else {
                        print(error!)
                        call.reject("LoginManager.reauthorize failed")
                    }
                }
            }
        }
    }

    private func refreshDomainConfiguration(completion: @escaping (Error?) -> Void) {
        guard let appID = Settings.shared.appID, !appID.isEmpty else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        let parameters: [String: String] = ["fields": ""]
        let request = GraphRequest(
            graphPath: "\(appID)/server_domain_infos",
            parameters: parameters,
            tokenString: nil,
            httpMethod: .get,
            flags: [.skipClientToken, .disableErrorRecovery]
        )

        let connection = GraphRequestConnection()
        connection.timeout = domainConfigurationRequestTimeout
        connection.add(request) { [weak self] _, result, error in
            guard let self = self else { return }
            let processedError = self.processDomainConfigurationResult(result: result, error: error)
            DispatchQueue.main.async {
                completion(processedError)
            }
        }
        connection.start()
    }

    private func processDomainConfigurationResult(result: Any?, error: Error?) -> Error? {
        if let error = error {
            return error
        }

        guard let resultDictionary = result as? [String: Any],
              let dataArray = resultDictionary["data"] as? [[String: Any]],
              let endpointsContainer = dataArray.first,
              let endpoints = endpointsContainer["endpoints"] as? [[String: Any]] else {
            return domainConfigurationParsingError()
        }

        var domainInfo: [String: [String: Any]] = [:]
        for endpoint in endpoints {
            guard let key = endpoint["key"] as? String,
                  let value = endpoint["value"] as? [String: Any] else {
                continue
            }
            domainInfo[key] = value
        }

        let configuration = _DomainConfiguration(timestamp: Date(), domainInfo: domainInfo)
        do {
            let archivedData = try NSKeyedArchiver.archivedData(withRootObject: configuration, requiringSecureCoding: true)
            UserDefaults.standard.set(archivedData, forKey: domainConfigurationDefaultsKey)
            _DomainConfigurationManager.sharedInstance().loadDomainConfiguration(withCompletionBlock: nil)
            DispatchQueue.main.async {
                GraphRequestConnection.setDidFetchDomainConfiguration()
                GraphRequestQueue.sharedInstance().flush()
            }
            return nil
        } catch {
            return error
        }
    }

    private func domainConfigurationParsingError() -> NSError {
        NSError(
            domain: "FacebookLoginDomainConfiguration",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Unable to parse domain configuration response."]
        )
    }

    private func isDomainConfigurationTimeout(error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut && errorIsDomainConfiguration(error) {
            return true
        }

        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isDomainConfigurationTimeout(error: underlying)
        }

        return false
    }

    private func errorIsDomainConfiguration(_ error: NSError) -> Bool {
        guard let urlString = extractFailingURL(from: error) else {
            return false
        }

        return urlString.contains("/server_domain_infos")
    }

    private func extractFailingURL(from error: NSError) -> String? {
        if let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            return url.absoluteString
        }

        if let urlString = error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
            return urlString
        }

        if let urlString = error.userInfo[NSErrorFailingURLStringKey] as? String {
            return urlString
        }

        if let url = error.userInfo[NSErrorFailingURLKey] as? URL {
            return url.absoluteString
        }

        return nil
    }

    private func accessTokenToJson(_ accessToken: AccessToken) -> [String: Any?] {
        return [
            "applicationId": accessToken.appID,
            /*declinedPermissions: accessToken.declinedPermissions,*/
            "expires": dateToJS(accessToken.expirationDate),
            "lastRefresh": dateToJS(accessToken.refreshDate),
            /*permissions: accessToken.grantedPermissions,*/
            "token": accessToken.tokenString,
            "userId": accessToken.userID
        ]
    }

    @objc func getCurrentAccessToken(_ call: CAPPluginCall) {
        guard let accessToken = AccessToken.current else {
            call.resolve()
            return
        }

        call.resolve([ "accessToken": accessTokenToJson(accessToken) ])
    }

    @objc func getAuthToken(_ call: CAPPluginCall) {
        guard let authenticationToken = AuthenticationToken.current else {
            call.resolve()
            return
        }

        guard let userProfile = Profile.current else {
            call.resolve()
            return
        }

        call.resolve([ "authenticationToken": [
            "token": authenticationToken.tokenString,
            "userId": userProfile.userID,
            "name": userProfile.name,
            "email": userProfile.email,
        ]
        ])
    }


    @objc func getProfile(_ call: CAPPluginCall) {
        guard let accessToken = AccessToken.current else {
            call.reject("You're not logged in. Call FacebookLogin.login() first to obtain an access token.")
            return
        }

        if accessToken.isExpired {
            call.reject("AccessToken is expired.")
            return
        }

        guard let fields = call.getArray("fields", String.self) else {
            call.reject("Missing fields argument")
            return
        }
        let parameters = ["fields": fields.joined(separator: ",")]
        let graphRequest = GraphRequest.init(graphPath: "me", parameters: parameters)

        graphRequest.start { (_ connection, _ result, _ error) in
            if error != nil {
                call.reject("An error has been occured.")
                return
            }

            call.resolve(result as! [String: Any])
        }
    }

    @objc func logEvent(_ call: CAPPluginCall) {
        if let eventName = call.getString("eventName") {
            AppEvents.shared.logEvent(AppEvents.Name(eventName))
        }

        call.resolve()
    }

    @objc func setAutoLogAppEventsEnabled(_ call: CAPPluginCall) {
        if let enabled = call.getBool("enabled") {
            Settings.shared.isAutoLogAppEventsEnabled = enabled
        } else {
            Settings.shared.isAutoLogAppEventsEnabled = false
        }
        call.resolve()
    }

    @objc func setAdvertiserTrackingEnabled(_ call: CAPPluginCall) {
        if let enabled = call.getBool("enabled") {
            Settings.shared.isAdvertiserTrackingEnabled = enabled
        } else {
            Settings.shared.isAdvertiserTrackingEnabled = false
        }
        call.resolve()
    }

    @objc func setAdvertiserIDCollectionEnabled(_ call: CAPPluginCall) {
        if let enabled = call.getBool("enabled") {
            Settings.shared.isAdvertiserIDCollectionEnabled = enabled
        } else {
            Settings.shared.isAdvertiserIDCollectionEnabled = false
        }
        call.resolve()
    }

    @objc func getDeferredDeepLink(_ call: CAPPluginCall) {
        fetchDeferredDeepLink(call: call, attempt: 0)
    }

    private func fetchDeferredDeepLink(call: CAPPluginCall, attempt: Int) {
        AppLinkUtility.fetchDeferredAppLink { url, error in
            if let error = error as NSError? {
                if attempt == 0 && self.isDomainConfigurationTimeout(error: error) {
                    self.refreshDomainConfiguration { refreshError in
                        if let refreshError = refreshError {
                            call.reject("Error retrieving deferred deep link", nil, refreshError)
                        } else {
                            self.fetchDeferredDeepLink(call: call, attempt: attempt + 1)
                        }
                    }
                    return
                }

                call.reject("Error retrieving deferred deep link", nil, error)
                return
            }

            if let url = url {
                call.resolve(["uri": url.absoluteString])
            } else {
                call.reject("No deferred deep link found")
            }
        }
    }
}
