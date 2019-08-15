//
//  DataStruct.m
//  Crazyflie client
//
//  Created by Martin Eberl on 12.02.17.
//  Copyright © 2017 Bitcraze. All rights reserved.
//

#import "CommandPacket.h"

@implementation CrtpPacketCreator: NSObject

+ (NSData *)dataFrom: (CrtpPacketHeader)header payload:(NSData *)data {
    NSMutableData *packetData = [NSMutableData dataWithBytes:&header length:sizeof(CrtpPacketHeader)];

    if (data) {
        [packetData appendData:data];
    }

    return packetData;
}

+ (CrtpPacket)crtpPacketFrom:(NSData *)data {
    CrtpPacket packet;
    NSUInteger lenPayload = data.length - sizeof(CrtpPacketHeader);

    [data getBytes:&packet.header length:sizeof(CrtpPacketHeader)];
    packet.payload = [NSData dataWithBytes:(data.bytes + sizeof(CrtpPacketHeader)) length:lenPayload];

    return packet;
}

+ (NSData *)getCrtpHeaderFrom:(NSData *)data header:(CrtpPacketHeader *) header {
    NSUInteger lenPayload = data.length - sizeof(CrtpPacketHeader);

    [data getBytes:header length:sizeof(CrtpPacketHeader)];
    NSData *payload = [NSData dataWithBytes:(data.bytes + sizeof(CrtpPacketHeader)) length:lenPayload];

    return payload;
}


@end

@implementation ParamTocPacketCreator: NSObject

+ (NSData *)dataFrom:(uint8_t)messageId payload:(NSData *)data {
    NSMutableData *packetData = [NSMutableData dataWithBytes:&messageId length:sizeof(uint8_t)];

    if (data) {
        [packetData appendData:data];
    }

    return packetData;
}

+ (ParamTocPacket)paramTocPacketFrom:(NSData *)data {
    ParamTocPacket packet;
    NSUInteger lenPayload = data.length - sizeof(uint8_t);

    [data getBytes:&packet.messageId length:sizeof(uint8_t)];
    packet.payload = [NSMutableData dataWithBytes:(data.bytes + sizeof(uint8_t)) length:lenPayload];

    return packet;
}

+ (NSData *)getMessageIdFrom:(NSData *)data messageId:(uint8_t *) messageId {
    NSUInteger lenPayload = data.length - sizeof(uint8_t);

    [data getBytes:messageId length:sizeof(uint8_t)];
    NSData *payload = [NSMutableData dataWithBytes:(data.bytes + sizeof(uint8_t)) length:lenPayload];

    return payload;
}

+(ParamTocInfoResponse)paramTocInfoResponseFrom: (NSData *)data {
    ParamTocInfoResponse response;
    [data getBytes:&response length:sizeof(ParamTocInfoResponse)];
    return response;
}

+(ParamTocItemResponse)paramTocItemResponseFrom: (NSData *)data {
    ParamTocItemResponse response;

    NSUInteger lenTrimmed = sizeof(ParamTocItemResponse) - sizeof(response.name);
    NSUInteger lenRemainder = data.length - lenTrimmed;

    [data getBytes:&response length:lenTrimmed];

    NSData *buf = [NSData dataWithBytes:(data.bytes + lenTrimmed) length:lenRemainder];

    [buf getBytes:&response.name length:buf.length];

    return response;
}

@end

@implementation ParamPacketCreator: NSObject

+ (NSData *)dataFrom:(uint16_t)paramId payload:(NSData *)data {
    NSMutableData *packetData = [NSMutableData dataWithBytes:&paramId length:sizeof(uint16_t)];

    if (data) {
        [packetData appendData:data];
    }

    return packetData;
}

+ (NSData *)parseReadPacketFrom:(NSData *)data paramId:(uint16_t *) paramId {
    NSUInteger lenPayload = data.length - sizeof(uint16_t);

    [data getBytes:paramId length:sizeof(uint16_t)];
    // FIXME Seems like a bug in BLE implementation: there is an extra empty byte after the param ID
    // so we just skip it
    NSData *payload = [NSMutableData dataWithBytes:(data.bytes + sizeof(uint16_t) + 1) length:lenPayload - 1];

    return payload;
}

+ (NSData *)parseWritePacketFrom:(NSData *)data paramId:(uint16_t *) paramId {
    NSUInteger lenPayload = data.length - sizeof(uint16_t);

    [data getBytes:paramId length:sizeof(uint16_t)];
    // NOTE there is no bug in write packet though
    NSData *payload = [NSMutableData dataWithBytes:(data.bytes + sizeof(uint16_t)) length:lenPayload];

    return payload;
}

