# macOS DeskPins 置顶语义与 Overlay 性能深研报告

## 结论摘要

本项目在“仅公开 API、无注入、无 SIP 关闭、MVP 尽量少权限”的约束下，要同时满足 **（a）跨 App 的强置顶语义** 与 **（b）交互无感**，关键矛盾在于：**macOS 没有公开 API 允许你直接把“别的进程的真实窗口”提升到更高的系统级 window level 并长期维持**；因此你的“强置顶”只能靠两条路：**不断把真实窗口 raise 到前面**（会抢焦点/扰动用户工作流），或 **把内容捕获后画到你自己的浮窗上**（即 ScreenCaptureKit 的“镜像/替身窗口”，需要 Screen Recording 权限）。这也是为什么你的内容预览改成 SCStream 后语义更接近“置顶”，但随之出现明显的交互副作用。citeturn9search0turn10view2

基于你当前分支实现（菜单栏 App 主循环 + overlay 三窗体 + 单窗 SCStream + latest frame cache），造成“输入卡顿、光标残影”的最高概率主因并不是“命中不准”，而是 **你在用户交互时仍显示镜像帧（有捕获/转换/合成延迟），用户看到的是“远程桌面式”画面**，从而感知到输入延迟与鼠标残影；再叠加 **主线程高频刷新与窗口重排**，会把这种体感放大。fileciteturn22file0 fileciteturn7file0 fileciteturn6file0 citeturn10view1

因此，**第一优先级的可落地改动**应当是“双态渲染策略 + 降低捕获负载 + 主线程减压”：

- **把镜像层从“交互态”里拿掉**：当 pinned 窗口处于前台/未被遮挡/正在交互时，**隐藏内容镜像预览窗**（保留 badge/拖拽手柄即可），让用户直接看到真实窗口；只有当 pinned 窗口被遮挡、需要“强置顶视觉语义”时才启用镜像层。这样通常能一次性显著改善“输入卡顿 + 光标残影”。fileciteturn7file0
- **显式关闭捕获光标**（`showsCursor = false`）并按帧状态跳过 idle 帧：ScreenCaptureKit 的官方讲解明确指出：视频样本以 `CMSampleBuffer` 传递且由 `IOSurface` 支撑，同时可通过帧状态判断 `complete`/`idle`，`idle` 表示没有新 `IOSurface`；另外 Apple 示例配置中也建议可隐藏鼠标光标。citeturn10view1turn9search0turn17view1
- **将 SCStream 的吞吐目标对齐到“预览用途”**：把 `minimumFrameInterval` 下调到 10–15 FPS 等级，并将 `queueDepth` 固定为 3（系统最小值）以压低延迟与 WindowServer 内存占用；Apple 文档强调队列深度默认最小为 3 且不要超过 8。citeturn7search0turn17view1turn9search0
- **主线程减压**：当前实现以 80ms 周期在主线程执行后台刷新并每次重建菜单 + 更新 overlays（且 pinned 存在时基本持续运行），这非常可能成为输入卡顿放大器。需要将“菜单渲染刷新”与“overlay 跟随刷新”解耦，并把窗口枚举/匹配等工作移出主线程或显著降频。fileciteturn22file0
- **运行形态改为 .app**：只要你以 `swift run` 运行，TCC 会把 Screen Recording 归属到宿主进程（Terminal），用户看到“Terminal 正在共享”是符合 macOS 权限/UI 的；要改成“DeskPins 正在共享”，必须让发起捕获的进程是你的应用包（签名/Bundle ID 稳定）。macOS 的屏幕录制授权与管理在系统设置中以“应用”为粒度呈现。citeturn0search6turn16search0turn9search0

在“无 Screen Recording”前提下，你能做到的置顶语义上限应定义为 **Soft Pin**：用户能把窗口标记为 pinned、维护 pinned 列表与顺序、快速 bring-to-front、跨 Space 可见的 badge/边框提示、以及一定程度的自动修复（例如窗口被关闭/重建后重新绑定到新窗口实例）。但 **无法在其他窗口遮挡时继续显示其内容**，也无法在不打扰焦点的情况下让其真实窗口永远处于最前。citeturn10view2turn15search4turn13search5

