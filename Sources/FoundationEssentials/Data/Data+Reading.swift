//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if FOUNDATION_FRAMEWORK
internal import _ForSwiftFoundation
#endif

internal import _CShims

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private func readExtendedAttributesFromFileDescriptor(_ fd: Int32, attrsToRead: [String]) -> [String : Data] {
#if canImport(Darwin) && !NO_FILESYSTEM
    var output: [String : Data] = [:]
    for key in attrsToRead {
        key.withCString { keyStr in
            let maxXAttrLength = 1000
            withUnsafeTemporaryAllocation(of: CUnsignedChar.self, capacity: maxXAttrLength) { buf in
                let result = fgetxattr(fd, keyStr, buf.baseAddress, maxXAttrLength, 0, 0)
                if result != -1 {
                    // -1 means no such attribute
                    // Force unwrap buffer - if we do not have a base address, assert is appropriate.
                    output[key] = Data(bytes: buf.baseAddress!, count: result)
                } else if errno == ERANGE {
                    // ERANGE indicates that the buffer was too small
                    // Get its needed size (passing nil buffer)
                    let neededSize = fgetxattr(fd, keyStr, nil, 0, 0, 0)
                    let fullBuffer = malloc(neededSize)!
                    if fgetxattr(fd, keyStr, fullBuffer, neededSize, 0, 0) != neededSize {
                        // If still an error, then give up
                        free(fullBuffer)
                    } else {
                        output[key] = Data(bytesNoCopy: fullBuffer, count: neededSize, deallocator: .free)
                    }
                }
            }
        }
    }
    return output
#else
    // No extended attributes on this platform
    return [:]
#endif
    
}

private func shouldMapFileDescriptor(_ fd: Int32, path: PathOrURL, options: Data.ReadingOptions) -> Bool {
    if options.contains(.alwaysMapped) {
        return true
    }
    
    if options.contains(.mappedIfSafe) {
#if FOUNDATION_FRAMEWORK && !NO_FILESYSTEM
        // Failures from here out are non-fatal.
        // The file's protection class must not be == 'Class A'
        let protectionClass = fcntl(fd, F_GETPROTECTIONCLASS)
        let protectionClassIsSafeToMap = protectionClass >= 0 && protectionClass != -1 /* Class A */
        if protectionClassIsSafeToMap {
            // The file must live on a local (== not network), non-removal volume.
            var fileSystemInfo = statfs()
            if fstatfs(fd, &fileSystemInfo) == 0 {
                if (fileSystemInfo.f_flags & UInt32(MNT_LOCAL) != 0) && (fileSystemInfo.f_flags & UInt32(MNT_REMOVABLE) == 0) {
                    // The file must not be compressed in a format that requires another process to be running in order to provide the contents (i.e. type 5)
                    // An unfortunate path-based operation in the midst of all this fd-specific work.
                    // Checks with AppleFSCompression
                    return path.withFileSystemRepresentation { pathFileSystemRep in
                        guard let pathFileSystemRep else { return true }
                        return _NSFileCompressionTypeIsSafeForMapping(pathFileSystemRep)
                    }
                }
            }
        }
#else
        // For other platforms or configurations, any appropriate checks would go here. For now, we assume it is unsafe.
        return false
#endif
    }
    
    return false
}

// MARK: - Reading

#if FOUNDATION_FRAMEWORK
extension NSData {    
    /// Objective-C entry point to Swift `Data` reading. Returns bytes that must be freed with `free` or `unmap` as requested.
    @objc(_readBytesFromPath:maxLength:bytes:length:didMap:options:reportProgress:error:)
    internal static func _readBytes(fromPath path: String, maxLength: Int, bytes: UnsafeMutablePointer<UnsafeMutableRawPointer?>, length: UnsafeMutablePointer<Int>, didMap: UnsafeMutablePointer<ObjCBool>, options: Data.ReadingOptions, reportProgress: Bool) throws {
        var attrs: [String : Data] = [:]
        let result = try readBytesFromFile(path: .path(path), reportProgress: reportProgress, maxLength: maxLength == Int.max ? nil : maxLength, options: options, attributesToRead: [], attributes: &attrs)
        
        bytes.pointee = result.bytes
        length.pointee = result.length
        
        switch result.deallocator {
        case .unmap:
            didMap.pointee = ObjCBool(true)
        default:
            didMap.pointee = ObjCBool(false)
        }
    }