@end

@implementation LogTocPacketCreator: NSObject

+ (NSData *)dataFrom:(uint8_t)command payload:(NSData *)data {
    NSMutableData *packetData = [NSMutableData dataWithBytes:&command length:sizeof(uint8_t)];

    if (data) {
        [packetData appendData:data];
    }

    return packetData;
}

+ (LogTocPacket)logTocPacketFrom:(NSData *)data {
    LogTocPacket packet;
    NSUInteger lenPayload = data.length - sizeof(uint8_t);

    [data getBytes:&packet.command length:sizeof(uint8_t)];
    packet.payload = [NSMutableData dataWithBytes:(data.bytes + sizeof(uint8_t)) length:lenPayload];

    return packet;
}

+ (NSData *)getCommandFrom:(NSData *)data command:(uint8_t *) command {
    NSUInteger lenPayload = data.length - sizeof(uint8_t);

    [data getBytes:command length:sizeof(uint8_t)];
    NSData *payload = [NSMutableData dataWithBytes:(data.bytes + sizeof(uint8_t)) length:lenPayload];

    return payload;
}

+(LogTocInfoResponse)logTocInfoResponseFrom: (NSData *)data {
    LogTocInfoResponse response;
    [data getBytes:&response length:sizeof(LogTocInfoResponse)];
    return response;
}

+(LogTocItemResponse)logTocItemResponseFrom: (NSData *)data {
    LogTocItemResponse response;

    NSUInteger lenTrimmed = sizeof(LogTocItemResponse) - sizeof(response.name);
    NSUInteger lenRemainder = data.length - lenTrimmed;

    [data getBytes:&response length:lenTrimmed];

    NSData *buf = [NSData dataWithBytes:(data.bytes + lenTrimmed) length:lenRemainder];

    [buf getBytes:&response.name length:buf.length];

    return response;
}

@end

@implementation LogBlockPacketCreator: NSObject

+ (NSData *)dataWith:(uint8_t)blockId vars:(NSArray*)items payload:(NSData *)data {

    return NULL;
}

@end


@implementation LogControlPacketCreator: NSObject

+ (NSData *)dataWith:(uint8_t)command payload:(NSData *)data {
    NSMutableData *packetData = [NSMutableData dataWithBytes:&command length:sizeof(uint8_t)];

    if (data) {
        [packetData appendData:data];
    }

    return packetData;
}

+ (LogControlResponse)logControlFrom:(NSData *)data {
    LogControlResponse resp;

    [data getBytes:&resp length:sizeof(LogControlResponse)];

    return resp;
}

@end

@implementation LogDataPacketCreator: NSObject

+ (NSData *)logDataFrom:(NSData *)data to:(LogDataResponseHeader*)header {
    NSUInteger lenTrimmed = sizeof(LogDataResponseHeader);
    NSUInteger lenRemainder = data.length - lenTrimmed;

    [data getBytes:header length:lenTrimmed];

    NSData *buf = [NSData dataWithBytes:(data.bytes + lenTrimmed) length:lenRemainder];

    return buf;
}

@end

@implementation CommandPacketCreator

+ (NSData *)dataFrom:(CommanderPacket) packet {
    NSData *data = [NSData dataWithBytes:&packet length:sizeof(CommanderPacket)];
    //NSLog(@"%@", data);
    //30000000 00000000 80000000 000000 -> Default data package without any input
    return data;
}

@end

@implementation TakeoffPacketCreator

+ (NSData *)dataFrom:(TakeoffPacket) packet {
    NSData *data = [NSData dataWithBytes:&packet length:sizeof(TakeoffPacket)];
    return data;
}

@end

@implementation LandPacketCreator

+ (NSData *)dataFrom:(LandPacket) packet {
    NSData *data = [NSData dataWithBytes:&packet length:sizeof(LandPacket)];
    return data;
}

@end

@implementation StopPacketCreator

+ (NSData *)dataFrom:(StopPacket) packet {
    NSData *data = [NSData dataWithBytes:&packet length:sizeof(StopPacket)];
    return data;
}

@end

@implementation GoToPacketCreator

+ (NSData *)dataFrom:(GoToPacket) packet {
    NSData *data = [NSData dataWithBytes:&packet length:sizeof(GoToPacket)];
    return data;
}

@end

@implementation GenericSetpointPacketCreator

+ (NSData *)dataWith:(uint8_t)command payload:(NSData *)data {
    NSMutableData *packetData = [NSMutableData dataWithBytes:&command length:sizeof(uint8_t)];

    if (data) {
        [packetData appendData:data];
    }

    return packetData;
}

@end