---

## 技术细节

### 无 Screen Recording 的可行性结论

在不使用 ScreenCaptureKit（或任何需要 Screen Recording 权限的内容捕获）时，你能稳定交付的“置顶语义”应被拆成三层能力，并清晰告知用户：

1) **状态层（可 100% 达成）**：pin/unpin、多窗口 pinned 队列、持久化、热键、menu bar 控制等（全不依赖录屏）。这层主要依赖你现有的 pinned store + WindowCatalog + Accessibility 定位。fileciteturn24file0 fileciteturn4file0

2) **提示层（可 100% 达成）**：你自己的 overlay（badge/边框/阴影/占位卡片）可以始终浮在最上方，因为它是你自己的 `NSPanel/NSWindow`。你当前就是三窗体组合（preview/drag-handle/badge）并设置 `.floating` 与跨 Space 行为。fileciteturn7file0

3) **内容层（无录屏无法达成）**：当真实窗口被其他 App 的窗口遮挡时，仍能“看到 pinned 窗口内容在最上层”——这本质上要么需要把别人的窗口提升到更高层（公开 API做不到），要么需要把内容捕获后画到你自己的浮窗上（需要 ScreenCaptureKit/录屏权限）。因此无录屏只能做到“提示仍在、内容不在”。citeturn9search0turn10view2turn15search4

补充约束：即使在“无录屏”模式下仍使用 `CGWindowListCopyWindowInfo` 做窗口枚举，WWDC19 安全讲解提到：窗口元数据会被隐私策略过滤，诸如窗口名称在未被用户预批准屏幕录制时不可用，并且该 API 不会弹系统授权框，而是直接过滤返回字段；所以“只靠 WindowCatalog 的标题去识别窗口”的鲁棒性会受影响，你更需要 Accessibility 或几何/进程信息作为主键。citeturn13search5

### 架构候选与对比

下面三套架构都满足“仅公开 API、不注入、不关 SIP”，差别在于 **是否以 ScreenCaptureKit 提供内容层**，以及 **在交互态是否显示镜像**。

**A: Lite（无录屏，Soft Pin）**

核心：只保留提示层 overlay（badge/边框/占位卡片），不做内容镜像；置顶语义依靠“快速 bring-to-front / 可选自动 raise”。  
关键点：
- Overlay 只做提示与交互入口（拖动、unpin、bring-to-front），其余区域尽量透传或在“窗口被遮挡时”主动拦截点击，避免误点到遮挡窗口。fileciteturn7file0
- 通过 Accessibility API 做窗口激活、移动、必要时 raise。Accessibility 低层接口用于“与可访问应用通信并控制 UI 元素”。citeturn11search0
- WindowCatalog 继续用于枚举、几何、前后顺序推断（allowedLayers=0 并按 frontToBackIndex 排序）。fileciteturn24file0

优点：不触发 Screen Recording；体验更轻量；不会出现“镜像导致的输入延迟/残影”。  
缺点：无法在遮挡时显示内容；“自动置顶”只能做成“自动 raise/切焦点”，容易打扰。

**B: Hybrid（可选录屏，默认 Lite，按需镜像）**

核心：默认 A；用户显式开启“强置顶内容层”时启用 ScreenCaptureKit；同时引入“交互态不镜像”的双态策略：  
- **交互态（Focused/Frontmost/未遮挡）**：隐藏 previewWindow，只显示 badge/drag-handle，并尽量不占用捕获资源。  
- **展示态（被遮挡/用户切到别的 App）**：启用 previewWindow，显示镜像内容维持置顶语义。

优点：把权限与价值对齐（用户明确知道“为了强置顶内容，需要录屏权限”）；在交互态避免 remote-desktop 感；综合体验最平衡。  
缺点：状态机复杂度上升（遮挡判断、焦点判断、切换抖动）；仍需处理录屏权限与系统共享提示。citeturn0search6turn16search0turn9search0

**C: Full mirror（录屏增强，强置顶内容层）**

