import AppKit
import os.log

private let spaceLog = Logger(subsystem: "com.local.cachetracker", category: "SpaceBridge")

/// Thin, isolated wrapper over the private CoreGraphics/SkyLight "CGS" Space
/// APIs.
///
/// WHY THIS EXISTS
/// ---------------
/// With "Displays have separate Spaces" on, a display that sleeps/wakes or is
/// reconfigured can end up backed by a *new* managed Space. A window that was
/// created earlier is only ever associated with the Spaces that existed when it
/// was registered with the WindowServer — `.canJoinAllSpaces` is applied at
/// registration time, not continuously, which is the long-standing "window
/// doesn't appear on Spaces created after app launch" behavior. That leaves the
/// window `isVisible == true` but `isOnActiveSpace == false`, forever, and
/// nothing at the NSWindow level (reassigning collectionBehavior, reordering)
/// nor recreating the NSStatusItem repairs it — only relaunching the process, or
/// some genuine activation on the currently-active Space, does.
///
/// These calls ask the WindowServer directly to move our window onto the Space
/// that is *currently* active on a given display, which is the same mechanism
/// yabai / AltTab / Ice reach for (`CGSMainConnectionID`, `CGSGetActiveSpace`,
/// `CGSManagedDisplayGetCurrentSpace`, `CGSMoveWindowsToManagedSpace`).
///
/// RISK: these are undocumented private APIs. They are resolved lazily via
/// `dlsym` rather than linked, so if Apple renames or removes any of them the
/// app keeps working — every entry point below degrades to a logged no-op
/// instead of failing to launch or crashing.
enum SpaceBridge {
    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias GetActiveSpaceFn = @convention(c) (Int32) -> size_t
    private typealias DisplayCurrentSpaceFn = @convention(c) (Int32, CFString) -> size_t
    private typealias MoveWindowsFn = @convention(c) (Int32, CFArray, size_t) -> Void

    private static let handle: UnsafeMutableRawPointer? = {
        // CoreGraphics re-exports most CGS symbols, but SkyLight is where they
        // actually live on modern macOS. Try the already-loaded image first.
        if dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSMainConnectionID") != nil {
            return UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        }
        return dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    }()

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else {
            spaceLog.notice("SpaceBridge: symbol \(name) unavailable")
            return nil
        }
        return unsafeBitCast(sym, to: T.self)
    }

    private static let mainConnectionID = symbol("CGSMainConnectionID", as: MainConnectionIDFn.self)
    private static let getActiveSpace = symbol("CGSGetActiveSpace", as: GetActiveSpaceFn.self)
    private static let displayCurrentSpace = symbol("CGSManagedDisplayGetCurrentSpace", as: DisplayCurrentSpaceFn.self)
    private static let moveWindows = symbol("CGSMoveWindowsToManagedSpace", as: MoveWindowsFn.self)

    static var isAvailable: Bool {
        mainConnectionID != nil && moveWindows != nil
    }

    /// The Space currently displayed on `screen`. With separate Spaces per
    /// display the "active" Space is per-display, so prefer the display-scoped
    /// query and only fall back to the global one.
    private static func currentSpaceID(for screen: NSScreen?) -> size_t? {
        guard let cid = mainConnectionID?() else { return nil }
        if let displayCurrentSpace, let uuid = displayUUIDString(for: screen) {
            let sid = displayCurrentSpace(cid, uuid as CFString)
            if sid != 0 { return sid }
        }
        guard let getActiveSpace else { return nil }
        let sid = getActiveSpace(cid)
        return sid == 0 ? nil : sid
    }

    private static func displayUUIDString(for screen: NSScreen?) -> String? {
        guard
            let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// Forces `window` onto the Space currently active on `screen`.
    /// Returns true if the move was actually issued.
    @discardableResult
    static func moveToActiveSpace(window: NSWindow, screen: NSScreen?) -> Bool {
        guard let cid = mainConnectionID?(), let moveWindows else {
            spaceLog.notice("moveToActiveSpace: CGS symbols unavailable, skipping")
            return false
        }
        guard let sid = currentSpaceID(for: screen) else {
            spaceLog.notice("moveToActiveSpace: could not resolve current space id")
            return false
        }
        let windowID = CGWindowID(window.windowNumber)
        guard windowID != 0 else {
            spaceLog.notice("moveToActiveSpace: window has no window number yet")
            return false
        }
        moveWindows(cid, [NSNumber(value: windowID)] as CFArray, sid)
        spaceLog.notice("moveToActiveSpace: moved windowID=\(windowID) to spaceID=\(sid) screen=\(screen?.frame.debugDescription ?? "nil") isOnActiveSpaceAfter=\(window.isOnActiveSpace)")
        return true
    }
}
