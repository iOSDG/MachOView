/*
 *  DataController.h
 *  MachOView
 *
 *  Created by psaghelyi on 15/06/2010.
 *
 */

// 定义右侧详情表的第一列索引，用于显示文件偏移或RVA
#define OFFSET_COLUMN       0
// 定义右侧详情表的第二列索引，用于显示原始数据（如十六进制数值）
#define DATA_COLUMN         1   // use this with details
// 定义右侧详情表的第三列索引，用于显示字段的描述信息
#define DESCRIPTION_COLUMN  2   // use this with details
// 定义右侧详情表的第四列索引，用于显示解析后的具体数值
#define VALUE_COLUMN        3

// 定义无详情模式下的第二列索引，显示数据的低位部分
#define DATA_LO_COLUMN      1   // use this with no details
// 定义无详情模式下的第三列索引，显示数据的高位部分
#define DATA_HI_COLUMN      2   // use this with no details

// 声明用于文本属性的键名，表示下划线样式
extern NSString * const MVUnderlineAttributeName;
// 声明用于文本属性的键名，表示单元格背景颜色
extern NSString * const MVCellColorAttributeName;
// 声明用于文本属性的键名，表示文本颜色
extern NSString * const MVTextColorAttributeName;
// 声明用于文本属性的键名，表示元数据信息
extern NSString * const MVMetaDataAttributeName;

// 声明UserInfo字典的键名，用于传递MVLayout对象
extern NSString * const MVLayoutUserInfoKey;
// 声明UserInfo字典的键名，用于传递MVNode对象
extern NSString * const MVNodeUserInfoKey;
// 声明UserInfo字典的键名，用于传递状态信息字符串
extern NSString * const MVStatusUserInfoKey;

// 声明通知名称，表示数据树即将发生改变
extern NSString * const MVDataTreeWillChangeNotification;
// 声明通知名称，表示数据树已经发生改变
extern NSString * const MVDataTreeDidChangeNotification;
// 声明通知名称，表示数据树内容变更
extern NSString * const MVDataTreeChangedNotification;
// 声明通知名称，表示数据表内容变更
extern NSString * const MVDataTableChangedNotification;
// 声明通知名称，表示后台线程状态变更
extern NSString * const MVThreadStateChangedNotification;

// 声明状态字符串常量，表示任务已启动
extern NSString * const MVStatusTaskStarted;
// 声明状态字符串常量，表示任务已终止
extern NSString * const MVStatusTaskTerminated;

// 前向声明MVNodeSaver结构体，用于节点保存操作
struct MVNodeSaver;

/**
 * 序列化协议，定义对象保存到文件和从文件加载的接口
 */
@protocol MVSerializing <NSObject>
// 从指定的文件指针加载数据，恢复对象状态
- (void)loadFromFile:(FILE *)pFile;
// 将对象状态保存到指定的文件指针
- (void)saveToFile:(FILE *)pFile;
// 清除对象在内存中的数据，通常在保存后释放内存
- (void)clear;
@end

//----------------------------------------------------------------------------
/**
 * MVColumns 类，表示表格中一行的四列数据
 */
//----------------------------------------------------------------------------
@interface MVColumns : NSObject
{
  // 存储第一列（偏移）的字符串数据
  NSString *            offsetStr;
  // 存储第二列（数据）的字符串数据
  NSString *            dataStr;
  // 存储第三列（描述）的字符串数据
  NSString *            descriptionStr;
  // 存储第四列（数值）的字符串数据
  NSString *            valueStr;
}

// 定义offsetStr属性，对应偏移列
@property (nonatomic)   NSString * offsetStr;
// 定义dataStr属性，对应数据列
@property (nonatomic)   NSString * dataStr;
// 定义descriptionStr属性，对应描述列
@property (nonatomic)   NSString * descriptionStr;
// 定义valueStr属性，对应数值列
@property (nonatomic)   NSString * valueStr;

/**
 * 工厂方法，创建一个包含四列数据的MVColumns对象
 * @param col0 偏移列内容
 * @param col1 数据列内容
 * @param col2 描述列内容
 * @param col3 数值列内容
 * @return 初始化后的MVColumns对象
 */
+(MVColumns *) columnsWithData:(NSString *)col0 :(NSString *)col1 :(NSString *)col2 :(NSString *)col3;

