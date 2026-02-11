# MachOView SwiftUI 重写流程

本文档梳理如何用 **SwiftUI** 重写 MachOView 的推荐步骤与架构选择，便于按阶段推进、降低风险。

---

## 一、总体策略建议

### 1.1 推荐：**「SwiftUI 壳 + 复用解析层」**（增量迁移）

| 策略 | 做法 | 优点 | 风险/成本 |
|------|------|------|-----------|
| **A. 全量 Swift 重写** | 解析 + UI 全部用 Swift 重写 | 架构统一、长期好维护 | 工作量大（约 2 万+ 行）、易引入解析错误 |
| **B. SwiftUI 壳 + 复用 ObjC++ 解析**（推荐） | 新 SwiftUI 工程，通过桥接调用现有 DataController/Layout/MachOLayout 等 | 先换 UI、功能不变、可逐步替换底层 | 需维护桥接、部分 AppKit 嵌入 |
| **C. 仅换部分界面** | 在现有工程里用 SwiftUI 替换部分 XIB/ViewController | 改动小 | 混用 AppKit/SwiftUI，长期杂乱 |

**建议采用 B**：新建 SwiftUI 应用，文档与主界面用 SwiftUI，解析与树形数据仍用现有 ObjC/C++ 代码，通过桥接头或 Swift 包装类调用。

### 1.2 核心原则

1. **先跑通、再优化**：先实现「打开文件 → 树 + 详情」主流程，再补搜索、附加、偏好等。
2. **数据层尽量少动**：DataController、MVNode、MVLayout、ReadWrite、各 Category 解析逻辑保持不动或仅做薄封装。
3. **UI 层完全 SwiftUI**：主窗口、侧边树、详情表、工具栏、菜单用 SwiftUI；必要时用 `NSViewRepresentable` 包一层 AppKit（如复杂表格）。

---

## 二、阶段划分（推荐流程）

```
阶段 0：准备与桥接
  → 新建 SwiftUI App 工程、配置与现有代码共存、桥接 DataController

阶段 1：文档与主界面
  → DocumentGroup + 主界面（树 + 详情）、从现有解析拿到 rootNode

阶段 2：树与表数据绑定
  → 将 MVNode 树绑定到 SwiftUI List/OutlineGroup，详情绑定到 Table/List

阶段 3：交互与副功能
  → 搜索、停止、进度、RVA 切换、状态栏、偏好、附加

阶段 4：（可选）逐步迁移解析到 Swift
  → 按模块把 ReadWrite / LoadCommands / LinkEdit 等用 Swift 重写，最终去掉 ObjC++
```

---

## 三、阶段 0：准备与桥接

### 3.1 工程结构选择

**方案 A：同一仓库内新 Target（推荐）**

- 保留现有 `MachOView` target（AppKit）。
- 新建 Target：`MachOViewSwiftUI`，类型为 **macOS App**，Life Cycle 选 **SwiftUI App**。
- 把现有解析相关源文件（DataController、Layout、MachOLayout、ReadWrite、LoadCommands、LinkEdit、DyldInfo、Exceptions、SectionContents、ObjC、CRTFootPrints、FatLayout、ArchiveLayout、Common、mach-o 头、capstone）**同时**加入两个 Target，或放在一个 Shared 的 Group 里只勾选两个 Target。
- SwiftUI Target 中只新增：`MachOViewSwiftUIApp.swift`、`ContentView`、`DocumentViewModel`、桥接/包装类等。

**方案 B：新仓库/新工程**

- 新建 SwiftUI 工程，把上述解析源码复制或 git submodule 进来，再配置桥接与 Capstone。

### 3.2 桥接 ObjC/C++ 到 Swift

1. **桥接头（Bridging Header）**  
   - 在 SwiftUI target 中创建 `MachOView-Bridging-Header.h`。  
   - 在其中 `#import` 需要在 Swift 里用的 ObjC 头文件，例如：
     - `DataController.h`
     - `Document.h`（若仍用 MVDocument 打开文件则可先不暴露）
     - `Common.h`
     - 以及你希望直接调用的 Layout/MachOLayout 相关头（可选，见下）。

