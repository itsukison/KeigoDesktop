// Dumps what Accessibility exposes for whatever text field currently has focus, and
// attempts the exact write `AXTextIO` performs so you can see whether it lands.
//
// This exists because "insertion doesn't work in app X" is otherwise unfalsifiable
// from the outside: AX can report success and do nothing, and Chromium apps report no
// focused element at all until primed. Run this with focus in the offending field and
// the answer is one line of output.
//
//   swiftc -O scripts/axdiag.swift -o /tmp/axdiag
//   # click into the field you care about, then within 5 seconds:
//   /tmp/axdiag --write
//
// `--write` is destructive: it replaces the field's contents with ZZPROBEZZ. Omit it
// to inspect only. The host terminal needs Accessibility permission.

import AppKit
import ApplicationServices

let shouldWrite = CommandLine.arguments.contains("--write")
let delay = 5.0

func string(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
    else { return nil }
    return value as? String
}

func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
    else { return false }
    return settable.boolValue
}

func focusedElement() -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.5)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        system, kAXFocusedUIElementAttribute as CFString, &value
    ) == .success, let raw = value, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
    return (raw as! AXUIElement)
}

guard AXIsProcessTrusted() else {
    print("✗ no Accessibility permission for this binary's host process")
    exit(1)
}

print("Click into the field you want to inspect. Reading in \(Int(delay))s…")
Thread.sleep(forTimeInterval: delay)

guard let front = NSWorkspace.shared.frontmostApplication else {
    print("✗ no frontmost application"); exit(1)
}
print("frontmost: \(front.localizedName ?? "?") [\(front.bundleIdentifier ?? "?")] pid \(front.processIdentifier)")

let primedBefore = focusedElement() != nil
print("focused element before priming: \(primedBefore ? "present" : "nil")")

// The AXTextIO ordering: prime the frontmost app before the first read.
let app = AXUIElementCreateApplication(front.processIdentifier)
AXUIElementSetMessagingTimeout(app, 0.5)
let primeError = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
print("AXManualAccessibility: \(primeError == .success ? "set" : "err \(primeError.rawValue)")")
Thread.sleep(forTimeInterval: 0.4)

guard let element = focusedElement() else {
    print("focused element after priming: still nil  → capture falls back to the clipboard,")
    print("  which can only serve a manual selection (⌘C with nothing selected copies nothing).")
    exit(1)
}
AXUIElementSetMessagingTimeout(element, 0.5)
if !primedBefore { print("focused element after priming: PRESENT — priming was what made it readable") }

var pid: pid_t = 0
AXUIElementGetPid(element, &pid)
let before = string(element, kAXValueAttribute)

print("""

  element pid:            \(pid)\(pid == front.processIdentifier ? "" : "  (different process than frontmost)")
  role:                   \(string(element, kAXRoleAttribute) ?? "nil")
  subrole:                \(string(element, kAXSubroleAttribute) ?? "nil")
  kAXValue:               \(before.map { "\"\($0.prefix(60))\"" } ?? "NOT READABLE")
  kAXSelectedText:        \(string(element, kAXSelectedTextAttribute).map { "\"\($0)\"" } ?? "nil")
  settable(SelectedText): \(isSettable(element, kAXSelectedTextAttribute))   ← picks the write strategy
  settable(Value):        \(isSettable(element, kAXValueAttribute))
""")

guard shouldWrite else {
    print("\n(pass --write to attempt the AX write and verify it lands)")
    exit(0)
}

let probe = "ZZPROBEZZ"
var all = CFRange(location: 0, length: (before ?? "").utf16.count)
if let rangeValue = AXValueCreate(.cfRange, &all) {
    let err = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
    print("  set SelectedTextRange:  \(err == .success ? "success" : "FAILED(\(err.rawValue))")")
}
let setError = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, probe as CFString)
print("  set SelectedText:       \(setError == .success ? "success" : "FAILED(\(setError.rawValue))")")

let after = string(element, kAXValueAttribute)
print("  kAXValue after:         \(after.map { "\"\($0.prefix(60))\"" } ?? "NOT READABLE")")
// The whole point: a `success` return above proves nothing.
print("\nVERDICT: AX write \(after == probe ? "LANDED — .ax strategy works here" : "DID NOT LAND — must fall back to ⌘V")")