@end

//----------------------------------------------------------------------------
/**
 * MVRow 类，表示表格中的一行，实现了序列化协议
 */
//----------------------------------------------------------------------------
@interface MVRow : NSObject <MVSerializing>
{
  // 该行包含的列数据对象
  MVColumns *          columns;
  // 该行的属性字典，如颜色、字体等
  NSDictionary *        attributes;
  // 该行对应的数据在文件中的偏移量，用于排序等
  uint64_t              offset;             // for sorting if necessary
  // 列数据在交换文件中的偏移量，用于延迟加载
  off_t                 columnsOffset;      // offset of columns
  // 属性数据在交换文件中的偏移量
  off_t                 attributesOffset;   // offset of attribues
  // 标记该行是否已被删除
  BOOL                  deleted;
  // 标记该行数据是否已修改（脏数据），需要保存
  BOOL                  dirty;              // eg. attributes has changed
}

// 定义attributes属性，存储行属性
@property (nonatomic)   NSDictionary * attributes;
// 定义columns属性，存储列数据
@property (nonatomic)   MVColumns * columns;
// 定义offset属性，存储文件偏移
@property (nonatomic)   uint64_t offset;
// 定义deleted属性，标记删除状态
@property (nonatomic)   BOOL deleted;
// 定义dirty属性，标记修改状态
@property (nonatomic)   BOOL dirty;

/**
 * 获取指定列索引的字符串内容
 * @param index 列索引
 * @return 对应列的字符串
 */
-(NSString *)columnAtIndex:(NSUInteger)index;

@end

// 前向声明MVArchiver类
@class MVArchiver;

//----------------------------------------------------------------------------
/**
 * MVTable 类，表示一个数据表，包含多行数据
 */
//----------------------------------------------------------------------------
@interface MVTable : NSObject
{
  // 存储所有行对象的数组
  NSMutableArray *      rows;         // array of MVRow * (host of all the rows)
  // 存储当前显示行对象的数组（可能是过滤后的结果）
  NSMutableArray *      displayRows;  // array of MVRow * (rows filtered by search criteria)
  // 弱引用归档器对象，用于处理数据交换
  MVArchiver *          __weak archiver;
  // 交换文件的文件指针
  FILE *                swapFile;
  // 线程锁，用于保护表格数据的并发访问
  NSLock *              tableLock;
}

// 定义swapFile属性，指向交换文件
@property (nonatomic)   FILE * swapFile;

/**
 * 获取需要显示的行数
 * @return 显示行的数量
 */
- (NSUInteger)          rowCountToDisplay;
/**
 * 获取指定显示索引的行对象
 * @param rowIndex 显示行的索引
 * @return 对应的MVRow对象
 */
- (MVRow *)             getRowToDisplay:(NSUInteger)rowIndex;

/**
 * 移除表格的最后一行
 */
- (void)                popRow;
/**
 * 在表格末尾追加一行数据
 * @param col0 第一列内容
 * @param col1 第二列内容
 * @param col2 第三列内容
 * @param col3 第四列内容
 */
- (void)                appendRow:(id)col0 :(id)col1 :(id)col2 :(id)col3;
/**
 * 在指定偏移位置插入一行数据
 * @param offset 数据偏移量
 * @param col0 第一列内容
 * @param col1 第二列内容
 * @param col2 第三列内容
 * @param col3 第四列内容
 */
- (void)                insertRowWithOffset:(uint64_t)offset :(id)col0 :(id)col1 :(id)col2 :(id)col3;
/**
 * 更新指定行和列的单元格内容
 * @param object 新的内容对象
 * @param rowIndex 行索引
 * @param colIndex 列索引
 */
- (void)                updateCellContentTo:(id)object atRow:(NSUInteger)rowIndex andCol:(NSUInteger)colIndex;

/**
 * 获取表格的总行数
 * @return 总行数
 */
- (NSUInteger)          rowCount;
/**
 * 设置最后一行的属性
 * @param firstArg 属性键值对列表，以nil结尾
 */
- (void)                setAttributes:(NSString *)firstArg, ... NS_REQUIRES_NIL_TERMINATION;
/**
 * 设置指定索引行的属性
 * @param index 行索引
 * @param firstArg 属性键值对列表，以nil结尾
 */
