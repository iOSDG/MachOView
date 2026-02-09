//
//  main.m
//  MachOView
//
//  Created by psaghelyi on 10/06/2010.
//
//  应用程序入口：初始化全局 IO 同步变量，并启动 Cocoa 主运行循环。
//


// 全局条件变量：所有涉及标准 IO（如管道）的操作在执行前需等待此条件，避免多线程同时使用管道导致输出交错或竞争
NSCondition * pipeCondition;
// 当前正在使用管道/标准 IO 的线程数；与 pipeCondition 配合，实现“同一时刻仅允许一个线程做 std IO”的互斥
int32_t numIOThread;

int
main(int argc, const char *argv[])
{
  // 分配并初始化条件变量，供后续多线程在读写管道时加锁/等待使用
  pipeCondition = [[NSCondition alloc]init];
  // 初始时没有线程在进行 IO
  numIOThread = 0;
  // 启动 Cocoa 应用主循环（处理事件、窗口、菜单等），直到应用退出
  return NSApplicationMain(argc, argv);
}
