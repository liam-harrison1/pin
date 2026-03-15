# macOS 镜像覆盖层 DeskPins 交互回归深研与可落地修复方案

## 推荐方案摘要

你现在的两项回归，本质都来自同一个矛盾：**镜像层（floating overlays）在视觉上“盖住一切”，但在输入路由上并没有一个与“视觉最上层”严格一致、可证明正确的路由规则**。当你引入“直接交互模式”后，这个矛盾被放大：你把目标窗口的 preview 隐藏，只留下可穿透区域，但**其它 pinned 的 floating preview/handle 仍然可能在几何上覆盖目标真实窗口**，导致“看见 A、点到 B”。同时，切换时你会遇到**激活/聚焦的异步完成 + 80ms 刷新节拍 + 交互后冷却/串行 capture**叠加在一起的“短但可感知延迟”。fileciteturn27file0L1-L1 fileciteturn28file0L1-L1 fileciteturn29file0L1-L1

我推荐的最终架构是你 Brief 里提到的 **Interaction Lease Model** 的“工程化版本”：  
**把“直接交互”变成一个带握手的全局租约（lease），并在 lease 有效期间对“几何重叠的其它 pinned overlays”实施强一致的抑制策略（至少抑制它们的 preview 与任何可能截获输入的窗口层）**。这能保证：

- **交互正确性**：重叠场景下，**用户看到谁＝输入就稳定路由到谁**（至少“不会路由到别的目标”；在需要时通过租约切换实现）。  
- **切换近似即时**：UI 切换立刻发生（层级与高亮立即），而“放开穿透/把输入交给真实窗口”只在聚焦确认后发生，避免误路由；并通过“维持 stream warm”避免重新 warmup。fileciteturn30file0L1-L1
- **不牺牲你现在的流畅度收益**：保留 SCStream 会话复用 + 最新帧缓存（你现在的 StreamPreviewSessionRegistry + LatestPreviewFrameStore 已经在做这件事）。fileciteturn30file0L1-L1

关键实现点（最重要的三条）：

1) **“输入透明必须与视觉透明一致”**：只要某个 pinned 的镜像内容还可见，它就不能让输入“盲穿透”到别的真实窗口；否则必然出现视觉与路由不一致。AppKit 的鼠标事件分发机制本质上是 `NSWindow` 通过 `hitTest` 找到接收事件的 view 并派发。citeturn0search5turn3search2  
2) **租约期间抑制重叠竞争者**：当 A 进入 direct 交互（显示真实窗口）时，所有与 A 的 frame 相交的 pinned（B/C…）必须至少“隐藏它们的 preview 层”，否则它们仍是 floating，会继续视觉覆盖 A 的真实窗口。  
3) **切换握手（activation gate）**：切换时先“视觉上切过去（z-order/高亮立即）”，但**直到确认聚焦确实到了目标窗口**，才把 overlay 转成穿透/直通。这样避免“输入提前放开导致路由到旧窗口/别的窗口”，从而消除那段“短但可感知”的不确定等待。fileciteturn29file0L1-L1 fileciteturn32file0L1-L1

---

## 现状与根因

### 直接交互在重叠多 pin 下不可靠的结构性原因

你当前的 direct 交互模式链路是：

- 在 drag surface 的内容区点击触发 `.contentInteractionRequested`。fileciteturn27file0L1-L1  
- App 侧做 `activatePinnedWindow`（AX 激活/raise）并设置 `directInteractionPinnedWindowID`，从而让该 pinned 的 `shouldRenderPreview=false`。fileciteturn29file0L1-L1 fileciteturn28file0L1-L1  
- OverlayManager 收到 `shouldRenderPreview=false` 后对该 pinned：取消 capture、`orderOut` 预览、把 drag handle 切到 direct 模式（大区域 hitTest 返回 nil，仅顶部拖拽区继续命中）。fileciteturn27file0L1-L1

同时，对于其它 pinned：

- 它们仍然 `shouldRenderPreview=true`，预览窗体仍存在，并且你的 `PinnedPreviewWindow` 明确设置 `ignoresMouseEvents = true`（视觉有内容，但输入透明）。fileciteturn27file0L1-L1

在“多 pinned 重叠”时，只要发生以下任意情况，你就会出现“看见 A、点到 B/点不到”的回归：

