//
//  LogStore.swift
//  CrazyFlieKit
//
//  Created by Boris Gromov on 22/07/2019.
//  Copyright © 2019 Boris Gromov. All rights reserved.
//

import Foundation

let varTypes: [UInt8: Any.Type] = [
    0x01: UInt8.self,
    0x02: UInt16.self,
    0x03: UInt32.self,

    0x04: Int8.self,
    0x05: Int16.self,
    0x06: Int32.self,

    0x07: Float.self,
    //0x08: Float16.self,
]

let varTypesRev: [String: UInt8] = [
    "UInt8.Type":  0x01,
    "UInt16.Type": 0x02,
    "UInt32.Type": 0x03,

    "Int8.Type":   0x04,
    "Int16.Type":  0x05,
    "Int32.Type":  0x06,

    "Float.Type":  0x07,
    //"Float16.Type": 0x08,
]

public class LogVar {
    private(set) public var ls: LogStore
    private(set) public var id: UInt16
    private(set) public var group: String!
    private(set) public var name: String!
    private(set) public var typeAnyType: AnyType

    private var cachedValue: Any?
    private(set) var lock: DispatchSemaphore = DispatchSemaphore(value: 1)

    public var swiftTypeStr: String {
        return String(describing: type(of: typeAnyType.base))
    }

    public var value: Any? {
        get {
            return cachedValue
        }
    }

    public var dictionary: [String: Any?] {
        let typeStr: String = String(describing: type(of: typeAnyType.base))

        return ["id": id,
                "group": group,
                "name": name,
                "type": varTypesRev[typeStr]
        ]
    }

    public init?(ls: LogStore, id: UInt16, group: String!, name: String!, type: Any.Type) {
        self.ls = ls
        self.id = id
        self.group = group
        self.name = name

        self.typeAnyType = getAnyType(type: type)!
    }

    public convenience init?(ls: LogStore, dictionary: [String: Any]) {
        self.init(ls: ls,
                  id: dictionary["id"] as! UInt16,
                  group: dictionary["group"] as? String,
                  name: dictionary["name"] as? String,
                  type: varTypes[dictionary["type"] as! UInt8]!
        )
    }

    public init?(ls: LogStore, data: Data!) {
        self.ls = ls

        let tocItem = LogTocPacketCreator.logTocItemResponse(from: data)
        var t = tocItem.name
        let len = MemoryLayout.size(ofValue: t)
        let buf = withUnsafePointer(to: &t, { (ptr) -> Data in
            return ptr.withMemoryRebound(to: Int8.self, capacity: len, {(cptr) in
                return Data(bytes: cptr, count: len)
            })
        })

        let names = buf.split(separator: 0x00, maxSplits: 2) // Make sure all rubish is in the last chunk

        let groupName = String(data: names[0], encoding: .ascii)
        let paramName = String(data: names[1], encoding: .ascii)

        self.id = tocItem.request.varId
        self.group = groupName
        self.name = paramName

        guard let type = varTypes[tocItem.type] else {
            print("Unsupported data type: \(String(format: "0x%02X", tocItem.type))")
            return nil
        }
        self.typeAnyType = getAnyType(type: type)!
    }

    private func castValueToType<T>(_ data: Data) -> T {
        return data.withUnsafeBytes { $0.load(as: T.self)}
    }

    private func castValue(_ data: Data) -> Any? {
        var val: Any?
        switch typeAnyType.base {
        case is UInt8.Type:
            val = castValueToType(data) as UInt8
        case is UInt16.Type:
            val = castValueToType(data) as UInt16
        case is UInt32.Type:
            val = castValueToType(data) as UInt32
        case is UInt64.Type:
            val = castValueToType(data) as UInt64

        case is Int8.Type:
            val = castValueToType(data) as Int8
        case is Int16.Type:
            val = castValueToType(data) as Int16
        case is Int32.Type:
            val = castValueToType(data) as Int32
        case is Int64.Type:
            val = castValueToType(data) as Int64

        case is Float.Type:
            val = castValueToType(data) as Float
        case is Double.Type:
            val = castValueToType(data) as Double

        default:
            return nil
        }

        return val
    }

    public func update(data: Data) {
        cachedValue = castValue(data)
    }
}

public class LogBlock {
    private(set) public var ls: LogStore
    private(set) public var id: UInt8
    private(set) public var items: [LogBlockItem] = []
    private(set) public var blockVars: [LogVar] = []

    fileprivate(set) var added: Bool = false
    fileprivate(set) var started: Bool = false

    fileprivate(set) public var period: UInt8  = 0 // in increments of 10 ms
    fileprivate(set) public var timestamp: UInt32? // in ms from the start of Crazyflie

    private var didUpdate: ((LogBlock) -> Void)?

