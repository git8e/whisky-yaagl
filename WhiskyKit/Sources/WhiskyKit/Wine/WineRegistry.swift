//
//  WineRegistry.swift
//  WhiskyKit
//

import Foundation

public enum WineRegistry {
    private static func quietEnv() -> [String: String] {
        ["WINEDEBUG": "-all"]
    }

    public static func addString(bottle: Bottle, key: String, name: String, value: String) async throws {
        _ = try await Wine.runWine(
            ["reg", "add", key, "-v", name, "-t", "REG_SZ", "-d", value, "-f"],
            bottle: bottle,
            environment: quietEnv()
        )
    }

    public static func addDword(bottle: Bottle, key: String, name: String, value: Int) async throws {
        _ = try await Wine.runWine(
            ["reg", "add", key, "-v", name, "-t", "REG_DWORD", "-d", String(value), "-f"],
            bottle: bottle,
            environment: quietEnv()
        )
    }

    public static func addBinary(bottle: Bottle, key: String, name: String, hex: String) async throws {
        _ = try await Wine.runWine(
            ["reg", "add", key, "-v", name, "-t", "REG_BINARY", "-d", hex, "-f"],
            bottle: bottle,
            environment: quietEnv()
        )
    }

    public static func deleteValue(bottle: Bottle, key: String, name: String) async throws {
        _ = try await Wine.runWine(
            ["reg", "delete", key, "-v", name, "-f"],
            bottle: bottle,
            environment: quietEnv()
        )
    }
}