- A 进入 direct 后，A 的 preview 被隐藏，但与 A frame 相交的 B/C 仍保留 floating preview（且它们本来就会在视觉上覆盖普通级别的真实窗口），导致用户在 A 的区域仍然“看见 B 的镜像”。  
- 这些可见镜像层又是输入透明或输入截获不稳定（取决于当前窗口栈与 hitTest 结果、以及你 direct 模式下 view-level hitTest 的穿透策略），于是点击/滚动在重叠区变成“不可预测”。fileciteturn27file0L1-L1

这不是“命中算法再调一调”能彻底解决的，它是 window-level 叠层 + 输入透明策略与视觉呈现策略不一致的必然结果。

### 切换仍有可感知延迟的叠加来源

你的切换延迟是多个固定节拍叠加出来的（即使每个都不大，体感会被放大）：

- 全局后台刷新节拍 80ms（Timer）。fileciteturn29file0L1-L1  
- post-drag refresh delay 60ms。fileciteturn29file0L1-L1  
- Overlay 侧交互后 capture 冷却 120ms（postInteractionCaptureCooldown）。fileciteturn27file0L1-L1  
- capture 串行限制 `maxConcurrentCaptures = 1`。fileciteturn27file0L1-L1  

以及一个更“隐形但关键”的点：

- `activatePinnedWindow` 的 AX 激活/raise 从 API 调用返回到“系统真正完成前台/聚焦切换”之间存在不可控的异步窗口；你目前在进入 direct 时**立即把 overlay 变成穿透**，于是用户在这段窗口内的输入会落到旧的焦点或其它窗口，产生“需要等一下才接受”的体感。fileciteturn32file0L1-L1

---

## 推荐最终架构与状态机

### 目标形态

维持你现在的三层 overlay（preview + drag handle + badge）思路不变，但引入两项架构级控制：

- **全局 Interaction Lease（交互租约）**：同一时刻最多一个 pinned window 处于 direct 交互“放开穿透”的状态。
- **Overlapped Competitor Suppression（重叠竞争者抑制）**：lease 激活期间，对“与 lease owner 几何相交的其它 pinned”执行一致的渲染与输入抑制策略，消灭视觉-路由不一致。

这会比“只把 owner 的 preview 关掉”更稳健，因为它直接消除了导致回归的必要条件：**lease owner 的真实窗口不再被其它 pinned 的 floating 镜像层覆盖**。

### 推荐状态机

我建议把状态机放在 App 层（和 `directInteractionPinnedWindowID` 同一层级），并让 `DeskPinsMenuBarStateController.overlayTargets()` 输出一个更丰富的渲染/交互意图（而不是只有 `shouldRenderPreview`）。当前 `shouldRenderPreview` 仅描述“要不要画 preview”，不足以表达“要不要抑制其它 pinned”。fileciteturn28file0L1-L1

建议新增：

```swift
enum OverlayInteractionMode {
  case pinnedPreview              // 默认：镜像为主
  case leaseAcquiring(owner: UUID) // 正在切换/激活（握手中）
  case leaseActive(owner: UUID)    // direct 交互有效
}
```

并且对每个 pinned 目标输出：

```swift
enum OverlayRenderPolicy {
  case mirrorVisible            // 正常画 preview
  case mirrorSuppressed         // 不画 preview（避免覆盖 lease owner）
  case directPassThrough        // owner 专用：允许真实窗口交互
}
```

#### 状态迁移

- `pinnedPreview` → `leaseAcquiring(owner=A)`  
  触发：用户点击 A 的内容区（你现在的 `.contentInteractionRequested`）。fileciteturn27file0L1-L1  
  动作：
  - 立即把 A 置为 pinned 栈顶（保持你“点击/拖动就上浮”的语义）。你现在通过 `activatePinnedWindow` + store.markActivated 已经在做，但建议拆出一个“UI 先行”的 fast-path（见后文“低延迟机制”）。fileciteturn28file0L1-L1 fileciteturn29file0L1-L1  
  - 计算 `suppressedIDs = {id | frame(id) intersects frame(A) && id != A}`，并对这些 pinned 输出 `mirrorSuppressed`（至少关掉它们的 preview，必要时关掉它们的 dragHandle）。  
  - 启动 activation handshake（异步），但此时**不把 A 变成 pass-through**（仍由 overlay “接管输入”，避免误路由）。

- `leaseAcquiring(owner=A)` → `leaseActive(owner=A)`  
  触发：确认系统焦点已经在 A（或 A 的 app 的目标 window）上。  
  动作：
  - A 输出 `directPassThrough`（此时才真正放开穿透），其它 suppressedIDs 继续 `mirrorSuppressed`。

