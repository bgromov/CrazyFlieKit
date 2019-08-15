//
//  CrazyFlie.swift
//  Crazyflie client
//
//  Created by Martin Eberl on 15.07.16.
//  Copyright © 2016 Bitcraze. All rights reserved.
//

import UIKit

protocol CrazyFlieCommander {
    var pitch: Float { get }
    var roll: Float { get }
    var thrust: Float { get }
    var yaw: Float { get }

    func prepareData()
}

protocol HLCrazyFlieCommander {
    var command: UInt8 { get }
    var height: Float { get }
    var duration: Float { get }

    func prepareData()
}



enum Port: UInt8 {
    case console           = 0x0

    case parameters        = 0x2
    case commander         = 0x3
    case memoryAccess      = 0x4
    case dataLogging       = 0x5
    case localization      = 0x6
    case genericSetpoint   = 0x7
    case highlevelSetpoint = 0x8

    case platform          = 0xD
    case clientDebugging   = 0xE
    case linkLayer         = 0xF
}

enum ParamChannel: UInt8 {
    case tocAccess      = 0x0
    case parameterRead  = 0x1
    case parameterWrite = 0x2
    case miscCommands   = 0x3
}

enum ParamTocMessage: UInt8 {
    case item = 0x2  // protocol v2
    case info = 0x3  // protocol v2
}

enum LogChannel: UInt8 {
    case tocAccess = 0x0
    case control   = 0x1
    case logData   = 0x2
}

enum LogTocCommand: UInt8 {
    case item = 0x2  // protocol v2
    case info = 0x3  // protocol v2
}

enum LogControlCommand: UInt8 {
    case createBlock  = 0x6 // protocol v2
    case appendBlock  = 0x7 // protocol v2
    case deleteBlock  = 0x2

    case startLogging = 0x3
    case stopLogging  = 0x4
    case resetLogging = 0x5
}

enum LogControlResult: UInt8 {
    case ok            = 0
    case outOfMemory   = 12 // ENOMEM
    case cmdNotFound   = 8  // ENOEXEC
    case wrongBlockId  = 2  // ENOENT
    case blockTooLarge = 7  // E2BIG
    case blockExists   = 17 // EEXIST
}


enum CrazyFlieHeader: UInt8 {
    case param            = 0x20
    case commander        = 0x30
    case commanderGeneric = 0x70
    case commanderHL      = 0x80
}

enum GenericCommand: UInt8 {
    case stop          = 0
    case velocityWorld = 1
    case zDistance     = 2
    case cppmEmulation = 3
    case altitudeHold  = 4
    case hover         = 5
    case fullState     = 6
    case position      = 7
}

enum GenericChannel: UInt8 {
    case genericSetpoint = 0
}

enum HighLevelCommand: UInt8 {
    case setGroupMask     = 0
    case takeoff          = 1
    case land             = 2
    case stop             = 3
    case goTo             = 4
    case startTrajectory  = 5
    case defineTrajectory = 6
}

public enum CrazyFlieState {
    case idle, connected , scanning, connecting, services, characteristics
}

public protocol CrazyFlieDelegate {
    func didSend()
    func didUpdate(state: CrazyFlieState)
    func didLog(message msg: String)
    func didFail(with title: String, message: String?)
}

open class CrazyFlie: NSObject {
    
    private(set) public var state:CrazyFlieState {
        didSet {
            delegate?.didUpdate(state: state)
        }
    }

    private var partialLogMessage: String = ""

    private(set) public var paramStore: ParamStore?
    private(set) public var log: LogStore?

    private var tocNextIndex: UInt16 = 0
    private var tocParamCount: UInt16 = 0

    private var timer:Timer?
    private var delegate: CrazyFlieDelegate?
    private(set) public var bluetoothLink:BluetoothLink!

    private var packetHandlers: [Port:((UInt8, Data?) -> Void)] = [:] // callback(channel, payload)

