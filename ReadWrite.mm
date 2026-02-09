/*
 *  ReadWrite.mm
 *  MachOView
 *
 *  Created by psaghelyi on 20/07/2010.
 *
 */

#include <string>
#include <vector>
#include <set>
#include <map>

#import "Common.h"
#import "ReadWrite.h"
#import "DataController.h"

//============================================================================
// MVDataController (ReadWrite)：从 fileData/realData 按 NSRange 读写整数、字符串、LEB128，range 读后自动推进
//============================================================================
@implementation MVDataController (ReadWrite)

//-----------------------------------------------------------------------------
// 读 1 字节无符号整数；range 更新为本次读取的区间，lastReadHex 可选返回该字节十六进制串；最终从 realData 取数返回（若 realData 已修补）
- (uint8_t)read_uint8:(NSRange &)range lastReadHex:(NSString **)lastReadHex
{
  uint8_t buffer;
  range = NSMakeRange(NSMaxRange(range),sizeof(uint8_t));
  [fileData getBytes:&buffer range:range];
  if (lastReadHex) *lastReadHex = [NSString stringWithFormat:@"%.2X",(0xFF & buffer)];
  [realData getBytes:&buffer range:range];
  return buffer;
}

//-----------------------------------------------------------------------------
// 读 2 字节无符号整数，lastReadHex 为 4 位十六进制
- (uint16_t)read_uint16:(NSRange &)range lastReadHex:(NSString **)lastReadHex
{
  uint16_t buffer;
  range = NSMakeRange(NSMaxRange(range),sizeof(uint16_t));
  [fileData getBytes:&buffer range:range];
  if (lastReadHex) *lastReadHex = [NSString stringWithFormat:@"%.4X",(0xFFFF & buffer)];
  [realData getBytes:&buffer range:range];
  return buffer;
}

//-----------------------------------------------------------------------------
// 读 4 字节无符号整数，lastReadHex 为 8 位十六进制
- (uint32_t)read_uint32:(NSRange &)range lastReadHex:(NSString **)lastReadHex
{
  uint32_t buffer;
  range = NSMakeRange(NSMaxRange(range),sizeof(uint32_t));
  [fileData getBytes:&buffer range:range];
  if (lastReadHex) *lastReadHex = [NSString stringWithFormat:@"%.8X",buffer];
  [realData getBytes:&buffer range:range];
  return buffer;
}

//-----------------------------------------------------------------------------
// 读 8 字节无符号整数，lastReadHex 为 16 位十六进制
- (uint64_t)read_uint64:(NSRange &)range lastReadHex:(NSString **)lastReadHex
{
  uint64_t buffer;
  range = NSMakeRange(NSMaxRange(range),sizeof(uint64_t));
  [fileData getBytes:&buffer range:range];
  if (lastReadHex) *lastReadHex = [NSString stringWithFormat:@"%.16qX",buffer];
  [realData getBytes:&buffer range:range];
  return buffer;
}

//-----------------------------------------------------------------------------
// 读 1 字节有符号整数
- (int8_t)read_int8:(NSRange &)range lastReadHex:(NSString **)lastReadHex
{
  int8_t buffer;
  range = NSMakeRange(NSMaxRange(range),sizeof(int8_t));
  [fileData getBytes:&buffer range:range];
  if (lastReadHex) *lastReadHex = [NSString stringWithFormat:@"%.2X",(0xFF & buffer)];
  [realData getBytes:&buffer range:range];
  return buffer;
}

//-----------------------------------------------------------------------------
// 读 2 字节有符号整数
- (int16_t)read_int16:(NSRange &)range lastReadHex:(NSString **)lastReadHex
{
  int16_t buffer;
  range = NSMakeRange(NSMaxRange(range),sizeof(int16_t));
  [fileData getBytes:&buffer range:range];
  if (lastReadHex) *lastReadHex = [NSString stringWithFormat:@"%.4X",(0xFFFF & buffer)];
  [realData getBytes:&buffer range:range];
  return buffer;
}

