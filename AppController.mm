/*
 *  AppController.mm
 *  MachOView
 *
 *  Created by psaghelyi on 15/06/2010.
 *
 */

// 引入项目公共头文件，包含全局宏定义和extern声明
#import "Common.h"
// 引入AppController类定义头文件
#import "AppController.h"
// 引入数据控制器头文件，用于管理Mach-O数据解析
#import "DataController.h"
// 引入文档类头文件，用于处理文件打开和显示逻辑
#import "Document.h"
// 引入偏好设置控制器头文件，用于管理应用偏好设置
#import "PreferenceController.h"
// 引入进程附加功能头文件，提供find_main_binary、get_image_size等接口
#import "Attach.h"
// 引入Mach-O Fat二进制格式定义的系统头文件
#import <mach-o/fat.h>
// 引入Mach-O加载命令和文件头定义的系统头文件
#import <mach-o/loader.h>

// 定义全局变量nrow_total，用于统计已加载和空行的总数量，服务于MV_STATISTICS统计功能
int64_t nrow_total;  // number of rows (loaded and empty)
// 定义全局变量nrow_loaded，用于统计实际已加载到内存的行数
int64_t nrow_loaded; // number of loaded rows

// 开始MVAppController类的实现代码块
@implementation MVAppController

// 实现NSApplicationDelegate协议方法，控制应用是否在启动时自动打开未命名文档
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
  // 返回NO，表示应用启动时不自动创建或打开空白文档
  return NO;
}

// 实现NSApplicationDelegate协议方法，控制当最后一个窗口关闭时是否终止应用
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
  // 返回NO，表示即使所有窗口关闭，应用仍然保持运行状态（驻留Dock）
  return NO;
}

// 实现IBAction方法newDocument，响应菜单“新建”操作
- (IBAction)newDocument:(id)sender
{
  // 打印日志，提示新建文档功能尚未实现
  NSLog(@"Not yet possible");
}