    private var semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)

    public init(bluetoothLink:BluetoothLink? = BluetoothLink(), delegate: CrazyFlieDelegate?) {
        
        state = .idle
        self.delegate = delegate
        
        self.bluetoothLink = bluetoothLink
        super.init()

        self.setPacketHandler(port: Port.console, callback: self.handleConsole)

        bluetoothLink?.onStateUpdated{[weak self] (state) in
            if state.isEqual(to: "idle") {
                self?.state = .idle
            } else if state.isEqual(to: "connected") {
                self?.state = .connected
                self?.bluetoothLink?.rxCallback = self?.packetReceived
            } else if state.isEqual(to: "scanning") {
                self?.state = .scanning
            } else if state.isEqual(to: "connecting") {
                self?.state = .connecting
            } else if state.isEqual(to: "services") {
                self?.state = .services
            } else if state.isEqual(to: "characteristics") {
                self?.state = .characteristics
            }
        }
    }
    
    public func connect(_ callback:((Bool) -> Void)?) {
        guard state == .idle else {
            self.disconnect()
            return
        }
        
        self.bluetoothLink.connect(nil, callback: {[weak self] (connected) in
            callback?(connected)
            guard connected else {
                var title:String
                var body:String?
                
                // Find the reason and prepare a message
                if self?.bluetoothLink.getError() == "Bluetooth disabled" {
                    title = "Bluetooth disabled"
                    body = "Please enable Bluetooth to connect a Crazyflie"
                } else if self?.bluetoothLink.getError() == "Timeout" {
                    title = "Connection timeout"
                    body = "Could not find Crazyflie"
                } else {
                    title = "Error";
                    body = self?.bluetoothLink.getError()
                }

                print("CrazyFlie \(title): \(body!)")
                return
            }
        })
    }
    
    public func disconnect() {
        bluetoothLink.disconnect()
        semaphore.signal()
        semaphore.signal()
        semaphore.signal()
    }

    func setPacketHandler(port: Port, callback: ((UInt8, Data?) -> Void)?) {
        if callback != nil {
            packetHandlers[port] = callback
        } else {
            packetHandlers.removeValue(forKey: port)
        }
    }

    func handleConsole(channel: UInt8, data: Data?) {
        guard let logString = String(data: data!, encoding: .utf8) else {return}

        partialLogMessage += logString

        if partialLogMessage.rangeOfCharacter(from: .newlines) != nil {
            print("CF: \(partialLogMessage.trimmingCharacters(in: .newlines))")
            partialLogMessage = ""
        }
    }

    public func fetchTocs() {
        paramStore = ParamStore(cf: self)//, forceNoCache: true)
        log = LogStore(cf: self)//, forceNoCache: true)

        log?.resetLogging() { () in
            self.semaphore.signal()
        }
        semaphore.wait()

        paramStore?.fetchParams() { () in
            self.semaphore.signal()
        }

        log?.fetchLogVars() { () in
            self.semaphore.signal()
        }

        semaphore.wait()
        semaphore.wait()
    }

    public func takeoff(_ height: Float = 0.20, duration: Float = 2.0) {
        let takeoffCmd = TakeoffPacket(header: CrazyFlieHeader.commanderHL.rawValue, command: HighLevelCommand.takeoff.rawValue, groupMask: 0, height: height, duration: duration)

        let data = TakeoffPacketCreator.data(from: takeoffCmd)
        bluetoothLink.sendPacket(data!, callback: nil)
    }

    public func land(_ height: Float = 0.0, duration: Float = 2.0) {
        let landCmd = LandPacket(header: CrazyFlieHeader.commanderHL.rawValue, command: HighLevelCommand.land.rawValue, groupMask: 0, height: height, duration: duration)

        let data = LandPacketCreator.data(from: landCmd)
        bluetoothLink.sendPacket(data!, callback: nil)
    }

    public func stop(callback: @escaping (Bool) -> ()) {
        let stopCmd = StopPacket(header: CrazyFlieHeader.commanderHL.rawValue, command: HighLevelCommand.stop.rawValue, groupMask: 0)

        let data = StopPacketCreator.data(from: stopCmd)
        bluetoothLink.sendPacket(data!, callback: callback)
    }

    public func goTo(_ relative: Bool, x: Float, y: Float, z: Float, yaw: Float, duration: Float) {
        let goToCmd = GoToPacket(header: CrazyFlieHeader.commanderHL.rawValue, command: HighLevelCommand.goTo.rawValue, groupMask: 0, relative: (relative ? 1 : 0), x: x, y: y, z: z, yaw: yaw, duration: duration)

        let data = GoToPacketCreator.data(from: goToCmd)
        bluetoothLink.sendPacket(data!, callback: nil)
    }

    public func genericStop(callback: @escaping (Bool) -> ()) {
        sendGenericCommand(command: .stop, didSend: callback)
    }

    public func genericTakeoff(_ height: Float = 0.20) {
        genericGoTo(x: 0.0, y: 0.0, z: height, yaw: 0.0)
    }

    public func genericGoTo(x: Float, y: Float, z: Float, yaw: Float) {
        var position = PositionSetpointPacket(x: x, y: y, z: z, yaw: yaw)
        let data = Data(bytes: &position, count: MemoryLayout<PositionSetpointPacket>.size)
        sendGenericCommand(command: .position, payload: data)
    }

    func sendGenericCommand(command: GenericCommand, payload: Data? = nil, didSend: ((Bool) -> ())? = nil) {
        let data = GenericSetpointPacketCreator.data(with: command.rawValue, payload: payload)
        sendCrtpPacket(port: Port.genericSetpoint, channel: GenericChannel.genericSetpoint.rawValue, data: data!, didSend: didSend)
    }

    func sendCrtpPacket(port: Port, channel: UInt8, data: Data, didSend: ((Bool) -> ())? = nil) {
        let header = CrtpPacketHeader(channel: channel, link: 0, port: port.rawValue)
        let crtpPacket = CrtpPacketCreator.data(from: header, payload: data)

        bluetoothLink.sendPacket(crtpPacket!, callback: didSend)
//        print("Sending: \(crtpPacket!.hexEncodedString())")
    }

    // MARK: - Private Methods

    private func packetReceived(data: Data) {
//        print("Received something \(data.count) bytes long: \(data.hexEncodedString())")
        let crtpHeader = UnsafeMutablePointer<CrtpPacketHeader>.allocate(capacity: 1)
        let crtpPayload = CrtpPacketCreator.getCrtpHeader(from: data, header: crtpHeader)

        guard let port = Port(rawValue: crtpHeader.pointee.port) else {return}
        guard let callback = self.packetHandlers[port] else {
            print("Unhandled port: \(port)")
            print("Received something \(data.count) bytes long: \(data.hexEncodedString())")

            return
        }

        callback(crtpHeader.pointee.channel, crtpPayload)
    }

}
