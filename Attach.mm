/*
 *  Attach.mm
 *  MachOView
 *
 *  Created by fG! on 08/09/13.
 *  reverser@put.as
 *
 *  Contains functions for the attach to process feature.
 *
 */

// 引入Attach模块头文件
#include "Attach.h"

// 引入标准输入输出头文件
#include <stdio.h>

/* local functions */
// 声明静态辅助函数readmem，用于从目标进程内存读取数据
static kern_return_t readmem(mach_vm_offset_t *buffer, mach_vm_address_t address, mach_vm_size_t size, pid_t pid, vm_region_basic_info_data_64_t *info);

#pragma mark Public functions

/*
 * find main binary by iterating memory region
 * assumes there's only one binary with filetype == MH_EXECUTE
 */
// 函数find_main_binary：通过遍历内存区域查找目标进程的主二进制基址
kern_return_t
find_main_binary(pid_t pid, mach_vm_address_t *main_address)
{
  // 目标进程的任务端口
  vm_map_t targetTask = 0;
  // 内核返回码
  kern_return_t kr = 0;
  // 获取目标进程的任务端口，如果失败则返回错误
  if (task_for_pid(mach_task_self(), pid, &targetTask))
  {
    // 打印错误日志：无法获取任务端口，可能是权限不足
    NSLog(@"[ERROR] Can't execute task_for_pid! Do you have the right permissions/entitlements?\n");
    // 返回失败状态
    return KERN_FAILURE;
  }
  
  // 遍历起始地址
  vm_address_t iter = 0;
  // 无限循环遍历内存区域
  while (1)
  {
    // Mach-O头部结构体，用于临时存储读取的头部
    struct mach_header mh = {0};
    // 当前遍历地址
    vm_address_t addr = iter;
    // 区域大小
    vm_size_t lsize = 0;
    // 区域深度
    uint32_t depth;
    // 实际读取字节数
    mach_vm_size_t bytes_read = 0;
    // 内存子映射信息结构体
    struct vm_region_submap_info_64 info;
    // 信息结构体大小
    mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;
    // 递归获取64位内存区域信息，如果失败（遍历结束）则跳出循环
    if (vm_region_recurse_64(targetTask, &addr, &lsize, &depth, (vm_region_info_t)&info, &count))
    {
      // 遍历结束
      break;
    }
    // 读取当前区域头部的mach_header大小的数据
    kr = mach_vm_read_overwrite(targetTask, (mach_vm_address_t)addr, (mach_vm_size_t)sizeof(struct mach_header), (mach_vm_address_t)&mh, &bytes_read);
    // 如果读取成功且读取大小正确
    if (kr == KERN_SUCCESS && bytes_read == sizeof(struct mach_header))
    {
      /* only one image with MH_EXECUTE filetype */
      // 检查魔数是否为Mach-O（32位或64位）且文件类型为可执行文件（MH_EXECUTE）
      if ( (mh.magic == MH_MAGIC || mh.magic == MH_MAGIC_64) && mh.filetype == MH_EXECUTE)
      {
#if DEBUG
        // 调试模式下打印找到的主二进制地址
        NSLog(@"Found main binary mach-o image @ %p!\n", (void*)addr);
#endif
        // 将找到的地址赋值给输出参数
        *main_address = addr;
        // 找到后跳出循环
        break;
      }
    }
    // 更新遍历起始地址为当前区域结束位置
    iter = addr + lsize;
  }
  // 返回成功状态
  return KERN_SUCCESS;
}

/*
 * we need to find the binary file size
 * which is taken from the filesize field of each segment command
 * and not the vmsize (because of alignment)
 * if we dump using vmaddresses, we will get the alignment space into the dumped
 * binary and get into problems :-)
 */
