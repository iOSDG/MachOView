/*
 *  ArchiveLayout.h
 *  MachOView
 *
 *  Created by psaghelyi on 18/03/2011.
 *
 */

// 引入基础布局类MVLayout的头文件，MVLayout提供了布局管理的基本功能
#import "Layout.h"

// 定义MVObjectInfo类，用于存储归档（Archive）文件中单个对象（如.o文件）的元数据信息
@interface MVObjectInfo : NSObject
{
  // 声明实例变量name，用于存储对象文件的名称（如 "foo.o"）
  NSString *    name;
  // 声明实例变量length，用于存储对象文件在归档中的字节长度
  uint64_t      length;
  // 声明弱引用实例变量layout，指向该对象所属的布局管理器，避免循环引用
  MVLayout *    __weak layout;
}

// 声明属性name，对应实例变量name，表示对象名称，具有原子性读写权限
@property (nonatomic)                   NSString *  name;
// 声明属性length，对应实例变量length，表示对象长度，具有原子性读写权限
@property (nonatomic)                   uint64_t    length;
// 声明属性layout，对应实例变量layout，弱引用指向关联的布局对象
@property (nonatomic,weak)  MVLayout *  layout;

@end

// 定义ArchiveLayout类，继承自MVLayout，专门用于处理静态库（Archive）文件的布局解析
@interface ArchiveLayout : MVLayout 
{
  // 声明字典objectInfoMap，以对象在文件中的偏移量（NSNumber）为Key，MVObjectInfo为Value，建立偏移到对象信息的映射
  NSMutableDictionary * objectInfoMap; // <(NSNumber)object offset,MVObjectInfo>
}

// 声明类方法layoutWithDataController:rootNode:，用于创建一个新的ArchiveLayout实例，并关联数据控制器和根节点
+ (ArchiveLayout *)     layoutWithDataController:(MVDataController *)dc rootNode:(MVNode *)node;

@end
