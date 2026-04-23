import Foundation
import CoreGraphics
import IOKit

/// Brightness I/O for built-in and external displays.
///
/// Built-in: `DisplayServices.framework` (private, dlopen'd).
/// External: DDC/CI over I²C via `IOAVService` (Apple Silicon + Intel).
enum DisplayBrightness {

    // MARK: - Built-in (DisplayServices)

    private static let displayServices: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
    )

    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32

    private static let setBuiltIn: SetFn? = {
        guard let handle = displayServices,
              let sym = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: SetFn.self)
    }()

    private static let getBuiltIn: GetFn? = {
        guard let handle = displayServices,
              let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: GetFn.self)
    }()

    static func builtInBrightness(for id: CGDirectDisplayID) -> Double? {
        guard let fn = getBuiltIn else { return nil }
        var v: Float = 0
        let r = fn(id, &v)
        return r == 0 ? Double(v) : nil
    }

    @discardableResult
    static func setBuiltInBrightness(_ value: Double, for id: CGDirectDisplayID) -> Bool {
        guard let fn = setBuiltIn else { return false }
        return fn(id, Float(value)) == 0
    }

    // MARK: - External (DDC/CI via IOAVService)

    static func setExternalBrightness(_ value: Double, for id: CGDirectDisplayID) -> Bool {
        guard let service = DDCService(displayID: id) else { return false }
        let brightness = UInt8(max(0, min(100, value * 100)))
        return service.writeVCP(code: 0x10, value: UInt16(brightness))
    }
}

// MARK: - IOAVService bridge

private typealias IOAVService = UnsafeMutableRawPointer

@_silgen_name("IOAVServiceCreateWithService")
private func _IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> IOAVService?

@_silgen_name("IOAVServiceWriteI2C")
private func _IOAVServiceWriteI2C(
    _ service: IOAVService,
    _ chipAddress: UInt32,
    _ offset: UInt32,
    _ inputBuffer: UnsafeRawPointer,
    _ inputBufferSize: UInt32
) -> Int32

@_silgen_name("IOAVServiceReadI2C")
private func _IOAVServiceReadI2C(
    _ service: IOAVService,
    _ chipAddress: UInt32,
    _ offset: UInt32,
    _ outputBuffer: UnsafeMutableRawPointer,
    _ outputBufferSize: UInt32
) -> Int32

/// Minimal DDC/CI helper bound to a specific display via IOAVService.
///
/// Compatible with Apple Silicon (preferred path) and Intel.
final class DDCService {
    private let avService: IOAVService

    init?(displayID: CGDirectDisplayID) {
        guard let avService = DDCService.matchAVService(for: displayID) else { return nil }
        self.avService = avService
    }

    /// Write a VCP code. Brightness = 0x10, value in 0...100.
    func writeVCP(code: UInt8, value: UInt16) -> Bool {
        let hi = UInt8((value >> 8) & 0xFF)
        let lo = UInt8(value & 0xFF)
        // DDC/CI Set VCP feature: [len|0x80, opcode=0x03, VCP, hi, lo, checksum]
        // Checksum: XOR of dest(0x6E) ^ source(0x51) ^ each body byte.
        var msg: [UInt8] = [0x84, 0x03, code, hi, lo]
        var checksum: UInt8 = 0x6E ^ 0x51
        for byte in msg { checksum ^= byte }
        msg.append(checksum)

        return msg.withUnsafeBufferPointer { buf -> Bool in
            guard let base = buf.baseAddress else { return false }
            let result = _IOAVServiceWriteI2C(avService, 0x37, 0x51, base, UInt32(buf.count))
            return result == 0
        }
    }

    // MARK: - Matching

    /// Walks IOReg to find the IOAVService node bound to a given display ID.
    /// Compares `DisplayAttributes` -> `ProductAttributes` -> `ManufacturerID / ProductID`
    /// against the display's EDID info.
    private static func matchAVService(for displayID: CGDirectDisplayID) -> IOAVService? {
        let vendor = CGDisplayVendorNumber(displayID)
        let product = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)

        var iterator: io_iterator_t = 0
        let matchDict = IOServiceMatching("DCPAVServiceProxy")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            // Traverse up to find display attributes.
            if let found = aligns(service: service, vendor: vendor, product: product, serial: serial) {
                return _IOAVServiceCreateWithService(kCFAllocatorDefault, found)
            }
            IOObjectRelease(service)
        }
        return nil
    }

    private static func aligns(
        service: io_service_t,
        vendor: UInt32,
        product: UInt32,
        serial: UInt32
    ) -> io_service_t? {
        guard let attrs = IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            "DisplayAttributes" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        ) as? [String: Any] else { return nil }

        guard let productAttrs = attrs["ProductAttributes"] as? [String: Any] else { return nil }

        let svcVendor = (productAttrs["ManufacturerID"] as? UInt32)
            ?? (productAttrs["LegacyManufacturerID"] as? UInt32)
            ?? 0
        let svcProduct = (productAttrs["ProductID"] as? UInt32) ?? 0
        let svcSerial = (productAttrs["SerialNumber"] as? UInt32) ?? 0

        if svcVendor == vendor && svcProduct == product && (serial == 0 || svcSerial == serial) {
            return service
        }
        return nil
    }
}