核心：一旦 pinned 就尽可能保持镜像内容一直可见；并进一步用 ScreenCaptureKit 的高级元数据降低编码/合成成本（dirty rects、contentRect/scaleFactor 等），必要时多 stream 管理。  
- Apple 在进阶讲解中展示了如何从 `CMSampleBuffer` 元数据获取 `dirtyRects`，并“只编码/传输脏矩形区域”；也展示了 `contentRect/contentScale/scaleFactor` 的用法。citeturn17view1  
- ScreenCaptureKit 基础讲解明确：视频样本以 `CMSampleBuffer` 形式传递且有 `IOSurface` 支撑，并可通过帧状态识别 `complete/idle`。citeturn10view1

优点：语义最接近“真置顶”；可做出“被遮挡仍可见”的核心卖点。  
缺点：天然更吃资源与权限；如果镜像一直覆盖真实窗口，输入延迟/光标残影风险最高（特别是仍走“每帧 CI/CG 转换 + NSImageView”管线时）。fileciteturn6file0

综合建议：以 **B: Hybrid** 作为主线（默认 Lite + 可选录屏增强），并把 **“交互态不镜像”**设为硬约束，这是同时解决优先级痛点 1/2/3 的最短路径。

### 输入卡顿与光标残影根因树

你的两类症状（输入卡顿、光标残影）要分清“真实延迟”与“显示延迟”。在镜像覆盖真实窗口时，即便真实窗口响应很快，用户也会因为看到的是延迟帧而判断“输入卡”。fileciteturn7file0 fileciteturn6file0

**输入卡顿（尤其在 pinned 窗口内）根因树（从最可能到次要）：**

- **显示链路导致的“体感延迟”**
  - 交互态仍显示 previewWindow 的镜像帧：用户看到的是 SCStream → 解码/转换 → AppKit 绘制后的结果，而不是实时渲染的真实窗口。fileciteturn7file0
  - 帧率设置过高：当前单窗 stream 目标是 30 FPS，且你在输出回调里对每帧做 `CIContext.createCGImage`，属于高成本 CPU/GPU 同步点；即使只展示 latest，转换成本仍会持续发生。fileciteturn6file0 citeturn9search0turn10view1

- **合成层/转换层引起的资源抢占（真实卡顿放大器）**
  - 输出队列 QoS 设为 `.userInteractive`，会与主线程/UI 竞争调度，尤其在鼠标频繁移动或窗口内容变化大时。fileciteturn6file0
  - `NSImageView.image = ...` 的高频更新触发 AppKit/CA 合成开销与内存抖动（若每帧新建 CGImage/NSImage）。fileciteturn6file0

- **主线程占用与窗口重排**
  - 当前在主线程用 80ms 的定时刷新执行 workspace 刷新与 menu 重建，并每次调用 overlay 更新（进而可能触发 `setFrame/orderFront` 等 WindowServer 调用）。这在 pinned 存在时几乎持续发生，很容易成为系统输入处理的“抖动源”。fileciteturn22file0
  - overlay 三窗体每次更新都可能触发 WindowServer 重排/合成（尤其是跨 Space/全屏辅助窗口）。fileciteturn7file0

**光标残影根因树（从最可能到次要）：**

- **捕获帧包含光标（或包含光标导致 dirtyRects 高频）**
  - Apple 的示例与讲解都明确给出 `showsCursor = false` 作为常见配置；如果捕获帧里包含鼠标光标，且你展示帧率低于系统光标刷新，会天然出现“旧光标位置残留在上一帧里”的现象（看起来像残影/拖影）。citeturn9search0turn10view1turn17view1

- **帧状态未过滤**
  - ScreenCaptureKit 提供 `complete/idle` 帧状态语义，`idle` 意味着没有新 `IOSurface`；如果你对非 complete 帧也做转换/展示，可能引入重复帧、错误合成或额外抖动。citeturn10view1turn17view1

- **像素管线选择不当**
  - 用 Core Image 把 `CVPixelBuffer` 转成 `CGImage` 再转 `NSImage` 是“通用但不便宜”的路径；Apple 的讲解指出视频样本由 `IOSurface` 支撑，这更适合走“直接把 IOSurface 作为 layer contents”的零拷贝（或更少拷贝）显示路径，以减少延迟与拖影风险。citeturn10view1turn17view1