2. **暴露给 Swift 的接口尽量「薄」**  
   - 建议在 ObjC 侧新增一个 **Facade 类**（如 `MVParseService`），专门给 Swift 调用，例如：
     - `loadFile(url:) -> MVDataController?`
     - `rootNode`、`selectedNode`、`layouts` 等只读属性或简单方法。  
   - 这样 Swift 只依赖一个 Facade + DataController，而不必直接引用所有 Layout/Category 头。

3. **C++ 与 STL**  
   - 凡带 C++（如 `vector`、`map`）的类不能直接进桥接头，只能通过 ObjC 类或 ObjC++ 的 `.mm` 封装后，用纯 ObjC 接口暴露给 Swift。  
   - 因此 **MachOLayout、LoadCommands 等保持为 ObjC++ 实现**，通过 DataController 或 MVParseService 在 ObjC 层封装成「打开文件 → 返回某棵树的根节点 + 选中节点」的接口即可。

### 3.3 依赖与构建

- **Capstone**：SwiftUI target 同样链接 `libcapstone.a`，并设置 Header Search Paths。  
- **系统库**：`mach-o`、`mach` 等保持与现有一致。  
- **最低系统版本**：若用 SwiftUI 新特性，可设为 macOS 12+；若需兼容更早系统，则用 @available 或条件编译。

---

## 四、阶段 1：文档与主界面

### 4.1 应用入口与文档

- 使用 **DocumentGroup**（SwiftUI 文档模型）：
  - 定义 `MachODocument` 遵循 `FileDocument`，用 `read()` 读入 `Data`，在内部调用桥接的 `MVParseService.loadFile(url:)` 或等价接口，得到「解析结果」抽象（如 `MVDataController` 或你封装的 Swift 侧 ViewModel 数据源）。
  - 在 `DocumentGroup` 的 scene 里传入该 Document 类型，实现「打开文件 → 创建文档」。
- 若希望先不换文档模型，也可以暂时用 **一个 Window + 工具栏「打开」**，用 `NSOpenPanel` 选文件，再调解析层得到同一数据结构。

### 4.2 主界面布局

- **NavigationSplitView**（或两列 List）：
  - **左栏**：树形结构（对应现有 `NSOutlineView` 的层级）。
  - **右栏**：详情（对应现有 `NSTableView` 的 Offset / Data / Description / Value）。
- 数据来源：从 Document 或 ViewModel 中取「当前树的根节点」和「选中的节点」；右侧根据选中节点展示其 `details`（行列表）。

### 4.3 从解析层拿到「树」和「详情」

- 在 ObjC Facade 或 DataController 中提供：
  - 根节点（如 `rootNode`）的**可遍历子节点**（children）。
  - 当前**选中节点**的 **details 行**（Offset、Hex、Description、Value）。
- 在 Swift 侧：
  - 定义 `NodeItem`（或直接包装 `MVNode`）：id、标题、children、可选 associated 的 MVNode。
  - 定义 `DetailRow`：offset、hex、description、value。
- 首次可用**同步**接口（解析在 Facade 内阻塞完成）；后续在阶段 2/3 再改为后台解析 + 进度回调。

---

## 五、阶段 2：树与表数据绑定

### 5.1 树形列表

- 用 **`List` + `OutlineGroup`** 或 **`DisclosureGroup`** 递归展示层级。
- 数据：将 `MVNode` 的 children 转成 Swift 的 `Identifiable` 数组（如 `[NodeItem]`），或对 MVNode 做轻量包装并实现 `Identifiable`（用节点指针或 `location+caption` 做 id）。
- 选中状态：用 `@State` 或 `@Binding` 保存当前选中的节点 id/对象，并驱动右侧详情。

### 5.2 详情表

- 用 **`Table`**（macOS 13+）或 **`List` + `HStack`/Grid** 展示多列：Offset、Data、Description、Value。
- 数据：从「当前选中节点」的 `details` 取行，映射为 `[DetailRow]`，绑定到 Table/List。

### 5.3 刷新与线程

- 解析若在后台线程完成，需在**主线程**更新 `@State`/`@Published`，可用：
  - ObjC 侧 completion 回调里 `DispatchQueue.main.async { ... }`，或
  - Combine / async 封装后，在 SwiftUI 中 `await` 或 `sink` 更新。

---

## 六、阶段 3：交互与副功能

