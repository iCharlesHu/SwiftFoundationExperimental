//
//  Subprocess.swift
//
//
//  Created by Charles Hu
//

import System
import Darwin
internal import _CShims

public typealias ProcessIdentifier = pid_t

public struct Subprocess {
    public let executablePath: String
    public let arguments: [String]
    public let environments: [String : String]

    public let standardInput: FileDescriptor?
    public let standardOutput: FileDescriptor?
    public let standardError: FileDescriptor?
    // We don't support launching these processes
    internal let blacklist: Set<String> = ["/usr/bin/swift", "/bin/sh", "/bin/zsh"]

    public init(
        executablePath: String,
        arguments: [String],
        environments: [String : String],
        standardInput: FileDescriptor? = nil,
        standardOutput: FileDescriptor? = nil,
        standardError: FileDescriptor? = nil) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environments = environments
        self.standardInput = standardInput
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

#if os(macOS)
    public func run() throws -> ProcessIdentifier {
        // Sanity check: executablePath can't be empty
        guard !executablePath.isEmpty else {
            throw SubprocessError.invalidExecutablePath
        }
        if self.blacklist.contains(executablePath) {
            throw SubprocessError.processNotSupported
        }
        // Prepare the environment
        // Inheirt the environent value from the master process
        var environmentValues = ProcessInfo.processInfo.environment
        for (key, value) in self.environments {
            environmentValues[key] = value
        }
        let env = environmentValues.map { (key, value) in
            return strdup("\(key)=\(value)")
        }
        // Prepare the environment
        var args: [UnsafeMutablePointer<CChar>?] = [
            strdup(self.executablePath)
        ]
        for arg in self.arguments {
            args.append(strdup(arg))
        }
        // Setup file actions
        var fileActions: posix_spawn_file_actions_t? = nil
        // Create file actions
        posix_spawn_file_actions_init(&fileActions)
        defer {
            // Destroy file actions
            posix_spawn_file_actions_destroy(&fileActions)
        }
        // Setup standard input
        if let inputFd = self.standardInput {
            posix_spawn_file_actions_adddup2(&fileActions, inputFd.rawValue, 0)
        }
        // Setup standard output
        if let outputFd = self.standardOutput {
            posix_spawn_file_actions_adddup2(&fileActions, outputFd.rawValue, 1)
        }
        // Setup standard error
        if let errorFd = self.standardError {
            posix_spawn_file_actions_adddup2(&fileActions, errorFd.rawValue, 2)
        }
        // Setup spawn attributes
        var spawnAttributes: posix_spawnattr_t? = nil
        defer {
            posix_spawnattr_destroy(&spawnAttributes)
        }
        var noSignals = sigset_t()
        var allSignals = sigset_t()
        sigemptyset(&noSignals)
        sigfillset(&allSignals)
        posix_spawnattr_setsigmask(&spawnAttributes, &noSignals)
        posix_spawnattr_setsigdefault(&spawnAttributes, &allSignals)
        let flags: Int32 = POSIX_SPAWN_CLOEXEC_DEFAULT |
            POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
        posix_spawnattr_setflags(&spawnAttributes, Int16(flags))
        // Spawn
        var pid: pid_t = 0
        executablePath.withCString { exePath in
            _subprocess_spawn(
                &pid, exePath,
                &fileActions, &spawnAttributes,
                args, env)
        }

        return pid
    }
#endif
}

public enum SubprocessError: Error {
    case invalidExecutablePath
    case processNotSupported
}

//extension Subprocess {
//    public func resolvedEnvironmentValues() -> [String : String] {
//        // Prepare the environment
//        // Inheirt the environent value from the master process
//        var environmentValues = ProcessInfo.processInfo.environment
//        for (key, value) in self.environments {
//            environmentValues[key] = value
//        }
//        return environmentValues
//    }
//}