    /// Objective-C entry point to Swift `Data` reading. Returns bytes that must be freed with `free` or `unmap` as requested.
    @objc(_readBytesAndEncodingFromPath:maxLength:encoding:bytes:length:didMap:options:reportProgress:error:)
    internal static func _readBytesAndEncoding(fromPath path: String, maxLength: Int, encoding outEncoding: UnsafeMutablePointer<UInt>, bytes: UnsafeMutablePointer<UnsafeMutableRawPointer?>, length: UnsafeMutablePointer<Int>, didMap: UnsafeMutablePointer<ObjCBool>, options: Data.ReadingOptions, reportProgress: Bool) throws {
        
        var attrs: [String : Data] = [:]
        let result = try readBytesFromFile(path: .path(path), reportProgress: reportProgress, maxLength: maxLength == Int.max ? nil : maxLength, options: options, attributesToRead: [NSFileAttributeStringEncoding], attributes: &attrs)
        if let encodingAttributeData = attrs[NSFileAttributeStringEncoding] {
            outEncoding.pointee = _NSEncodingFromDataForExtendedAttribute(encodingAttributeData)
        } else {
            outEncoding.pointee = UInt(kCFStringEncodingInvalidId)
        }
        
        bytes.pointee = result.bytes
        length.pointee = result.length
        
        switch result.deallocator {
        case .unmap:
            didMap.pointee = ObjCBool(true)
        default:
            didMap.pointee = ObjCBool(false)
        }
    }
}
#endif

internal func readDataFromFile(path inPath: PathOrURL, reportProgress: Bool, maxLength: Int? = nil, options: Data.ReadingOptions = []) throws -> Data {
    var attributes: [String : Data] = [:]
    return try readDataFromFile(path: inPath, reportProgress: reportProgress, maxLength: maxLength, options: options, attributesToRead: [], attributes: &attributes)
}

internal func readDataFromFile(path inPath: PathOrURL, reportProgress: Bool, maxLength: Int? = nil, options: Data.ReadingOptions = [], attributesToRead: [String], attributes: inout [String: Data]) throws -> Data {
    let result = try readBytesFromFile(path: inPath, reportProgress: reportProgress, maxLength: maxLength, options: options, attributesToRead: attributesToRead, attributes: &attributes)
    
    if result.length == 0 {
        return Data()
    } else {
        return Data(bytesNoCopy: result.bytes!, count: result.length, deallocator: result.deallocator!)
    }
}

struct ReadBytesResult {
    /// Pointer to the read bytes.
    var bytes: UnsafeMutableRawPointer?
    
    /// Number of bytes.
    /// Matches `Data`'s count type.
    var length: Int
    
    /// The deallocator to use for these bytes, or nil if no deallocator is needed.
    var deallocator: Data.Deallocator?
}

internal func readBytesFromFile(path inPath: PathOrURL, reportProgress: Bool, maxLength: Int?, options: Data.ReadingOptions, attributesToRead: [String], attributes: inout [String: Data]) throws -> ReadBytesResult {
    if inPath.isEmpty {
        // For compatibility, throw a different error than the perhaps-expected 'file not found' here (41646641)
        throw CocoaError(.fileReadInvalidFileName)
    }
    
    let fd = try inPath.withFileSystemRepresentation { inPathFileSystemRep in
        guard let inPathFileSystemRep else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return open(inPathFileSystemRep, O_RDONLY, 0o666)
    }
        
    guard fd >= 0 else {
        throw CocoaError.errorWithFilePath(inPath, errno: errno, reading: true)
    }
    
    defer {
        close(fd)
    }
    
#if FOUNDATION_FRAMEWORK
    if options.contains(.uncached) {
        // Non-zero arg turns off caching; we ignore error as uncached is just a hint
        _ = fcntl(fd, F_NOCACHE, 1)
    }
#endif
    
    var filestat: stat = stat()
    let err = fstat(fd, &filestat)
    
    guard err == 0 else {
        throw CocoaError.errorWithFilePath(inPath, errno: errno, reading: true)
    }
    
    // The following check is valid for 64-bit platforms.
    if filestat.st_size > Int.max {
        // We cannot hold this in `Data`, which uses Int as its count.
        throw CocoaError.errorWithFilePath(inPath, errno: EFBIG, reading: true)
    }
    
    let fileSize = min(Int(clamping: filestat.st_size), maxLength ?? Int.max)
    let fileType = filestat.st_mode & S_IFMT
    let preferredChunkSize = filestat.st_blksize
#if !NO_FILESYSTEM
    let shouldMap = shouldMapFileDescriptor(fd, path: inPath, options: options)
#else
    let shouldMap = false
#endif
        
    if fileType != S_IFREG {
        // EACCES is still an odd choice, but at least we have a better error for directories.
        let code = (fileType == S_IFDIR) ? EISDIR : EACCES
        throw CocoaError.errorWithFilePath(inPath, errno: code, reading: true)
    }
    
    if fileSize < 0 {
        throw CocoaError.errorWithFilePath(inPath, errno: ENOMEM, reading: true)
    }
    
#if _pointerBitWidth(_32)
    // Refuse to do more than 2 GB on 32-bit platforms
    if fileSize > SSIZE_MAX {
        throw CocoaError.errorWithFilePath(inPath, errno: EFBIG, reading: true)
    }
#endif
    
    let result: ReadBytesResult
    let localProgress = (reportProgress && Progress.current() != nil) ? Progress(totalUnitCount: Int64(fileSize)) : nil
    
    if fileSize == 0 {
        localProgress?.totalUnitCount = 1
        localProgress?.completedUnitCount = 1
        result = ReadBytesResult(bytes: nil, length: 0, deallocator: nil)
    } else if shouldMap {
#if !NO_FILESYSTEM
        guard let bytes = mmap(nil, Int(fileSize), PROT_READ, MAP_PRIVATE, fd, 0) else {
            throw CocoaError.errorWithFilePath(inPath, errno: errno, reading: true)
        }
        
        guard bytes != MAP_FAILED else {
            throw CocoaError.errorWithFilePath(inPath, errno: errno, reading: true)
        }
        
        // Using bytes as the unit in this case doesn't really make any sense, since the amount of work required for mmap isn't meanginfully proportional to the size being mapped.
        localProgress?.totalUnitCount = 1
        localProgress?.completedUnitCount = 1
        
        result = ReadBytesResult(bytes: bytes, length: Int(fileSize), deallocator: .unmap)
#else
        // This was disabled above
        fatalError("mapping should not be enabled")
#endif
    } else {
        // We've verified above that fileSize will fit in `Int`
        guard let bytes = malloc(Int(fileSize)) else {
            throw CocoaError.errorWithFilePath(inPath, errno: ENOMEM, reading: true)
        }
        
        localProgress?.becomeCurrent(withPendingUnitCount: Int64(fileSize))
        do {
            let length = try readBytesFromFileDescriptor(fd, path: inPath, buffer: bytes, length: fileSize, chunkSize: size_t(preferredChunkSize), reportProgress: reportProgress)
            localProgress?.resignCurrent()
            
            result = ReadBytesResult(bytes: bytes, length: length, deallocator: .free)
        } catch {
            localProgress?.resignCurrent()
            free(bytes)
            throw error
        }
    }
    
    if !attributesToRead.isEmpty {
        attributes = readExtendedAttributesFromFileDescriptor(fd, attrsToRead: attributesToRead)
    }

    return result
}

