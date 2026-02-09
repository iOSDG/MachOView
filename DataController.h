/*
 *  DataController.h
 *  MachOView
 *
 *  Created by psaghelyi on 15/06/2010.
 *
 */

// 右侧详情表列索引：第 0 列，表示“偏移”（文件或 RVA 偏移的字符串显示）
#define OFFSET_COLUMN       0
// 右侧详情表列索引：第 1 列，表示“数据”（十六进制等），在“有详情”模式下使用
#define DATA_COLUMN         1   // use this with details
// 右侧详情表列索引：第 2 列，表示“描述”（如字段含义说明）
#define DESCRIPTION_COLUMN  2   // use this with details
// 右侧详情表列索引：第 3 列，表示“值”（解析后的可读值）
#define VALUE_COLUMN        3

// 无详情模式下列索引：数据低字节部分对应列（此时表格列布局与有详情不同）
#define DATA_LO_COLUMN      1   // use this with no details
// 无详情模式下列索引：数据高字节部分对应列
#define DATA_HI_COLUMN      2   // use this with no details

// 行属性键名常量：下划线，值为 @"YES" 时该行显示下划线（如分隔线）
extern NSString * const MVUnderlineAttributeName;
// 行属性键名常量：单元格背景色，值为 NSColor，用于高亮某一行
extern NSString * const MVCellColorAttributeName;
// 行属性键名常量：文字颜色，值为 NSColor
extern NSString * const MVTextColorAttributeName;
// 行属性键名常量：元数据字符串，用于搜索过滤时对整行做 contains 匹配
extern NSString * const MVMetaDataAttributeName;

// userInfo 字典键：存放当前 MVLayout 实例，供节点在插入子节点或访问 archiver 时获取所属 Layout
extern NSString * const MVLayoutUserInfoKey;
// userInfo 字典键：存放当前 MVNode 实例，在通知的 userInfo 中传递
extern NSString * const MVNodeUserInfoKey;
// userInfo 字典键：存放状态条文案（如“任务开始”“任务结束”），在 MVThreadStateChangedNotification 的 userInfo 中
extern NSString * const MVStatusUserInfoKey;

// 通知名：左侧树即将发生结构变化（如插入节点前发送，UI 可做批量更新准备）
extern NSString * const MVDataTreeWillChangeNotification;
// 通知名：左侧树结构变化已完成（如插入节点后发送）
extern NSString * const MVDataTreeDidChangeNotification;
// 通知名：树数据已更新，object 为 DataController，userInfo 中可带 MVNodeUserInfoKey 表示变更的节点
extern NSString * const MVDataTreeChangedNotification;
// 通知名：右侧详情表数据已更新，需刷新表格显示
extern NSString * const MVDataTableChangedNotification;
// 通知名：后台任务状态变化（如开始/结束），userInfo 中带 MVStatusUserInfoKey 为状态文案
extern NSString * const MVThreadStateChangedNotification;

// 状态文案常量：表示任务已开始（用于状态条或 userInfo）
extern NSString * const MVStatusTaskStarted;
// 状态文案常量：表示任务已结束
extern NSString * const MVStatusTaskTerminated;

// 前向声明：C++ 结构体，用于 insertChildWithDetails: 的 RAII；构造时记录节点，析构时将该节点加入对应 Layout 的 archiver 保存队列
struct MVNodeSaver;

// 协议：可序列化到交换文件的对象必须实现以下三个方法，MVRow、MVNode 等均实现此协议
@protocol MVSerializing <NSObject>
// 从已打开的交换文件 pFile 中按当前格式反序列化并填充自身（如 MVRow 按 columnsOffset/attributesOffset 读取）
- (void)loadFromFile:(FILE *)pFile;
// 将自身数据追加写入交换文件 pFile（如 MVRow 写入四列字符串与属性，并更新 columnsOffset/attributesOffset）
- (void)saveToFile:(FILE *)pFile;
// 释放已写入交换文件的内存（如 MVRow 将 columns 置 nil，在未 dirty 时也可将 attributes 置 nil），不删文件
- (void)clear;
@end