// 函数get_image_size：获取目标进程Mach-O镜像的文件大小，并计算ASLR偏移
int64_t
get_image_size(mach_vm_address_t address, pid_t pid, uint64_t *vmaddr_slide)
{
  // 内存区域基本信息结构体
  vm_region_basic_info_data_64_t region_info = {0};
  // allocate a buffer to read the header info
  // NOTE: this is not exactly correct since the 64bit version has an extra 4 bytes
  // but this will work for this purpose so no need for more complexity!
  // Mach-O头部结构体
  struct mach_header header = {0};
  // 读取Mach-O头部，如果失败则打印错误并返回-1
  if (readmem((mach_vm_offset_t*)&header, address, sizeof(struct mach_header), pid, &region_info))
  {
    // 打印无法读取头部错误
    NSLog(@"Can't read header!");
    // 返回错误
    return -1;
  }
  
  // 检查魔数是否合法
  if (header.magic != MH_MAGIC && header.magic != MH_MAGIC_64)
  {
    // 打印非Mach-O二进制错误
		printf("[ERROR] Target is not a mach-o binary!\n");
    // 返回错误
    return -1;
  }
  
  // 初始化镜像文件大小
  int64_t imagefilesize = -1;
  /* read the load commands */
  // 分配缓冲区用于存储加载命令
  uint8_t *loadcmds = (uint8_t*)malloc(header.sizeofcmds);
  // Mach-O头部大小（默认32位）
  uint16_t mach_header_size = sizeof(struct mach_header);
  // 如果是64位，更新头部大小
  if (header.magic == MH_MAGIC_64)
  {
    // 使用64位头部大小
    mach_header_size = sizeof(struct mach_header_64);
  }
  // 读取加载命令区域数据
  if (readmem((mach_vm_offset_t*)loadcmds, address+mach_header_size, header.sizeofcmds, pid, &region_info))
  {
    // 打印无法读取加载命令错误
    NSLog(@"Can't read load commands");
    // 释放缓冲区
    free(loadcmds);
    // 返回错误
    return -1;
  }
  
  /* process and retrieve address and size of linkedit */
  // 加载命令遍历指针
  uint8_t *loadCmdAddress = 0;
  // 初始化为加载命令缓冲区起始位置
  loadCmdAddress = (uint8_t*)loadcmds;
  // 通用加载命令结构指针
  struct load_command *loadCommand    = NULL;
  // 32位段命令结构指针
  struct segment_command *segCmd      = NULL;
  // 64位段命令结构指针
  struct segment_command_64 *segCmd64 = NULL;
  // 遍历所有加载命令
  for (uint32_t i = 0; i < header.ncmds; i++)
  {
    // 获取当前加载命令
    loadCommand = (struct load_command*)loadCmdAddress;
    // 如果是32位段命令
    if (loadCommand->cmd == LC_SEGMENT)
    {
      // 转换为32位段命令结构
      segCmd = (struct segment_command*)loadCmdAddress;
      // 忽略__PAGEZERO段（通常无文件内容）
      if (strncmp(segCmd->segname, "__PAGEZERO", 16) != 0)
      {
        // 如果是__TEXT段，计算ASLR偏移
        if (strncmp(segCmd->segname, "__TEXT", 16) == 0)
        {
          // ASLR偏移 = 实际加载地址 - 静态链接地址
          *vmaddr_slide = address - segCmd->vmaddr;
        }
        // 累加文件大小（使用filesize而非vmsize以排除对齐填充）
        imagefilesize += segCmd->filesize;
      }
    }
    // 如果是64位段命令
    else if (loadCommand->cmd == LC_SEGMENT_64)
    {
      // 转换为64位段命令结构
      segCmd64 = (struct segment_command_64*)loadCmdAddress;
      // 忽略__PAGEZERO段
      if (strncmp(segCmd64->segname, "__PAGEZERO", 16) != 0)
      {
        // 如果是__TEXT段，计算ASLR偏移
        if (strncmp(segCmd64->segname, "__TEXT", 16) == 0)
        {
          // ASLR偏移 = 实际加载地址 - 静态链接地址
          *vmaddr_slide = address - segCmd64->vmaddr;
        }
        // 累加文件大小
        imagefilesize += segCmd64->filesize;
      }
    }
    // advance to next command
    // 移动指针到下一个加载命令
    loadCmdAddress += loadCommand->cmdsize;
  }
  // 释放加载命令缓冲区
  free(loadcmds);
  // 返回计算得到的镜像文件大小
  return imagefilesize;
}