- (void)                setAttributesForRowIndex:(NSUInteger)index :(NSString *)firstArg, ... NS_REQUIRES_NIL_TERMINATION;
/**
 * 从指定索引行开始设置后续所有行的属性
 * @param index 起始行索引
 * @param firstArg 属性键值对列表，以nil结尾
 */
- (void)                setAttributesFromRowIndex:(NSUInteger)index :(NSString *)firstArg, ... NS_REQUIRES_NIL_TERMINATION;

@end

//----------------------------------------------------------------------------
/**
 * MVNode 类，表示树形结构中的一个节点，实现了序列化协议
 */
//----------------------------------------------------------------------------
@interface MVNode : NSObject <MVSerializing>
{
  // 节点的标题文本
  NSString *            caption;
  // 弱引用父节点，防止循环引用
  MVNode *              __weak parent;
  // 子节点数组
  NSMutableArray *      children;
  // 节点对应的数据范围（位置和长度）
  NSRange               dataRange;
  // 节点关联的详情表对象
  MVTable *             details;
  // 用户信息字典，存储额外的数据
  NSMutableDictionary * userInfo;
  // 详情表在交换文件中的偏移量
  off_t                 detailsOffset;
}

// 定义caption属性，节点标题
@property (nonatomic)                   NSString *            caption;
// 定义parent属性，父节点
@property (nonatomic,weak)      MVNode *              parent;
// 定义dataRange属性，数据范围
@property (nonatomic)                   NSRange               dataRange;
// 定义details属性，详情表
@property (nonatomic)                   MVTable *             details;
// 定义userInfo属性，用户信息
@property (nonatomic)                   NSMutableDictionary * userInfo;
// 定义detailsOffset属性，详情表文件偏移
@property (nonatomic)                   off_t              detailsOffset;

/**
 * 获取子节点的数量
 * @return 子节点个数
 */
- (NSUInteger)          numberOfChildren;
/**
 * 获取指定索引的子节点
 * @param n 子节点索引
 * @return 子节点对象
 */
- (MVNode *)            childAtIndex:(NSUInteger)n;
/**
 * 插入一个新的子节点
 * @param _caption 子节点标题
 * @param location 数据起始位置
 * @param length 数据长度
 * @return 新插入的MVNode对象
 */
- (MVNode *)            insertChild:(NSString *)_caption location:(uint64_t)location length:(uint64_t)length;
/**
 * 插入一个带有详情表的子节点，并使用saver进行管理
 * @param _caption 子节点标题
 * @param location 数据起始位置
 * @param length 数据长度
 * @param saver 节点保存器引用
 * @return 新插入的MVNode对象
 */
- (MVNode *)            insertChildWithDetails:(NSString *)_caption location:(uint64_t)location length:(uint64_t)length saver:(MVNodeSaver &)saver;
/**
 * 通过用户信息查找子节点
 * @param uinfo 要匹配的用户信息字典
 * @return 匹配的MVNode对象，未找到返回nil
 */
- (MVNode *)            findNodeByUserInfo:(NSDictionary *)uinfo;
/**
 * 打开详情表的交换文件，准备读取
 */
- (void)                openDetails;  // open swap file for reading details on demand
/**
 * 关闭详情表的交换文件
 */
- (void)                closeDetails; // close swap file
/**
 * 对详情表进行排序
 */
- (void)                sortDetails;
/**
 * 根据过滤字符串筛选详情表内容
 * @param filter 过滤关键词
 */
- (void)                filterDetails:(NSString *)filter;
/**
 * 从文件加载节点数据
 * @param pFile 文件指针
 */
- (void)                loadFromFile:(FILE *)pFile;
/**
 * 将节点数据保存到文件
 * @param pFile 文件指针
 */
- (void)                saveToFile:(FILE *)pFile;

@end

//----------------------------------------------------------------------------
/**
 * MVDataController 类，数据控制器，管理文件数据和布局
 */
