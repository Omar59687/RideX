import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    var mapsConfigured = false
    if let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey") as? String {
      let normalizedMapsApiKey = mapsApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
      if !normalizedMapsApiKey.isEmpty && !normalizedMapsApiKey.contains("$(") {
        GMSServices.provideAPIKey(normalizedMapsApiKey)
        mapsConfigured = true
      }
    }
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "ridex/maps_configuration",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "isConfigured" {
          result(mapsConfigured)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
