/*
 *  Layout.mm
 *  MachOView
 *
 *  Created by psaghelyi on 18/03/2011.
 *
 */

// 公共宏与全局声明
#import "Common.h"
// 临时目录等文档相关
#import "Document.h"
// 数据控制器与节点定义
#import "DataController.h"
#import "Layout.h"

//============================================================================
// MVLayout：布局基类实现，初始化时创建 archiver 与后台线程，提供 imageAt:、createDataNode、findNodeByUserInfo 等
//============================================================================
@implementation MVLayout

// 为只读属性生成 dataController、backgroundThread、archiver 的 getter
@synthesize dataController, backgroundThread, archiver;

/*
- (void)dealloc
{
  NSLog(@"********MVLayout deallocated: %@", self);
}
*/

//-----------------------------------------------------------------------------
// 指定初始化：绑定 dataController 与 rootNode，从 rootNode.dataRange 取 imageOffset/imageSize，创建后台线程与临时交换文件
- (instancetype)initWithDataController:(MVDataController *)dc rootNode:(MVNode *)node
{
    // 先调用父类初始化
    if (self = [super init]) {
        // 弱引用保存数据控制器与根节点
        dataController = dc;
        rootNode = node;
        // 从根节点区间取本布局的镜像偏移与长度
        imageOffset = node.dataRange.location;
        imageSize = node.dataRange.length;
        // 创建后台线程，入口为 doBackgroundTasks
        backgroundThread = [[NSThread alloc] initWithTarget:self selector:@selector(doBackgroundTasks) object:nil];

        // 取临时目录 C 字符串用于 mkstemp
        const char *tmp = [[MVDocument temporaryDirectory] UTF8String];
        char *swapFilePath = strdup(tmp);
        // 创建临时交换文件，失败则释放路径并返回 nil
        if (mkstemp(swapFilePath) == -1) {
            NSLog(@"mkstemp failed!");
            free(swapFilePath);
            return nil;
        }

        // 交换文件路径：临时文件路径 + 原文件名扩展名，便于识别
        NSString *swapPath = [NSString stringWithFormat:@"%s.%@", swapFilePath, [[dataController fileName] lastPathComponent]];
        free(swapFilePath);
        // 用该路径创建 archiver，供节点详情延迟写入
        archiver = [MVArchiver archiverWithPath:swapPath];
    }
    return self;
}

//-----------------------------------------------------------------------------
// 返回 realData 中 location 处的只读指针；location 为相对当前镜像的偏移，基类用 dataController.realData 计算
- (void const *)imageAt:(uint64_t)location
{
  // 取 realData 基址，location 为相对当前镜像的偏移
  auto p = (uint8_t const *)[dataController.realData bytes];
  // 基址有效则返回基址+偏移，否则返回 NULL
  return p ? p + location : NULL;
}

//-----------------------------------------------------------------------------
// 调试描述：在父类描述后追加 [rootNode.caption]
- (NSString *)description
{
  // 在父类描述后追加根节点标题，便于调试区分不同 layout
  return [[super description] stringByAppendingFormat:@" [%@]",rootNode.caption];
}

//-----------------------------------------------------------------------------
// 在 @synchronized([NSApp class]) 下打印异常名称、原因、userInfo 与调用栈
-(void)printException:(NSException *)exception caption:(NSString *)caption
{
  // 使用 NSApp 类对象做锁，避免多 layout 并发打印交错
  @synchronized([NSApp class])
  {
    NSLog(@"%@: Exception (%@): %@", self, caption, [exception name]);
    NSLog(@"  Reason: %@", [exception reason]);
    NSLog(@"  User Info: %@", [exception userInfo]);
    NSLog(@"  Backtrace:\n%@", [exception callStackSymbols]);
  }
}

//-----------------------------------------------------------------------------
// 基类默认返回 NO；MachOLayout 根据 mach_header 的 cputype 判断
- (BOOL)is64bit
{
  // 基类默认非 64 位；MachOLayout 根据 mach_header 覆盖
  return NO;
}

//-----------------------------------------------------------------------------
// 主线程任务；基类空实现，子类可覆盖
- (void)doMainTasks
{
}

//-----------------------------------------------------------------------------
// 后台线程入口；基类仅停止 archiver，子类在解析完成后调用以释放资源
- (void)doBackgroundTasks
{
  // 基类仅停止 archiver；子类在解析完成后调用 [super doBackgroundTasks]
  [archiver halt];
}

//-----------------------------------------------------------------------------
// 将偏移字符串转为 RVA；基类返回空串，子类可覆盖（如 MachOLayout 根据 segment 计算）
- (NSString *)convertToRVA: (NSString *)offsetStr
{
  // 基类不做转换，返回空串；MachOLayout 等可覆盖
  return @"";
}

//-----------------------------------------------------------------------------
// 持 treeLock 后在 rootNode 子树中递归查找 userInfo 匹配的节点
//-----------------------------------------------------------------------------
- (MVNode *)findNodeByUserInfo:(NSDictionary *)userInfo
{
  // 持树锁后递归查找，避免遍历时树被修改
  [dataController.treeLock lock];
  MVNode * node = [rootNode findNodeByUserInfo:userInfo];
  [dataController.treeLock unlock];

  return node;
}

//-----------------------------------------------------------------------------
// 创建无详情表的数据节点：仅调用 parent 的 insertChild:location:length:，用于仅显示十六进制等内容
//-----------------------------------------------------------------------------
- (MVNode *)createDataNode:(MVNode *)parent
                   caption:(NSString *)caption
                  location:(uint64_t)location
                    length:(uint64_t)length
{
  // 调用父节点的 insertChild，生成无详情表的数据节点
  MVNode * node = [parent insertChild:caption location:location length:length];
  return node;
}

@end
