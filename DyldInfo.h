/*
 *  DyldInfo.h
 *  MachOView
 *
 *  Created by psaghelyi on 21/09/2010.
 *
 */

// 引入 MachOLayout 头文件，MachOLayout (DyldInfo) 将作为其 Category
#import "MachOLayout.h"


// DyldHelper 类：辅助处理 Dyld 信息，主要用于管理外部符号映射
@interface DyldHelper : NSObject
{
  // 外部符号映射表：key 为符号名，value 为符号索引（负数表示外部）
  NSMutableDictionary * externalMap; // external symbol name --> symbols index (negative number)
}

// 工厂方法：根据符号表字典和是否 64 位创建 DyldHelper 实例
+(DyldHelper *) dyldHelperWithSymbols:(NSDictionary *)symbolNames is64Bit:(bool)is64Bit;

@end


// MachOLayout 的分类 (DyldInfo)：扩展 MachOLayout 以支持 Rebase、Binding 和 Export 信息的解析
@interface MachOLayout (DyldInfo)

// 绑定节点类型枚举：普通绑定、弱绑定、延迟绑定
enum BindNodeType {NodeTypeBind, NodeTypeWeakBind, NodeTypeLazyBind};

// 创建重定位（Rebase）信息节点
- (MVNode *)createRebaseNode:(MVNode *)parent
                     caption:(NSString *)caption
                    location:(uint64_t)location
                      length:(uint64_t)length
                 baseAddress:(uint64_t)baseAddress;

// 创建绑定（Binding）信息节点
- (MVNode *)createBindingNode:(MVNode *)parent
                      caption:(NSString *)caption
                     location:(uint64_t)location
                       length:(uint64_t)length
                  baseAddress:(uint64_t)baseAddress
                     nodeType:(BindNodeType)nodeType
                   dyldHelper:(DyldHelper *)helper;

// 创建导出（Export）符号信息节点
- (MVNode *)createExportNode:(MVNode *)parent
                     caption:(NSString *)caption
                    location:(uint64_t)location
                      length:(uint64_t)length
                 baseAddress:(uint64_t)baseAddress;

@end
