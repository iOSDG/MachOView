 /*
 *  AppController.mm
 *  MachOView
 *
 *  Created by psaghelyi on 15/06/2010.
 *
 */

// 引入项目公共头（全局宏、extern 等）
#import "Common.h"
// 引入本类头文件
#import "AppController.h"
// 引入数据控制器
#import "DataController.h"
// 引入文档类
#import "Document.h"
// 引入偏好设置控制器
#import "PreferenceController.h"
// 引入附加进程相关接口（find_main_binary、get_image_size、dump_binary 等）
#import "Attach.h"
// 引入 Fat 二进制魔数等
#import <mach-o/fat.h>
// 引入 Mach-O 加载器与魔数（MH_MAGIC 等）
#import <mach-o/loader.h>

// counters for statistics
// 总行数（已加载与空行合计），用于 MV_STATISTICS 统计
int64_t nrow_total;  // number of rows (loaded and empty)
// 已加载行数
int64_t nrow_loaded; // number of loaded rows

//============================================================================
// MVAppController 实现开始
@implementation MVAppController

//----------------------------------------------------------------------------
// NSApplicationDelegate：是否在启动时自动打开未命名文档
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
  // 返回 NO 表示不自动打开
  return NO;
}

//----------------------------------------------------------------------------
// NSApplicationDelegate：最后一个窗口关闭时是否退出应用
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
  // 返回 NO 表示不退出
  return NO;
}

//----------------------------------------------------------------------------
// 菜单“新建”动作
- (IBAction)newDocument:(id)sender
{
  // 当前未实现，仅打日志
  NSLog(@"Not yet possible");
}