- **搜索**：在 ViewModel 或 Facade 中提供「按字符串过滤节点」接口，驱动树与详情的过滤展示。  
- **停止**：解析层已有的 `backgroundThread` 取消逻辑，通过 Facade 暴露 `cancelParse()`，按钮调用即可。  
- **进度**：解析进度通过回调或 Combine 传到 Swift，用 `ProgressView` 或自定义进度条绑定。  
- **RVA 切换**：仅影响展示格式，在 Swift 侧根据开关切换 Offset/Data 列的显示方式。  
- **状态栏**：用 SwiftUI 的 `Text` 等展示当前选中节点或行数信息。  
- **偏好设置**：新开一个 SwiftUI 的 Settings 场景或 `Form`，替换现有 PreferenceController。  
- **附加到进程**：保留 Attach 的 ObjC 实现，通过 Facade 暴露「选择进程 → 读 Mach-O 头」接口，SwiftUI 只负责弹窗与结果展示。

---

## 七、阶段 4（可选）：逐步迁移解析到 Swift

- 从**依赖最少**的模块开始，例如：
  1. **Common** → 用 Swift 全局/枚举替代。  
  2. **ReadWrite** → 用 Swift 封装 `Data` 与字节序读写，接口与现有一致，再替换 DataController 内调用。  
  3. **LoadCommands / LinkEdit / DyldInfo / Exceptions** → 按「批次」用 Swift 重写，每批保留与 MachOLayout 的接口一致。  
  4. **DataController / Layout / MachOLayout** → 最后迁移，并逐步去掉 C++ STL，改用 Swift 集合类型。  
- **Capstone**：可继续用 C 库通过桥接调用，或评估 Swift 的 Capstone 绑定。  
- **mach-o 头**：可保留 C 头通过桥接使用，或用 Swift 重新声明需要的结构体。

---

## 八、文件与目录建议（SwiftUI Target）

```
MachOViewSwiftUI/
  App/
    MachOViewSwiftUIApp.swift      # @main, WindowGroup / DocumentGroup
  Scenes/
    ContentView.swift              # NavigationSplitView，左树右详情
    Document/
      MachODocument.swift          # FileDocument，读文件并调解析
  ViewModels/
    MachODocumentViewModel.swift   # 持有一个「解析结果」、选中节点、details 行
  Views/
    NodeOutlineView.swift         # 树形 List/OutlineGroup
    DetailTableView.swift         # 详情 Table/List
  Services/
    ParseServiceBridge.swift      # 封装对 MVParseService / DataController 的调用
  Resources/
    ...
```

现有 ObjC/C++ 解析代码可仍在项目根目录或 `Shared/` 下，通过 Target 归属与桥接头供 SwiftUI 使用。

---

## 九、风险与注意点

1. **大文件/大体积**：解析大 Mach-O 时仍要在后台线程，避免阻塞主线程导致界面卡顿。  
2. **内存**：树节点多时，SwiftUI 的 List/OutlineGroup 会做复用，注意不要在一次解析中保留过多未释放的 ObjC 对象引用。  
3. **Attach 与签名**：Attach 功能所需的 codesign 与 entitlements 在 SwiftUI 工程中同样要配置。  
4. **兼容性**：若需支持 macOS 10.15/11，部分 SwiftUI API（如 NavigationSplitView）需做系统版本判断或降级为 NavigationView + 双列。

---

## 十、最小可行路径（MVP）小结

若希望**尽快看到 SwiftUI 版能打开文件并展示树+详情**，可按以下最小步骤：

1. **新建 SwiftUI macOS App Target**，与现有 target 共用解析源码。  
2. **写桥接头 + Facade**：`MVParseService` 提供 `loadFile(url:) -> 根节点 + 子节点访问 + details`。  
3. **不先用 DocumentGroup**：先单窗口 + 工具栏「打开」→ NSOpenPanel → 调 `loadFile` → 得到树数据。  
4. **ContentView**：左 `List`（递归或 OutlineGroup）绑树，右 `Table` 绑当前节点的 details。  
5. **选中同步**：左栏选中一项 → 更新 `@State selectedNode` → 右栏刷新。

完成以上即可得到「SwiftUI 壳 + 现有解析」的可运行版本，之后再按阶段 2、3 补交互与体验，必要时再考虑阶段 4 的解析迁移。

---

*文档基于当前 MachOView 项目结构与《MachOView 项目分析报告》整理，可根据实际进度调整各阶段范围。*
