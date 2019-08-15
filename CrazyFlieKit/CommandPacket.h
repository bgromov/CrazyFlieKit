//
//  DataStruct.m
//  Crazyflie client
//
//  Created by Martin Eberl on 12.02.17.
//  Copyright © 2017 Bitcraze. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef struct __attribute__((packed)) {
    uint8_t channel: 2;
    uint8_t link: 2;
    uint8_t port: 4;
} CrtpPacketHeader;

typedef struct __attribute((packed)) {
    CrtpPacketHeader header;
    __unsafe_unretained NSData* payload;
} CrtpPacket;

typedef struct __attribute((packed)) {
    uint8_t messageId;
    __unsafe_unretained NSData* payload;
} ParamTocPacket;

typedef struct __attribute__((packed)) {
    uint16_t paramCount;
    uint32_t crc32;
} ParamTocInfoResponse;

typedef struct __attribute__((packed)) {
    uint16_t paramId;

    union {
        uint8_t metadata;
        struct {
            uint8_t type: 4;
            uint8_t _reserved0: 2;
            uint8_t readonly: 1;
            uint8_t group: 1;
        };
    };
    char name[26];
} ParamTocItemResponse;

typedef struct __attribute((packed)) {
    uint8_t command;
    __unsafe_unretained NSData* payload;
} LogTocPacket;

typedef struct __attribute__((packed)) {
    uint16_t varCount;
    uint32_t crc32;
    uint8_t maxPackets;
    uint8_t maxOps;
} LogTocInfoResponse;

typedef struct __attribute__((packed)) {
    uint16_t varId;
} LogTocItemRequest;

typedef struct __attribute__((packed)) {
    LogTocItemRequest request;
    
    uint8_t type;
    char name[26];
} LogTocItemResponse;

typedef struct __attribute__((packed)) {
    uint8_t command;
    uint8_t blockId;
    uint8_t result;
} LogControlResponse;

typedef struct __attribute__((packed)) {
    uint8_t type;
    uint16_t varId;
} LogBlockItem;

typedef struct __attribute__((packed)) {
    uint8_t blockId;
    uint8_t timestampLo;
    uint16_t timestampHi;
} LogDataResponseHeader;


@interface CrtpPacketCreator: NSObject

+ (NSData *)dataFrom:(CrtpPacketHeader)header payload:(NSData *)data;
+ (CrtpPacket)crtpPacketFrom:(NSData *)data;

+ (NSData *)getCrtpHeaderFrom:(NSData *)data header:(CrtpPacketHeader *) header;

@end

@interface ParamTocPacketCreator: NSObject

+ (NSData *)dataFrom:(uint8_t)messageId payload:(NSData *)data;
+ (ParamTocPacket)paramTocPacketFrom:(NSData *)data;

+ (ParamTocInfoResponse)paramTocInfoResponseFrom: (NSData *)response;
+ (ParamTocItemResponse)paramTocItemResponseFrom: (NSData *)response;

+ (NSData *)getMessageIdFrom:(NSData *)data messageId:(uint8_t *) messageId;

@end

@interface ParamPacketCreator: NSObject

+ (NSData *)dataFrom:(uint16_t)paramId payload:(NSData *)data;
+ (NSData *)parseReadPacketFrom:(NSData *)data paramId:(uint16_t *) paramId;
+ (NSData *)parseWritePacketFrom:(NSData *)data paramId:(uint16_t *) paramId;

@end

@interface LogTocPacketCreator: NSObject

+ (NSData *)dataFrom:(uint8_t)command payload:(NSData *)data;
+ (LogTocPacket)logTocPacketFrom:(NSData *)data;

+ (LogTocInfoResponse)logTocInfoResponseFrom: (NSData *)response;
+ (LogTocItemResponse)logTocItemResponseFrom: (NSData *)response;

+ (NSData *)getCommandFrom:(NSData *)data command:(uint8_t *) command
NS_SWIFT_NAME(getCommand(from:command:));

@end

@interface LogBlockPacketCreator: NSObject

+ (NSData *)dataWith:(uint8_t)blockId vars:(NSArray*)items payload:(NSData *)data;

@end

@interface LogControlPacketCreator: NSObject

+ (NSData *)dataWith:(uint8_t)command payload:(NSData *)data;
+ (LogControlResponse)logControlFrom:(NSData *)data;

@end

@interface LogDataPacketCreator: NSObject

+ (NSData *)logDataFrom:(NSData *)data to:(LogDataResponseHeader*)header;


@end


typedef struct __attribute__((packed)) {
    float x;
    float y;
    float z;
    float yaw;
} PositionSetpointPacket;



typedef struct __attribute__((packed)) {
    uint8_t header;
    float roll;
    float pitch;
    float yaw;
    uint16_t thrust;
} CommanderPacket;

typedef struct __attribute__((packed)) {
    uint8_t header;
    uint8_t command;
    uint8_t groupMask;
    float height;
    float duration;
} TakeoffPacket;

typedef struct __attribute__((packed)) {
    uint8_t header;
    uint8_t command;
    uint8_t groupMask;
    float height;
    float duration;
} LandPacket;

typedef struct __attribute__((packed)) {
    uint8_t header;
    uint8_t command;
    uint8_t groupMask;
} StopPacket;

typedef struct __attribute__((packed)) {
    uint8_t header;
    uint8_t command;
    uint8_t groupMask;
    uint8_t relative;
    float x;
    float y;
    float z;
    float yaw;
    float duration;
} GoToPacket;

@interface CommandPacketCreator : NSObject

+ (NSData *)dataFrom:(CommanderPacket) packet;

@end

@interface TakeoffPacketCreator : NSObject

+ (NSData *)dataFrom:(TakeoffPacket) packet;

@end

@interface LandPacketCreator : NSObject

+ (NSData *)dataFrom:(LandPacket) packet;

@end

@interface StopPacketCreator : NSObject

+ (NSData *)dataFrom:(StopPacket) packet;

@end

@interface GoToPacketCreator : NSObject

+ (NSData *)dataFrom:(GoToPacket) packet;

@end


@interface GenericSetpointPacketCreator : NSObject

+ (NSData *)dataWith:(uint8_t)command payload:(NSData *)data;

@end