    fileprivate init?(ls: LogStore, id: UInt8, logVars: [LogVar], period: Double, didUpdate: ((LogBlock) -> Void)? = nil )  {
        self.ls = ls
        self.id = id

        let ms10 = Int(period * 1000.0 / 10.0)
        precondition(ms10 <= 255 && ms10 > 0, "Period can be less than zero and more than 0.255 s")
        self.period = UInt8(ms10)

        self.didUpdate = didUpdate

        var sz = 0
        for v in logVars {
            let typeStr: String = String(describing: type(of: v.typeAnyType.base))
            let item = LogBlockItem(type: varTypesRev[typeStr]!, varId: v.id)
            sz += v.typeAnyType.memorySize

            if sz > 26 {
                print("""
                    Error: Can't configure that many variables in a single log block!
                    Ignoring \(v.group!)/\(v.name!)
                    """
                )
                return nil
            }
            items.append(item)
            blockVars.append(v)
        }
    }

    fileprivate func updateVars(data: Data, timestamp: UInt32) {
        var buf: Data = data

        for v in blockVars {
            let sz = v.typeAnyType.memorySize
            let varData: Data = buf.subdata(in: 0..<sz)

            if buf.count > sz {
                buf = buf.advanced(by: sz)
            }

            v.update(data: varData)
        }

        self.timestamp = timestamp

        if didUpdate != nil {
            didUpdate!(self)
        }
    }

    public var values: [String: Any] {
        var dict:[String: Any] = [:]

        for v in blockVars {
            dict[String("\(v.group!)/\(v.name!)")] = v.value!
        }

        return dict
    }

    public func startLogging(period: Double? = nil) {
        guard ls.isConnected else {print("Error: Crazyflie is not connected"); return}

        guard added else {print("Error: Block id = \(id) is not valid"); return}
        guard !started else {print("Warn: Block id = \(id) is already started. Ignoring"); return}

        precondition(self.period > 0 || period != nil, "Error: period is not specified neither in constructor nor at start")

        if period != nil {
            let ms10 = Int(period! * 1000.0 / 10.0)
            precondition(ms10 <= 255 && ms10 > 0, "Period can be less than zero and more than 0.255 s")
            self.period = UInt8(ms10)
        }

        ls.sendLogStartLogging(block: self)
    }

    public func stopLogging() {
        guard ls.isConnected else {print("Error: Crazyflie is not connected"); return}

        guard added else {print("Error: Block id = \(id) is not valid"); return}
        guard started else {print("Error: Block id = \(id) is not started"); return}

        ls.sendLogStopLogging(block: self)
    }
}

public class LogStore {
    private(set) public var cf: CrazyFlie
    private(set) public var varsByName: [String: LogVar] = [:]
    private(set) public var varsById: [UInt16: LogVar] = [:]

    private(set) public var blocksById: [UInt8: LogBlock] = [:]

    private var blockCounter: UInt8 = 0

    private var tocNextIndex: UInt16 = 0
    private var tocVarCount: UInt16 = 0
    private var tocHash: UInt32?

    private var logTocArray: [[String: Any]] = []

    private var forceNoCache: Bool = false

    private var didFetchVars: (() -> Void)?
    private var didResetLogging: (() -> Void)?
    private var didCreateBlock: ((LogBlock) -> Void)?
    private var didDeleteBlock: (() -> Void)?

    private(set) var semaphore: DispatchSemaphore = DispatchSemaphore(value: 1)

    public var isConnected: Bool {
        return cf.bluetoothLink.isConnected
    }

    public init(cf: CrazyFlie, forceNoCache: Bool = false) {
        self.cf = cf
        self.cf.setPacketHandler(port: Port.dataLogging, callback: self.handlePackets)

        if forceNoCache {
            self.forceNoCache = forceNoCache
            return
        }

        let uuid = self.cf.bluetoothLink.bleUUID!

        guard let root = UserDefaults.standard.dictionary(forKey: uuid.uuidString) else {return}

        guard let logToc = root["varsToc"] as! [String: Any]? else {return}
        guard let hash = logToc["hash"] as! UInt32? else {return}
        guard let count = logToc["count"] as! UInt16? else {return}
        guard let vars = logToc["vars"] as! [[String: Any]]? else {return}

        guard vars.count == count else {return}

        tocHash = hash
        tocVarCount = count

        for v in vars {
            guard let logVar = LogVar(ls: self, dictionary: v) else {return}
            addVar(id: logVar.id, logVar: logVar)

            print("Cached var [\(logVar.id)]: \(logVar.group!)/\(logVar.name!): \(logVar.swiftTypeStr.trimRight(at: "."))")
        }
    }

    fileprivate func sendLogTocInfoRequest() {
        let data = LogTocPacketCreator.data(from: LogTocCommand.info.rawValue, payload: nil)
        cf.sendCrtpPacket(port: Port.dataLogging, channel: LogChannel.tocAccess.rawValue, data: data!)
    }