//----------------------------------------------------------------------------
// 类：表格一行的四列字符串容器，对应右侧表的一行中的 Offset / Data / Description / Value 四个单元格的显示文本
//----------------------------------------------------------------------------
@interface MVColumns : NSObject
{
  // 实例变量：第 0 列偏移的字符串（如 @"0x1000"）
  NSString *            offsetStr;
  // 实例变量：第 1 列数据的字符串（如十六进制或解析后的短文本）
  NSString *            dataStr;
  // 实例变量：第 2 列描述的字符串
  NSString *            descriptionStr;
  // 实例变量：第 3 列值的字符串
  NSString *            valueStr;
}

// 属性：偏移列字符串，供外部读写
@property (nonatomic)   NSString * offsetStr;
// 属性：数据列字符串
@property (nonatomic)   NSString * dataStr;
// 属性：描述列字符串
@property (nonatomic)   NSString * descriptionStr;
// 属性：值列字符串
@property (nonatomic)   NSString * valueStr;

// 类方法：用四列字符串创建并返回一个 MVColumns 实例，col0~col3 对应 offset/data/description/value
+(MVColumns *) columnsWithData:(NSString *)col0 :(NSString *)col1 :(NSString *)col2 :(NSString *)col3;

@end

//----------------------------------------------------------------------------
// 类：详情表中的一行，持有四列内容、属性字典、在交换文件中的偏移，支持延迟加载与脏标记，实现 MVSerializing
//----------------------------------------------------------------------------
@interface MVRow : NSObject <MVSerializing>
{
  // 实例变量：本行四列字符串，可能为 nil（已交换到磁盘时），按需从 columnsOffset 加载
  MVColumns *          columns;
  // 实例变量：行属性字典（键为 MVUnderlineAttributeName 等），控制下划线、颜色等显示
  NSDictionary *        attributes;
  // 实例变量：行在二进制中的逻辑偏移，用于排序及在交换文件索引中定位
  uint64_t              offset;             // for sorting if necessary
  // 实例变量：columns 在交换文件中的偏移，0 表示尚未写入，非 0 表示已写入可按需读取
  off_t                 columnsOffset;      // offset of columns
  // 实例变量：attributes 在交换文件中的偏移，0 表示无属性块
  off_t                 attributesOffset;   // offset of attribues
  // 实例变量：逻辑删除标记，为 YES 时 getRowToDisplay 等会视为无效行（如 popRow 置为 YES）
  BOOL                  deleted;
  // 实例变量：属性已修改未写回，为 YES 时下次 saveToFile 会写回 attributes 并更新 attributesOffset
  BOOL                  dirty;              // eg. attributes has changed
}

// 属性：行属性字典
@property (nonatomic)   NSDictionary * attributes;
// 属性：四列内容
@property (nonatomic)   MVColumns * columns;
// 属性：行偏移
@property (nonatomic)   uint64_t offset;
// 属性：是否已逻辑删除
@property (nonatomic)   BOOL deleted;
// 属性：是否脏（属性未写回）
@property (nonatomic)   BOOL dirty;

// 实例方法：根据列索引（OFFSET_COLUMN/DATA_COLUMN/DESCRIPTION_COLUMN/VALUE_COLUMN）返回对应列字符串，无则返回 nil
-(NSString *)columnAtIndex:(NSUInteger)index;

@end

// 前向声明：交换文件管理类，负责将 MVRow、MVNode 等延迟写入磁盘
@class MVArchiver;

