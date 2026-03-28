//
//  HKRPGTweaks.swift
//  WhiskyKit
//

import Foundation

public enum HKRPGTweaks {
    // Mirrors YAAGL's setNVExtension (HKRPG uses it when DXMT is enabled).
    public static func applyNVExtension(bottle: Bottle) async throws {
        let guid = "{41FCC608-8496-4DEF-B43E-7D9BD675A6FF}"
        try await WineRegistry.addBinary(
            bottle: bottle,
            key: #"HKEY_LOCAL_MACHINE\SOFTWARE\NVIDIA Corporation\Global"#,
            name: guid,
            hex: "1"
        )
        try await WineRegistry.addBinary(
            bottle: bottle,
            key: #"HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\nvlddmkm"#,
            name: guid,
            hex: "1"
        )
        try await WineRegistry.addString(
            bottle: bottle,
            key: #"HKEY_LOCAL_MACHINE\SOFTWARE\NVIDIA Corporation\Global\NGXCore"#,
            name: "FullPath",
            value: "C:\\Windows\\System32"
        )
    }

    public static func revertNVExtension(bottle: Bottle) async {
        let guid = "{41FCC608-8496-4DEF-B43E-7D9BD675A6FF}"
        try? await WineRegistry.deleteValue(
            bottle: bottle,
            key: #"HKEY_LOCAL_MACHINE\SOFTWARE\NVIDIA Corporation\Global"#,
            name: guid
        )
        try? await WineRegistry.deleteValue(
            bottle: bottle,
            key: #"HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Services\nvlddmkm"#,
            name: guid
        )
        try? await WineRegistry.deleteValue(
            bottle: bottle,
            key: #"HKEY_LOCAL_MACHINE\SOFTWARE\NVIDIA Corporation\Global\NGXCore"#,
            name: "FullPath"
        )
    }
}
