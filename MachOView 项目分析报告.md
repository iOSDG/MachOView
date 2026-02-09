# MachOView 项目分析报告

## 1. 项目概览

**MachOView** 是 macOS 平台上的可视化 Mach-O 文件格式分析工具，用于查看和检查可执行文件、动态库（dylib）以及目标文件（object files）的内部结构。

| 项目属性 | 说明 |
|----------|------|
| **当前版本** | 3.0（Fork 自原版并“复活”维护） |
| **最低系统** | macOS 10.13+ |
| **架构支持** | x86_64 / arm64 通用二进制 |
| **核心用途** | 逆向工程、安全分析、编译器/链接器调试 |

### 1.1 主要改进（相对原版）

- 通用二进制与 arm64 支持
- 使用 **Capstone** 替代 LLVM 反汇编器（无需 Clang/LLVM）
- 修复 Mountain Lion、iOS 6 及现代 macOS 上的兼容性问题
- **Attach** 功能：附加到运行中进程，分析其内存中的 Mach-O 头（需 codesign + entitlements）

---

## 2. 技术栈与架构

- **语言**：Objective-C++（ObjC 与 C++ 混编，大量使用 C++ STL）
- **UI 框架**：Cocoa (AppKit)，Document-based 应用
- **核心依赖**：
  - **Cocoa**：NSDocument、NSOutlineView、NSTableView 等
  - **Capstone**：反汇编引擎（`capstone/` 子目录，链接 `libcapstone.a`）
  - **系统头**：`<mach-o/loader.h>`、`<mach-o/fat.h>`、`<mach/mach.h>` 等
- **构建**：Xcode 项目，建议 Xcode 13+，推荐最新 Xcode + SDK

---

## 3. 源码目录与文件规模

### 3.1 项目自有源码（不含 capstone）

仅统计根目录下 `.h` / `.mm` / `main.mm` / `Prefix.pch`：

| 文件 | 行数 | 说明 |
|------|------|------|
| **Common.h** | 23 | 全局宏、extern 变量（如 pipeCondition, nrow_total） |
| **main.mm** | 19 | 入口，初始化 pipeCondition / numIOThread，调 NSApplicationMain |
| **Prefix.pch** | 9 | 预编译头 |
| **DataSources.h** | 17 | 树形/详情 DataSource 接口声明 |
| **FatLayout.h** | 16 | 通用二进制布局 |
| **LoadCommands.h** | 22 | Load Command 解析扩展（Category） |
| **PreferenceController.h** | 15 | 偏好设置窗口控制器 |
| **ArchiveLayout.h** | 31 | 静态库（Archive）布局 |
| **Attach.h** | 31 | 附加到进程相关声明 |
| **Exceptions.h** | 31 | 异常处理（CFI/LSDA/Unwind）解析 |
| **AppController.h** | 31 | 应用级生命周期与菜单 |
| **CRTFootPrints.h** | 29 | CRT 函数识别、运行时版本 |
| **DyldInfo.h** | 46 | dyld 信息（Rebase/Bind/Lazy Bind/Export） |
| **Layout.h** | 48 | 所有布局的基类 MVLayout |
| **ReadWrite.h** | 56 | 二进制读写扩展（DataController Category） |
| **Document.h** | 63 | 文档类 MVDocument、左右视图、格式化器 |
| **SectionContents.h** | 73 | Section 内容解析（指针、C 字符串、字面量等） |
| **ObjC.h** | 77 | Objective-C 元数据解析 |
| **MachOLayout.h** | 89 | Mach-O 单镜像布局核心（Command/Section/Symbol 等） |
| **LinkEdit.h** | 94 | 符号表、重定位等 LinkEdit 解析 |
| **DataController.h** | 209 | 数据模型核心：MVNode、MVTable、MVRow、MVArchiver 等 |
| **Layout.mm** | 123 | MVLayout 基类实现 |
| **FatLayout.mm** | 188 | Fat 解析实现 |
| **ArchiveLayout.mm** | 330 | Archive 解析实现 |
| **ReadWrite.mm** | 368 | 读写实现 |
| **Attach.mm** | 370 | 附加进程、读取远程 Mach-O 头 |
| **DataSources.mm** | 313 | 左侧树、右侧表 DataSource 实现 |
| **AppController.mm** | 525 | 应用菜单、打开/附加、偏好等 |
| **SectionContents.mm** | 655 | __text 反汇编、__data 等 Section 展示 |
| **Exceptions.mm** | 792 | 异常表、LSDA、Unwind 解析 |
| **Document.mm** | 853 | 文档、视图协调、后台解析、搜索/停止 |
| **DyldInfo.mm** | 924 | Rebase/Weak/Lazy Bind、Export 等 |
| **DataController.mm** | 1396 | 布局创建、树/表更新、Archiver 等 |
| **CRTFootPrints.mm** | 1516 | CRT 模式匹配、版本判断 |
| **LinkEdit.mm** | 1864 | 重定位、符号表、间接符号等 |
| **MachOLayout.mm** | 2558 | Mach-O 头、Load Commands、各 Segment/Section 节点 |
| **LoadCommands.mm** | 2581 | 各类 LC_* 解析 |
| **ObjC.mm** | 3328 | ObjC 类/方法/协议/分类等解析 |

