/*
 *  Attach.h
 *  MachOView
 *
 *  Created by fG! on 08/09/13.
 *  reverser@put.as
 *
 */

// 防止头文件重复包含的宏定义开始
#ifndef machoview_Attach_h
// 定义宏标识，表示已包含此头文件
#define machoview_Attach_h

// 引入Mach内核接口头文件
#include <mach/mach.h>
// 引入Mach虚拟内存接口头文件
#include <mach/mach_vm.h>
// 引入虚拟内存映射接口头文件
#include <mach/vm_map.h>
// 引入Mach-O加载命令定义头文件
#include <mach-o/loader.h>

// 声明函数get_image_size，用于获取目标进程中Mach-O镜像的大小和ASLR偏移
int64_t get_image_size(mach_vm_address_t address, pid_t pid, uint64_t *vmaddr_slide);
// 声明函数find_main_binary，用于查找目标进程的主二进制加载基址
kern_return_t find_main_binary(pid_t pid, mach_vm_address_t *main_address);
// 声明函数dump_binary，用于从目标进程内存中读取Mach-O镜像到缓冲区
kern_return_t dump_binary(mach_vm_address_t address, pid_t pid, uint8_t *buffer, uint64_t aslr_slide);

// 防止头文件重复包含的宏定义结束
#endif