### SCStream 最优参数建议与流策略

你当前实现是“按窗口建流 + latest frame cache”。这个方向正确，但参数与显示管线需要“预览用途化”。fileciteturn6file0

**minimumFrameInterval**
- 建议分级动态设置：  
  - 顶层 pinned（但处于展示态需要镜像）：**1/15s（≈15 FPS）**  
  - 非顶层 pinned：**1/8s–1/10s（≈8–10 FPS）** 或直接停流（只保留静态占位）  
  - 交互态（真实窗口在前台）：**停流/隐藏镜像**（最省 & 最治本）
- Apple 的示例明确展示了将配置从 60 FPS 动态降到 15 FPS，并通过 `updateConfiguration` 应用到运行中的 stream（不必重启）。citeturn17view1

**queueDepth**
- 固定 **3**（系统最小）作为交互/预览用途的默认值：Apple 文档指出队列深度默认最小为 3，增大会更耗内存但减少阻塞，且不要超过 8。对你这种“latest frame 展示”的场景，应尽量压低延迟与 WindowServer 内存占用。citeturn7search0turn17view1
- 你当前代码对 queueDepth 做了 1–8 的 clamp，但建议改为 3–8，并把默认锁死 3。fileciteturn6file0turn7file0

**showsCursor 是否应关闭**
- 建议 **默认关闭**（`false`），除非你明确要在“展示态镜像”里表达鼠标位置（一般也不建议）。Apple 的示例配置多处演示隐藏光标。citeturn9search0turn10view1turn17view1
- 若未来一定要展示光标，建议走“单独绘制光标 sprite（来自当前鼠标位置）”而不是把光标烘焙进捕获帧，从源头避免残影。

**单窗口流 vs 多窗口流**
- 你当前“每个 pinned 窗口一个 stream”在 pinned 数量小（例如 ≤3）时可接受；但一旦 pinned 数量增多，每个 stream 都会带来持续的帧回调与处理开销。fileciteturn6file0
- Apple 进阶讲解展示了“一组窗口 filters → 多 stream”的 window picker 做法，同时也展示了 display filter 可以“including windows / including apps / excluding apps”。对 DeskPins 而言，更可控的策略通常是：  
  - 只对“当前需要展示态镜像”的窗口开 stream；  
  - 其余窗口停流（或低帧率）并以 badge/占位提示。citeturn17view1

**帧缓存策略、过期策略、背压策略**
- 你的 latest cache 已有“只保留最新帧”的背压雏形（不会无限积累）。fileciteturn6file0  
- 但真正的背压关键在于：**不要对每一个回调帧都做昂贵转换**。建议按 Apple 的语义：
  - 只在 `SCFrameStatus.complete` 时更新展示；`idle` 直接跳过。citeturn10view1
  - 进一步可利用 `dirtyRects`：若 dirtyRects 为空或面积极小（且你不展示光标），可选择不触发 UI 更新或只做局部更新。citeturn17view1
- 过期策略建议与你的“展示态/交互态”绑定，而不是固定 TTL：交互态直接停流最干净；展示态才维持 stream，并在“连续 N 秒未被遮挡/无变化”时降级或停流。citeturn10view1turn14search6

### 交互层策略建议

你的 overlay 目前是三窗体：previewWindow（忽略鼠标）、dragHandleWindow（选择性命中）、badgeWindow（可点击）。这为“轻量交互”打了基底，但要解决优先级痛点 4（unpin 不稳定）与进一步降低误点，需要把交互规则“状态机化”。fileciteturn7file0

**顶部拖拽区 / 边缘护栏 / 中区透传**
- 建议保留现有三区域概念，但增加“展示态 vs 交互态”差异：  
  - 交互态：中区透传（让真实窗口吃事件），顶部仅拖拽区命中，边缘护栏用于“防止误点到遮挡窗口边缘”。fileciteturn7file0  
  - 展示态：中区不再透传，改为“点击=bring-to-front（一次点击只做激活/抬升，不尝试合成转发原始点击）”，从而避免用户点在镜像内容上却误操作下面的别的 App 窗口。