// 定义私有辅助方法isOnlyRunningMachOView，用于检查当前是否只有本应用的一个实例在运行
- (BOOL)isOnlyRunningMachOView
{
  // 获取当前进程的详细信息对象
  NSProcessInfo * procInfo = [NSProcessInfo processInfo];
  // 获取应用程序的主Bundle对象
  NSBundle * mainBundle = [NSBundle mainBundle];
  // 从Info.plist中读取CFBundleShortVersionString键对应的值，即应用短版本号
  NSString * versionString = [mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
  
  // 初始化计数器变量numberOfInstance，用于统计同名同版本的应用实例数量
  NSUInteger numberOfInstance = 0;
  
  // 获取当前共享的工作空间对象，用于查询系统运行的应用程序
  NSWorkspace * workspace = [NSWorkspace sharedWorkspace];
  // 遍历工作空间中所有正在运行的应用程序列表
  for (NSRunningApplication * runningApplication in [workspace runningApplications])
  {
    // 获取运行中应用的可执行文件URL的最后一部分（即文件名）
    NSString * fileName = [[runningApplication executableURL] lastPathComponent];
    // 判断运行中应用的文件名是否与当前进程名不同，如果不同则返回NO（即不匹配）
    if ([fileName isEqualToString: [procInfo processName]] == NO)
    {
      // 如果文件名不匹配，跳过本次循环，继续检查下一个应用
      continue;
    }

    // 根据运行中应用的Bundle URL获取其NSBundle对象
    NSBundle * bundle = [NSBundle bundleWithURL:[runningApplication bundleURL]];
    // 判断运行中应用的版本号是否与当前应用一致，并递增实例计数器，如果实例数超过1
    if ([versionString isEqualToString:[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]] == YES && ++numberOfInstance > 1)
    {
      // 如果存在超过1个同名同版本的实例，返回NO
      return NO;
    }
  }
  
  // 如果遍历结束后未发现其他同名同版本实例（计数<=1），返回YES
  return YES;
}

/* 
 * menu item action to attach to a process and read its mach-o header
 */
// 实现IBAction方法attach，响应菜单“附加到进程”操作
- (IBAction)attach:(id)sender
{
  // 创建一个NSAlert对象，用于显示PID输入对话框
  NSAlert *alert = [[NSAlert alloc] init];
  // 设置对话框的主提示信息，提示用户输入目标进程PID
  alert.messageText = @"Insert PID to attach to:";
  // 向对话框添加“Attach”按钮，作为默认操作按钮
  [alert addButtonWithTitle:@"Attach"];
  // 向对话框添加“Cancel”按钮，作为取消操作按钮
  [alert addButtonWithTitle:@"Cancel"];

  // 创建一个NSTextField对象作为输入框，设置其frame大小
  NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
  // 初始化输入框内容为空字符串
  [input setStringValue:@""];
  // 将输入框设置为Alert对话框的附件视图
  [alert setAccessoryView:input];
  // 以模态方式运行Alert对话框，并获取用户的点击结果
  NSInteger button = [alert runModal];
  // 判断用户是否点击了第一个按钮（即“Attach”）
  if (button == NSAlertFirstButtonReturn)
  {
    // 强制输入框结束编辑，确保输入值同步到模型
    [input validateEditing];
    // 从输入框获取整数值，作为目标进程ID
    pid_t targetPid = [input intValue];
    // 打印日志，记录正在尝试附加到的目标进程PID
    NSLog(@"Trying to attach to process %d", targetPid);
    // 声明变量mainAddress，用于存储目标进程主二进制的基地址
    mach_vm_address_t mainAddress = 0;
    // 调用find_main_binary查找目标进程的主二进制地址，如果返回非0表示失败
    if (find_main_binary(targetPid, &mainAddress))
    {
      // 打印错误日志，提示无法找到主二进制地址
      NSLog(@"Failed to find main binary address!");
      // 创建一个新的NSAlert对象，用于报告附加失败
      NSAlert *attachfail = [[NSAlert alloc] init];
      // 设置错误提示信息
      attachfail.messageText = @"Failed to attach to process";
      // 添加“Ok”按钮以关闭错误提示
      [attachfail addButtonWithTitle:@"Ok"];
      // 以模态方式运行错误提示对话框
      [attachfail runModal];
      // 终止当前方法执行，返回
      return;
    }
    // 声明变量aslr_slide，用于存储ASLR偏移量
    uint64_t aslr_slide = 0;
    // 声明变量imagesize，用于存储镜像大小
    uint64_t imagesize = 0;
    // 调用get_image_size获取镜像大小和ASLR偏移，如果返回0表示获取失败
    if ( (imagesize = get_image_size(mainAddress, targetPid, &aslr_slide)) == 0 )
    {
      // 打印错误日志，提示获取到的镜像大小为0
      NSLog(@"[ERROR] Got image file size equal to 0!");
      // 终止当前方法执行，返回
      return;
    }
    /* allocate the buffer to contain the memory dump */
    // 使用malloc分配内存缓冲区，大小为镜像大小，用于存储Dump的数据
    uint8_t *readbuffer = (uint8_t*)malloc(imagesize);
    // 判断内存分配是否失败（指针为NULL）
    if (readbuffer == NULL)
    {
      // 打印错误日志，提示内存分配失败
      NSLog(@"Can't allocate mem for dumping target!");
      // 终止当前方法执行，返回
      return;
    }
    /* and finally read the sections and dump their contents to the buffer */
    // 调用dump_binary将目标进程的内存数据读取到缓冲区，如果返回非0表示失败
    if (dump_binary(mainAddress, targetPid, readbuffer, aslr_slide))
    {
      // 打印错误日志，提示主二进制内存Dump失败
      NSLog(@"Main binary memory dump failed!");
      // 释放已分配的缓冲区内存
      free(readbuffer);
      // 终止当前方法执行，返回
      return;
    }
    /* dump buffer contents to temporary file to use the NSDocument model */
    // 获取MVDocument类的临时目录路径，并转换为C字符串
    const char *tmp = [[MVDocument temporaryDirectory] UTF8String];
    // 分配内存用于存储临时文件路径，长度为目录路径长度+1（虽然后续会用到mkstemp的模板长度，但此处分配策略如此）
    char *dumpFilePath = (char*)malloc(strlen(tmp)+1);
    // 判断路径内存分配是否失败
    if (dumpFilePath == NULL)
    {
      // 打印错误日志，提示临时文件名路径内存分配失败
      NSLog(@"Can't allocate mem for temp filename path!");
      // 释放之前分配的数据缓冲区
      free(readbuffer);
      // 终止当前方法执行，返回
      return;
    }
    // 将临时目录路径复制到dumpFilePath缓冲区
    strcpy(dumpFilePath, tmp);
    // 声明整型变量outputFile，用于存储临时文件的文件描述符
    int outputFile = 0;
    // 调用mkstemp创建唯一的临时文件，并返回文件描述符，如果返回-1表示失败
    if ( (outputFile = mkstemp(dumpFilePath)) == -1 )
    {
      // 打印错误日志，提示mkstemp创建临时文件失败
      NSLog(@"mkstemp failed!");
      // 释放路径缓冲区内存
      free(dumpFilePath);
      // 释放数据缓冲区内存
      free(readbuffer);
      // 终止当前方法执行，返回
      return;
    }
    
    // 调用write系统调用将readbuffer中的数据写入临时文件，如果返回-1表示写入错误
    if (write(outputFile, readbuffer, imagesize) == -1)
    {
      // 打印错误日志，包含出错的文件路径
      NSLog(@"[ERROR] Write error at %s occurred!\n", dumpFilePath);
      // 释放路径缓冲区内存
      free(dumpFilePath);
      // 释放数据缓冲区内存
      free(readbuffer);
      // 终止当前方法执行，返回
      return;
    }
    // 打印成功日志，显示Dump文件的保存路径
    NSLog(@"\n[OK] Full binary dumped to %s!\n\n", dumpFilePath);
    // 关闭临时文件的文件描述符
    close(outputFile);
    
    // 调用本类的application:openFile:方法，使用文档系统打开生成的临时文件
    [self application:NSApp openFile:[NSString stringWithCString:dumpFilePath encoding:NSUTF8StringEncoding]];
    /* remove temporary dump file, not required anymore */
    // 获取默认的NSFileManager实例
    NSFileManager * fileManager = [NSFileManager defaultManager];
    // 删除临时文件，因为文档已加载到内存，不再需要磁盘上的副本
    [fileManager removeItemAtPath:[NSString stringWithCString:dumpFilePath encoding:NSUTF8StringEncoding] error:NULL];
    // 释放路径缓冲区内存
    free(dumpFilePath);
    // 释放数据缓冲区内存
    free(readbuffer);
  }
  // 判断用户是否点击了第二个按钮（即“Cancel”）
  else if (button == NSAlertSecondButtonReturn)
  {
    // 不执行任何操作，仅作为占位符
    /* nothing to do here */
  }
  // 处理其他意外的按钮返回值
  else
  {
    // 抛出断言错误，提示无效的输入对话框按钮值
    NSAssert1(NO, @"Invalid input dialog button %ld", button);
  }
}

// 实现IBAction方法openDocument，响应菜单“打开”操作
- (IBAction)openDocument:(id)sender
{
  // 创建并获取一个NSOpenPanel实例，用于显示文件打开面板
  NSOpenPanel *openPanel = [NSOpenPanel openPanel];
  // 设置面板将File Packages（如.app）视为目录，允许进入查看
  [openPanel setTreatsFilePackagesAsDirectories:YES];
  // 设置面板允许用户同时选择多个文件
  [openPanel setAllowsMultipleSelection:YES];
  // 设置面板不允许用户选择目录（文件夹）
  [openPanel setCanChooseDirectories:NO];
  // 设置面板允许用户选择文件
  [openPanel setCanChooseFiles:YES];
  // 设置面板的代理为当前对象，以便通过panel:shouldEnableURL:方法过滤文件
  [openPanel setDelegate:self]; // for filtering files in open panel with shouldShowFilename
  // 以Sheet形式在主窗口上显示面板，并设置完成后的回调Block
  [openPanel beginSheetModalForWindow:NSApp.modalWindow
   completionHandler:^(NSInteger result) 
   {
     // 判断用户的选择结果是否不是OK（例如点击了取消）
     if (result != NSModalResponseOK)
     {
       // 如果不是OK，直接返回，不处理后续逻辑
       return;
     }
     // 关闭面板，确保在可能显示错误之前面板已消失
     [openPanel orderOut:self]; // close panel before we might present an error
     // 遍历用户在面板中选择的所有文件URL
     for (NSURL * url in [openPanel URLs])
     {
       // 调用本类的application:openFile:方法打开每一个选中的文件路径
       [self application:NSApp openFile:[url path]];
     }
   }];
}

// 实现NSOpenSavePanelDelegate协议方法，决定面板中的URL是否应被启用（可选）
- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url
{
  // 声明NSNumber变量isDirectory，用于接收是否为目录的判断结果
  NSNumber * isDirectory = nil;
  // 获取URL资源的NSURLIsDirectoryKey属性值
  [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
  // 判断该URL是否为目录，如果是
  if ([isDirectory boolValue] == YES) 
  {
    // 允许选择（进入）目录，返回YES
    return YES;
  }

  // 声明NSNumber变量isRegularFile，用于接收是否为普通文件的判断结果
  NSNumber * isRegularFile = nil;
  // 获取URL资源的NSURLIsRegularFileKey属性值
  [url getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:NULL];
  // 判断是否为非普通文件（如符号链接、Socket等），如果是
  if ([isRegularFile boolValue] == NO) 
  {
    // 不允许选择，返回NO
    return NO;
  }
  
  // 创建NSFileHandle对象，以只读方式打开URL对应的文件
  NSFileHandle * fileHandle = [NSFileHandle fileHandleForReadingFromURL:url error:NULL];
  // 读取文件的前8个字节数据，用于检查魔数
  NSData * magicData = [fileHandle readDataOfLength:8];
  // 关闭文件句柄
  [fileHandle closeFile];
  
  // 判断读取的数据长度是否小于4字节（无法构成最小魔数）
  if ([magicData length] < sizeof(uint32_t))
  {
    // 数据不足，不允许选择，返回NO
    return NO;
  }
  
  // 将读取数据的前4字节转换为uint32_t类型的魔数
  uint32_t magic = *(uint32_t*)[magicData bytes];
  // 判断魔数是否匹配32位Mach-O、64位Mach-O、Fat Cigam或Fat Magic
  if (magic == MH_MAGIC || magic == MH_MAGIC_64 || 
      magic == FAT_CIGAM || magic == FAT_MAGIC)
  {
    // 魔数匹配，确认为支持的文件类型，返回YES
    return YES;
  }
  
  // 判断读取的数据长度是否小于8字节（无法构成Archive魔数）
  if ([magicData length] < sizeof(uint64_t))
  {
    // 数据不足，不允许选择，返回NO
    return NO;
  }
  
  // 判断前8字节是否匹配静态库Archive的魔数"!<arch>\n"
  if (*(uint64_t*)[magicData bytes] == *(uint64_t*)"!<arch>\n")
  {
    // 魔数匹配，确认为Archive文件，返回YES
    return YES;
  }
  
  // 如果都不匹配，默认不允许选择，返回NO
  return NO;
}

// 实现NSApplicationDelegate协议方法，应用即将完成启动时调用
- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
  // 调用isOnlyRunningMachOView判断是否是第一个运行的实例
  BOOL isFirstMachOView = [self isOnlyRunningMachOView];
  
  // 检查NSUserDefaults中是否未设置"ApplePersistenceIgnoreState"键
  if([[NSUserDefaults standardUserDefaults] objectForKey: @"ApplePersistenceIgnoreState"] == nil)
      // 如果未设置，将其设为YES，禁用系统的窗口状态恢复功能
      [[NSUserDefaults standardUserDefaults] setBool: YES forKey:@"ApplePersistenceIgnoreState"];

  // 获取默认的NSFileManager实例
  NSFileManager * fileManager = [NSFileManager defaultManager];
  // 获取MVDocument用于存储临时文件的目录路径
  NSString * tempDir = [MVDocument temporaryDirectory];
  
  // 声明一个NSError变量，用于接收文件操作错误
  __autoreleasing NSError * error;
  
  // 判断如果是第一个实例且临时目录已经存在（可能是上次崩溃残留）
  if (isFirstMachOView && [fileManager fileExistsAtPath:tempDir isDirectory:NULL] == YES)
  {
    // 尝试删除该临时目录，如果删除失败
    if ([fileManager removeItemAtPath:tempDir error:&error] == NO)
    {
      // 向用户展示删除错误信息
      [NSApp presentError:error];
    }
  }
  
  // 判断临时目录是否不存在
  if ([fileManager fileExistsAtPath:tempDir isDirectory:NULL] == NO)
  {
    // 尝试创建临时目录，不创建中间目录，无特定属性
    if ([fileManager createDirectoryAtPath:tempDir
               withIntermediateDirectories:NO
                                attributes:nil
                                     error:&error] == NO)
    {
      // 如果创建失败，向用户展示错误信息
      [NSApp presentError:error];
    }
  }
}

// 实现NSApplicationDelegate协议方法，应用完成启动后调用
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification 
{
// 检查是否定义了MV_STATISTICS宏，用于启用统计功能
#ifdef MV_STATISTICS
  // 初始化全局统计变量，将总行数和已加载行数重置为0
  nrow_total = nrow_loaded = 0;
  // 创建并分离一个新的后台线程，执行printStat方法进行周期性统计打印
  [NSThread detachNewThreadSelector:@selector(printStat) toTarget:self withObject:nil];
// 结束MV_STATISTICS宏判断
#endif 

  // 检查NSUserDefaults中是否存在"OpenAtLaunch"键
  if ([[NSUserDefaults standardUserDefaults] objectForKey:@"OpenAtLaunch"] != nil)
  {
    // 检查"OpenAtLaunch"键的值是否为YES
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"OpenAtLaunch"] == YES)
    {
      // 检查当前文档控制器中是否没有已打开的文档
      if ([[[NSDocumentController sharedDocumentController] documents] count] == 0)
      {
        // 如果没有文档，自动调用openDocument方法弹出打开文件面板
        [self openDocument:nil];
      }
    }
  }
}

