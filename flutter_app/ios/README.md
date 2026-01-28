# iOS / Xcode setup

This Flutter project currently ships with Android-only build configuration.
To open and run it in Xcode, generate the iOS platform files with the Flutter
SDK and then open the workspace in Xcode:

```bash
flutter create --platforms=ios .
open ios/Runner.xcworkspace
```

## Required iOS changes
- Add location usage strings to `ios/Runner/Info.plist`:
  - `NSLocationWhenInUseUsageDescription`
- Build and link the Microsoft SEAL library for iOS (arm64) and add it to the
  Runner target, then update the FFI dynamic library loading as needed.
