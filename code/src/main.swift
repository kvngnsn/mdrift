import Cocoa

#if NATIVE_TESTS
    NativeVerification.run()
#else
    let app = NSApplication.shared
    let delegate = MdriftApp()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
#endif
