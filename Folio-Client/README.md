# Folio-Client

Android client for Folio. Package name: `com.scatl.folio`.

```powershell
cd Folio-Client
flutter pub get
flutter run
```

登录页填写服务端地址、用户名和密码。会话 Cookie 会保留到退出登录。

结构按 MVVM 划分：页面在各功能目录，状态在 `*_ui_state.dart`，逻辑在 `*_view_model.dart`（Riverpod）。路由使用 go_router（`lib/router`）。
