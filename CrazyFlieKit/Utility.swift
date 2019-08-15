//
//  Utility.swift
//  CrazyFlieKit
//
//  Created by Boris Gromov on 22/07/2019.
//  Copyright © 2019 Boris Gromov. All rights reserved.
//

import Foundation

/// From https://stackoverflow.com/a/47930353
public struct AnyType {
    public let base: Any.Type
    private let _memorySize: () -> Int
    private let _memoryStride: () -> Int
    private let _memoryAlignment: () -> Int

    public var memorySize: Int { return _memorySize() }
    public var memoryStride: Int { return _memoryStride() }
    public var memoryAlignment: Int { return _memoryAlignment() }

    /// Creates a new AnyType wrapper from a given metatype.
    /// The passed metatype's value **must** match its static value,
    /// i.e `T.self == base` must be `true`.
    public init<T>(_ base: T.Type) {
        precondition(T.self == base, """
            The static value \(T.self) and dynamic value \(base) of the \
            passed metatype do not match
            """
        )
        self.base = T.self
        self._memorySize = { MemoryLayout<T>.size }
        self._memoryStride = { MemoryLayout<T>.stride }
        self._memoryAlignment = { MemoryLayout<T>.alignment }
    }
}

public func getAnyType(type: Any.Type) -> AnyType? {
    var val: AnyType?
    switch type {
    case is UInt8.Type:
        val = AnyType(UInt8.self)
    case is UInt16.Type:
        val = AnyType(UInt16.self)
    case is UInt32.Type:
        val = AnyType(UInt32.self)
    case is UInt64.Type:
        val = AnyType(UInt64.self)

    case is Int8.Type:
        val = AnyType(Int8.self)
    case is Int16.Type:
        val = AnyType(Int16.self)
    case is Int32.Type:
        val = AnyType(Int32.self)
    case is Int64.Type:
        val = AnyType(Int64.self)

    case is Float.Type:
        val = AnyType(Float.self)
    case is Double.Type:
        val = AnyType(Double.self)

    default:
        return nil
    }

    return val
}

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let hexDigits = Array((options.contains(.upperCase) ? "0123456789ABCDEF" : "0123456789abcdef").utf16)
        var chars: [unichar] = []
        chars.reserveCapacity(2 * count)
        for byte in self {
            chars.append(hexDigits[Int(byte / 16)])
            chars.append(hexDigits[Int(byte % 16)])
        }
        return String(utf16CodeUnits: chars, count: chars.count)
    }
}

extension String {
    func trimRight(at char: Character) -> String {
        guard let last = self.lastIndex(of: char) else {return self}

        return String(self[..<last])
    }
}

/*
 Source: https://github.com/raywenderlich/swift-algorithm-club/tree/dd1ed39fca150d4fa2905b902736f12a49f3efb1/Ring%20Buffer

 Fixed-length ring buffer
 In this implementation, the read and write pointers always increment and
 never wrap around. On a 64-bit platform that should not get you into trouble
 any time soon.
 Not thread-safe, so don't read and write from different threads at the same
 time! To make this thread-safe for one reader and one writer, it should be
 enough to change read/writeIndex += 1 to OSAtomicIncrement64(), but I haven't
 tested this...
 */
public struct RingBuffer<T> {
    private var array: [T?]
    private var readIndex = 0
    private var writeIndex = 0

    public init(count: Int) {
        array = [T?](repeating: nil, count: count)
    }

    /* Returns false if out of space. */
    @discardableResult
    public mutating func write(_ element: T) -> Bool {
        guard !isFull else { return false }
        defer {
            writeIndex += 1
        }
        array[wrapped: writeIndex] = element
        return true
    }

    /* Returns nil if the buffer is empty. */
    public mutating func read() -> T? {
        guard !isEmpty else { return nil }
        defer {
            array[wrapped: readIndex] = nil
            readIndex += 1
        }
        return array[wrapped: readIndex]
    }

    public var availableSpaceForReading: Int {
        return writeIndex - readIndex
    }

    public var isEmpty: Bool {
        return availableSpaceForReading == 0
    }

