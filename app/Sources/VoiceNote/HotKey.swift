import Carbon.HIToolbox
import Foundation

/// 전역 단축키 (Carbon RegisterEventHotKey). ⌥⌘R
enum HotKey {
    nonisolated(unsafe) static var action: (() -> Void)?
    nonisolated(unsafe) private static var ref: EventHotKeyRef?
    nonisolated(unsafe) private static var handlerRef: EventHandlerRef?

    @discardableResult
    static func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x564E4F54), id: 1) // 'VNOT'
        let st = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        return st == noErr
    }
}