// Takes an `Int` size and returns an `Int` to match `Data`'s count. If we are going to read more than Int.max, throws - because we won't be able to store it in `Data`.
private func readBytesFromFileDescriptor(_ fd: Int32, path: PathOrURL, buffer inBuffer: UnsafeMutableRawPointer, length: Int, chunkSize: size_t, reportProgress: Bool) throws -> Int {
    
    var buffer = inBuffer
    // If chunkSize (8-byte value) is more than blksize_t.max (4 byte value), then use the 4 byte max and chunk
    var preferredChunkSize = chunkSize
    let localProgress = (reportProgress && Progress.current() != nil) ? Progress(totalUnitCount: Int64(length)) : nil
    
    if localProgress != nil {
        // To report progress, we have to try reading in smaller chunks than the whole file. If we have a readingAttributes struct, we already know it. Otherwise, get one that makes sense for this destination.
        preferredChunkSize = chunkSize
    }
    
    var numBytesRemaining = length
    while numBytesRemaining > 0 {
        if let localProgress, localProgress.isCancelled {
            throw CocoaError(.userCancelled)
        }
        
        // We will only request a max of Int32.max bytes
        var numBytesRequested = Int32(clamping: preferredChunkSize)
        
        // Furthermore, don't request more than the number of bytes remaining
        if numBytesRequested > numBytesRemaining {
            numBytesRequested = Int32(clamping: numBytesRemaining)
        }
        
        var numBytesRead: Int
        repeat {
            if let localProgress, localProgress.isCancelled {
                throw CocoaError(.userCancelled)
            }
            
            // read takes an Int-sized argument, which will always be at least the size of Int32.
            numBytesRead = read(fd, buffer, Int(numBytesRequested))
        } while numBytesRead < 0 && errno == EINTR
        
        if numBytesRead < 0 {
            let errNum = errno
            logFileIOErrno(errNum, at: "read")
            // The read failed
            throw CocoaError.errorWithFilePath(path, errno: errNum, reading: true)
        } else if numBytesRead == 0 {
            // Getting zero here is weird, since it may imply unexpected end of file... If we do, return the number of bytes read so far (which is compatible with the way read() would work with just one call).
            break
        } else {
            numBytesRemaining -= Int(clamping: numBytesRead)
            localProgress?.completedUnitCount = Int64(length - numBytesRemaining)
            // Anytime we read less than actually requested, stop, since the length is considered "max" for socket calls
            if numBytesRead < numBytesRequested {
                break
            }
            
            buffer = buffer.advanced(by: numBytesRead)
        }
    }
    
    return length - numBytesRemaining
}