//----------------------------------------------------------------------------
// 类：某个树节点对应的详情表，持有所有行、过滤后的显示行、交换文件句柄，由 MVArchiver 协调写入
//----------------------------------------------------------------------------
@interface MVTable : NSObject
{
  // 实例变量：所有详情行（MVRow*），行内容可能尚未加载而在交换文件中
  NSMutableArray *      rows;         // array of MVRow * (host of all the rows)
  // 实例变量：当前参与显示的行（经 filter 过滤后的子集），表格按此数组顺序显示
  NSMutableArray *      displayRows;  // array of MVRow * (rows filtered by search criteria)
  // 实例变量：弱引用，用于将新行或修改行加入保存队列
  MVArchiver *          __weak archiver;
  // 实例变量：打开交换文件时的 FILE*，用于 getRowToDisplay 时对行按需 loadFromFile
  FILE *                swapFile;
  // 实例变量：保护 rows 数组并发修改的锁（如 insertRowWithOffset 与 applyFilter）
  NSLock *              tableLock;
}

// 属性：交换文件句柄，打开详情时赋值，关闭时置 NULL
@property (nonatomic)   FILE * swapFile;

// 实例方法：返回当前应显示的行数（displayRows 的 count）
- (NSUInteger)          rowCountToDisplay;
// 实例方法：返回当前显示的第 rowIndex 行，若该行未加载则从 swapFile 按需 loadFromFile；若已删除则返回 nil
- (MVRow *)             getRowToDisplay:(NSUInteger)rowIndex;

// 实例方法：将最后一行标记为逻辑删除（deleted = YES）
- (void)                popRow;
// 实例方法：在末尾追加一行，四列由 col0~col3 指定，内部调用 insertRowWithOffset:0:...
- (void)                appendRow:(id)col0 :(id)col1 :(id)col2 :(id)col3;
// 实例方法：在指定偏移处插入一行，offset 用于排序，并将该行加入 archiver 保存队列
- (void)                insertRowWithOffset:(uint64_t)offset :(id)col0 :(id)col1 :(id)col2 :(id)col3;
// 实例方法：更新第 rowIndex 行第 colIndex 列的单元格内容为 object，并标记该行待保存
- (void)                updateCellContentTo:(id)object atRow:(NSUInteger)rowIndex andCol:(NSUInteger)colIndex;

// 实例方法：返回总行数（rows 的 count，含已删除）
- (NSUInteger)          rowCount;
// 实例方法：为最后一行设置属性，可变参数为 key1, value1, key2, value2, ... , nil
- (void)                setAttributes:(NSString *)firstArg, ... NS_REQUIRES_NIL_TERMINATION;
// 实例方法：为第 index 行设置属性，可变参数同上
- (void)                setAttributesForRowIndex:(NSUInteger)index :(NSString *)firstArg, ... NS_REQUIRES_NIL_TERMINATION;
// 实例方法：从第 index 行起至末尾，为每一行设置相同的属性字典（每行一份副本）
- (void)                setAttributesFromRowIndex:(NSUInteger)index :(NSString *)firstArg, ... NS_REQUIRES_NIL_TERMINATION;

@end

//----------------------------------------------------------------------------
// 类：左侧树的一个节点，有标题、父子关系、数据区间、可选的详情表（右侧表）、userInfo 携带 Layout 等，实现 MVSerializing
//----------------------------------------------------------------------------
@interface MVNode : NSObject <MVSerializing>
{
  // 实例变量：节点在树中显示的标题（如 "LC_SEGMENT"、"__TEXT"）
  NSString *            caption;
  // 实例变量：父节点弱引用，根节点的 parent 为 nil
  MVNode *              __weak parent;
  // 实例变量：子节点数组，按 dataRange.location 有序
  NSMutableArray *      children;
  // 实例变量：该节点在二进制中对应的区间 [location, length)，用于排序与展示
  NSRange               dataRange;
  // 实例变量：该节点的详情表（右侧表数据），可能已交换到磁盘，detailsOffset 非 0 时表示已写入
  MVTable *             details;
  // 实例变量：携带 MVLayoutUserInfoKey 等，用于从节点反查 Layout、或查找节点时匹配
  NSMutableDictionary * userInfo;
  // 实例变量：details 的索引区在交换文件中的偏移，0 表示尚未写入
  off_t                 detailsOffset;
}

