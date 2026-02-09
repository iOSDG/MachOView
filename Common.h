/*
 *  Common.h
 *  MachOView
 *
 *  Created by Peter Saghelyi on 10/09/2011.
 *
 */

// 编译开关：若取消下一行的注释则禁用多线程，所有解析工作将在主线程执行（用于调试竞态或管道问题）
//#define MV_NO_MULTITHREAD
// 编译开关：若取消下一行的注释则禁用 Archiver，节点详情不会交换到磁盘，全部驻留内存（内存占用增大）
//#define MV_NO_ARCHIVER
// 编译开关：若取消下一行的注释则开启统计信息，会原子增减 nrow_total/nrow_loaded 并可能输出到日志
//#define MV_STATISTICS

// 全局变量：管道/标准 IO 同步用的条件变量，多线程在写管道或做 std IO 前需先 lock、递增 numIOThread，完成后递减并 signal，保证同一时刻仅一个线程使用管道
extern NSCondition * pipeCondition;
// 全局变量：当前正在执行管道/标准 IO 的线程个数，与 pipeCondition 配合实现互斥
extern int32_t numIOThread;
// 全局变量：详情表总行数（包含已从交换文件加载的行和尚未加载的空槽），用于进度与统计（需 MV_STATISTICS）
extern int64_t nrow_total;  // number of rows (loaded and empty)
// 全局变量：已从交换文件加载到内存的详情行数，用于统计与进度显示（需 MV_STATISTICS）
extern int64_t nrow_loaded; // number of loaded rows

// 宏：将 C 风格字符串转为 NSString，使用系统默认 C 字符串编码（常用于从二进制读出的字节转成可显示字符串）
#define NSSTRING(C_STR) [NSString stringWithCString: (char *)(C_STR) encoding: [NSString defaultCStringEncoding]]
// 宏：将 NSString 转为 C 字符串指针，用于传入需要 const char* 的 C API（如 fopen、fwrite）
#define CSTRING(NS_STR) [(NS_STR) cStringUsingEncoding: [NSString defaultCStringEncoding]]

// 宏：计算静态数组元素个数，sizeof(数组)/sizeof(首元素)；不能用于指针，仅用于真实数组
#define N_ELEMENTS(ARR)   (sizeof(ARR)/sizeof(*(ARR)))
// 宏：取数组首元素地址，等价于 &(ARR)[0]，用于在遍历或传递给 C 函数时取得起始指针
#define FIRST_ELEM(ARR)   (&(ARR)[0])
// 宏：取数组最后一个元素的地址，依赖 N_ELEMENTS，用于表示区间尾或边界检查
#define LAST_ELEM(ARR)    (&(ARR)[N_ELEMENTS(ARR)-1])
