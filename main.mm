//
//  main.m
//  MachOView
//
//  Created by psaghelyi on 10/06/2010.
//

// 全局变量：所有涉及管道或标准 IO 的线程在操作前需在此条件变量上协调，避免多线程同时写导致输出交错或竞争
NSCondition * pipeCondition;
// 全局变量：当前正在使用管道或标准 IO 的线程数量，与 pipeCondition 配合实现“同一时刻只允许一个线程做 std IO”
int32_t numIOThread;

// 声明 main 函数，返回类型为 int
int
// 应用程序入口：argc 为命令行参数个数，argv 为参数字符串数组
main(int argc, const char *argv[])
{
  // 分配并初始化条件变量对象，供后续多线程在读写管道时 lock/wait/signal 使用
  pipeCondition = [[NSCondition alloc]init];
  // 初始时没有任何线程在进行 IO，置为 0
  numIOThread = 0;
  // 将控制权交给 Cocoa，启动主运行循环（处理事件、窗口、菜单等），直到应用退出时返回
  return NSApplicationMain(argc, argv);
}