// 属性：节点标题
@property (nonatomic)                   NSString *            caption;
// 属性：父节点
@property (nonatomic,weak)      MVNode *              parent;
// 属性：数据区间
@property (nonatomic)                   NSRange               dataRange;
// 属性：详情表
@property (nonatomic)                   MVTable *             details;
// 属性：userInfo 字典
@property (nonatomic)                   NSMutableDictionary * userInfo;
// 属性：详情在交换文件中的偏移
@property (nonatomic)                   off_t              detailsOffset;

// 实例方法：返回子节点个数
- (NSUInteger)          numberOfChildren;
// 实例方法：返回第 n 个子节点
- (MVNode *)            childAtIndex:(NSUInteger)n;
// 实例方法：创建并插入一个无详情表的子节点，标题与区间由参数指定，userInfo 继承自 self
- (MVNode *)            insertChild:(NSString *)_caption location:(uint64_t)location length:(uint64_t)length;
// 实例方法：创建并插入带详情表的子节点，saver 在析构时会把该节点加入 Layout 的 archiver 保存队列
- (MVNode *)            insertChildWithDetails:(NSString *)_caption location:(uint64_t)location length:(uint64_t)length saver:(MVNodeSaver &)saver;
// 实例方法：在子树中递归查找 userInfo 与 uinfo 完全相等的节点，用于从 userInfo 反查 MVNode
- (MVNode *)            findNodeByUserInfo:(NSDictionary *)uinfo;
// 实例方法：打开交换文件，若 details 已写入则从 detailsOffset 恢复 details，否则仅赋 swapFile
- (void)                openDetails;  // open swap file for reading details on demand
// 实例方法：关闭 details 的交换文件句柄
- (void)                closeDetails; // close swap file
// 实例方法：对 details 表按 offset 排序
- (void)                sortDetails;
// 实例方法：对 details 应用搜索过滤（filter 为空则显示全部）
- (void)                filterDetails:(NSString *)filter;
// 实例方法：从 pFile 的 detailsOffset 处反序列化并恢复 details（MVSerializing）
- (void)                loadFromFile:(FILE *)pFile;
// 实例方法：将 details 的索引区写入 pFile 并记录 detailsOffset，刷新树/表（MVSerializing）
- (void)                saveToFile:(FILE *)pFile;

@end

//----------------------------------------------------------------------------
// 类：数据控制器，持有文件路径、原始/修补后数据、布局数组、根节点与当前选中节点，负责根据文件头创建布局并发送树/表/状态更新通知
//----------------------------------------------------------------------------
@interface MVDataController : NSObject
{
  // 实例变量：当前打开的二进制文件路径
  NSString *            fileName;         // path to the binary handled by this data controller
  // 实例变量：文件原始内容，所有 Layout 通过 imageAt: 等从此读取
  NSMutableData *       fileData;         // content of the binary
  // 实例变量：经重定位/绑定等修补后的内容（若功能启用），用于需要“真实”地址的场景
  NSMutableData *       realData;         // patched content by relocs and bindings
  // 实例变量：当前文档的所有布局（FatLayout、MachOLayout、ArchiveLayout 等），支持多架构/多镜像
  NSMutableArray *      layouts;
  // 实例变量：左侧树的根节点，其 children 为顶层镜像或 Fat slice
  MVNode *              rootNode;
  // 实例变量：当前选中的树节点，决定右侧表格显示哪个节点的 details
  MVNode *              __weak selectedNode;
  // 实例变量：保护树结构修改的锁（如 insertNode 时加锁）
  NSLock *              treeLock;         // semaphore for the node tree
}