    public var availableSpaceForWriting: Int {
        return array.count - availableSpaceForReading
    }

    public var isFull: Bool {
        return availableSpaceForWriting == 0
    }
}

extension RingBuffer: Sequence {
    public func makeIterator() -> AnyIterator<T> {
        var index = readIndex
        return AnyIterator {
            guard index < self.writeIndex else { return nil }
            defer {
                index += 1
            }
            return self.array[wrapped: index]
        }
    }
}

private extension Array {
    subscript (wrapped index: Int) -> Element {
        get {
            return self[index % count]
        }
        set {
            self[index % count] = newValue
        }
    }
}

public protocol StopWatchDelegate: class {
    func stopWatch(_ stopWatch: StopWatch, window: Int, didEstimateHz value: Double)
    func stopWatch(_ stopWatch: StopWatch, window: Int, didEstimateTime value: CFTimeInterval)
}

public class StopWatch {
    /// Class delegate
    public weak var delegate: StopWatchDelegate?
    /// How often to report statistics
    public var statsInterval: CFTimeInterval
    /// Current window size. Can be less than maxWindow
    private(set) public var window: Int

    private var buf: RingBuffer<CFTimeInterval>
    private var startTime: CFTimeInterval
    private var stopTime: CFTimeInterval
    private var avgTime: CFTimeInterval?

    private var throttleLastTime: CFTimeInterval?
    private var hzLastTime: CFTimeInterval?
    private let statsQueue: DispatchQueue

    private let bufSize: Int

    public init(maxWindow: Int, statsInterval: CFTimeInterval = 1.0, delegate: StopWatchDelegate? = nil) {
        bufSize = maxWindow
        buf = RingBuffer(count: maxWindow)
        startTime = 0.0
        stopTime = 0.0

        self.statsInterval = statsInterval
        self.delegate = delegate
        self.window = 0

        statsQueue = DispatchQueue(label: "ch.volaly.crazyfliekit.stopwatch", attributes: [])
    }

    private func printTime() {
        guard let avg = self.avgTime else {return}

        let str = String(format: "StopWatch: [\(bufSize)], time: %3.6f", avg)
        print(str)
    }

    private func printHz() {
        guard let avg = self.avgTime else {return}

        let str = String(format: "StopWatch: [\(bufSize)], freq: %3.2f", 1.0 / avg)
        print(str)
    }

    func throttle(timeInterval: TimeInterval, _ closure: () -> ()) {
        let now = CACurrentMediaTime()

        if let last = throttleLastTime {
            if now < last + timeInterval {
                return
            }
        }

        throttleLastTime = now

        closure()
    }

    private func average() -> (Int, CFTimeInterval) {
        let sum = buf.reduce(CFTimeInterval(), +)
        let count = buf.availableSpaceForReading

        return (count, sum / Double(count))
    }

    public func start() {
        startTime = CACurrentMediaTime()
    }

    public func stop() {
        stopTime = CACurrentMediaTime()
        let dt = stopTime - startTime
        statsQueue.async {
            self.buf.write(dt)

            if self.buf.availableSpaceForWriting == 0 {
                _ = self.buf.read()
                let (count, avg) = self.average()
                (self.window, self.avgTime) = (count, avg)
            }
        }

        if let avg = self.avgTime {
            throttle(timeInterval: statsInterval) {
                guard let delegate = delegate else {
                    printTime()
                    return
                }

                delegate.stopWatch(self, window: self.window, didEstimateTime: avg)
            }
        }
    }

    public func hz() {
        let now = CACurrentMediaTime()

        if let last = self.hzLastTime {
            let dt = now - last
            statsQueue.async {
                self.buf.write(dt)

                if self.buf.availableSpaceForWriting == 0 {
                    _ = self.buf.read()
                    let (count, avg) = self.average()
                    (self.window, self.avgTime) = (count, avg)
                }
            }
        }

        if let avg = self.avgTime {
            throttle(timeInterval: statsInterval) {
                guard let delegate = delegate else {
                    printHz()
                    return
                }

                delegate.stopWatch(self, window: self.window, didEstimateHz: 1.0 / avg)
            }
        }

        self.hzLastTime = now
    }
}