    fileprivate func sendLogTocItemRequest(index: UInt16) {
        let ptrPayload = UnsafeMutablePointer<UInt16>.allocate(capacity: 1)
        ptrPayload.pointee = index
        let payload = Data(bytes: ptrPayload, count: index.bitWidth / UInt8.bitWidth)

        let data = LogTocPacketCreator.data(from: LogTocCommand.item.rawValue, payload: payload)
        cf.sendCrtpPacket(port: Port.dataLogging, channel: LogChannel.tocAccess.rawValue, data: data!)
    }

    fileprivate func sendLogControlRequest(command: LogControlCommand, payload: Data? = nil) {
        DispatchQueue.global().async {
            self.semaphore.wait()

            let data = LogControlPacketCreator.data(with: command.rawValue, payload: payload)
            self.cf.sendCrtpPacket(port: Port.dataLogging, channel: LogChannel.control.rawValue, data: data!)
        }
    }

    fileprivate func sendLogReset() {
        sendLogControlRequest(command: .resetLogging)
    }

    fileprivate func sendLogCreateBlock(block: LogBlock) {
        var blockId = block.id
        var payload = Data(bytes: &blockId, count: block.id.bitWidth / UInt8.bitWidth)

        for item in block.items {
            var it = item
            let itemData = Data(bytes: &it, count: MemoryLayout<LogBlockItem>.size)
            payload.append(itemData)
        }

        sendLogControlRequest(command: .createBlock, payload: payload)
    }

    fileprivate func sendLogDelete(block: LogBlock) {
        var blockId = block.id
        let payload = Data(bytes: &blockId, count: blockId.bitWidth / UInt8.bitWidth)

        sendLogControlRequest(command: .deleteBlock, payload: payload)
    }

    fileprivate func sendLogStartLogging(block: LogBlock) {
        guard block.period != 0 else {print("Error: period can't be zero, block id = \(block.id)"); return}

        var blockId = block.id
        var period = block.period

        var payload = Data(bytes: &blockId, count: blockId.bitWidth / UInt8.bitWidth)
        payload.append(&period, count: period.bitWidth / UInt8.bitWidth)

        sendLogControlRequest(command: .startLogging, payload: payload)
    }

    fileprivate func sendLogStopLogging(block: LogBlock) {
        var blockId = block.id
        let payload = Data(bytes: &blockId, count: blockId.bitWidth / UInt8.bitWidth)

        sendLogControlRequest(command: .stopLogging, payload: payload)
    }

    private func addVar(id: UInt16, logVar: LogVar) {
        let name = String("\(logVar.group!)/\(logVar.name!)")
        varsByName[name] = logVar
        varsById[id] = logVar
    }

    private func createBlock(logVars: [LogVar], period: Double, didUpdate: ((LogBlock) -> Void)? = nil ) {
        guard let logBlock = LogBlock(ls: self, id: blockCounter, logVars: logVars, period: period, didUpdate: didUpdate) else {return}

        blockCounter += 1
        blocksById[logBlock.id] = logBlock
        sendLogCreateBlock(block: logBlock)
    }

