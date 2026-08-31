import AppKit
import Foundation
import IOKit
import IOKit.hid
import IOKit.ps
import IOKit.pwr_mgt
import Darwin
import SwiftUI

let systemDefinedCGEventType = CGEventType(rawValue: 14) ?? .null
let monitorVolumeUpKeyCode: Int = 0
let monitorVolumeDownKeyCode: Int = 1
let monitorVolumeMuteKeyCode: Int = 7

enum MonitorVolumeKeyAction {
    case increase
    case decrease
    case mute
}

final class MonitorVolumeKeyRouter {
    private weak var app: DisplayCoordinator?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var enabled = false

    init(app: DisplayCoordinator) {
        self.app = app
    }

    deinit {
        stop()
    }

    func start() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(1 << systemDefinedCGEventType.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }
            let router = Unmanaged<MonitorVolumeKeyRouter>.fromOpaque(refcon).takeUnretainedValue()
            return router.handle(event: event, type: type)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        guard type == systemDefinedCGEventType, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        guard enabled else {
            return Unmanaged.passUnretained(event)
        }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyState = (data1 & 0x0000FF00) >> 8
        guard keyState == 0x0A else {
            return nil
        }

        switch keyCode {
        case monitorVolumeUpKeyCode:
            route(.increase)
        case monitorVolumeDownKeyCode:
            route(.decrease)
        case monitorVolumeMuteKeyCode:
            route(.mute)
        default:
            return Unmanaged.passUnretained(event)
        }
        return nil
    }

    private func route(_ action: MonitorVolumeKeyAction) {
        let app = self.app
        Task { @MainActor [app] in
            guard let app else { return }
            let success = app.performMonitorVolumeKeyAction(action)
            app.showVolumeRoutedBanner(message: success ? "Volume routed to monitor" : "Volume route failed")
        }
    }
}
