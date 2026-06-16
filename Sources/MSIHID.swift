import Foundation
import IOKit.hid

struct MSIHIDStatus {
    let connected: Bool
    let values: [String: String]
}

enum MSIHID {
    static let modeRegister = "002E0"
    static let confirmationRegister = "00190"

    static func readStatus() -> MSIHIDStatus {
        guard let session = HIDSession() else {
            return MSIHIDStatus(connected: false, values: [:])
        }

        return MSIHIDStatus(
            connected: true,
            values: [
                modeRegister: session.send("58002E0", waitSeconds: 0.25) ?? "NO_RESPONSE",
                confirmationRegister: session.send("5800190", waitSeconds: 0.25) ?? "NO_RESPONSE"
            ]
        )
    }

    static func setModeValue(_ value: String) -> Bool {
        guard value == "000" || value == "001", let session = HIDSession() else {
            return false
        }

        _ = session.send("5b002E0\(value)", waitSeconds: 0.35)
        return true
    }
}

private final class HIDReportSink {
    var reports: [[UInt8]] = []
}

private final class HIDSession {
    private let reportID: CFIndex = 0x01
    private let reportLength = 64
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let sink = HIDReportSink()
    private let buffer: UnsafeMutablePointer<UInt8>

    init?() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey as String: 0x1462,
            kIOHIDProductIDKey as String: 0x3fa4
        ] as CFDictionary)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return nil
        }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let firstDevice = devices.first else {
            return nil
        }
        guard IOHIDDeviceOpen(firstDevice, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return nil
        }

        device = firstDevice
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportLength)
        buffer.initialize(repeating: 0, count: reportLength)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(sink).toOpaque())
        IOHIDDeviceRegisterInputReportCallback(device, buffer, reportLength, { context, _, _, _, _, report, length in
            guard let context else { return }
            let sink = Unmanaged<HIDReportSink>.fromOpaque(context).takeUnretainedValue()
            sink.reports.append(Array(UnsafeBufferPointer(start: report, count: length)))
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deinitialize(count: reportLength)
        buffer.deallocate()
    }

    func send(_ asciiCommand: String, waitSeconds: Double) -> String? {
        sink.reports.removeAll()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.03, false)
        sink.reports.removeAll()

        var output = [UInt8](repeating: 0, count: reportLength)
        output[0] = UInt8(reportID)
        let commandBytes = Array((asciiCommand + "\r").utf8)
        for (index, byte) in commandBytes.enumerated() where index + 1 < output.count {
            output[index + 1] = byte
        }

        let result = output.withUnsafeBytes {
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                reportID,
                $0.bindMemory(to: UInt8.self).baseAddress!,
                reportLength
            )
        }
        guard result == kIOReturnSuccess else {
            return nil
        }

        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, waitSeconds, false)
        guard let report = sink.reports.first, let terminator = report.firstIndex(of: 0x0d), terminator > 1 else {
            return nil
        }

        return String(bytes: report[1..<terminator], encoding: .utf8)
    }
}