    private func handlePackets(channel: UInt8, data: Data?) {
        guard let ch = LogChannel(rawValue: channel) else {
            print("Warning: unknown log channel: \(channel). Ignoring")
            return
        }

        switch ch {
        case .tocAccess:
            let cmd = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
            let logTocPayload = LogTocPacketCreator.getCommand(from: data, command: cmd)

            guard let command = LogTocCommand(rawValue: cmd.pointee) else {
                print("Warning: unknown log TOC command: \(cmd). Ignoring")
                return
            }

            switch command {
            case .info:
                let tocInfo = LogTocPacketCreator.logTocInfoResponse(from: logTocPayload)
                print("Vars: \(tocInfo.varCount), Hash: \(tocInfo.crc32), Max Packets: \(tocInfo.maxPackets), Max Ops: \(tocInfo.maxOps)")

                if !forceNoCache && tocInfo.crc32 == tocHash && tocInfo.varCount == tocVarCount {
                    print("Log TOC did not change, will use cache")
                    self.didFetchVars?()
                    self.didFetchVars = nil
                } else {
                    print("Fetching log TOC...")

                    forceNoCache = false

                    tocVarCount = tocInfo.varCount
                    tocHash = tocInfo.crc32
                    tocNextIndex = 0

                    sendLogTocItemRequest(index: tocNextIndex)
                }
            case .item:
                guard let logVar = LogVar(ls: self, data: logTocPayload) else {return}
                addVar(id: logVar.id, logVar: logVar)
                logTocArray.append(logVar.dictionary as [String : Any])

                if tocNextIndex < tocVarCount - 1 {
                    tocNextIndex += 1
                    sendLogTocItemRequest(index: tocNextIndex)
                }

                if logTocArray.count == tocVarCount {
                    print("Fetched \(logTocArray.count) vars")

                    let varsToc: [String: Any] = ["hash": tocHash as Any,
                                                  "count": tocVarCount,
                                                  "vars": logTocArray]

                    let uuid = self.cf.bluetoothLink.bleUUID!

                    var root: [String:Any]? = UserDefaults.standard.dictionary(forKey: uuid.uuidString)
                    if root == nil {
                        root = [:]
                    }

                    root!["varsToc"] = varsToc
                    UserDefaults.standard.set(root, forKey: uuid.uuidString)

                    print("Cached vars to persistent storage")

                    self.didFetchVars?()
                    self.didFetchVars = nil
                }
            }

        case .control:
            let resp = LogControlPacketCreator.logControl(from: data)
            let block = blocksById[resp.blockId]
            guard let command = LogControlCommand(rawValue: resp.command) else {
                print("Warning: unknown log control command: \(resp.command). Ignoring")
                return
            }

            switch command {
            case .createBlock:
                guard let b = block else {print("Warning: created block is not on the list. Ignoring"); return}
                if resp.result == LogControlResult.ok.rawValue || resp.result == LogControlResult.blockExists.rawValue {
                    if !b.added {
                        print("Block id = \(b.id) was successfully created")
                        b.added = true

                        self.didCreateBlock?(b)
                        self.didCreateBlock = nil

                        semaphore.signal()

                        b.startLogging()
                    }
                } else {
                    print("Error: failed to create a block id = \(resp.blockId), error_code = \(resp.result)")
                }
            case .appendBlock:
                print("Error: append block is not implemented")
                return
            case .deleteBlock:
                guard let b = block else {print("Warning: deleted block is not on the list. Ignoring"); return}
                if resp.result == LogControlResult.ok.rawValue || resp.result == LogControlResult.wrongBlockId.rawValue {
                    print("Block id = \(resp.blockId) was successfully deleted")

                    b.added = false
                    b.started = false

                    self.didDeleteBlock?()
                    self.didDeleteBlock = nil

                    semaphore.signal()
                }
            case .startLogging:
                guard let b = block else {print("Warning: started block is not on the list. Ignoring"); return}
                if resp.result == LogControlResult.ok.rawValue {
                    print("Block id = \(resp.blockId) was successfully started")

                    b.started = true

                    semaphore.signal()
                } else {
                    print("Error: failed to start a block id = \(resp.blockId), error_code = \(resp.result)")
                }
            case .stopLogging:
                guard let b = block else {print("Warning: stopped block is not on the list. Ignoring"); return}
                if resp.result == LogControlResult.ok.rawValue {
                    print("Block id = \(resp.blockId) was successfully stopped")

                    b.started = false
                    b.period = 0
                    b.timestamp = nil

                    semaphore.signal()
                } else {
                    print("Error: failed to stop a block id = \(resp.blockId), error_code = \(resp.result)")
                }
            case .resetLogging:
                for b in blocksById.values {
                    b.added = false
                    b.started = false
                }
                self.didResetLogging?()
                self.didResetLogging = nil

                semaphore.signal()
            }

        case .logData:
            let headerPtr = UnsafeMutablePointer<LogDataResponseHeader>.allocate(capacity: 1)
            let payload = LogDataPacketCreator.logData(from: data, to: headerPtr)!
            let header = headerPtr.pointee

            guard let b = blocksById[header.blockId] else {print("Warning: received a block that is not on the list. Ignoring"); return}

            let ts: UInt32 = UInt32(header.timestampHi << 8) | UInt32(header.timestampLo)

            b.updateVars(data: payload, timestamp: ts)
        }

    }

    public func fetchLogVars(forceNoCache: Bool? = nil, didFinish: (() -> Void)? = nil) {
        if forceNoCache != nil {
            self.forceNoCache = forceNoCache!
        }

        self.didFetchVars = didFinish
        sendLogTocInfoRequest()
    }

    public func createBlock(vars: [String], period: Double, didCreate: ((LogBlock) -> Void)? = nil, didUpdate: ((LogBlock) -> Void)? = nil ) {
        var logVars: [LogVar] = []
        for name in vars {
            guard let v = varsByName[name] else {
                print("Error: Variable '\(name)' was not found in TOC")
                return
            }

            logVars.append(v)
        }
        self.didCreateBlock = didCreate
        self.createBlock(logVars: logVars, period: period, didUpdate: didUpdate)
    }

    public func deleteBlock(block: LogBlock, didFinish: (() -> Void)? = nil) {
        self.didDeleteBlock = didFinish
        sendLogDelete(block: block)
    }

    public func resetLogging(didFinish: (() -> Void)? = nil) {
        self.didResetLogging = didFinish
        sendLogReset()
    }
}