// 属性：文件路径
@property (nonatomic)                   NSString *      fileName;
// 属性：文件原始数据
@property (nonatomic)                   NSMutableData * fileData;
// 属性：修补后数据
@property (nonatomic)                   NSMutableData * realData;
// 属性：只读，当前所有布局
@property (nonatomic,readonly)          NSArray *       layouts;
// 属性：只读，根节点
@property (nonatomic,readonly)          MVNode *        rootNode;
// 属性：当前选中节点
@property (nonatomic,weak)              MVNode *        selectedNode;
// 属性：只读，树锁
@property (nonatomic,readonly)          NSLock *        treeLock;

// 实例方法：将 cpu_type_t 转为可读架构名（如 @"X86_64"、@"ARM64"）
-(NSString *)           getMachine:(cpu_type_t)cputype;
// 实例方法：将 32 位 ARM 的 cpusubtype 转为可读字符串
-(NSString *)           getARMCpu:(cpu_subtype_t)cpusubtype;

// 实例方法：根据 parent 在 location 处的 magic 创建对应布局（Fat/Mach-O 32/64/Archive）并挂到 parent 下，更新树
- (void)                createLayouts:(MVNode *)parent location:(uint64_t)location length:(uint64_t)length;
// 实例方法：发送树更新通知，可选在 userInfo 中携带变更的 node
- (void)                updateTreeView: (MVNode *)node;
// 实例方法：发送右侧表格更新通知
- (void)                updateTableView;
// 实例方法：发送线程状态变化通知，status 放入 userInfo 的 MVStatusUserInfoKey
- (void)                updateStatus: (NSString *)status;

@end

//----------------------------------------------------------------------------
// 类：交换文件管理器，维护临时文件路径、待保存对象队列与后台保存线程，将 MVRow、MVNode 等延迟写入磁盘以节省内存
//----------------------------------------------------------------------------
@interface MVArchiver : NSObject
{
  // 实例变量：交换文件路径（如 /tmp 下的临时文件）
  NSString *            swapPath;
  // 实例变量：待写入的实现了 MVSerializing 的对象队列，由后台线程批量 saveToFile 后 clear
  NSMutableArray *      objectsToSave; // conforms MVSerializing
  // 实例变量：后台保存线程，循环调用 doSave，除非 MV_NO_ARCHIVER
  NSThread *            saverThread;
  // 实例变量：保护 objectsToSave 及 suspend/resume 的锁
  NSLock *              saverLock;
}

// 属性：只读，交换文件路径
@property (nonatomic,readonly)  NSString * swapPath;

// 类方法：用指定路径创建并返回一个 MVArchiver 实例
+(MVArchiver *) archiverWithPath:(NSString *)path;
// 实例方法：将对象加入待保存队列，对象必须实现 MVSerializing；若保存线程已取消则同步执行一次 doSave
-(void) addObjectToSave:(id)object;
// 实例方法：暂停保存（持 saverLock），用于过滤时避免与 doSave 并发写
-(void) suspend;
// 实例方法：恢复保存（释放 saverLock）
-(void) resume;
// 实例方法：取消保存线程并退出，在不需要再写入时调用（如不支持的架构）
-(void) halt;

@end

//----------------------------------------------------------------------------
// C++ 结构体：RAII 辅助，构造时记录节点，析构时将该节点加入其 userInfo 中 Layout 的 archiver 保存队列，用于 insertChildWithDetails: 后自动登记
//----------------------------------------------------------------------------
struct MVNodeSaver
{
  // 默认构造，m_node 为 nil
  MVNodeSaver();
  // 析构时若 m_node 非 nil 则 addObjectToSave:m_node
  ~MVNodeSaver();

  // 设置要登记的节点，由 insertChildWithDetails: 在创建节点后调用
  void setNode(MVNode * node) { m_node = node; }

private:
  // 禁止拷贝构造
  MVNodeSaver(MVNodeSaver const &);
  // 禁止拷贝赋值
  MVNodeSaver & operator=(MVNodeSaver const &);

  // 弱引用，待加入保存队列的节点
  MVNode * __weak m_node;
};
