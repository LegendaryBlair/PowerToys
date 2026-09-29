# PowerToys 多 Agent 验证：阶段 1 初步设计

**状态：讨论后的修订草案，待 review；本轮只交付设计与计划，不开始框架实现。**

本文取代此前以 SG 为试点、单列 scenario driver 的初稿建议。
[Brainstorm](multi-agent-verification.md) 是讨论来源，
[用户随想](multi-agent-verification-comments.md) 保留原文，
[执行计划](multi-agent-verification-execution-plan.md) 给出后续落地顺序。
`tools\verification\` 的早期代码是暂停中的未验证草稿，不是本设计的实现或约束。

## 1. 已确认方向与目标

- CLI-first，不先做 Web 界面。
- 阶段 1 以生成、完善可靠的 checklist/profile 及其引用的 helpers 为目标。
- 试点选 Color Picker：当前 skill 没有其专用 checklist/profile，产品刚完成 WinUI 3 迁移，复杂度适中。
- 初始假设是迁移不改变既有 UX 行为；明确声明的例外单独 review。不是要求两代 UI 像素相同。
- 完善阶段的材料来自 baseline checklist 和选定的 merged PR claims。这里的“训练”是验证能力迭代，不是模型参数训练。
- 系统同时面向 module checklist verification 和 active PR verification，但二者不必使用相同的 agent 编排。
- 不新增 scenario driver 概念；模块操作组合和公共机械操作都归入 helper/test infra。
- 产品 FAIL 可以是正确、可信的执行结果；不能用 PASS 数增加作为 profile 收敛的定义。

SG 的经验要求按证据改进正确的层：模块知识缺失改 profile，等待/身份/输入/记录错误改 helper，
期待有问题则提交 checklist 变更。不能每次遇错都给 profile 加一句注意事项。

### 两个阶段与 skill 的两种模式

| 维度 | 阶段 1：生产/完善能力 | 阶段 2：使用成熟能力 |
|---|---|---|
| 主要输入 | Baseline checklist + merged PR claims + 产品资料 | Active PR + 适用的既有 profile/helpers |
| 目标 | 得到可重复使用、能够产出可信结果的验证材料 | 判断这次 PR 的承诺是否成立 |
| 角色 | Engineer、Executor、Evaluator 的迭代 | Claim 提炼/执行、结果评估；不默认加入 Engineer |
| 发现能力缺口 | 本阶段内定向改进 | 明确转回完善任务，不在验证中悄悄修改方法 |
| 产物 | 接受的材料版本、适用范围、已知限制与确认记录 | PR 结果及必要的相关回归，不等于模块全面通过 |

阶段不是 skill 的 A/B 模式：A 是执行模块清单，B 是从 PR 提炼 claim 并验证；
阶段 1 可以用 A 验证 baseline，也用 B 的方法从 merged PR 提炼补充材料。
阶段 2 主要处理 active PR，也能使用成熟材料执行模块回归。第一版只落地阶段 1。

## 2. 最小架构

```text
人：范围、指导、决定
          |
          v
CLI Orchestrator ---- 本地工作记录、任务与待审事项
          |
          +-- Engineer：准备/改进 checklist、profile、helpers
          +-- Executor：操作、观察、记录、恢复
          +-- Evaluator：核验证据、归因、建议下一步
                           |
          现有 verification skill / helpers / recorder
                           |
                    指定的产品 build 与环境