- 任意 → `pinnedPreview`  
  触发：焦点离开 A、用户显式退出 direct（Esc / 点击 badge / 快捷键）、或 acquiring 超时。  
  动作：恢复所有 suppressedIDs 的 preview，回到默认镜像态。

#### 为什么这种状态机更稳

- 它把“是否允许真实窗口接管输入”从“用户点击的一瞬间”改为“系统确认聚焦完成之后”，从源头消灭“切换时短暂但可感知的不确定期”。  
- 它把“多层 pinned 重叠”变成一个确定的问题：lease owner 的几何域内，**只允许 lease owner 的真实窗口可见**（其它 pinned 的镜像必须被抑制），因此“看见谁＝操作谁”可被工程保证，而不是靠窗口栈巧合。fileciteturn27file0L1-L1

---

## 关键机制设计

### 重叠场景下的输入路由与层级策略

#### 核心原则

- **镜像可见 ⇒ 输入不可穿透**。否则用户看到的是 overlay 的画面，输入却路由到下层真实窗口，必然错。  
- **真实窗口可见 ⇒ 上方不得存在任何“几何覆盖且可截获输入”的 overlay 窗口**。否则滚轮/点击会被 overlay 抢走或被路由到错误 pinned。  
- AppKit 的事件派发路径是 `NSWindow.sendEvent:` → `NSView.hitTest:` → 特定 responder 方法。也就是说，你必须从“窗口层（window server 选择哪个 window 收到事件）”与“视图层（hitTest 谁接收事件）”两层同时确保一致性。citeturn0search5turn3search2

#### 具体做法

- 在 `leaseActive(owner=A)` 下：
  - A：只保留最小交互 affordance（drag bar + badge），内容区让真实窗口接管。  
  - suppressedIDs：至少 `previewWindow.orderOut`；并且要避免它们的 dragHandleWindow 在 A 的内容区“成为下一层命中目标”。你现在 drag handle 是全尺寸面板（frame=window frame），即使 view hitTest 返回 nil，它仍可能在 window-server 命中链中制造不确定性。fileciteturn27file0L1-L1  
  - 因此建议两步走：
    - **短期低风险**：suppressedIDs 的 dragHandleWindow 在 leaseActive 期间直接 `orderOut` 或 `ignoresMouseEvents=true`（但注意：如果你靠该窗口做拖动，leaseActive 下它本来就不该参与内容区输入）。  
    - **中期治本**：把 drag handle 从“整窗覆盖”改成“仅顶部 rail/window”，让内容区根本不存在 overlay window，这比任何 hitTest hack 都更可靠。

### 低延迟切换的实现策略

#### 把“菜单刷新”从交互路径中拿掉

你当前在很多交互后走 `updateMenuPresentation()`，它会 rebuild menu 并触发 overlay 更新。菜单构建不一定很慢，但它是一条不必要的同步路径。fileciteturn29file0L1-L1  
建议拆成两条：

- `updateOverlaysNow()`：只计算 overlayTargets 并调用 `overlayManager.updateOverlays`（交互路径用它）。  
- `updateMenuLater()`：仅在菜单打开、或 pinned 列表变化、或定时刷新时做。

这样能在“用户连续快速切换 pinned”时减少主线程同步工作，改善“立即切换”的体感。

#### activation handshake（切换握手）

实现方式建议从易到难分两档：

- MVP（足够稳）：**短轮询确认焦点**  
  - 在触发 `activatePinnedWindow(id:)` 后，起一个 `Task` 每 16ms（或 10ms）检查一次“当前 focused window 是否匹配 owner pinned”。你已有 `LiveFocusedWindowReader` 可直接读取 focused window snapshot（AX + frontmostApplication）。fileciteturn31file0L1-L1  
  - 匹配方式：用现有 pinned store 的 `matchingWindow` 逻辑（你在 stateController 已经有 `focusedPinnedWindowID()`，但它依赖 workspaceSnapshot；建议加一个不依赖完整 refresh 的 fast matcher）。fileciteturn28file0L1-L1  
  - 超时：120–200ms。超时则回退到 `pinnedPreview` 或停留在 `leaseAcquiring` 并提示“点击再次尝试/按 Esc 退出”。

- 进阶（更优雅）：AXObserver/NSWorkspace 通知驱动  
  - 监听 app 激活/前台切换并在通知里更新状态，减少轮询负担。你可以把它作为后续优化，不作为第一阶段必需。

#### 保持“立即切换”的视觉效果

