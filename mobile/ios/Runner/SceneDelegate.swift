import Flutter
import UIKit
import app_links

class SceneDelegate: FlutterSceneDelegate {

  // Called on cold start — forward any launch URL / Universal Link to app_links
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Forward custom URL schemes that opened the app from cold start
    if !connectionOptions.urlContexts.isEmpty {
      self.scene(scene, openURLContexts: connectionOptions.urlContexts)
    }

    // Forward Universal Links that opened the app from cold start
    for userActivity in connectionOptions.userActivities {
      self.scene(scene, continue: userActivity)
    }

    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  // Called when a custom URL scheme opens the app while it is running
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      AppLinks.shared.handleLink(url: context.url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }

  // Called when a Universal Link continues the app while it is running
  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if let url = userActivity.webpageURL {
      AppLinks.shared.handleLink(url: url)
    }
    super.scene(scene, continue: userActivity)
  }
}