**说明**：`capstone/` 为第三方反汇编库，一般不参与“项目内注释顺序”，仅在使用处（如 SectionContents）说明即可。

### 3.2 资源与配置

- **Base.lproj**：Layout.xib、MainMenu.xib、Preferences.xib  
- **en.lproj**：Credits.rtf、InfoPlist.strings  
- **mach-o/**：thread_status.h、thread_status_arm.h、arm64/reloc.h 等平台相关头  
- **Info.plist**：含 Attach 所需 entitlements 配置  

---

## 4. 核心架构与数据流

### 4.1 应用入口与文档模型

- **main.mm**  
  - 初始化 `pipeCondition`、`numIOThread`，调用 `NSApplicationMain`。

- **MVDocument (Document.h/mm)**  
  - Document-based 应用的核心文档类。  
  - 持有：左侧 `MVOutlineView`（leftView）、右侧 `MVTableView`（rightView）、搜索框、状态栏、进度条、停止按钮等。  
  - 通过 **MVDataController** 管理二进制数据与布局；后台线程做解析，避免阻塞 UI。

- **AppController (AppController.h/mm)**  
  - 应用级委托：菜单（打开、附加到进程、偏好等）、窗口管理。  
  - 依赖：Common、DataController、Document、PreferenceController、Attach、mach-o/fat、mach-o/loader。

### 4.2 数据与 UI 桥梁

- **MVDataController (DataController.h/mm)**  
  - 连接“二进制 + 布局”与“UI 展示”。  
  - 持有：`fileData` / `realData`、`layouts`（MVLayout 数组）、`rootNode`（MVNode 树）、`selectedNode`。  
  - 提供：`createLayouts:location:length:`（根据文件类型创建 Fat/Archive/MachO 等）、`updateTreeView` / `updateTableView`、`updateStatus`。  
  - 定义表格列：Offset、Data、Description、Value；以及 MVNode、MVTable、MVRow、MVArchiver、MVNodeSaver 等数据结构和通知名。

- **DataSources (DataSources.h/mm)**  
  - 实现左侧树（MVDataSourceTree）与右侧表（MVDataSourceDetails）的 DataSource/Delegate。  
  - 依赖：DataController、Document、Layout。

### 4.3 布局层次（Layout 体系）

- **MVLayout (Layout.h/mm)**  
  - 所有二进制布局的**基类**。  
  - 提供：`imageAt:`（按偏移读二进制）、`createDataNode:caption:location:length:`、`doMainTasks` / `doBackgroundTasks`、`is64bit`、`convertToRVA:`、`findNodeByUserInfo:` 等。  
  - 持有：`rootNode`、`dataController`、`imageOffset`、`imageSize`、`backgroundThread`、`archiver`。

- **MachOLayout (MachOLayout.h/mm)**  
  - **单 Mach-O 镜像**解析核心。  
  - 维护：CommandVector、SegmentVector/Segment64Vector、SectionVector/Section64Vector、NListVector/NList64Vector、DylibVector、ModuleVector、DataInCodeEntryVector、IndirectSymbolVector、strtab、segmentInfo、sectionInfo、lsdaInfo、symbolNames 等。  
  - 通过 **Category** 分散到多个文件：LoadCommands、LinkEdit、DyldInfo、Exceptions、SectionContents、ObjC、CRTFootPrints。

- **FatLayout (FatLayout.h/mm)**  
  - 识别 Fat 二进制，按架构切片创建子 **MachOLayout**。

- **ArchiveLayout (ArchiveLayout.h/mm)**  
  - 解析静态库（Archive），每个 member 一个 **MachOLayout**（或相应布局）。

### 4.4 读写与工具

- **ReadWrite (ReadWrite.h/mm)**  
  - 以 **MVDataController** 的 Category 形式提供：  
    - `read_uint8/16/32/64`、`read_int8/16/32/64`、`read_string`、`read_bytes`、`read_sleb128`、`read_uleb128` 等；  
    - 以及对应的 `write_*`。  
  - 所有解析层（MachOLayout、LoadCommands、LinkEdit、DyldInfo、SectionContents、ObjC、Exceptions、CRTFootPrints 等）都依赖 ReadWrite + DataController。

### 4.5 依赖关系简图（项目内）

```
main.mm
  → (NSApplicationMain) → AppController
       → Document, DataController, PreferenceController, Attach

Document
  → DataController, Layout

DataSources
  → DataController, Document, Layout

DataController
  → MachOLayout, FatLayout, ArchiveLayout

Layout (基类)
  ← FatLayout, ArchiveLayout, MachOLayout

MachOLayout
  → Layout
  ← LoadCommands, LinkEdit, DyldInfo, Exceptions, SectionContents, ObjC, CRTFootPrints (Category)

FatLayout / ArchiveLayout
  → Layout, (Fat/Archive 内再创建 MachOLayout)

ReadWrite
  → DataController（以 Category 形式挂在 DataController 上）

LoadCommands / LinkEdit / DyldInfo / Exceptions / SectionContents / ObjC / CRTFootPrints
  → MachOLayout, ReadWrite, DataController（及 SectionContents 用 Capstone）
```

---

## 5. 关键功能摘要

1. **通用二进制**：FatLayout 解析 Fat header，为每个架构切片创建 MachOLayout。  
2. **静态库**：ArchiveLayout 解析 ar 格式，为每个 member 创建布局（多为 MachOLayout）。  
3. **单 Mach-O**：MachOLayout + 各 Category 解析 Header、Load Commands、Segment/Section、符号表、重定位、dyld 信息、异常、ObjC 元数据、CRT 等。  
4. **反汇编**：SectionContents 使用 Capstone 对 __text 等做反汇编（遇非法指令会停止）。  
5. **附加进程**：Attach 使用 task_for_pid、vm_read 等 Mach API 读取目标进程内存中的 Mach-O 头并展示。

---

## 6. 构建与运行

- **环境**：Xcode 13+，推荐最新 Xcode + SDK。  
- **Attach**：需对 MachOView.app 进行 **codesign**，并在 Info.plist 中配置相应 entitlements（如 task_for_pid）。  
- **安全**：README 指出当前 Mach-O 解析器对恶意构造的二进制不够健壮，解析不可信文件时需注意安全。

---

## 7. 与“代码注释顺序”的关系

- 注释顺序按**依赖自底向上**安排：先 Common、DataController（含 ReadWrite）、Layout，再 MachOLayout 及各 Category，再 Fat/Archive，再 Document、DataSources，最后 AppController、Attach、PreferenceController、main。  
- 具体批次与每批包含的文件见 **《代码注释顺序文档》**。

---

*报告生成自项目源码与 Xcode 项目结构分析。*
