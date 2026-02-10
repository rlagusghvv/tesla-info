import Foundation

enum TeslaConstants {
    static let authorizeURL = URL(string: "https://auth.tesla.com/oauth2/v3/authorize")!
    static let tokenURL = URL(string: "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token")!

    static let defaultFleetApiBase = "https://fleet-api.prd.na.vn.cloud.tesla.com"
    static let defaultAudience = "https://fleet-api.prd.na.vn.cloud.tesla.com"
    static let defaultRedirectURI = "https://www.splui.com/oauth/callback"

    static let scopes = "openid offline_access vehicle_device_data vehicle_cmds vehicle_charging_cmds"
}

