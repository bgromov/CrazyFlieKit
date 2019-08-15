//
//  ParamStore.swift
//  CrazyFlieKit
//
//  Created by Boris Gromov on 10/07/2019.
//  Copyright © 2019 Boris Gromov. All rights reserved.
//

import Foundation

let paramTypes: [UInt8: Any.Type] = [
    0x08: UInt8.self,
    0x09: UInt16.self,
    0x0A: UInt32.self,
    0x0B: UInt64.self,

    0x00: Int8.self,
    0x01: Int16.self,
    0x02: Int32.self,
    0x03: Int64.self,

    //0x05: Float16.self,
    0x06: Float.self,
    0x07: Double.self
]

let paramTypesRev: [String: UInt8] = [
    "UInt8.Type":  0x08,
    "UInt16.Type": 0x09,
    "UInt32.Type": 0x0A,
    "UInt64.Type": 0x0B,

    "Int8.Type":   0x00,
    "Int16.Type":  0x01,
    "Int32.Type":  0x02,
    "Int64.Type":  0x03,

    //"Float16.Type": 0x05,
    "Float.Type":  0x06,
    "Double.Type": 0x07f
]

public class Param {
    private(set) public var ps: ParamStore
    private(set) public var id: UInt16
    private(set) public var group: String!
    private(set) public var name: String!
    private var typeAnyType: AnyType
    private(set) public var readOnly: Bool

    private var cachedValue: Any?
    private(set) public var expectedValue: Any?
    private(set) public var lock: DispatchSemaphore = DispatchSemaphore(value: 1)

    public var swiftTypeStr: String {
        return String(describing: type(of: typeAnyType.base))
    }

    public var value: Any? {
        get {
            return cachedValue
        }
        set(newVal) {
            guard ps.isConnected else {return}
            guard let val = newVal else {return}

//            guard lock.wait(timeout: .now() + DispatchTimeInterval.seconds(3)) == .success else {
//                print("Write lock for \(group!)/\(name!) timed out!")
//                return
//            }
//            if lock.wait(timeout: .now() + DispatchTimeInterval.seconds(3)) != .success {
//                print("Write lock for \(group!)/\(name!) timed out!")
//            }

            expectedValue = val

            let data = valueToData(val)

            ps.sendParamWriteRequest(index: self.id, payload: data)
        }
    }

    public var dictionary: [String: Any?] {
        let typeStr: String = String(describing: type(of: typeAnyType.base))

        return ["id": id,
                "group": group,
                "name": name,
                "type": paramTypesRev[typeStr],
                "readOnly": readOnly,
                ]
    }

    public init?(ps: ParamStore, id: UInt16, group: String!, name: String!, type: Any.Type, readOnly: Bool, requestUpdate: Bool = false) {
        self.ps = ps
        self.id = id
        self.group = group
        self.name = name
        self.readOnly = readOnly

        self.typeAnyType = getAnyType(type: type)!

        if requestUpdate {
            updateValue()
        }
    }

    public convenience init?(ps: ParamStore, dictionary: [String: Any]) {
        self.init(ps: ps,
                  id: dictionary["id"] as! UInt16,
                  group: dictionary["group"] as? String,
                  name: dictionary["name"] as? String,
                  type: paramTypes[dictionary["type"] as! UInt8]!,
                  readOnly: dictionary["readOnly"] as! Bool
        )
    }

    public init?(ps: ParamStore, data: Data!, requestUpdate: Bool = false) {
        self.ps = ps

        let tocItem = ParamTocPacketCreator.paramTocItemResponse(from: data)
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

        self.id = tocItem.paramId
        self.group = groupName
        self.name = paramName
        self.readOnly = tocItem.readonly != 0 ? true : false

        guard let type = paramTypes[tocItem.type] else {
            print("Unsupported data type: \(String(format: "0x%02X", tocItem.type))")
            return nil
        }
        self.typeAnyType = getAnyType(type: type)!

        // Send request to update variable value
        if requestUpdate {
            updateValue()
        }
    }