//-----------------------------------------------------------------------------
// 读 4 字节有符号整数
- (int32_t)read_int32:(NSRange &)range lastReadHex:(NSString **)lastReadHex
{
  int32_t buffer;
  range = NSMakeRange(NSMaxRange(range),sizeof(int32_t));
  [fileData getBytes:&buffer range:range];
  if (lastReadHex) *lastReadHex = [NSString stringWithFormat:@"%.8X",buffer];
  [realData getBytes:&buffer range:range];
  return buffer;
}

//-----------------------------------------------------------------------------
// 读 8 字节有符号整数
- (int64_t)read_int64:(NSRange &)range lastReadHex:(NSString **)lastReadHex
{
  int64_t buffer;
  range = NSMakeRange(NSMaxRange(range),sizeof(int64_t));
  [fileData getBytes:&buffer range:range];
  if (lastReadHex) *lastReadHex = [NSString stringWithFormat:@"%.16qX",buffer];
  [realData getBytes:&buffer range:range];
  return buffer;
}

//-----------------------------------------------------------------------------
// 将 range 所指的字节转为十六进制字符串（每字节两位），用于详情表 Data 列显示
- (NSString *)getHexStr:(NSRange &)range
{
  NSMutableString * lastReadHex = [NSMutableString stringWithCapacity:2*range.length];
  for (NSUInteger i = 0; i < range.length; ++i)
  {
    int value = *((uint8_t *)[fileData bytes] + range.location + i);
    [lastReadHex appendFormat:@"%.2X",value];
  }
  return lastReadHex;
}

//-----------------------------------------------------------------------------
// 将字符串中的不可见字符转成转义形式（\n \t \r 等），便于在界面中显示
- (NSString *) replaceEscapeCharsInString: (NSString *)orig
{
  NSUInteger len = [orig length];
  NSMutableString * str = [[NSMutableString alloc] init];
  SEL sel = @selector(characterAtIndex:);
  unichar (*charAtIdx)(id, SEL, NSUInteger) = (typeof(charAtIdx)) [orig methodForSelector:sel];
  for (NSUInteger i = 0; i < len; i++)
  {
    unichar c = charAtIdx(orig, sel, i);
    switch (c)
    {
      default:    [str appendFormat:@"%C",c]; break;
      case L'\f': [str appendString:@"\\f"]; break; // form feed - new page (byte 0x0c)
      case L'\n': [str appendString:@"\\n"]; break; // line feed - new line (byte 0x0a)
      case L'\r': [str appendString:@"\\r"]; break; // carriage return (byte 0x0d)
      case L'\t': [str appendString:@"\\t"]; break; // horizontal tab (byte 0x09)
      case L'\v': [str appendString:@"\\v"]; break; // vertical tab (byte 0x0b)
    }
  }
  return str;
}

//-----------------------------------------------------------------------------
// 从 range 当前末端起读以 \0 结尾的 C 字符串，range 更新为读过的区间，lastReadHex 可选为整段十六进制
- (NSString *)read_string:(NSRange &)range lastReadHex:(NSString **)lastReadHex
{
  range.location = NSMaxRange(range);
  NSString * str = NSSTRING((uint8_t *)[fileData bytes] + range.location);
  range.length = [str length] + 1;
  if (lastReadHex) *lastReadHex = [self getHexStr:range];
  return [self replaceEscapeCharsInString:str];
}

//-----------------------------------------------------------------------------
// 从 range 当前末端起读固定长度 len 的字节（补 \0）转为 NSString
- (NSString *)read_string:(NSRange &)range fixlen:(NSUInteger)len lastReadHex:(NSString **)lastReadHex
{
  range = NSMakeRange(NSMaxRange(range),len);
  uint8_t * buffer = (uint8_t *)malloc(len + 1); buffer[len] = '\0';
  [fileData getBytes:buffer range:range];
  if (lastReadHex) *lastReadHex = [self getHexStr:range];
  NSString * str = NSSTRING(buffer);
  free (buffer);
  return [self replaceEscapeCharsInString:str];
}