**如何避免误点穿透下层窗口**
- 关键是：当 previewWindow 真的在“遮挡其他 windows 之上显示内容镜像”时，**它必须消费掉点击**，否则用户会“看着 A 点到 B”。目前你的 previewWindow 是 `ignoresMouseEvents = true`，这会天然产生误点。fileciteturn7file0
- 因此建议：展示态将 previewWindow 或其上层的捕获视图改为可命中（至少在中区），并把默认行为设为“消费点击并抬升 pinned 窗口”。

**单击/双击 unpin 一致性设计**
- 建议在 MVP 里只定义一种强一致动作：**单击 badge 永远 unpin**。不要让双击触发二次 toggle（会出现“偶尔可以”的错觉：双击变成两次单击）。  
- 实现建议：  
  - 点击判定改用 `NSClickGestureRecognizer(numberOfClicksRequired: 1)` 或明确检查 `NSEvent.clickCount >= 1` 后立刻禁用 badge（短暂 cooldown 200–300ms），避免重复触发。  
  - badge 命中区适度外扩（视觉上保持圆形，逻辑 hit area 可略大），并保障其窗口始终处于同 pinned bundle 的最高层（你当前按 preview→drag→badge orderFront 的顺序设计是对的，但需要避免跨 bundle 重排时 badge 被盖住）。fileciteturn7file0

---

## 实施计划

下面给出以 **B: Hybrid（默认 Lite + 可选录屏增强）** 为目标方案的分阶段计划，每阶段可独立验收，且都具备清晰回滚面。

### 目标方案

- 默认（无录屏）：Soft Pin（提示层 + 快速 bring-to-front + 稳定拖动/取消）。  
- 用户打开“强置顶内容镜像”后：进入 Hybrid；但 **交互态绝不镜像**，只在展示态开启镜像流。citeturn9search0turn10view2

### 里程碑与可验收项

**里程碑一：把“体感卡顿”先打掉（最短路径）**  
交付内容：
- 实装“交互态不镜像”：当 pinned 窗口处于前台/未遮挡/正在交互时隐藏 previewWindow，并停/降 capture。fileciteturn7file0
- 显式设置 `showsCursor = false`；并按 `complete/idle` 跳帧。citeturn10view1turn9search0
- `minimumFrameInterval` 下调到 10–15 FPS；`queueDepth = 3` 固定。citeturn7search0turn17view1
验收指标：
- 主观：在 pinned 窗口内输入与鼠标移动不再出现明显“跟手变慢/画面迟滞”。  
- 客观：DeskPins CPU 峰值下降、WindowServer CPU 峰值下降（对比改动前）；镜像态端到端展示延迟下降（可用帧时间戳与屏幕录制对比测量）。citeturn10view1turn17view1  
回滚策略：保留旧逻辑开关（FeatureFlag），一键恢复“始终镜像”行为。

**里程碑二：主线程减压与刷新解耦（解决“真实卡顿放大器”）**  
交付内容：
- 将“菜单构建/刷新”从后台刷新主循环中移除：仅在菜单打开/用户触发时刷新菜单项；后台循环只刷新 overlays 和必要状态。fileciteturn22file0
- 降低后台轮询频率（例如 150–200ms），并把 CGWindowList 枚举/匹配移到后台队列，在主线程只做最小 UI commit。  
- 尝试引入 AXObserver 通知来替代部分轮询（窗口移动/焦点切换等），降低持续轮询成本：Accessibility 低层接口明确提供 Observer 创建与通知机制。citeturn11search0turn12search1
验收指标：
- 主线程 Time Profiler：刷新 tick 的主线程占用显著下降（峰值/平均）。  
- 输入延迟：在 pinned 窗口内连续打字时，系统事件处理无明显 backlog（可用 Instruments 的主线程 runloop/卡顿指标观察）。  
回滚策略：保留旧 Timer 刷新路径作为 fallback。

