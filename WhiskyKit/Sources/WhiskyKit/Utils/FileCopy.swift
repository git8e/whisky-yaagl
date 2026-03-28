//
//  FileCopy.swift
//  WhiskyKit
//

import Foundation
import Darwin

public enum FileCopy {
    private static var fm: FileManager { FileManager.default }

    /// Copy a file or directory, preferring APFS copy-on-write cloning when available.
    /// Falls back to a normal copy when cloning is unsupported.
    public static func copyItem(
        at src: URL,
        to dst: URL,
        replacing: Bool = false
    ) throws {
        let srcPath = src.path(percentEncoded: false)
        let dstPath = dst.path(percentEncoded: false)

        // Ensure parent exists.
        let parent = dst.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path(percentEncoded: false)) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        if replacing, fm.fileExists(atPath: dstPath) {
            try? fm.removeItem(at: dst)
        }

        // copyfile() supports recursive directory copies and can request CoW clones.
        let baseFlags: copyfile_flags_t = copyfile_flags_t(COPYFILE_ALL) | copyfile_flags_t(COPYFILE_RECURSIVE)
        let cloneFlags: copyfile_flags_t = baseFlags | copyfile_flags_t(COPYFILE_CLONE)

        if copyfile(srcPath, dstPath, nil, cloneFlags) == 0 {
            return
        }

        let err = errno

        // Retry without clone on filesystems / cross-volume copies that don't support it.
        if err == ENOTSUP || err == EOPNOTSUPP || err == EXDEV || err == EINVAL {
            if copyfile(srcPath, dstPath, nil, baseFlags) == 0 {
                return
            }
        }

        // Final fallback: FileManager copy.
        try fm.copyItem(at: src, to: dst)
    }
}
