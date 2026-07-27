import CoreGraphics
import Foundation

@main
private enum ScreenCapturePermissionCheck {
    static func main() {
        if CGPreflightScreenCaptureAccess() {
            print("PASS: screen capture permission is granted")
        } else {
            fputs("FAIL: screen capture permission is not granted\n", stderr)
            Foundation.exit(1)
        }
    }
}