//-----------------------------------------------------------------------------
// 从 range 当前末端起读 length 字节，返回 NSData，lastReadHex 可选为整段十六进制
- (NSData *)read_bytes:(NSRange &)range length:(NSUInteger)length lastReadHex:(NSString **)lastReadHex
{
  range = NSMakeRange(NSMaxRange(range),length);
  uint8_t * buffer = (uint8_t *)malloc(length);
  [fileData getBytes:buffer range:range];
  if (lastReadHex) *lastReadHex = [self getHexStr:range];
  NSData * ret = [NSData dataWithBytes:buffer length:length];
  free (buffer);
  return ret;
}

//-----------------------------------------------------------------------------
// 从 range 当前末端起解析 SLEB128 变长有符号整数，range 更新为读过的字节，lastReadHex 可选为这段十六进制
- (int64_t)read_sleb128:(NSRange &)range lastReadHex:(NSString **)lastReadHex
{
  range.location = NSMaxRange(range);
  uint8_t * p = (uint8_t *)[fileData bytes] + range.location, *start = p;

  int64_t result = 0;
  int bit = 0;
  uint8_t byte;

  do {
    byte = *p++;
    result |= ((byte & 0x7f) << bit);
    bit += 7;
  } while (byte & 0x80);

  if ( (byte & 0x40) != 0 )
  {
    result |= (-1LL) << bit;
  }

  range.length = (p - start);
  if (lastReadHex) *lastReadHex = [self getHexStr:range];
  return result;
}

// ----------------------------------------------------------------------------
// 从 range 当前末端起解析 ULEB128 变长无符号整数，溢出或超 64 位抛异常
- (uint64_t)read_uleb128:(NSRange &)range lastReadHex:(NSString **)lastReadHex
{
  range.location = NSMaxRange(range);
  uint8_t * p = (uint8_t *)[fileData bytes] + range.location, *start = p;

  uint64_t result = 0;
  int bit = 0;

  do {
    uint64_t slice = *p & 0x7f;

    if (bit >= 64 || slice << bit >> bit != slice)
      [NSException raise:@"uleb128 error" format:@"uleb128 too big"];
    else {
      result |= (slice << bit);
      bit += 7;
    }
  }
  while (*p++ & 0x80);

  range.length = (p - start);
  if (lastReadHex) *lastReadHex = [self getHexStr:range];
  return result;
}

// ----------------------------------------------------------------------------
// 在指定位置写入 1 字节无符号整数到 fileData
- (void) write_uint8:(NSUInteger)location data:(uint8_t)data
{
  [fileData replaceBytesInRange:NSMakeRange(location,sizeof(uint8_t))
                                     withBytes:&data];
}

// ----------------------------------------------------------------------------
// 在指定位置写入 2 字节无符号整数
- (void) write_uint16:(NSUInteger)location data:(uint16_t)data
{
  [fileData replaceBytesInRange:NSMakeRange(location,sizeof(uint16_t))
                                     withBytes:&data];
}

// ----------------------------------------------------------------------------
// 在指定位置写入 4 字节无符号整数
- (void) write_uint32:(NSUInteger)location data:(uint32_t)data
{
  [fileData replaceBytesInRange:NSMakeRange(location,sizeof(uint32_t))
                                     withBytes:&data];
}

// ----------------------------------------------------------------------------
// 在指定位置写入 8 字节无符号整数
- (void) write_uint64:(NSUInteger)location data:(uint64_t)data
{
  [fileData replaceBytesInRange:NSMakeRange(location,sizeof(uint64_t))
                                     withBytes:&data];
}

// ----------------------------------------------------------------------------
// 在指定位置写入 1 字节有符号整数
- (void) write_int8:(NSUInteger)location data:(int8_t)data
{
  [fileData replaceBytesInRange:NSMakeRange(location,sizeof(int8_t))
                                     withBytes:&data];
}

// ----------------------------------------------------------------------------
// 在指定位置写入 2 字节有符号整数
- (void) write_int16:(NSUInteger)location data:(int16_t)data
{
  [fileData replaceBytesInRange:NSMakeRange(location,sizeof(int16_t))
                                     withBytes:&data];
}