    public func updateValue() {
        ps.sendParamReadRequest(index: id)
    }

    private func valueToData(_ value: Any) -> Data {
        var data: Data = Data()
        var val = value

        data = withUnsafePointer(to: &val, { (ptr) -> Data in
            return Data(bytes: ptr, count: self.typeAnyType.memorySize)
        })

        return data
    }

    private func castValueToType<T>(_ data: Data) -> T {
        return data.withUnsafeBytes { $0.load(as: T.self)}
    }

    public func castValue(_ data: Data) -> Any? {
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

public class ParamStore {
    private(set) public var cf: CrazyFlie
    private(set) public var paramsByName: [String: Param] = [:]
    private(set) public var paramsById: [UInt16: Param] = [:]

    private var tocNextIndex: UInt16 = 0
    private var tocParamCount: UInt16 = 0
    private var tocHash: UInt32?

    private var paramsArray: [[String: Any]] = []

    private var forceNoCache: Bool = false

    private var didFetchParams: (() -> Void)?

    public var isConnected: Bool {
        return cf.bluetoothLink.isConnected
    }

    public init(cf: CrazyFlie, forceNoCache: Bool = false) {
        self.cf = cf
        self.cf.setPacketHandler(port: Port.parameters, callback: self.handlePackets)

        if forceNoCache {
            self.forceNoCache = forceNoCache
            return
        }

        let uuid = self.cf.bluetoothLink.bleUUID!

        guard let root = UserDefaults.standard.dictionary(forKey: uuid.uuidString) else {return}

        guard let paramsToc = root["paramsToc"] as! [String: Any]? else {return}
        guard let hash = paramsToc["hash"] as! UInt32? else {return}
        guard let count = paramsToc["count"] as! UInt16? else {return}
        guard let params = paramsToc["params"] as! [[String: Any]]? else {return}

        guard params.count == count else {return}

        tocHash = hash
        tocParamCount = count

        for p in params {
            guard let param = Param(ps: self, dictionary: p) else {return}
            addParam(id: param.id, param: param)

            let rw = param.readOnly ? "RO" : "RW"

            print("Cached param [\(param.id)]: \(rw) \(param.group!)/\(param.name!): \(param.swiftTypeStr.trimRight(at: "."))")
        }
    }

    fileprivate func sendParamTocInfoRequest() {
        let data = ParamTocPacketCreator.data(from: ParamTocMessage.info.rawValue, payload: nil)
        cf.sendCrtpPacket(port: Port.parameters, channel: ParamChannel.tocAccess.rawValue, data: data!)
    }

    fileprivate func sendParamTocItemRequest(index: UInt16) {
        let ptrPayload = UnsafeMutablePointer<UInt16>.allocate(capacity: 1)
        ptrPayload.pointee = index
        let payload = Data(bytes: ptrPayload, count: index.bitWidth / UInt8.bitWidth)

        let data = ParamTocPacketCreator.data(from: ParamTocMessage.item.rawValue, payload: payload)
        cf.sendCrtpPacket(port: Port.parameters, channel: ParamChannel.tocAccess.rawValue, data: data!)
    }

    fileprivate func sendParamReadRequest(index: UInt16) {
        let ptrPayload = UnsafeMutablePointer<UInt16>.allocate(capacity: 1)
        ptrPayload.pointee = index
        let data = Data(bytes: ptrPayload, count: index.bitWidth / UInt8.bitWidth)

        cf.sendCrtpPacket(port: Port.parameters, channel: ParamChannel.parameterRead.rawValue, data: data)
    }

    fileprivate func sendParamWriteRequest(index: UInt16, payload: Data) {
        let ptrData = UnsafeMutablePointer<UInt16>.allocate(capacity: 1)
        ptrData.pointee = index
        var data = Data(bytes: ptrData, count: index.bitWidth / UInt8.bitWidth)

        data.append(payload)

        cf.sendCrtpPacket(port: Port.parameters, channel: ParamChannel.parameterWrite.rawValue, data: data)
    }

    private func addParam(id: UInt16, param: Param) {
        let name = String("\(param.group!)/\(param.name!)")
        paramsByName[name] = param
        paramsById[id] = param
    }

    private func handlePackets(channel: UInt8, data: Data?) {
        switch channel {
        case ParamChannel.tocAccess.rawValue:
            let messageId = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
            let paramTocPayload = ParamTocPacketCreator.getMessageId(from: data, messageId: messageId)

            switch messageId.pointee {
            case ParamTocMessage.info.rawValue:
                let tocInfo = ParamTocPacketCreator.paramTocInfoResponse(from: paramTocPayload)
                print("Params: \(tocInfo.paramCount), Hash: \(tocInfo.crc32)")

                if !forceNoCache && tocInfo.crc32 == tocHash && tocInfo.paramCount == tocParamCount {
                    print("Params TOC did not change, will use cache")

                    self.didFetchParams?()
                    self.didFetchParams = nil
                } else {
                    print("Fetching params TOC...")

                    forceNoCache = false

                    tocParamCount = tocInfo.paramCount
                    tocHash = tocInfo.crc32
                    tocNextIndex = 0

                    sendParamTocItemRequest(index: tocNextIndex)
                }

            case ParamTocMessage.item.rawValue:
                guard let param = Param(ps: self, data: paramTocPayload) else {return}
                addParam(id: param.id, param: param)
                paramsArray.append(param.dictionary as [String : Any])

                if tocNextIndex < tocParamCount - 1 {
                    tocNextIndex += 1
                    sendParamTocItemRequest(index: tocNextIndex)
                }

                if paramsArray.count == tocParamCount {
                    print("Fetched \(paramsArray.count) params")

                    let paramsToc: [String: Any] = ["hash": tocHash as Any,
                                                    "count": tocParamCount,
                                                    "params": paramsArray]

                    let uuid = self.cf.bluetoothLink.bleUUID!

                    var root: [String:Any]? = UserDefaults.standard.dictionary(forKey: uuid.uuidString)
                    if root == nil {
                        root = [:]
                    }

                    root!["paramsToc"] = paramsToc
                    UserDefaults.standard.set(root, forKey: uuid.uuidString)

                    print("Cached params to persistent storage")

                    self.didFetchParams?()
                    self.didFetchParams = nil
                }

            default:
                return
            }

        case ParamChannel.parameterRead.rawValue:
            let paramId = UnsafeMutablePointer<UInt16>.allocate(capacity: 1)
            let paramPayload = ParamPacketCreator.parseReadPacket(from: data, paramId: paramId)

            guard let param = paramsById[paramId.pointee] else {return}

            let name = String("\(param.group!)/\(param.name!)")
//            print("\(name) = \(paramPayload!.hexEncodedString())")

            param.update(data: paramPayload!)
            print("\(name) = \(param.value!)")

        case ParamChannel.parameterWrite.rawValue:
            let paramId = UnsafeMutablePointer<UInt16>.allocate(capacity: 1)
            let paramPayload = ParamPacketCreator.parseWritePacket(from: data, paramId: paramId)

            guard let param = paramsById[paramId.pointee] else {return}

//            let newVal = param.castValue(paramPayload!)!
//            let expectedVal = param.expectedValue!
//            if String(describing: newVal) == String(describing: expectedVal) {
//                print("Param \(param.group!)/\(param.name!) was succesfully set to '\(newVal)'")
//            } else {
//                print("Error: tried to set param \(param.group!)/\(param.name!) to '\(expectedVal)', but heard '\(newVal)' back")
//            }

            param.update(data: paramPayload!)

//            param.lock.signal()
        default:
            return
        }
    }

    public func fetchParams(forceNoCache: Bool? = nil, didFinish: (()->Void)? = nil ) {
        if forceNoCache != nil {
            self.forceNoCache = forceNoCache!
        }

        self.didFetchParams = didFinish
        sendParamTocInfoRequest()
    }

}
