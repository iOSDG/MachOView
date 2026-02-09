/*
 *  ReadWrite.h
 *  MachOView
 *
 *  Created by psaghelyi on 20/07/2010.
 *
 */

// 引入 DataController，本 Category 将扩展 MVDataController 的读写能力
#import "DataController.h"
// 声明 MVDataController 的 ReadWrite Category：从 fileData/realData 按 NSRange 读写各类整数、字符串、LEB128 等
@interface MVDataController (ReadWrite)

// 从 range 起始处读 1 字节无符号整数，读后 range 推进；lastReadHex 可选返回该字节的十六进制字符串（用于详情表 Data 列）
- (uint8_t)     read_uint8:(NSRange &)range;
// 读 2 字节无符号整数（当前未做字节序交换，依赖文件原生序）
- (uint16_t)    read_uint16:(NSRange &)range;
// 读 4 字节无符号整数
- (uint32_t)    read_uint32:(NSRange &)range;
// 读 8 字节无符号整数
- (uint64_t)    read_uint64:(NSRange &)range;
// 读 1 字节有符号整数
- (int8_t)      read_int8:(NSRange &)range;
// 读 2 字节有符号整数
- (int16_t)     read_int16:(NSRange &)range;
// 读 4 字节有符号整数
- (int32_t)     read_int32:(NSRange &)range;
// 读 8 字节有符号整数
- (int64_t)     read_int64:(NSRange &)range;

// 同上 read_uint8，并通过 lastReadHex 输出该字节的十六进制串
- (uint8_t)     read_uint8:(NSRange &)range   lastReadHex:(NSString * __autoreleasing *)lastReadHex;
- (uint16_t)    read_uint16:(NSRange &)range  lastReadHex:(NSString * __autoreleasing *)lastReadHex;
- (uint32_t)    read_uint32:(NSRange &)range  lastReadHex:(NSString * __autoreleasing *)lastReadHex;
- (uint64_t)    read_uint64:(NSRange &)range  lastReadHex:(NSString * __autoreleasing *)lastReadHex;
- (int8_t)      read_int8:(NSRange &)range    lastReadHex:(NSString * __autoreleasing *)lastReadHex;
- (int16_t)     read_int16:(NSRange &)range   lastReadHex:(NSString * __autoreleasing *)lastReadHex;
- (int32_t)     read_int32:(NSRange &)range   lastReadHex:(NSString * __autoreleasing *)lastReadHex;
- (int64_t)     read_int64:(NSRange &)range   lastReadHex:(NSString * __autoreleasing *)lastReadHex;

// 从 range 起始处读以 \0 结尾的 C 字符串并转为 NSString，读后 range 推进
- (NSString *)  read_string:(NSRange &)range;
// 从 range 起始处读固定长度 len 的字节作为 C 字符串（补 \0），转为 NSString
- (NSString *)  read_string:(NSRange &)range  fixlen:(NSUInteger)len;
// 从 range 起始处读指定长度字节，返回 NSData
- (NSData *)    read_bytes:(NSRange &)range   length:(NSUInteger)length;
// 从 range 起始处读 SLEB128 变长整数，读后 range 推进
- (int64_t)     read_sleb128:(NSRange &)range;
// 从 range 起始处读 ULEB128 变长整数，读后 range 推进
- (uint64_t)    read_uleb128:(NSRange &)range;

// 同上 read_string，并通过 lastReadHex 输出该段字节的十六进制串
- (NSString *)  read_string:(NSRange &)range  lastReadHex:(NSString * __autoreleasing *)lastReadHex;
- (NSString *)  read_string:(NSRange &)range  fixlen:(NSUInteger)len lastReadHex:(NSString * __autoreleasing *)lastReadHex;
- (NSData *)    read_bytes:(NSRange &)range   length:(NSUInteger)length lastReadHex:(NSString * __autoreleasing *)lastReadHex;
- (int64_t)     read_sleb128:(NSRange &)range lastReadHex:(NSString * __autoreleasing *)lastReadHex;
- (uint64_t)    read_uleb128:(NSRange &)range lastReadHex:(NSString * __autoreleasing *)lastReadHex;

// 在指定位置写入 1 字节无符号整数（修改 fileData）
- (void)        write_uint8:(NSUInteger)location data:(uint8_t)data;
// 在指定位置写入 2 字节无符号整数
- (void)        write_uint16:(NSUInteger)location data:(uint16_t)data;
// 在指定位置写入 4 字节无符号整数
- (void)        write_uint32:(NSUInteger)location data:(uint32_t)data;
// 在指定位置写入 8 字节无符号整数
- (void)        write_uint64:(NSUInteger)location data:(uint64_t)data;
// 在指定位置写入 1 字节有符号整数
- (void)        write_int8:(NSUInteger)location data:(int8_t)data;
// 在指定位置写入 2 字节有符号整数
- (void)        write_int16:(NSUInteger)location data:(int16_t)data;
// 在指定位置写入 4 字节有符号整数
- (void)        write_int32:(NSUInteger)location data:(int32_t)data;
// 在指定位置写入 8 字节有符号整数
- (void)        write_int64:(NSUInteger)location data:(int64_t)data;
// 在指定位置写入字符串（当前实现中 assert(false)，未实现）
- (void)        write_string:(NSUInteger)location data:(NSString *)data;
// 在指定位置写入 NSData 字节（当前实现中 assert(false)，未实现）
- (void)        write_bytes:(NSUInteger)location data:(NSData *)data;
// 在指定位置写入 SLEB128（当前实现中 assert(false)，未实现）
- (void)        write_sleb128:(NSUInteger)location data:(int64_t)data;
// 在指定位置写入 ULEB128（当前实现中 assert(false)，未实现）
- (void)        write_uleb128:(NSUInteger)location data:(uint64_t)data;

@end