哪怕焦点还没确认，UI 也应立刻做三件事：

1) pinned 栈顺序立即调整（被操作的 pinned 立刻浮到最上）。  
2) 对重叠竞争者立刻 suppression（不然用户还会短暂看到其它 preview 覆盖）。  
3) lease owner 显示“正在接管输入”的轻量提示（比如 drag bar 变色/小 spinner）。  

这样用户体感是“切过去了”，而不是“点了没反应”。

### 保持 capture warm，避免恢复镜像时的重新 warmup 延迟

你现在 StreamPreviewSessionRegistry 的 session idleTTL 默认 1.8s，且只有在 `previewImage(...)` 被调用时才会 touch session。fileciteturn30file0L1-L1  
如果在 leaseActive 期间你把大量 preview 抑制掉、并且也不再调用 capturePreview，那么 session 很可能在 1.8s 后被停掉，导致“退出 direct/切回镜像时”出现 warmup 等待（你现在 warmupTimeout=0.2s）。fileciteturn30file0L1-L1

因此推荐：

- lease 期间 **不以 `shouldRenderPreview` 为依据去 stopAllPreviews**。你当前 OverlayManager 会在 `!hasPreviewTarget` 时 `stopAllPreviews()`，如果你在 lease 下把 previews 全部 suppress，就会触发这一逻辑，直接杀掉所有 session。fileciteturn27file0L1-L1  
- 两个可选实现：
  - **最小改动**：把 streamIdleTTL 提高到 8–15 秒（足够覆盖用户一次 direct 交互会话），并且只在 pinnedCount==0 或权限失效时 stopAll。  
  - **更精细**：lease 期间用低频（例如 500ms–1000ms）“touch”所有 pinned session（不必渲染），保持它们不被 registry 回收；必要时给非 top pinned 降低 FPS。ScreenCaptureKit 支持在不重启 stream 的情况下更新配置/过滤器；Apple 的示例与 WWDC 都明确展示了 `updateConfiguration`/`updateContentFilter` 的模式。citeturn1search0turn0search2

---

## 分阶段实施计划

每阶段都要满足：可单独上线验证、可快速回滚、不破坏你当前“不卡顿/少残影/不模糊”的收益（你现在 preferredFrameRate=15、queueDepth=3、showsCursor=false、complete-frame filtering 已经很好）。fileciteturn30file0L1-L1

### 阶段一：修复交互正确性（最低风险，最快见效）

交付点：

- 在 App 层新增 `OverlayInteractionMode`（至少 `pinnedPreview / leaseAcquiring / leaseActive`）。  
- 当进入 leaseAcquiring/leaseActive(owner=A) 时：  
  - 计算所有与 A frame 相交的 pinned IDs，令其 preview **直接 suppress**（不让它们的镜像覆盖 A 真实窗口）。  
  - 同时对这些 suppressed pinned：至少让它们的 dragHandleWindow 不再参与输入命中（orderOut 或 `ignoresMouseEvents=true`）。  
- 切换时先不放开穿透：只有在确认 focused window 匹配 A 后，才进入 leaseActive 并允许 A 内容区直通。

验收：

- 重叠场景下：在 A direct 时，A 的内容区不会再出现 B/C 的镜像覆盖（视觉一致）。  
- 点击/滚轮：在 A direct 时，A 内容区滚动/点击稳定作用于 A（命中正确率显著提升）。

回滚策略：

- Feature flag：关闭 lease 模式，回到现有 directInteractionPinnedWindowID + shouldRenderPreview 逻辑。fileciteturn28file0L1-L1

### 阶段二：降低切换延迟（把“短但可感知”压到可忽略）

交付点：

- 拆分 `updateMenuPresentation()`：交互路径只走 overlay 更新，不 rebuild menu。fileciteturn29file0L1-L1  
- activation handshake 轮询从“等下一次 80ms background refresh”改为“交互后立刻启动 16ms 轮询”，并在成功时立刻切 state。  
- 把 postDragRefreshDelay、postInteractionCaptureCooldown、maxConcurrentCaptures 对“切换交互接受”的影响隔离：  
  - 切换 direct 不应该被 capture 冷却影响（冷却只影响 preview 刷新，不应影响输入接管）。fileciteturn27file0L1-L1

验收：

- 切换延迟（定义见下文）P50 < 40ms、P95 < 120ms（以“leaseAcquiring → leaseActive”为准）。  
- 主观：用户无需“等一下再拖/再滚动”，连续切换不会偶发落到旧窗口。

回滚策略：