// ----------------------------------------------------------------------------
// 在指定位置写入 4 字节有符号整数
- (void) write_int32:(NSUInteger)location data:(int32_t)data
{
  [fileData replaceBytesInRange:NSMakeRange(location,sizeof(int32_t))
                                     withBytes:&data];
}

// ----------------------------------------------------------------------------
// 在指定位置写入 8 字节有符号整数
- (void) write_int64:(NSUInteger)location data:(int64_t)data
{
  [fileData replaceBytesInRange:NSMakeRange(location,sizeof(int64_t))
                                     withBytes:&data];
}

// ----------------------------------------------------------------------------
// 在指定位置写入字符串（当前未实现，会 assert）
- (void) write_string:(NSUInteger)location data:(NSString *)data
{
  assert(false);
}

// ----------------------------------------------------------------------------
// 在指定位置写入 NSData（当前未实现，会 assert）
- (void) write_bytes:(NSUInteger)location data:(NSData *)data
{
  assert(false);
}

// ----------------------------------------------------------------------------
// 在指定位置写入 SLEB128（当前未实现，会 assert）
- (void) write_sleb128:(NSUInteger)location data:(int64_t)data
{
  assert(false);
  /*
   uint8_t * 
   writeSLEB128(uint8_t *p, int64_t value)
   {
    bool isNeg = ( value < 0 );
    uint8_t byte;
    bool more;
    do {
      byte = value & 0x7F;
      value = value >> 7;
      if ( isNeg ) 
        more = ( (value != -1) || ((byte & 0x40) == 0) );
      else
        more = ( (value != 0) || ((byte & 0x40) != 0) );
      if ( more )
        byte |= 0x80;
      *(p++) = byte;
    } 
    while( more );
    return p;
   }
   */
}

// ----------------------------------------------------------------------------
// 在指定位置写入 ULEB128（当前未实现，会 assert）
- (void) write_uleb128:(NSUInteger)location data:(uint64_t)data
{
  assert(false);
  /*
   uint8_t *
   writeULEB128 (uint8_t *p, uint64_t value)
   {
    uint8_t byte;
    do {
      byte = value & 0x7F;
      value &= ~0x7F;
      if ( value != 0 )
        byte |= 0x80;
      *(p++) = byte;
      value = value >> 7;
    } while( byte >= 0x80 );
   return p;
   }
   */
}



// ----------------------------------------------------------------------------
// 无 lastReadHex 的重载：读 1 字节无符号整数
- (uint8_t)read_uint8:(NSRange &)range    { return [self read_uint8:range  lastReadHex:NULL]; }
- (uint16_t)read_uint16:(NSRange &)range  { return [self read_uint16:range lastReadHex:NULL]; }
- (uint32_t)read_uint32:(NSRange &)range  { return [self read_uint32:range lastReadHex:NULL]; }
- (uint64_t)read_uint64:(NSRange &)range  { return [self read_uint64:range lastReadHex:NULL]; }
- (int8_t)read_int8:(NSRange &)range      { return [self read_int8:range   lastReadHex:NULL]; }
- (int16_t)read_int16:(NSRange &)range    { return [self read_int16:range  lastReadHex:NULL]; }
- (int32_t)read_int32:(NSRange &)range    { return [self read_int32:range  lastReadHex:NULL]; }
- (int64_t)read_int64:(NSRange &)range    { return [self read_int64:range  lastReadHex:NULL]; }

// ----------------------------------------------------------------------------
// 无 lastReadHex 的重载：读字符串、定长字符串、字节、SLEB128、ULEB128
- (NSString *)  read_string:(NSRange &)range  { return [self read_string:range lastReadHex:NULL]; }
- (NSString *)  read_string:(NSRange &)range  fixlen:(NSUInteger)len   { return [self read_string:range fixlen:len lastReadHex:NULL]; }
- (NSData *)    read_bytes:(NSRange &)range   length:(NSUInteger)length  { return [self read_bytes:range length:length lastReadHex:NULL]; }
- (int64_t)     read_sleb128:(NSRange &)range  { return [self read_sleb128:range lastReadHex:NULL]; }
- (uint64_t)    read_uleb128:(NSRange &)range  { return [self read_uleb128:range lastReadHex:NULL]; }

@end
