//
//  PortableExecutable.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation
import AppKit

public struct PEError: Error {
    public let message: String

    static let invalidPEFile = PEError(message: "Invalid PE file")
}

public enum Architecture: Hashable {
    case x32
    case x64
    case unknown

    public func toString() -> String? {
        switch self {
        case .x32:
            return "32-bit"
        case .x64:
            return "64-bit"
        default:
            return nil
        }
    }
}

/// Microsoft Portable Executable
///
/// https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
public struct PEFile: Hashable, Equatable, Sendable {
    /// URL to the file
    public let url: URL
    /// COFF File Header (Object and Image)
    public let coffFileHeader: COFFFileHeader
    /// The Optional Header
    public let optionalHeader: OptionalHeader?
    /// The Section Table (Section Headers)
    public let sections: [Section]

    public init?(url: URL?) throws {
        guard let url else { return nil }
        try self.init(url: url)
    }

    public init(url: URL) throws {
        self.url = url
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer {
            try? fileHandle.close()
        }

        // (0x3C) Pointer to PE Header
        guard let peOffset = fileHandle.extract(UInt32.self, offset: 0x3C) else {
            throw PEError.invalidPEFile
        }
        var offset = UInt64(peOffset)
        guard let peHeader = fileHandle.extract(UInt32.self, offset: offset) else {
            throw PEError.invalidPEFile
        }
        // Check signature ("PE\0\0")
        guard peHeader.bigEndian == 0x50450000 else {
            throw PEError.invalidPEFile
        }

        let coffFileHeader = COFFFileHeader(handle: fileHandle, offset: offset)
        offset += 24 // Size of COFFHeader
        self.coffFileHeader = coffFileHeader

        if coffFileHeader.sizeOfOptionalHeader > 0 {
            self.optionalHeader = OptionalHeader(handle: fileHandle, offset: offset)
            offset += UInt64(coffFileHeader.sizeOfOptionalHeader)
        } else {
            self.optionalHeader = nil
        }

        var sections: [Section] = []
        for _ in 0..<coffFileHeader.numberOfSections {
            if let section = Section(handle: fileHandle, offset: offset) {
                sections.append(section)
            }
            offset += 40 // Size of Section
        }
        self.sections = sections
    }

    /// The ``Architecture`` of the executable
    public var architecture: Architecture {
        switch optionalHeader?.magic {
        case .pe32:
            return .x32
        case .pe32Plus:
            return .x64
        default:
            return .unknown
        }
    }

    /// Read the resource section
    /// 
    /// - Parameters:
    ///   - handle: The `FileHandle` to read the resource table section from.
    ///   - types: Only read entrys of the given types. Only applies to the root table. Default includes all types.
    /// - Returns: The resource table section
    private func rsrc(handle: FileHandle, types: [ResourceType] = ResourceType.allCases) -> ResourceDirectoryTable? {
        if let resourceSection = sections.first(where: { $0.name == ".rsrc" }) {
            return ResourceDirectoryTable(
                handle: handle,
                pointerToRawData: UInt64(resourceSection.pointerToRawData),
                types: types
            )
        } else {
            return nil
        }
    }

    /// The Resource Directory Table
    public var rsrc: ResourceDirectoryTable? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        return rsrc(handle: handle)
    }

    private struct IconResource {
        let data: Data
        let width: Int
        let height: Int
        let bitCount: UInt16
    }

    /// The best icon for this executable
    /// - Returns: An `NSImage` if there is a renderable icon in the resource directory table
    ///
    /// Windows executable icons are `RT_ICON` resources. Rather than rendering
    /// the different DIB layouts ourselves, assemble the resources into an ICO
    /// file and let ImageIO decode it. This also handles indexed, 16-bit, PNG
    /// and 32-bit icons, which all appear in real Windows programs.
    public func bestIcon() -> NSImage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        guard let rsrc = rsrc(handle: handle, types: [.icon]) else { return nil }
        let icons = rsrc.allEntries.compactMap { entry -> IconResource? in
            guard let offset = entry.resolveRVA(sections: sections),
                  entry.size > 0,
                  entry.size < 16 * 1024 * 1024 else {
                return nil
            }
            guard (try? handle.seek(toOffset: UInt64(offset))) != nil,
                  let data = try? handle.read(upToCount: Int(entry.size)),
                  let icon = iconResource(from: data) else {
                return nil
            }
            return icon
        }
        guard !icons.isEmpty else { return nil }

        if let image = icoImage(from: icons) {
            return image
        }

        // A malformed member should not hide the other sizes.
        for icon in icons {
            if let image = icoImage(from: [icon]) {
                return image
            }
        }
        return nil
    }

    private func iconResource(from data: Data) -> IconResource? {
        guard data.count >= 24 else { return nil }

        // Vista and later store large icons as a PNG stream inside RT_ICON.
        if data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47,
           data[12] == 0x49, data[13] == 0x48, data[14] == 0x44, data[15] == 0x52 {
            let width = Int(readUInt32BE(data, offset: 16))
            let height = Int(readUInt32BE(data, offset: 20))
            guard width > 0, height > 0 else { return nil }
            return IconResource(data: data, width: width, height: height, bitCount: 32)
        }

        guard data.count >= 40 else { return nil }
        let headerSize = readUInt32LE(data, offset: 0)
        guard headerSize >= 40, Int(headerSize) <= data.count else { return nil }

        let width = Int(abs(Int32(bitPattern: readUInt32LE(data, offset: 4))))
        let doubledHeight = Int(abs(Int32(bitPattern: readUInt32LE(data, offset: 8))))
        let bitCount = readUInt16LE(data, offset: 14)
        let height = doubledHeight / 2
        guard width > 0, height > 0, width <= 4096, height <= 4096 else { return nil }
        return IconResource(data: data, width: width, height: height, bitCount: bitCount)
    }

    private func icoImage(from icons: [IconResource]) -> NSImage? {
        guard !icons.isEmpty, icons.count <= Int(UInt16.max) else { return nil }
        let sorted = icons.sorted {
            if $0.width * $0.height != $1.width * $1.height {
                return $0.width * $0.height > $1.width * $1.height
            }
            return $0.bitCount > $1.bitCount
        }

        var ico = Data([0x00, 0x00, 0x01, 0x00])
        appendUInt16LE(UInt16(sorted.count), to: &ico)
        var imageOffset = 6 + 16 * sorted.count
        for icon in sorted {
            ico.append(UInt8(icon.width >= 256 ? 0 : icon.width))
            ico.append(UInt8(icon.height >= 256 ? 0 : icon.height))
            ico.append(0) // color count (0 = 256 or more)
            ico.append(0) // reserved
            appendUInt16LE(1, to: &ico) // color planes
            appendUInt16LE(icon.bitCount, to: &ico)
            appendUInt32LE(UInt32(icon.data.count), to: &ico)
            appendUInt32LE(UInt32(imageOffset), to: &ico)
            imageOffset += icon.data.count
        }
        for icon in sorted {
            ico.append(icon.data)
        }

        guard ico.count <= 64 * 1024 * 1024,
              let image = NSImage(data: ico),
              image.isValid,
              !image.representations.isEmpty else {
            return nil
        }
        return image
    }

    private func readUInt16LE(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func readUInt32BE(_ data: Data, offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    private func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}