- 保留旧的 refresh cadence/ reconcile 逻辑作为 fallback（出现异常就回到阶段一的正确性优先模式）。

### 阶段三：治本降低输入路由复杂度（建议一定做，但可后置）

交付点：

- 把 drag handle 从“整窗覆盖的 panel”改为“仅顶部 rail 的 panel”。  
  - 这样 A direct 时内容区上方根本不存在 overlay window，不再依赖 view-level `hitTest` 的穿透技巧，输入更确定。  
  - 同时减少多 pinned 时 window-server 命中链的复杂度。  
- 视需要保留 edge guard：用更窄的窗口或 tracking area 方式实现。

验收：

- 重叠 direct 交互下，点击/滚轮命中正确率进一步提升到“几乎不可能误路由”。  
- 事件监控显示 overlay 窗口截获的内容区输入显著减少。

回滚策略：

- 保留旧 dragHandleWindow（全尺寸）实现，可用运行时开关切回。

---

## 监控验收指标与失败模式

### 建议埋点与指标口径

建议用 `os_signpost`/统一 Logger 给出可量化目标（不必一开始就做很复杂，但至少要在切换与命中上有数据）。

- **切换延迟（核心）**  
  - t0：用户在 pinned B 上触发“我要交互 B”的输入（content click / switch action）。  
  - t1：状态机进入 `leaseAcquiring(owner=B)`（UI 已高亮/置顶）。  
  - t2：确认 focus 已到 B 并进入 `leaseActive(owner=B)`（此刻才允许内容区直通）。  
  - KPI：`t2 - t0`：P50、P95、Max。  
  目标建议：P50 < 40ms，P95 < 120ms，Max < 200ms（超过则要 fallback）。

- **点击命中正确率**  
  - 在重叠区域：用户点击“视觉最上层 pinned”的内容区后，最终 lease owner 是否与视觉一致。  
  - KPI：正确次数/总次数；目标建议 ≥ 99.5%（低于此值，用户会强烈感知“不可靠”）。

- **回归阈值（性能）**  
  - DeskPins CPU：与当前版本对比不增加 > 15%（同场景、同 pinned 数）。  
  - WindowServer CPU：不增加 > 10%。  
  - Preview 帧到达间隔：仍能维持你当前“无明显模糊/卡顿”的主观质量（你现在 15 FPS + queueDepth 3 是合理预览档）。fileciteturn30file0L1-L1  
  - 由于 ScreenCaptureKit 的队列深度与帧率配置会显著影响资源占用，Apple 示例明确提到 queueDepth 增大会增加 WindowServer 内存开销，同时也展示了在线降档到 15FPS 并 `updateConfiguration` 的模式。citeturn1search0turn0search2

### 失败模式与快速回退

下面这些症状一旦出现，应视为“方案在当前实现形态不可行或存在严重缺陷”，需要立刻回退到上一阶段：

- **lease acquiring 超时频繁**（>1% 交互）  
  表现：用户点击切换后长期停留在“正在接管输入”，最后回到 preview 或需要重复点击。  
  回退动作：直接改为“单击只激活不直通”，或缩短 suppression 范围，或恢复旧 reconcile 机制。

- **direct 模式下仍出现其它 pinned 镜像覆盖**  
  表现：A direct 时还能看到 B 的 preview 在 A 的区域出现。  
  原因：suppressedIDs 计算不全（比如坐标系转换、不同屏幕 backing scale、frame stale）。  
  回退动作：扩大 suppression 条件（frame 允许容差），或临时采取“direct 时 suppress 全部 pinned previews”的硬策略（但注意 stream warm 机制要保留）。

- **性能回归**（CPU、掉帧、再次出现残影/卡顿）  
  表现：切换机制引入过高频 refresh/capture，破坏了你现在的收益。  
  回退动作：把 handshake 轮询降频/改通知驱动；把 streamIdleTTL 设回较小并只 touch top few；必要时关闭“所有 pinned 都 warm”的策略。

---

## 备选方案对比与推荐顺序

### 方案一：Interaction Lease + Overlap Suppression（推荐主线）

复杂度：中；风险：低到中；预期效果：最高（正确性与低延迟兼顾）。  
关键点：你要扩展 `shouldRenderPreview` 为更细的 render/input 策略，并引入 handshake。fileciteturn28file0L1-L1

推荐顺序：先做（阶段一、二都在这条线上）。

### 方案二：不做 suppression，只做“点击镜像即切换，且镜像不穿透”