//----------------------------------------------------------------------------
@interface MVDataController : NSObject
{
  // 当前处理的文件路径
  NSString *            fileName;         // path to the binary handled by this data controller
  // 文件的原始数据内容
  NSMutableData *       fileData;         // content of the binary
  // 经过重定位和绑定补丁后的真实数据内容
  NSMutableData *       realData;         // patched content by relocs and bindings
  // 存储所有布局对象的数组（如Mach-O布局）
  NSMutableArray *      layouts;
  // 树形结构的根节点
  MVNode *              rootNode;
  // 当前被选中的节点（弱引用）
  MVNode *              __weak selectedNode;
  // 树形结构的线程锁，保护并发操作
  NSLock *              treeLock;         // semaphore for the node tree
}

// 定义fileName属性，文件路径
@property (nonatomic)                   NSString *      fileName;
// 定义fileData属性，原始数据
@property (nonatomic)                   NSMutableData * fileData;
// 定义realData属性，真实数据
@property (nonatomic)                   NSMutableData * realData;
// 定义layouts属性，只读，布局数组
@property (nonatomic,readonly)          NSArray *       layouts;
// 定义rootNode属性，只读，根节点
@property (nonatomic,readonly)          MVNode *        rootNode;
// 定义selectedNode属性，当前选中节点
@property (nonatomic,weak)              MVNode *        selectedNode;
// 定义treeLock属性，只读，树锁
@property (nonatomic,readonly)          NSLock *        treeLock;

/**
 * 根据CPU类型获取机器架构名称
 * @param cputype CPU类型
 * @return 架构名称字符串
 */
-(NSString *)           getMachine:(cpu_type_t)cputype;
/**
 * 根据CPU子类型获取ARM架构名称
 * @param cpusubtype CPU子类型
 * @return ARM架构名称字符串
 */
-(NSString *)           getARMCpu:(cpu_subtype_t)cpusubtype;

/**
 * 在指定位置创建布局对象
 * @param parent 父节点
 * @param location 布局起始位置
 * @param length 布局长度
 */
- (void)                createLayouts:(MVNode *)parent location:(uint64_t)location length:(uint64_t)length;
/**
 * 更新树视图显示
 * @param node 需要更新的节点，nil表示全部
 */
- (void)                updateTreeView: (MVNode *)node;
/**
 * 更新表格视图显示
 */
- (void)                updateTableView;
/**
 * 更新状态栏信息
 * @param status 状态信息字符串
 */
- (void)                updateStatus: (NSString *)status;

@end

//----------------------------------------------------------------------------
/**
 * MVArchiver 类，负责数据的归档和交换文件管理
 */
//----------------------------------------------------------------------------
@interface MVArchiver : NSObject
{
  // 交换文件的存储路径
  NSString *            swapPath;
  // 待保存的对象队列，对象需实现MVSerializing协议
  NSMutableArray *      objectsToSave; // conforms MVSerializing
  // 后台保存线程
  NSThread *            saverThread;
  // 保存操作的线程锁
  NSLock *              saverLock;
}

// 定义swapPath属性，只读，交换路径
@property (nonatomic,readonly)  NSString * swapPath;

/**
 * 使用指定路径创建归档器
 * @param path 交换文件路径
 * @return 初始化后的MVArchiver对象
 */
+(MVArchiver *) archiverWithPath:(NSString *)path;
/**
 * 添加对象到保存队列
 * @param object 待保存的对象
 */
-(void) addObjectToSave:(id)object;
/**
 * 暂停保存操作
 */
-(void) suspend;
/**
 * 恢复保存操作
 */
-(void) resume;
/**
 * 停止归档器工作
 */
-(void) halt;

@end

//----------------------------------------------------------------------------
/**
 * MVNodeSaver 结构体，用于自动管理MVNode的保存操作（RAII模式）
 */
//----------------------------------------------------------------------------
struct MVNodeSaver
{
  // 默认构造函数
  MVNodeSaver();
  // 析构函数，对象销毁时自动触发保存
  ~MVNodeSaver();

  // 设置需要管理的节点
  void setNode(MVNode * node)
  // 开始设置节点逻辑
  {
    // 将传入的节点赋值给成员变量m_node
    m_node = node;
  // 结束设置节点逻辑
  }

private:
  // 私有拷贝构造函数，禁止拷贝
  MVNodeSaver(MVNodeSaver const &);
  // 私有赋值运算符，禁止赋值
  MVNodeSaver & operator=(MVNodeSaver const &);

  // 弱引用被管理的节点
  MVNode * __weak m_node;
};
