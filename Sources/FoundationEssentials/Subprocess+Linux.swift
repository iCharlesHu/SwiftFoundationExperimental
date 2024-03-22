//
//  File.swift
//
//
//  Created by Charles Hu
//

import System
internal import _CShims

#if os(Linux)
import Glibc

extension Subprocess {
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
        let fileDescriptors: [CInt] = [
            self.standardInput?.rawValue ?? 0,
            self.standardInput?.rawValue ?? 0,
            self.standardError?.rawValue ?? 0
        ]
        var pid: ProcessIdentifier = 0
        self.executablePath.withCString { exePath in
            fileDescriptors.withUnsafeBufferPointer { fds in
                _subprocess_fork_exec(&pid, exePath, fds, args, env)
            }
        }
        return pid
    }
}

#endif