// 实现NSApplicationDelegate协议方法，应用即将终止时调用
- (void)applicationWillTerminate:(NSNotification *)aNotification
{
  // 调用isOnlyRunningMachOView判断是否是最后一个运行的实例
  BOOL isLastMachOView = [self isOnlyRunningMachOView];
  
  // 如果是最后一个实例，需要清理资源
  if (isLastMachOView == YES)
  {
    // 获取默认的NSFileManager实例
    NSFileManager * fileManager = [NSFileManager defaultManager];
    // 获取MVDocument的临时目录路径
    NSString * tempDir = [MVDocument temporaryDirectory];
    // 删除临时目录，清理所有临时文件
    [fileManager removeItemAtPath:tempDir error:NULL];
  }
}

// 实现application:openFile:方法，用于处理文件打开请求
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
    // 打印日志，显示正在打开的文件名
    NSLog (@"open file: %@", filename);

    // 获取共享的文档控制器单例
    NSDocumentController * documentController = [NSDocumentController sharedDocumentController];
    // 调用文档控制器的方法，通过文件URL打开文档，并在完成后执行回调
    [documentController openDocumentWithContentsOfURL:[NSURL fileURLWithPath:filename]
                                              display:YES
                                    completionHandler:^(NSDocument * _Nullable document, BOOL alreadyOpen, NSError * _Nullable error) {
         // 判断文档对象是否为空（即打开失败）
         if (!document) {
            // 如果打开失败，向用户展示错误信息
            [NSApp presentError:error];
         }
         // 判断文档是否已经是打开状态
         if (alreadyOpen) {
             // 如果已打开，打印日志提示
             NSLog(@"document was already open!");
         }
    }];
    // 返回YES，表示已接受处理打开文件的请求
    return YES;
}

// 定义printStat方法，用于打印内存行数统计信息
-(void) printStat
{
  // 开启无限循环
  for (;;)
  {
    // 打印当前已加载行数和总行数到控制台
    NSLog(@"stat: %lld/%lld rows in memory\n",nrow_loaded,nrow_total);
    // 使当前线程休眠1秒，避免占用过多CPU
    [NSThread sleepForTimeInterval:1];
  }
}

// 实现IBAction方法showPreferencePanel，响应菜单“偏好设置”操作
- (IBAction)showPreferencePanel:(id)sender
{
    // 判断preferenceController实例是否尚未创建
    if (!preferenceController)
    {
        // 如果未创建，分配并初始化一个新的MVPreferenceController实例
        preferenceController = [[MVPreferenceController alloc] init];
    }
    // 调用偏好设置控制器的showWindow方法，显示偏好设置窗口
    [preferenceController showWindow:self];
}

@end