**里程碑三：镜像显示管线升级（治本降成本）**  
交付内容：
- 从“CI/CG 转换 + NSImageView”升级到“IOSurface 驱动的 layer 显示”（或等价的低拷贝显示层）：Apple 明确指出视频样本 `CMSampleBuffer` 由 `IOSurface` 支撑，适合更直接的显示路径。citeturn10view1turn17view1
- 利用 `dirtyRects` 做 UI 更新节流（无变化不刷新/小变化局部刷新）。citeturn17view1
验收指标：
- CPU：镜像态 CPU 再下降一档；  
- 丢帧：镜像态 dropped/idle 帧处理符合预期（idle 不刷新）；  
- 主观：镜像态画面更稳定、残影进一步减少。  
回滚策略：保留旧渲染器实现，运行时切换。

**里程碑四：交互一致性与 unpin 稳定性**  
交付内容：
- badge 单击 unpin 的一致实现（手势识别 + cooldown + hit area 外扩）。fileciteturn7file0
- 展示态阻止误点穿透：镜像层消费点击并执行 bring-to-front。fileciteturn7file0
验收指标：
- “unpin 成功率”用户回访显著提升（可做埋点：badgeClicked 与实际 store 删除的一致率）。  
回滚策略：保留旧 badge 事件处理，允许用户关闭“点击即 unpin”。

### 风险与应对

- **遮挡判断抖动**：窗口快速切换时可能频繁在交互态/展示态切换，引入闪烁。应对：加入 150–300ms 的滞回（hysteresis）与“最近交互窗口优先稳定”。  
- **AXObserver 不可靠/权限问题**：部分 App 不发通知或发得不完整。应对：AXObserver 作为“降低轮询”的加分项，而非唯一信息源；保留低频轮询兜底。citeturn11search0turn12search1
- **录屏权限带来的信任成本**：必须把“开启强置顶内容镜像”绑定到明确的用户选择，并解释原因；系统也会在锁屏等场景显示隐私提示。citeturn16search0turn0search6turn9search0

### 验收表（建议指标口径）

- CPU：DeskPins 进程平均/峰值；WindowServer 峰值；镜像态与非镜像态分开统计。  
- 延迟：  
  - 交互态：键盘输入到真实窗口回显（主观 + Instruments）。  
  - 展示态：捕获帧显示延迟（可用 sampleBuffer 时间戳与显示时间对比，或视频标定）。citeturn10view1turn17view1
- 丢帧：统计 `idle/complete` 比例，确保 idle 不触发昂贵刷新。citeturn10view1turn17view1
- 主观流畅度：用户评分（1–5），至少覆盖“在 pinned 窗口打字/拖动/频繁切换 App”的典型场景。  
- 权限转化：启用录屏增强的用户比例、拒绝比例、拒绝后的留存（决定默认策略与文案）。

---

## 无录屏降级产品方案

如果产品策略上“必须无录屏”，建议把 DeskPins 的定位从“强置顶”收敛为 **Soft Pin 工作流加速器**，并把“置顶语义”改写为用户可理解的能力：

1) **Pinned 标签与空间存在感**：  
- 始终显示 badge/边框；跨 Space 可见（你目前 overlay 已设置 canJoinAllSpaces/fullScreenAuxiliary）。fileciteturn7file0  
- 提供 pinned 列表与快捷跳转（menu bar-first）。

2) **一键 bring-to-front（强推荐成为核心卖点）**：  
- 单击 badge（或快捷键）= bring-to-front；长按/右键 = unpin（把“误触 unpin”从主路径移走）。  
- 允许用户配置“自动 raise”的 aggressiveness：  
  - 关闭（默认，最不打扰）  
  - 温和（仅当窗口完全离屏或被最小化时恢复）  
  - 激进（检测到被遮挡就 raise，明确告知会抢焦点）

3) **窗口重建/失效修复**：  
- 利用 WindowCatalog 几何与 Accessibility 信息做“同源窗口”重新绑定（你已有 window catalog + accessibility 管线）。fileciteturn24file0turn11file0

4) **性能与信任优先的默认策略**：  
- 默认不申请 Screen Recording；也不展示任何“共享/录制”状态。  
- 在 UI 文案上明确：要实现“被遮挡仍可见的真·置顶内容”，必须开启录屏增强（作为未来可选项），并解释这是 macOS 隐私模型决定的——ScreenCaptureKit 在捕获前会请求用户许可并记录在系统的屏幕录制隐私设置中。citeturn9search0turn0search6