//----------------------------------------------------------------------------
// 判断当前是否只有本应用（同名且同版本）在运行
- (BOOL)isOnlyRunningMachOView
{
  // 获取当前进程信息
  NSProcessInfo * procInfo = [NSProcessInfo processInfo];
  // 获取主 bundle
  NSBundle * mainBundle = [NSBundle mainBundle];
  // 从 Info.plist 读取短版本字符串
  NSString * versionString = [mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
  
  // 同名同版本实例计数
  NSUInteger numberOfInstance = 0;
  
  // 获取当前工作空间
  NSWorkspace * workspace = [NSWorkspace sharedWorkspace];
  // 遍历所有正在运行的应用
  for (NSRunningApplication * runningApplication in [workspace runningApplications])
  {
    // check if process name matches
    // 取该应用的可执行文件路径最后一段作为文件名
    NSString * fileName = [[runningApplication executableURL] lastPathComponent];
    // 若进程名与当前进程名不同则跳过
    if ([fileName isEqualToString: [procInfo processName]] == NO)
    {
      continue;
    }

    // check if version string matches
    // 用该应用的 bundle URL 得到 NSBundle
    NSBundle * bundle = [NSBundle bundleWithURL:[runningApplication bundleURL]];
    // 版本一致则视为同一 MachOView，计数加一；若已大于 1 则返回 NO
    if ([versionString isEqualToString:[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]] == YES && ++numberOfInstance > 1)
    {
      return NO;
    }
  }
  
  // 仅有一个或零个同名同版本实例时返回 YES
  return YES;
}

//----------------------------------------------------------------------------
/* 
 * menu item action to attach to a process and read its mach-o header
 */
// 菜单“附加到进程”动作：弹框输入 PID，读目标进程主二进制并以临时文件用文档打开
- (IBAction)attach:(id)sender
{
  // 创建告警框
  NSAlert *alert = [[NSAlert alloc] init];
  // 设置主提示文字
  alert.messageText = @"Insert PID to attach to:";
  // 添加“Attach”按钮（第一个按钮）
  [alert addButtonWithTitle:@"Attach"];
  // 添加“Cancel”按钮（第二个按钮）
  [alert addButtonWithTitle:@"Cancel"];

  // 创建附件输入框，宽 200 高 24
  NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
  // 初始为空字符串
  [input setStringValue:@""];
  // 将输入框设为告警框的附件视图
  [alert setAccessoryView:input];
  // 以模态方式运行告警框，得到用户点击的按钮
  NSInteger button = [alert runModal];
  // 用户点击了“Attach”（第一个按钮）
  if (button == NSAlertFirstButtonReturn)
  {
    // 提交输入框中的编辑
    [input validateEditing];
    // 将输入内容转为整数作为目标 PID
    pid_t targetPid = [input intValue];
    // 打日志
    NSLog(@"Trying to attach to process %d", targetPid);
    // 主二进制在目标进程中的基址，由 find_main_binary 填充
    mach_vm_address_t mainAddress = 0;
    // 查找目标进程主二进制基址；返回非 0 表示失败
    if (find_main_binary(targetPid, &mainAddress))
    {
      // 打日志
      NSLog(@"Failed to find main binary address!");
      // 创建失败告警框
      NSAlert *attachfail = [[NSAlert alloc] init];
      attachfail.messageText = @"Failed to attach to process";
      [attachfail addButtonWithTitle:@"Ok"];
      [attachfail runModal];
      return;
    }
    // ASLR 偏移，由 get_image_size 填充
    uint64_t aslr_slide = 0;
    // 镜像大小，由 get_image_size 返回
    uint64_t imagesize = 0;
    // 获取镜像大小与 aslr_slide；返回 0 表示失败
    if ( (imagesize = get_image_size(mainAddress, targetPid, &aslr_slide)) == 0 )
    {
      NSLog(@"[ERROR] Got image file size equal to 0!");
      return;
    }
    /* allocate the buffer to contain the memory dump */
    // 分配与镜像大小相同的缓冲区
    uint8_t *readbuffer = (uint8_t*)malloc(imagesize);
    // 分配失败则返回
    if (readbuffer == NULL)
    {
      NSLog(@"Can't allocate mem for dumping target!");
      return;
    }
    /* and finally read the sections and dump their contents to the buffer */
    // 从目标进程内存将主二进制读出到 readbuffer；返回非 0 表示失败
    if (dump_binary(mainAddress, targetPid, readbuffer, aslr_slide))
    {
      NSLog(@"Main binary memory dump failed!");
      free(readbuffer);
      return;
    }
    /* dump buffer contents to temporary file to use the NSDocument model */
    // 获取 MVDocument 的临时目录并转为 C 字符串
    const char *tmp = [[MVDocument temporaryDirectory] UTF8String];
    // 分配足够长的路径缓冲区（临时目录路径 + 1 供 mkstemp 追加）
    char *dumpFilePath = (char*)malloc(strlen(tmp)+1);
    if (dumpFilePath == NULL)
    {
      NSLog(@"Can't allocate mem for temp filename path!");
      free(readbuffer);
      return;
    }
    // 先复制临时目录路径到 dumpFilePath
    strcpy(dumpFilePath, tmp);
    // 临时文件描述符
    int outputFile = 0;
    // mkstemp 会在 dumpFilePath 后追加 XXXXXX 并创建唯一文件，返回 fd；-1 表示失败
    if ( (outputFile = mkstemp(dumpFilePath)) == -1 )
    {
      NSLog(@"mkstemp failed!");
      free(dumpFilePath);
      free(readbuffer);
      return;
    }
    
    // 将 readbuffer 内容写入临时文件；返回 -1 表示写入失败
    if (write(outputFile, readbuffer, imagesize) == -1)
    {
      NSLog(@"[ERROR] Write error at %s occurred!\n", dumpFilePath);
      free(dumpFilePath);
      free(readbuffer);
      return;
    }
    NSLog(@"\n[OK] Full binary dumped to %s!\n\n", dumpFilePath);
    // 关闭文件描述符
    close(outputFile);
    
    // 用文档系统打开该临时文件（复用 MVDocument 解析与展示）
    [self application:NSApp openFile:[NSString stringWithCString:dumpFilePath encoding:NSUTF8StringEncoding]];
    /* remove temporary dump file, not required anymore */
    // 获取默认 NSFileManager
    NSFileManager * fileManager = [NSFileManager defaultManager];
    // 删除临时 dump 文件（文档已加载，不再需要）
    [fileManager removeItemAtPath:[NSString stringWithCString:dumpFilePath encoding:NSUTF8StringEncoding] error:NULL];
    // 释放路径缓冲区
    free(dumpFilePath);
    // 释放读缓冲区
    free(readbuffer);
  }
  // 用户点击了“Cancel”（第二个按钮）
  else if (button == NSAlertSecondButtonReturn)
  {
    /* nothing to do here */
  }
  else
  {
    // 理论上不应出现其他按钮值，断言
    NSAssert1(NO, @"Invalid input dialog button %ld", button);
  }
}

//----------------------------------------------------------------------------
// 菜单“打开”动作：弹出打开面板
- (IBAction)openDocument:(id)sender
{
  // 创建系统打开面板
  NSOpenPanel *openPanel = [NSOpenPanel openPanel];
  // 将 .app 等文件包视为目录（可进入）
  [openPanel setTreatsFilePackagesAsDirectories:YES];
  // 允许多选
  [openPanel setAllowsMultipleSelection:YES];
  // 不允许选择目录（仅文件）
  [openPanel setCanChooseDirectories:NO];
  // 允许选择文件
  [openPanel setCanChooseFiles:YES];
  [openPanel setDelegate:self]; // for filtering files in open panel with shouldShowFilename
  // 以 sheet 形式弹出，附 completion 块
  [openPanel beginSheetModalForWindow:NSApp.modalWindow
   completionHandler:^(NSInteger result) 
   {
     // 用户未点 OK 则直接返回
     if (result != NSModalResponseOK)
     {
       return;
     }
     [openPanel orderOut:self]; // close panel before we might present an error
     // 遍历用户选中的所有 URL
     for (NSURL * url in [openPanel URLs])
     {
       // 用 application:openFile: 打开每个文件
       [self application:NSApp openFile:[url path]];
     }
   }];
}

//----------------------------------------------------------------------------
// NSOpenSavePanelDelegate：决定打开面板中该 URL 是否可选（启用）
- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url
{
  // can enter directories
  // 用于接收“是否为目录”的 out 参数
  NSNumber * isDirectory = nil;
  // 从 url 读取 NSURLIsDirectoryKey
  [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
  // 若是目录则允许（可进入）
  if ([isDirectory boolValue] == YES) 
  {
    return YES;
  }

  // skip symbolic links, etc.
  // 用于接收“是否为普通文件”的 out 参数
  NSNumber * isRegularFile = nil;
  [url getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:NULL];
  // 非普通文件（如符号链接）则不可选
  if ([isRegularFile boolValue] == NO) 
  {
    return NO;
  }
  
  // check for magic values at front
  // 以只读方式打开该 URL 对应文件
  NSFileHandle * fileHandle = [NSFileHandle fileHandleForReadingFromURL:url error:NULL];
  // 读取前 8 字节用于魔数判断
  NSData * magicData = [fileHandle readDataOfLength:8];
  [fileHandle closeFile];
  
  // 数据不足 4 字节则无法读 uint32_t 魔数，不允许
  if ([magicData length] < sizeof(uint32_t))
  {
    return NO;
  }
  
  // 取前 4 字节为魔数
  uint32_t magic = *(uint32_t*)[magicData bytes];
  // Mach-O 32/64 或 Fat 魔数则允许选择
  if (magic == MH_MAGIC || magic == MH_MAGIC_64 || 
      magic == FAT_CIGAM || magic == FAT_MAGIC)
  {
    return YES;
  }
  
  // 不足 8 字节则无法读 uint64_t，不允许
  if ([magicData length] < sizeof(uint64_t))
  {
    return NO;
  }
  
  // 静态库 Archive 魔数为 "!<arch>\n"（8 字节）
  if (*(uint64_t*)[magicData bytes] == *(uint64_t*)"!<arch>\n")
  {
    return YES;
  }
  
  // 非上述类型则不允许
  return NO;
}

//----------------------------------------------------------------------------
// 应用即将完成启动时调用
- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
  // 判断是否当前只有本应用在运行（用于是否清理/创建临时目录）
  BOOL isFirstMachOView = [self isOnlyRunningMachOView];
  
  // disable the state resume feature, it's not very useful with MachOView
  // 若尚未设置过该键，则设为 YES，禁用窗口状态恢复
  if([[NSUserDefaults standardUserDefaults] objectForKey: @"ApplePersistenceIgnoreState"] == nil)
      [[NSUserDefaults standardUserDefaults] setBool: YES forKey:@"ApplePersistenceIgnoreState"];

  // load user's defaults for preferences
//  if([[NSUserDefaults standardUserDefaults] objectForKey: @"UseLLVMDisassembler"] != nil)
//    qflag = [[NSUserDefaults standardUserDefaults] boolForKey:@"UseLLVMDisassembler"];

  
  // 获取默认 NSFileManager
  NSFileManager * fileManager = [NSFileManager defaultManager];
  // 获取 MVDocument 使用的临时目录路径
  NSString * tempDir = [MVDocument temporaryDirectory];
  
  // 用于接收 removeItem/createDirectory 的错误，__autoreleasing 便于 ARC
  __autoreleasing NSError * error;
  
  // remove previously forgotten temporary files
  // 若是第一个实例且临时目录已存在，则先删除（清理上次未删的临时文件）
  if (isFirstMachOView && [fileManager fileExistsAtPath:tempDir isDirectory:NULL] == YES)
  {
    // 删除失败则向用户展示错误
    if ([fileManager removeItemAtPath:tempDir error:&error] == NO)
    {
      [NSApp presentError:error];
    }
  }
  
  // create placeholder for temporary files
  // 若临时目录不存在则创建
  if ([fileManager fileExistsAtPath:tempDir isDirectory:NULL] == NO)
  {
    // 不创建中间目录，属性为 nil；创建失败则展示错误
    if ([fileManager createDirectoryAtPath:tempDir
               withIntermediateDirectories:NO
                                attributes:nil
                                     error:&error] == NO)
    {
      [NSApp presentError:error];
    }
  }
}

//----------------------------------------------------------------------------
// 应用完成启动后调用
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification 
{
#ifdef MV_STATISTICS
  // 清零行数统计
  nrow_total = nrow_loaded = 0;
  // 在后台线程中周期打印统计（printStat）
  [NSThread detachNewThreadSelector:@selector(printStat) toTarget:self withObject:nil];
#endif 

  /* default is to not open a file dialogue */
  // 仅当用户曾设置过 OpenAtLaunch 键时才判断
  if ([[NSUserDefaults standardUserDefaults] objectForKey:@"OpenAtLaunch"] != nil)
  {
    // 若偏好为“启动时打开”
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"OpenAtLaunch"] == YES)
    {
      // if there is no document yet, then pop up an open file dialogue
      // 若当前尚无任何文档则弹出打开面板
      if ([[[NSDocumentController sharedDocumentController] documents] count] == 0)
      {
        [self openDocument:nil];
      }
    }
  }
}