/*
 * dump the binary into the allocated buffer
 * we dump each segment and advance the buffer
 */
// 函数dump_binary：将目标进程的Mach-O镜像Dump到缓冲区
kern_return_t
dump_binary(mach_vm_address_t address, pid_t pid, uint8_t *buffer, uint64_t aslr_slide)
{
  // 内存区域基本信息结构体
  vm_region_basic_info_data_64_t region_info = {0};
  // allocate a buffer to read the header info
  // NOTE: this is not exactly correct since the 64bit version has an extra 4 bytes
  // but this will work for this purpose so no need for more complexity!
  // Mach-O头部结构体
  struct mach_header header = {0};
  // 读取Mach-O头部
  if (readmem((mach_vm_offset_t*)&header, address, sizeof(struct mach_header), pid, &region_info))
  {
    // 打印读取头部失败
    NSLog(@"Can't read header!");
    // 返回内核错误
    return KERN_FAILURE;
  }
  
  // 检查魔数
  if (header.magic != MH_MAGIC && header.magic != MH_MAGIC_64)
  {
    // 打印非Mach-O错误
    printf("[ERROR] Target is not a mach-o binary!\n");
    // 退出程序（注意：此处直接exit可能过于粗暴，应返回错误码）
    exit(1);
  }
  
  // read the header info to find the LINKEDIT
  // 分配加载命令缓冲区
  uint8_t *loadcmds = (uint8_t*)malloc(header.sizeofcmds);
  
  // 头部大小（32位）
  uint16_t mach_header_size = sizeof(struct mach_header);
  // 如果是64位
  if (header.magic == MH_MAGIC_64)
  {
    // 使用64位头部大小
    mach_header_size = sizeof(struct mach_header_64);
  }
  // retrieve the load commands
  // 读取加载命令
  if (readmem((mach_vm_offset_t*)loadcmds, address+mach_header_size, header.sizeofcmds, pid, &region_info))
  {
    // 打印读取加载命令失败
    NSLog(@"Can't read load commands");
    // 释放缓冲区
    free(loadcmds);
    // 置空指针
    loadcmds = NULL;
    // 返回内核错误
    return KERN_FAILURE;
  }
  
  // process and retrieve address and size of linkedit
  // 加载命令遍历指针
  uint8_t *loadCmdAddress = 0;
  // 初始化遍历指针
  loadCmdAddress = (uint8_t*)loadcmds;
  // 通用加载命令结构
  struct load_command *loadCommand    = NULL;
  // 32位段命令结构
  struct segment_command *segCmd      = NULL;
  // 64位段命令结构
  struct segment_command_64 *segCmd64 = NULL;
  // 遍历加载命令
  for (uint32_t i = 0; i < header.ncmds; i++)
  {
    // 获取当前加载命令
    loadCommand = (struct load_command*)loadCmdAddress;
    // 如果是32位段命令
    if (loadCommand->cmd == LC_SEGMENT)
    {
      // 转换为32位段命令结构
      segCmd = (struct segment_command*)loadCmdAddress;
      // 忽略__PAGEZERO段
      if (strncmp(segCmd->segname, "__PAGEZERO", 16) != 0)
      {
#if DEBUG
        // 调试模式下打印Dump信息
        printf("[DEBUG] Dumping %s at %llx with size %x (buffer:%x)\n", segCmd->segname, segCmd->vmaddr+aslr_slide, segCmd->filesize, (uint32_t)*buffer);
#endif
        // 从目标进程读取该段内容到缓冲区，地址需加上ASLR偏移
        readmem((mach_vm_offset_t*)buffer, segCmd->vmaddr+aslr_slide, segCmd->filesize, pid, &region_info);
      }
      // 缓冲区指针前移，准备存放下一个段
      buffer += segCmd->filesize;
    }
    // 如果是64位段命令
    else if (loadCommand->cmd == LC_SEGMENT_64)
    {
      // 转换为64位段命令结构
      segCmd64 = (struct segment_command_64*)loadCmdAddress;
      // 忽略__PAGEZERO段
      if (strncmp(segCmd64->segname, "__PAGEZERO", 16) != 0)
      {
#if DEBUG
        // 调试模式下打印Dump信息
        printf("[DEBUG] Dumping %s at %llx with size %llx (buffer:%x)\n", segCmd64->segname, segCmd64->vmaddr+aslr_slide, segCmd64->filesize, (uint32_t)*buffer);
#endif
        // 从目标进程读取该段内容到缓冲区
        readmem((mach_vm_offset_t*)buffer, segCmd64->vmaddr+aslr_slide, segCmd64->filesize, pid, &region_info);
      }
      // 缓冲区指针前移
      buffer += segCmd64->filesize;
    }
    // advance to next command
    // 移动指针到下一个加载命令
    loadCmdAddress += loadCommand->cmdsize;
  }
  // 释放加载命令缓冲区
  free(loadcmds);
  // 置空指针
  loadcmds = NULL;
  // 返回成功
  return KERN_SUCCESS;
}

