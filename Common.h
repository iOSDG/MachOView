/*
 *  Common.h
 *  MachOView
 *
 *  Created by Peter Saghelyi on 10/09/2011.
 *
 *  公共头文件：定义全局编译开关、跨文件共享的变量、以及通用宏。
 */


// 若取消注释则禁用多线程（调试用，所有工作在主线程执行）
//#define MV_NO_MULTITHREAD
// 若取消注释则禁用 Archiver（不将节点详情交换到磁盘）
//#define MV_NO_ARCHIVER
// 若取消注释则开启统计信息输出（如行数、加载情况等）
//#define MV_STATISTICS

// 管道/IO 同步条件变量：在涉及标准 IO 或管道操作时，需先等待此条件，避免多线程同时写导致乱序或竞争
extern NSCondition * pipeCondition;
// 当前正在进行 IO（如管道读写）的线程数量，用于与 pipeCondition 配合做同步
extern int32_t numIOThread;
// 表格总行数（包含已加载与尚未加载的空行，用于进度/统计）
extern int64_t nrow_total;  // number of rows (loaded and empty)
// 已加载到内存的表格行数（用于进度显示与统计）
extern int64_t nrow_loaded; // number of loaded rows

// 将 C 字符串转为 NSString（使用系统默认 C 字符串编码）
#define NSSTRING(C_STR) [NSString stringWithCString: (char *)(C_STR) encoding: [NSString defaultCStringEncoding]]
// 将 NSString 转为 C 字符串（使用系统默认编码）
#define CSTRING(NS_STR) [(NS_STR) cStringUsingEncoding: [NSString defaultCStringEncoding]]

// 计算数组元素个数（仅适用于真正的数组，不适用于指针）
#define N_ELEMENTS(ARR)   (sizeof(ARR)/sizeof(*(ARR)))
// 取数组首元素地址
#define FIRST_ELEM(ARR)   (&(ARR)[0])
// 取数组末元素地址
#define LAST_ELEM(ARR)    (&(ARR)[N_ELEMENTS(ARR)-1])
