/*
 *  Layout.h
 *  MachOView
 *
 *  Created by psaghelyi on 18/03/2011.
 *
 */

// 宏：从当前 layout 的 imageAt:location 取得 struct obj 指针，若为空则抛异常；用于子类安全访问二进制中的结构体
#define MATCH_STRUCT(obj,location) \
  struct obj const * obj = (struct obj *)[self imageAt:(location)]; \
  if (!obj) [NSException raise:@"null exception" format:@#obj " is null"];

// 前向声明：数据控制器，Layout 通过其访问 fileData/realData 与树
@class MVDataController;
// 前向声明：交换文件管理，用于节点详情的延迟写入
@class MVArchiver;
// 前向声明：树节点，Layout 持有 rootNode 并为其创建子节点
@class MVNode;


// 布局基类：所有二进制布局（MachOLayout、FatLayout、ArchiveLayout）的父类，提供 imageAt:、后台解析、创建数据节点等
@interface MVLayout : NSObject
{
  // 根节点弱引用，对应左侧树根，其 dataRange 表示本布局在文件中的区间
  MVNode *              __weak rootNode;
  // 数据控制器弱引用，用于 imageAt: 访问 realData、createLayouts 等
  MVDataController *    __weak dataController;
  // 本布局对应的镜像在二进制中的绝对物理偏移（与 rootNode.dataRange.location 一致）
  uint64_t              imageOffset;  // absolute physical offset of the image in binary
  // 本布局对应的镜像长度（与 rootNode.dataRange.length 一致）
  uint64_t              imageSize;    // size of the image corresponds to this layout
  // 后台解析线程，执行 doBackgroundTasks，避免阻塞主线程
  NSThread *            backgroundThread;
  // 交换文件管理实例，供有详情表的节点写入 MVRow 等
  MVArchiver *          archiver;
}

// 只读属性：数据控制器
@property(nonatomic,weak,readonly)  MVDataController * dataController;
// 只读属性：后台线程
@property(nonatomic,readonly) NSThread * backgroundThread;
// 只读属性：交换文件管理
@property(nonatomic,readonly) MVArchiver * archiver;

// 禁止无参初始化，必须使用 initWithDataController:rootNode:
- (instancetype)        init NS_UNAVAILABLE;
// 指定初始化：绑定 dataController 与 rootNode，并创建 archiver、启动后台线程
- (instancetype)        initWithDataController:(MVDataController *)dc rootNode:(MVNode *)node NS_DESIGNATED_INITIALIZER;
// 返回 realData 中 location 处的只读指针，location 为相对当前镜像的偏移；子类用此读取二进制
- (void const *)        imageAt:(uint64_t)location NS_RETURNS_INNER_POINTER;
// 统一打印异常信息（名称、原因、userInfo、调用栈），便于调试
- (void)                printException:(NSException *)exception caption:(NSString *)caption;
// 是否 64 位架构；基类默认 NO，MachOLayout 根据 mach_header 返回
- (BOOL)                is64bit;
// 主线程任务，在布局创建后调用；基类空实现，子类可覆盖（如更新 UI）
- (void)                doMainTasks;
// 后台线程入口，解析二进制并填充树；基类仅调用 [archiver halt]，子类先解析再调 [super doBackgroundTasks]
- (void)                doBackgroundTasks;
// 将文件偏移字符串转为 RVA 字符串；基类返回空串，子类可覆盖
- (NSString *)          convertToRVA: (NSString *)offsetStr;
// 在 rootNode 子树中按 userInfo 查找节点，查找时持 treeLock
- (MVNode *)            findNodeByUserInfo:(NSDictionary *)userInfo;

// 创建无详情表的数据节点（仅标题与区间），用于仅显示十六进制等简单内容
- (MVNode *)            createDataNode:(MVNode *)parent
                               caption:(NSString *)caption
                              location:(uint64_t)location
                                length:(uint64_t)length;

@end
