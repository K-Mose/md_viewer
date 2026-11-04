import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// 콜드 스타트: 파일 앱 등에서 .md를 눌러 앱이 새로 실행된 경우
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts where context.url.isFileURL {
      DocumentsBridge.shared.handleOpenedURL(context.url)
    }
  }

  /// 앱 실행 중: 파일 URL은 직접 처리하고, 그 밖의 URL(딥링크 등)은 Flutter 플러그인으로 넘긴다.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let files = URLContexts.filter { $0.url.isFileURL }
    for context in files {
      DocumentsBridge.shared.handleOpenedURL(context.url)
    }
    let others = URLContexts.subtracting(files)
    if !others.isEmpty {
      super.scene(scene, openURLContexts: others)
    }
  }
}