```

首期一个模块、一个活动 agent 任务、一个 live 桌面，按依赖串行执行。
不设全模块调度、分布式队列、常驻 agent 集群、投票系统或通用 UI DSL。
Orchestrator 调度和校验事实，不通过自身的一句模型判断宣布产品正确。

### 技术建议，而非已批准选型

| 部分 | 初步建议 | 实现前需要确认 |
|---|---|---|
| CLI/控制器 | TypeScript/Node | 工具链与依赖成本；PowerShell-only 仍是替代方案 |
| Agent 接入 | Copilot SDK，放在一个薄 runtime adapter 后面 | 实际会话身份、权限限制、结构化输出、取消与恢复能力，先做验证，不凭接口名称猜测 |
| Windows 操作 | 保留现有 PowerShell helpers | 只修真实问题，不为框架统一而重写 |
| 状态持久化 | 本地 SQLite + 文件 artifact | 驱动/运行时选择及依赖批准；不存大段截图、UIA 树或会话缓存进数据库 |
| 进程形态 | 按需运行的 CLI；同一工作根单写者 | 不先开发 daemon；退出后如何识别尚存 worker 必须可验证 |

不同 CLI root 不能规避同一 Windows 桌面的占用：同机需共享实际资源检查/互斥，
其范围包括用户配置和安装实例。它只能协调本系统的 worker，不能阻止用户移动鼠标。
工具权限、文件 ACL、组织策略仍有效，角色 prompt 不是安全沙箱。
新增 SDK/数据库依赖需按仓库要求批准并登记；本轮不安装。

## 3. Agent contract：输入、输出、允许操作、交接条件

### 3.1 三个角色

| 角色 | 输入 | 必须交付 | 不允许 |
|---|---|---|---|
| Engineer | 指定 baseline/PR 资料、当前材料、评估或人工反馈 | 候选 checklist/profile/helper；diff；改动原因和问题引用；影响断言；验证/确认计划与已执行结果 | 改产品来消除 FAIL；改旧证据；自行批准期待削弱或越权操作 |
| Executor | 指定输入版本、断言范围、产品 build、环境、授权 | 逐条实际操作与观察；暂定 verdict；原始错误；未执行原因；恢复材料；run archive 引用 | 热修正在评分的正式材料；改变期待；以重启/替代入口冒充原路径 |
| Evaluator | 本轮材料、原始证据、暂定结果、可比的前轮记录 | 每个结论是否被证据支持；问题所属层与不确定性；保留/补测/改进/人工决定的建议及范围 | 只读 summary；直接覆写旧 report；将产品 FAIL 自动交给 Engineer 修产品 |

Engineer 可以进行获准的隔离诊断和 helper 回归；需要 live 桌面时同样占用资源、记录动作并恢复，
诊断不算 Executor 的正常验收证据。Executor 可写必要的 run-local glue，但机械修正要形成可追踪的候选，
不能临时修改正式 helper 后不留版本。

Evaluator 与本次作者/执行者使用独立 runtime session，读取相同证据而不是依赖作者私下解释。
身份由 runtime 提供，换一个自填名字不算独立；首期不要求不同模型投票。

### 3.2 共同任务信封

| 字段 | 含义 |
|---|---|
| `jobId / roundId / taskId / dispatchId` | 模块工作、改进轮次、任务及本次实际派发；重新派发产生新 dispatch |
| `role / sessionId` | 角色与实际 runtime 会话身份 |
| `inputRevision / buildRefs` | 本轮 checklist/profile/helper 字节身份，产品 commit/artifact 身份 |
| `caseIds / assertionIds` | 本任务覆盖范围；不允许交回另一批结果充数 |
| `authorization` | 允许工具、写范围、状态修改、诊断投入和停止条件 |
| `artifactRefs` | 原始输入、观察、报告、diff、确认结果的路径/相对引用和 hash |
| `executionStatus / error` | completed、error、cancelled、unknown；与产品 verdict 分离 |
| `requestedNextAction` | 有理由和证据的建议；不是 agent 自行启动下个角色的权限 |

程序检查信封、版本、产物存在与完整性；Evaluator 检查语义和证据是否足够。
格式合法不代表业务正确；`exit 0` 或 `completed` 不等于 PASS。
同 dispatch 的相同结果可幂等重送；不同内容的重复提交拒绝；已取消任务的迟到结果只保留历史。

### 3.3 每次改进必须回答

1. 上次发生了什么，证据在哪里？
2. 修改 checklist、profile 还是 helper，为什么？
3. 哪些行为期待保持不变，哪些变化需要人批准？
4. 确认哪些断言、为什么足够、哪些共享消费者可能受影响？
5. 相比上一版，是否真的减少执行问题，还是只改变了判定？

纯产品故障不触发“改 profile 直到 PASS”。未定位问题可以先执行有明确问题的诊断任务；
相同条件、没有新信息的重跑不能被称作一次改进。

## 4. Orchestrator 与小型状态机

### 4.1 管什么

Orchestrator 是当前工作状态的唯一写入方：记录输入版本、派发、结果引用、人工决定、
受影响断言和恢复事实，并按规则派下一步。它不重新实现 recorder 的 verdict 聚合。
Agent 只能提交结果/建议，不能直接把全局状态设为“已接受”。

首期可以将实现表示为两个字段，但通过合法转换表约束组合：

- `phase`：prepare / execute / evaluate。
- `status`：queued / running / waiting-human / interrupted / finished。

另记录 `outcome`（accepted-scope、partial、stopped）及 `resumeTarget`。
这些都是流程状态；产品 PASS/FAIL/BLOCKED/NOT-OBSERVED 是另一组字段。
恢复未完成是影响后续 live 调度的事实，不再造一组按动作标签的永久锁。

### 4.2 合法交接

| 当前任务/事件 | 校验与判断 | 后续 |
|---|---|---|
| 初始 prepare 完成 | 材料与来源齐全 | Evaluator 审查初始期待和覆盖，随后提交人工 baseline 决定 |
| 人确认初始清单/范围 | 决定匹配材料版本、环境与授权 | execute 入队 |
| execute 完成或有可读的部分结果 | 保留原始错误、逐条缺口、恢复事实 | evaluate；测试失败不能阻止审查 |
| evaluate：证据缺失 | 明确需要补什么；期待和方法未改变 | affected assertions 定向 execute |
| evaluate：profile/helper 缺陷 | 明确改进层、影响与确认计划 | Engineer prepare；新候选先审查再确认执行 |
| evaluate：产品不符合有效期待 | 证据足够；根因可仍未知 | 保存产品 finding，执行其他 eligible 覆盖 |
| evaluate：期待有冲突/改动后退化无法解释/超授权 | 生成具体决定材料 | waiting-human，记录 resumeTarget |
| 确认结果充分、新 Executor 复用成功 | 满足事先约定的接受范围和条件 | 等待人接受材料；然后 finished/accepted-scope |
| 预算耗尽/人停止 | 完成可行的清理与证据保存 | finished/partial 或 stopped，未完成项仍可见 |
| worker 消失或状态未知 | 不猜测 UI 动作有没有发生 | interrupted；先检查实际资源，再决定新派发 |

改进后先 evaluate 候选 diff，再 execute 确认，再 evaluate 证据；无需每次重建整个 checklist。
同一轮只合并有相同前置状态与操作的 case，断言分别保留。执行前可去除明显重复；
实际执行后再根据窗口生命周期、恢复与交互成本调整。不追求 case 数最少。

### 4.3 重启不重复手势

先在事务中登记 dispatch 和占用，再启动 worker，随后记录实际 session/process 身份。
启动与记录之间不是一个跨系统事务：控制器重启先检查待启动/运行中任务是否确实仍在执行。
无法确定时进入 interrupted，不能自动再按一次快捷键。

结果提交与后续任务入队在事务中完成；artifact 写完并校验后才被引用。
暂停不等于取消：pause 停止新步骤，到安全边界交出状态；cancel 请求清理后结束。
强制终止不能保证 `finally` 执行，不能按心跳过期自动释放 live 桌面。

## 5. Human-in-the-loop

### 首期建议：监督式，而非每一步审批

已批准范围内的 execute/evaluate 自动交接；Engineer 可生成候选并进行获准的离线回归。
初始 checklist、期待/范围变化、候选首次进入 live 确认、权限扩大、无法解释的退化、
材料最终采纳由人决定。后续若需要更多自治，可预授权特定 operational 改进，不默认启用。

每个待审事项包含：

```text
问题：什么与预期/前轮不同？
依据：具体断言、材料版本、原始观察、diff。
未知：缺什么信息，不能下什么结论？
选项：接受 / 退回并指导 / 定向补测 / 暂停或结束。
建议：推荐动作、影响范围、恢复方法。
继续位置：决定后回到 Engineer、Executor 还是 Evaluator。
```

人可用自然语言指导。涉及权限/语义变更时，系统先展示整理后的**结构化动作与作用范围**，
经人确认才写入有效决定；不把模糊的“可以”升级成更广授权。明确选择命令可直接记录。
决定绑定候选 hash 与范围；材料变化后旧决定不自动有效。

人离线时保存工作，不靠 agent 常驻等待，也不默认批准。首期串行可以暂停整个当前循环；
已经确定与该决定无关的 case 可形成独立工作包，不要求先做并行调度。
检查结果变差时不预判 profile 退化：也可能是旧假 PASS 被纠正，需要比较实际操作与证据。

## 6. 本轮输入版本与恢复边界

“冻结 bundle”不再作为新增打包概念。只记录本轮实际使用的 checklist/profile/helper 文件、
commit 和必要的 dirty diff/hash。Engineer 在候选目录中改进，Executor 不静默热修正式输入。
保持脚本原始执行上下文和相对依赖；证据快照不作为换目录执行的借口。

“隔离环境”具体化为：若本轮修改的快捷键、剪贴板、窗口或输入状态未恢复，
先暂停依赖它们的 live 操作，修复恢复问题；离线审查仍可继续。
恢复后解除当前限制，不让历史错误永久阻止后续工作。
恢复声明必须有完整作用域和对比证据，而不是一个成功返回值。

受控 worker 仍不能阻止真人改变桌面；每个关键动作前保留实际身份/前台检查。
不关闭用户窗口、不清空用户剪贴板、不通过改 registry 或重置默认来掩盖不完整恢复。

修复来源变化后形成新确认 run，链接前轮证据；不自动跨 archive 合成新的模块 PASS。
旧 archive 不改写，后来的纠正是带理由的关联记录。

## 7. Color Picker 的阶段 1 数据与正确性依据

### 7.1 输入材料

| 材料 | 用途 | 不能证明什么 |
|---|---|---|
| Baseline checklist/旧文档/现有测试 | 形成迁移前行为期待；没有可靠 baseline 时先草拟、溯源、让人确认 | 不是天然正确，也不自动成为已批准的新清单 |
| [#49174](https://github.com/microsoft/PowerToys/pull/49174) WinUI 3 迁移 | 提炼 parity claims，列出 UI 识别变化与明确例外 | 作者自报通过或 merged 状态不能代替本系统执行 |
| [#48762](https://github.com/microsoft/PowerToys/pull/48762) 放大视图排除 picker | 屏幕取色/放大内容的候选回归场景 | 静态 API 返回不能证明实际画面 |
| [#49973](https://github.com/microsoft/PowerToys/pull/49973) 刷新率特殊值 | 边界期待与可测性审查材料 | 普通显示器运行成功不能证明已覆盖 `0/1` 值 |
| 产品源码与单元/UI 测试 | 解释入口、控件、可观测字段；辅助建立独立检查 | 不把当前实现输出直接抄成期待 |

先做 PR-to-claim 映射，标注 superseded/reverted/not-applicable 和适用版本，避免重复累加历史 PR。
Merged claims 只扩充验证材料，不作为正确 verdict 的标签。
可以预留部分不参与反复调试的 baseline 场景供新 Executor 确认，避免只对熟悉例子有效。

### 7.2 建议的首批场景组

以下是范围建议，不是已通过的清单，也不在本轮生成最终 assertion inventory：

| 场景组 | 验证重点 | 独立观察 |
|---|---|---|
| 启用、启动方式、快捷键 | picker/editor 三种入口及关闭/再次使用 | 原生窗口、真实操作路径和可见状态 |
| 已知色块取色与复制 | 指针选取与 HEX/RGB 输出 | 已知输入、剪贴板实际格式/文本、画面；不只读 UIA 隐藏 hook |
| 编辑器、历史、格式选择 | 选取结果进入编辑器、历史选择/删除、格式显示与复制 | UI 状态、复制结果、持久化内容，按具体 claim 选择 |
| 设置持久化与恢复 | 修改后行为生效、重开后保留、最终回到原状态 | 配置与实际行为双向核对 |
| 放大及迁移边界 | 实际放大内容、picker 不污染画面、基本布局可用 | 受控色块、实际截图；不默认扩展逐帧动效要求 |

不把多显示器、HDR、提权、特定硬件刷新率等缺失条件伪装成全覆盖；在 baseline review 决定
哪些进入 pilot、哪些明确延期。不是执行中遇难就自行删除。
颜色核对明确显示模式/颜色管理/缩放、色块实际渲染与取样位置，避免把环境差异当回归。

### 7.3 怎样区分产品回归与验证能力问题

同一行为 claim、fixture 和可比环境，在 WPF/WinUI 两侧分别使用适用控件映射。
AutomationId、窗口类不同不是产品行为回归；复制内容、操作效果不符合有效期待才是。
旧版自身可能有缺陷，允许的行为变化也需标明；两版一致不等于一定正确。

Evaluator 检查：动作确实执行、观察能支持期待、版本/环境可比、恢复完整。
结果的独立可检验部分优先机械核对；语义歧义、视觉不确定或两轮结论冲突交给人。
不存在靠多个 LLM 同意就获得客观真相的机制。

## 8. 接受与停止条件

接受的是“材料在声明范围内支持可信执行”，不是产品全绿。建议在首次实测前确认：

1. 范围内断言有稳定 ID、明确期待、适用条件及观察方法；结果/缺口都可追踪。
2. 关键 helper 问题有复现和针对性回归，涉及 UI 的修复有真实确认，不能只用 mock 通过。
3. 改进前后结果差异能解释，未通过删除期待或隐式重启提高 PASS 数。
4. 原始状态恢复可核对；未知或失败的恢复在解决前禁止后续依赖操作。
5. 新 Executor 在不知道作者临场解释的情况下完成约定确认，Evaluator 检查原始证据。
6. 人接受材料的版本、适用 build/UI 栈和剩余限制；产品失败另列，不影响正确材料的接受。

重复次数、投入上限和 live 授权范围由人选，不沿用 SG 旧的失败次数/时间熔断。
达到上限时保存未完成项和交接；清理与证据保存不能依赖剩余模型调用额度。
没有新信息的循环应升级具体问题，而不是增加无依据的重试。

既有 recorder 暂时仍有 Diagnostic 非 PASS 影响 Signoff 的政策。
第一版原样展示 recorder 的 Signoff；`profileAccepted` 与产品/发布 sign-off 分开。
如需改变 recorder 政策，应单独批准与回归，控制器不能私下绕过。

## 9. Base code 与产品对照版本

**建议：新系统开发基于新建的 `main` 派生分支，复用当前分支的 verification 改进；不从当前脏工作树直接继续扩建。**

2026-09-18 只读核对结果：

| 对象 | 观察 |
|---|---|
| 当前分支 | `wip/powertoys-verification-20260819`，HEAD `f954455473938db9700088ba65106ba748e0a40d` |
| 本地 `main` / `origin/main` | 分别停留在 8 月 19 日 / 8 月 26 日，不能称为最新 main |
| 上游 API 查询的 `main` | `001b4f634640162ae8ec66f552697b8f1d7acfd9`；之后准备环境时重新 fetch 并固定 SHA |
| Color Picker 迁移 | #49174，merge commit `cd7f82c22d6859a5ab9db5ed90fa6b93b4e0f356`，9 月 4 日合并 |
| 迁移前父提交 | `a1ba833417919708dbee53267edb010513006a87` |
| 迁移与查询到的 main | main 比迁移提交又多 41 个提交；不能将所有前后差异都归给迁移 |
| 当前分支 ColorPickerUI 项目 | 仍为 `<UseWPF>true</UseWPF>`，不能作为 WinUI 候选 |
| 上游 verification skill | main 已有该 skill；需要比较共同来源、上游更新与本地改进，不能整体覆盖 |
| 当前分支特殊风险 | 最早 checkpoint commit 包含 skill 之外的 PR notes、截图与生成文件；另有未提交的 helper 修补、设计文档和停用框架草稿 |

三个版本轴必须分别记录：

- **系统/harness 版本**：新 main 派生分支 + 审查后迁入的 verification 改进。
- **回归主对照**：迁移前父提交与迁移提交构建的可比 WPF/WinUI artifacts，适合归因迁移。
- **后续实用性确认**：选定最新 main 的 WinUI build；区别于“仅迁移导致的差异”。

优先单独 worktree/build 输出，保持当前工作树和安装版不被覆盖。
使用源代码构建的迁移对照归入 skill B 的 PR 验证及相关回归，baseline 条目可作为回归选择；
不能把本地 build 宣称为 skill A 要求的 installed shipped artifact。
通过获准的 build+sideload 流程运行匹配的 Runner、模块与资源，不向安装目录临时覆盖 DLL。
两版不得并发使用同一配置/剪贴板/桌面；切换前完整恢复，并避免新配置格式污染旧版。
若历史 build 无法构建/运行，明确记录对照缺口，再决定使用可比发布版；不能默默把任意旧安装版当 migration parent。

选择性迁移应先审查依赖和最新 main 的已有更改：
不能只 cherry-pick 最后一笔增量，也不能直接 cherry-pick 混有无关产物的 checkpoint。
未提交的 Calculator 修补要单独评审，不能假设已包含在 `f954455473` 中。
旧 `tools\verification` 原型不迁入执行基线，除非后续设计评审决定复用其中的具体代码。
落地先打通一个已知色块 claim 的真实角色交接与恢复，再扩展 Color Picker 覆盖；
不是先写完通用框架才开始接触产品。
详见[执行计划的基线准备](multi-agent-verification-execution-plan.md#p1-建立干净的开发与产品对照基线)。

## 10. 实现前需要 Review 的细节

保留原 D01-D09 编号便于对账，以下含义以本修订为准；技术建议不等于已获授权。

| ID | 待确认 | 建议 |
|---|---|---|
| D01 | 控制器语言与 runtime 接入 | TypeScript CLI + Copilot SDK 可行性验证；Windows 操作继续用 PowerShell |
| D02 | 最小持久化/进程模型 | 按需 CLI、SQLite 事务、artifact 文件；先不做服务端/daemon |
| D03 | 开发与被测版本 | 新 main 分支复用 skill；迁移父提交/迁移提交作为产品主对照 |
| D04 | 人工关卡程度 | 初始清单、语义/权限变化、live 候选确认、分歧与最终采纳由人把关 |
| D05 | 首期执行粒度与并发 | 一个模块串行角色任务；同一实际桌面只有一个 live driver |
| D06 | Color Picker 范围和接受条件 | 先选第 7 节核心场景组；明确延期条件、新 Executor 确认及重复要求 |
| D07 | 结果与材料接受 | 沿用 recorder，不另算产品 PASS；产品 FAIL 可与材料接受并存 |
| D08 | 角色工具权限与恢复 | 受 runtime 约束的读写范围；不可靠权限/恢复检查显式阻止 live 阶段 |
| D09 | 修复循环投入 | 人确定预算与无进展升级条件；无 operation-key 封锁、无默认“直到全绿” |

建议先 review D03/D04/D06，确定用什么产品对照、自动到哪一步、怎样判断阶段 1 有用；
再验证 D01/D02 的实现可行性。阶段 2 active PR 自动执行、Web、并行集群和自动外发暂不实施。

## 参考

- [阶段 1 执行计划](multi-agent-verification-execution-plan.md)
- [Verification skill](../../../.github/skills/powertoys-verification/SKILL.md)
- [两种验证模式](../../../.github/skills/powertoys-verification/references/scenarios/index.md)
- [记录与按断言审查契约](../../../.github/skills/powertoys-verification/references/recording-workflow.md)
- [Operation 边界](../../../.github/skills/powertoys-verification/references/operation-boundaries.md)
