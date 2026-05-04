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
        guard let service = DDCService.shared(for: id) else { return false }
        let brightness = UInt8(max(0, min(100, value * 100)))
        return service.writeVCP(code: 0x10, value: UInt16(brightness))
    }

    static func invalidateDDCCache(for id: CGDirectDisplayID? = nil) {
        DDCService.invalidate(id: id)
    }
}

// MARK: - Private framework bridges

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

private typealias DisplayCreateInfoDictFn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?

private let _coreDisplayHandle: UnsafeMutableRawPointer? = dlopen(
    "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
    RTLD_LAZY
)

private let _CoreDisplay_DisplayCreateInfoDictionary: DisplayCreateInfoDictFn? = {
    guard let handle = _coreDisplayHandle,
          let sym = dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") else { return nil }
    return unsafeBitCast(sym, to: DisplayCreateInfoDictFn.self)
}()

/// DDC/CI over `IOAVService`, mirroring the m1ddc matching algorithm.
///
/// Compatible with Apple Silicon and Intel. Display is matched by IORegistry
/// path (via `CoreDisplay_DisplayCreateInfoDictionary` → `IODisplayLocation`)
/// rather than EDID vendor/product comparison, which proved unreliable in
/// practice on macOS Sonoma+.
final class DDCService {
    private let avService: IOAVService

    private static let cacheLock = NSLock()
    private static var cache: [CGDirectDisplayID: DDCService] = [:]

    init?(displayID: CGDirectDisplayID) {
        guard let avService = DDCService.matchAVService(for: displayID) else { return nil }
        self.avService = avService
    }

    static func shared(for displayID: CGDirectDisplayID) -> DDCService? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[displayID] { return cached }
        guard let svc = DDCService(displayID: displayID) else { return nil }
        cache[displayID] = svc
        return svc
    }

    static func invalidate(id: CGDirectDisplayID?) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let id { cache.removeValue(forKey: id) } else { cache.removeAll() }
    }

    /// Write a VCP code. Brightness = 0x10, value in 0...100.
    ///
    /// Mirrors m1ddc's `performDDCWrite`: 10 ms warm-up, then send the same
    /// packet twice in a row. Many monitors silently drop the first packet
    /// when the I²C channel is idle, so a single write looks like "the slider
    /// does nothing." Ignore the per-iteration result — even a failed write
    /// often unblocks the channel for the next attempt.
    @discardableResult
    func writeVCP(code: UInt8, value: UInt16) -> Bool {
        let hi = UInt8((value >> 8) & 0xFF)
        let lo = UInt8(value & 0xFF)
        // DDC/CI Set VCP feature: [len|0x80, opcode=0x03, VCP, hi, lo, checksum]
        // Checksum: dest(0x6E) ^ source(0x51) ^ each body byte.
        var msg: [UInt8] = [0x84, 0x03, code, hi, lo]
        var checksum: UInt8 = 0x6E ^ 0x51
        for byte in msg { checksum ^= byte }
        msg.append(checksum)

        var anySuccess = false
        for _ in 0..<2 {
            Thread.sleep(forTimeInterval: 0.010)
            let ok = msg.withUnsafeBufferPointer { buf -> Bool in
                guard let base = buf.baseAddress else { return false }
                return _IOAVServiceWriteI2C(avService, 0x37, 0x51, base, UInt32(buf.count)) == 0
            }
            anySuccess = anySuccess || ok
        }
        return anySuccess
    }

    // MARK: - Matching

    /// Resolves the `IOAVService` bound to a given display, mirroring m1ddc:
    /// walk the IORegistry from the root, find the entry matching the display's
    /// `IODisplayLocation`, then keep iterating the same recursive iterator
    /// until the next `DCPAVServiceProxy` whose `Location` is "External".
    ///
    /// This relies on depth-first traversal order — on Apple Silicon the AV
    /// service node is a sibling/descendant of the display adapter under the
    /// shared DCP container, not under the display itself.
    private static func matchAVService(for displayID: CGDirectDisplayID) -> IOAVService? {
        guard let createInfo = _CoreDisplay_DisplayCreateInfoDictionary,
              let infoUnmanaged = createInfo(displayID) else { return nil }
        let info = infoUnmanaged.takeRetainedValue() as NSDictionary
        guard let displayLocation = info["IODisplayLocation"] as? String else { return nil }

        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            root,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var foundDisplay = false
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            if !foundDisplay {
                let path = (IORegistryEntryCopyPath(entry, kIOServicePlane)?.takeRetainedValue()) as String?
                if path == displayLocation {
                    foundDisplay = true
                }
                IOObjectRelease(entry)
                continue
            }

            let className = (IOObjectCopyClass(entry)?.takeRetainedValue()) as String? ?? ""
            if className == "DCPAVServiceProxy" {
                let location = IORegistryEntrySearchCFProperty(
                    entry,
                    kIOServicePlane,
                    "Location" as CFString,
                    kCFAllocatorDefault,
                    IOOptionBits(kIORegistryIterateRecursively)
                ) as? String

                if location == "External",
                   let av = _IOAVServiceCreateWithService(kCFAllocatorDefault, entry) {
                    IOObjectRelease(entry)
                    return av
                }
            }
            IOObjectRelease(entry)
        }
        return nil
    }
}