//----------------------------------------------------------------------------
// 应用即将退出时调用
- (void)applicationWillTerminate:(NSNotification *)aNotification
{
  // 判断是否最后一个本应用实例
  BOOL isLastMachOView = [self isOnlyRunningMachOView];
  
  // 仅当最后一个实例退出时才删除临时目录
  if (isLastMachOView == YES)
  {
    // remove temporary files
    NSFileManager * fileManager = [NSFileManager defaultManager];
    NSString * tempDir = [MVDocument temporaryDirectory];
    [fileManager removeItemAtPath:tempDir error:NULL];
  }
}

//----------------------------------------------------------------------------
// 由系统或 openDocument/attach 调用，用文档控制器打开指定文件并显示
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
    // 打日志
    NSLog (@"open file: %@", filename);

    // 获取单例文档控制器
    NSDocumentController * documentController = [NSDocumentController sharedDocumentController];
    // 用 path 构造 file URL，打开并显示，异步完成回调
    [documentController openDocumentWithContentsOfURL:[NSURL fileURLWithPath:filename]
                                              display:YES
                                    completionHandler:^(NSDocument * _Nullable document, BOOL alreadyOpen, NSError * _Nullable error) {
         // If we can't open the document, present error to the user
         // 打开失败则展示错误
         if (!document) {
            [NSApp presentError:error];
         }
         if (alreadyOpen) {
             NSLog(@"document was already open!");
         }
    }];
    // 表示已接受该文件（即使异步打开）
    return YES;
}

//----------------------------------------------------------------------------
// MV_STATISTICS 下在后台线程中周期调用的统计打印方法
-(void) printStat
{
  // 无限循环
  for (;;)
  {
    // 每秒打印一次已加载行数/总行数
    NSLog(@"stat: %lld/%lld rows in memory\n",nrow_loaded,nrow_total);
    [NSThread sleepForTimeInterval:1];
  }
}

//----------------------------------------------------------------------------
// 菜单“偏好设置”动作
- (IBAction)showPreferencePanel:(id)sender
{
    // 若尚未创建偏好控制器则创建
    if (!preferenceController)
    {
        preferenceController = [[MVPreferenceController alloc] init];
    }
    // 显示偏好窗口
    [preferenceController showWindow:self];
}

@end