#pragma mark Local functions

// 静态函数readmem：从指定PID的进程读取内存
static kern_return_t
readmem(mach_vm_offset_t *buffer, mach_vm_address_t address, mach_vm_size_t size, pid_t pid, vm_region_basic_info_data_64_t *info)
{
  // get task for pid
  // 任务端口
  vm_map_t port;
  
  // 内核返回码
  kern_return_t kr;
  //#if DEBUG
  //    printf("[DEBUG] Readmem of address %llx to buffer %llx with size %llx\n", address, buffer, size);
  //#endif
  // 获取任务端口
  if (task_for_pid(mach_task_self(), pid, &port))
  {
    // 打印错误：权限不足
    fprintf(stderr, "[ERROR] Can't execute task_for_pid! Do you have the right permissions/entitlements?\n");
    // 返回失败
    return KERN_FAILURE;
  }
  
  // 区域信息计数
  mach_msg_type_number_t info_cnt = sizeof (vm_region_basic_info_data_64_t);
  // 对象名端口
  mach_port_t object_name;
  // 区域大小
  mach_vm_size_t size_info;
  // 查询地址
  mach_vm_address_t address_info = address;
  // 查询内存区域信息
  kr = mach_vm_region(port, &address_info, &size_info, VM_REGION_BASIC_INFO_64, (vm_region_info_t)info, &info_cnt, &object_name);
  // 如果查询失败
  if (kr)
  {
    // 打印mach_vm_region失败错误
    fprintf(stderr, "[ERROR] mach_vm_region failed with error %d\n", (int)kr);
    // 返回失败
    return KERN_FAILURE;
  }
  
  /* read memory - vm_read_overwrite because we supply the buffer */
  // 实际读取字节数
  mach_vm_size_t nread;
  // 使用mach_vm_read_overwrite读取内存到调用者提供的buffer
  kr = mach_vm_read_overwrite(port, address, size, (mach_vm_address_t)buffer, &nread);
  // 如果读取失败
  if (kr)
  {
    // 打印vm_read失败错误
    fprintf(stderr, "[ERROR] vm_read failed! %d\n", kr);
    // 返回失败
    return KERN_FAILURE;
  }
  // 如果实际读取大小不等于请求大小
  else if (nread != size)
  {
    // 打印大小不匹配错误
    fprintf(stderr, "[ERROR] vm_read failed! requested size: 0x%llx read: 0x%llx\n", size, nread);
    // 返回失败
    return KERN_FAILURE;
  }
  // 返回成功
  return KERN_SUCCESS;
}