复杂度：低；风险：低；预期效果：能解决一部分“误点”，但无法解决“direct 时其它 pinned 镜像仍覆盖真实窗口”的根因。  
它最多让“点击谁就切谁”更稳定，但仍会在 direct 重叠区出现视觉遮挡问题，因此不建议作为最终形态。

### 方案三：单一全屏 Canvas Window 承载所有 pinned（高阶重构）

复杂度：高；风险：中到高；预期效果：理论上最好（hitTest/层级完全由你控制，window 数量也更少）。  
但它对你现有架构改动很大（所有 pinned 变成一个 window 内的 layer/子视图体系），且需要非常小心地做“区域穿透”与多屏空间行为。适合在方案一稳定后再评估。

---

## 可直接开工的 TODO Checklist

以下按优先级排列，尽量映射到你现在的代码结构与文件。

### P0：马上修复“看见谁就操作谁”的正确性

- [ ] 在 App 层新增 `OverlayInteractionMode`（至少 `none / acquiring / active`），替代单一 `directInteractionPinnedWindowID` 的表达力不足问题。  
- [ ] 在 `DeskPinsMenuBarStateController.overlayTargets()` 中：  
  - [ ] 当存在 lease owner 时，计算 `suppressedIDs = pinnedIDs where frame intersects ownerFrame`；  
  - [ ] 输出给 Overlay 的目标里，给 suppressedIDs 标记为 `mirrorSuppressed`（不要只靠 `shouldRenderPreview=false` 复用 direct 语义）。fileciteturn28file0L1-L1  
- [ ] 在 `PinnedWindowOverlayManager.updateOverlays(with:)`：  
  - [ ] 支持 suppressed 目标：至少 `previewWindow.orderOut`，并让其 dragHandleWindow 在 leaseActive(owner) 期间不参与命中（orderOut 或 ignoresMouseEvents）。fileciteturn27file0L1-L1  
  - [ ] **不要因为“当前没有任何 shouldRenderPreview=true”就 stopAllPreviews**（否则会杀掉 warm session，影响切回即时性）。fileciteturn27file0L1-L1  

### P0：让切换“立刻发生”并消灭不确定等待

- [ ] 在 `.contentInteractionRequested` 的处理里（`main.swift`）：  
  - [ ] 把进入 direct 的动作改为：先进入 `leaseAcquiring(owner=id)`（UI 置顶/高亮立即），启动 activation handshake；  
  - [ ] 只有 handshake 成功才转 `leaseActive(owner=id)` 并放开内容区穿透。fileciteturn29file0L1-L1  
- [ ] 新增一个 16ms 轮询（或通知驱动）确认 focused window 是否为目标 pinned（可复用 `LiveFocusedWindowReader`）。fileciteturn31file0L1-L1  

### P1：移除交互路径上的“无意义同步工作”

- [ ] 将 `updateMenuPresentation()` 拆分：交互事件只更新 overlays，不 rebuild menu；menu 仅在 menu 打开或定时刷新时更新。fileciteturn29file0L1-L1  
- [ ] 保留 80ms timer 做后台对齐（窗口 frame stale 修复、权限状态刷新），但不要让它成为“切换是否生效”的唯一节拍。fileciteturn29file0L1-L1  

### P1：保持 stream warm，避免切回镜像时卡顿

- [ ] 将 `streamIdleTTL` 从 1.8s 提升（例如 8–15s），或在 leaseActive 期间对所有 pinned 做低频 touch（500ms–1000ms），确保不触发 warmupTimeout 等待。fileciteturn30file0L1-L1  
- [ ] 维持你现在的 15FPS + queueDepth 3（预览档），只在需要时对 top pinned 提升帧率（可用 `updateConfiguration` 思路；Apple 示例与 WWDC 都展示了在线更新配置）。citeturn1search0turn0search2  

### P2：治本降低输入路由复杂度（建议做）

- [ ] 将 drag handle 从“整窗尺寸 panel”改为“顶部 rail panel”（或至少在 leaseActive 时把整窗 handle orderOut，只保留 rail）。  
- [ ] 为 rail 增加明确的“退出 direct / 切换 pinned”的 affordance（例如一个小 tab switcher），避免用户只能靠点到其它 pinned 的内容区来切换（这在 suppression 期间会不可用）。

以上执行顺序能保证：你先把“交互正确性”稳住（P0），再把“立即切换”做到体感无延迟（P0/P1），最后再做结构优化进一步降低长期维护成本与隐藏 bug 风险（P2）。