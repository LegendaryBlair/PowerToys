# Color Picker 阶段 1：设计到试点的执行计划

**状态：待 review 的计划，尚未开始框架实现或产品验证。**
对应[初步设计](multi-agent-verification-design.md)。执行目标是从 baseline checklist 和 merged PR claims
建立可靠的 Color Picker profile/helpers，并检查 WinUI 3 迁移行为是否回归。
不是再跑 SG，不是将已有 PowerRename/Image Resizer 材料包装为新模块成果。

## 1. 执行边界

- 本轮仅更新设计/计划/文档索引；不创建分支、不 fetch/rebase/cherry-pick、不构建、不运行 agent loop。
- 之后经批准实施；每个阶段要有明确产物和退出依据，不用“agent 已回复完成”代替验收。
- 首期本机 CLI、单模块、角色串行；不新增 Web、独立 scenario-driver 层或通用资源调度平台。
- 三个版本分开：系统/harness 版本、WPF baseline、WinUI candidate。Expectations 变化需另批。
- 没有环境条件的条目明确延期/受阻；产品 FAIL 保留，不靠删 case 或改产品来接受 profile。

## 2. 依赖与工作顺序

```text
P0 范围/contract review
   → P1 干净代码基线
   → P2 runtime 与权限可行性验证
   → P3 串行状态机和 CLI
   → P4 接入现有 recorder/helpers，打通一个真实场景
   → P5 扩展并批准 Color Picker 初始材料
   → P6 执行—评估—改进—人工指导循环
   → P7 新 Executor 确认与阶段 1 交付
```

产品 build 准备和离线资料阅读可交错，但不是首期必须实现的并行调度能力。
P2 不通过则调整 runtime 选择，不先开发一大套仅靠 fake worker 能运行的控制器。
**第一个可演示里程碑是 P4 的单场景端到端执行，不是一个通用平台。**
P0 同时确认一个已知色块取色/复制 claim 的期待、初始操作说明及状态恢复范围，
让它贯穿 P2-P4；完整模块材料在 P5 扩展，不能拿单场景成功声称完整覆盖。

## P0. 范围与 contract review

**责任：人 + 设计者；不启动 live 执行。**

确认设计 D03/D04/D06：

- Color Picker 为阶段 1 试点；迁移不改变既有 UX 行为是初始假设。
- Engineer/Executor/Evaluator 的输入、输出和写权限；哪些动作需要人。
- 核心场景、暂不覆盖条件、行为差异如何判断、新 Executor 如何确认。
- 数据集含 baseline 与 merged PR claims；PR 文字和旧版行为都不是绝对真值。
- 诊断/修复预算、确认重复条件、无进展时的人工升级方式。

**产物：** 一份明确的 review 决定和试点范围，不要求逐条批准所有工具调用。
**退出：** 无歧义的角色交接、产品对照选择和 live 授权范围；未选具体预算时不得启动无人值守修复循环。

## P1. 建立干净的开发与产品对照基线

**建议选择 main，而不是把当前 WIP 分支直接作为长期开发 base。**

1. 记录当前分支 HEAD、未提交路径与需要保留的文档；不 stash/清理/覆盖现有工作。
2. 经批准获取最新 `origin/main`，固定准备时的 SHA，在独立 worktree 建立新 feature branch。
   本地 `main`/`origin/main` 当前落后于真实上游，不能只按分支名选择。
3. 盘点当前分支的 verification 改进与最新 main 的相同路径，迁入必要的完整依赖闭包。
   先整理已提交的 skill 改动，再单独处理未提交修补；逐笔或按路径生成可审查 patch。
4. 排除最早 checkpoint 中的无关 PR notes、截图、生成代码，排除未经接受的 `tools\verification` 原型。
   不直接 cherry-pick 最后一笔 commit，也不把整个 skill 目录粗暴覆盖到较新的 upstream。
5. 设计/计划作为独立文档变更带入，用户 comments 不擅自改写；代码与文档是否提交由后续明确请求决定。
6. 为产品建立独立 WPF/WinUI worktree 或已校验 artifacts，记录源码 SHA、构建配置、artifact hash、运行路径及依赖。
   使用仓库 build scripts；构建成功后才可运行，保留匹配的 Runner/资源，不混用两版目录。

只读调查所得候选：

| 用途 | 已确认身份 | 准备时再核实什么 |
|---|---|---|
| 当前 verification 改进来源 | HEAD `f954455473938db9700088ba65106ba748e0a40d` | 后续未提交修补不是该 commit 的一部分 |
| 系统开发上游候选 | `001b4f634640162ae8ec66f552697b8f1d7acfd9`（2026-09-18 查询） | 重新 fetch 后固定实际使用的 main SHA |
| WPF 产品对照 | `a1ba833417919708dbee53267edb010513006a87` | 构建与实际运行产物是否确实来自该提交 |
| WinUI 迁移对照 | `cd7f82c22d6859a5ab9db5ed90fa6b93b4e0f356`，#49174 | 两侧场景、fixture、配置和环境是否可比 |

当前 WIP 分支产品代码还是 WPF，因此不能直接验证 WinUI migration candidate。
最新 main 在迁移之后还有其他变更；先用紧邻迁移的版本做归因，再用最新 build 做适用性确认。

**产物：** 干净分支、迁移清单、三个版本轴的 manifest、明确未迁入的变更。
**退出：** 旧工作区未受损，相关既有 helper 回归通过；安装版没有被源代码输出混装。

## P2. 验证真实 agent runtime 与权限能力

**责任：实现者；先验证 D01/D02 建议，不增加大规模 agent 执行。**

在批准新增依赖之后，用一个小型离线任务验证：

- 能创建实际独立 session、提供明确任务与写范围、取得结构化结果和实际 session 身份。
- 可以观察运行结束/异常、请求取消、识别重启后是否仍有 worker，不把断开当结束。
- Evaluator 的只读边界、Engineer 的候选写范围可执行；权限失败会返回明确错误，不自动 `allow-all`。
- stdout/stderr/等价事件与用量可保留；不支持的字段为 unknown，不虚构费用/耗时。
- 只有 mock worker 通过不算此阶段通过；SDK 无法满足时记录限制，review 后选择替代 adapter。

**产物：** runtime 能力矩阵、最小真实 session 交接证据、已知限制及技术决定。
**退出：** 接入方案可满足首期 contract；不可满足时停止对应实现，而不是放宽为 prompt-only 保证。

## P3. 实现最小串行 Orchestrator 与 CLI

**责任：实现者；不运行产品 UI。建议开发顺序：**

1. 任务、结果、输入版本、finding、人工决定的 schema 与验证。
2. 单写者持久化：dispatch 与任务状态事务更新，artifact 用引用。
3. 阶段级状态机：prepare/execute/evaluate 与 queued/running/waiting-human/interrupted/finished。
4. 真实 runtime adapter 接入；角色只能提交结果/建议，不直接推进全局状态。
5. CLI 支持 start/status/inspect/pause/resume/decision/export，保留文本和 JSON 两种输出。
6. 取消与重启先 reconcile，未知动作不自动重放；同桌面防重复执行。

**必须通过的故障注入：**

| 输入/事件 | 必须观察到的行为 |
|---|---|
| 错 task/dispatch/版本结果 | 拒绝为当前结果，保留诊断 |
| 同一结果重复提交 | 幂等，不派两次后续任务 |
| 启动后登记前崩溃 | 重启先检查实际 worker，不重复执行 |
| worker 非零退出或无结果 | error/unknown，不自动 PASS |
| 同一桌面重复启动 | 第二个 live task 不获准运行 |
| 人未回复/旧批准对应旧候选 | waiting-human；不能用旧批准接受新候选 |
| 产物缺失/损坏/越界路径 | 显式失败，不读写其他工作区 |
| 有效 product FAIL | 正常到评估和后续独立工作，不开始无限修复产品 |

**产物：** 可运行 CLI、小型状态机及 conformance tests。
**退出：** 串行任务与人工暂停/恢复在新进程中可继续，和文件系统/worker 不一致的状态显式暴露。

## P4. 接入当前 skill/harness/report，打通一个真实场景

**责任：实现者 + 独立 Evaluator；不先重写 PowerShell helpers。**

- 将本轮输入版本、选定断言、实际 product build 与现有 run identity 关联。
- 调用既有记录/归档接口，保留按断言、Normal/Diagnostic、恢复和原始错误语义。
- 校验 archive 与任务匹配，不执行 archive 中的脚本，不重新生成一套产品 verdict。
- 允许完整和部分结果进入审查；未观察/缺条件/产品失败保持不同原因。
- 保留脚本上下文、相对依赖和加载来源，不能用“冻结”破坏 `$PSScriptRoot`。
- 对已有 Diagnostic 非 PASS 的 Signoff 限制显式展示；不趁框架接入偷偷改政策。
- 使用 P0 认可的单场景材料完成真实取色/复制：Executor 操作、记录和恢复，Evaluator 查原始证据，
  CLI 展示结果与交接。遇到问题保留真实失败，不用 mock 输出替代这个里程碑。
- 执行前确认交互桌面、真实进程路径/hash、已知色块的取样条件；若使用本地 build，
  按 skill B 标明 PR 与相关回归，不伪装成 installed-only 的模块签署。

**产物：** recorder 接入、已有 archive 的只读兼容性证据和一个真实场景的新 archive。
**退出：** 成功与失败 archive 均能正确审查，原文件未变；真实场景有可判断结果和恢复证据，
错误不会被包装为“基础设施通过”。产品 FAIL 可保留，但未能执行/恢复的场景不能算此里程碑完成。

## P5. 扩展并批准 Color Picker 初始材料

**责任：Engineer → Evaluator → 人。**

1. 从已认可的 baseline 文档/测试提炼核心行为，说明来源和不确定点。
2. 对 #49174、#48762、#49973 做 PR-to-claim 映射；根据实际 build 判断适用、重复与被替代关系。
3. 生成自然语言 checklist、稳定 case/assertion ID 和简洁 profile，引用已有 helpers。
4. 合并明显相同 Arrange/Act 的断言，保留重启前后、不同启动模式和负向操作的独立要求。
5. 为每个断言列观察方法、前置条件、会改变的状态与恢复方法；无法观察的不默认删掉。
6. 提议迭代集与保留确认集，以及新 Executor 的输入材料；人确认范围和语义例外。

**建议最小覆盖：** 启用/入口/快捷键、已知色块取色复制、编辑器/历史/格式、持久化与恢复、基本放大 parity。
不预设 case 数；无需模仿 SG 的全部分支。HDR/多屏/特殊刷新率等是否进入首期，由环境与目标共同决定。

**产物：** 第一版 checklist/profile、claim 映射、观察/恢复矩阵和人工 baseline 决定。
**退出：** Executor 拿到的期待可执行且可审查；未解决的歧义不会被当作产品必然正确或必然失败。

## P6. 完整运行一次完善循环

**责任：Orchestrator 编排 Engineer/Executor/Evaluator，人按需要介入。**

- Executor 执行获准场景并恢复，Evaluator 检查原始观察和遗漏。
- 对约定的 parity 断言分别取得 WPF/WinUI 同条件观察；缺一侧时标记对照缺口，
  不能把只执行 WinUI 的结果称为已完成迁移前后比较。
- 对真实产品问题保留 FAIL，不编辑产品代码“救活”测试。
- 对 profile/helper 问题，Engineer 交回问题引用、diff、影响范围、离线回归和 live 确认计划。
- Evaluator 审查候选；人确认必要的 live 行为/范围后，只重测受影响场景及合理邻近覆盖。
- 遇到结果退化或争议，生成可阅读的人工决定材料，等待指导后回到指定任务，不重走全部流程。
- 记录每轮版本和归因；版本变更后的确认用新 run，旧证据保留，不拼成“自动全绿”。

**产物：** 至少一条真实 execute→evaluate→改进/补测→确认链路，以及一次有意义的人工交接。
没有自然出现的问题时，可在隔离候选中注入已标注的设施故障验证流转，不能伪造产品 bug。
**退出：** 每个改进有原问题与确认依据，未解决项明确，环境恢复可核对；不要求产品全部 PASS。

## P7. 新 Executor 确认与交付

- 使用独立 session，只给已经整理的 checklist/profile/helper 和明确授权，不提供作者私有操作提示。
- 执行预先保留/约定的确认场景，Evaluator 查原始证据、重复条件与恢复。
- 给人一页接受材料：版本、适用 build/UI 栈、覆盖、产品 findings、设施限制、人工成本与是否可复用。
- 若不满足接受条件，保留具体差距回到相关任务；达到停止条件则交付 partial，不能继续无边界迭代。
- 人确认材料采纳；代码提交/合并和发布风险接受为独立操作。

**阶段 1 Definition of Done：**

1. CLI 能在真实 runtime 中完成角色交接及一次暂停/恢复，不只是输出 JSON。
2. Color Picker 的新 checklist/profile/helpers 在声明范围内可独立使用，且匹配被测版本。
3. 产品 FAIL、测试设施问题、未观察覆盖和工作状态没有被混淆。
4. 至少有一次版本可追踪的改进/确认，原始失败证据保留。
5. 人工指导进入实际后续任务；恢复、异常与预算边界可说明。
6. 已知剩余限制明示；不把阶段 1 接受等同于完整产品发布签署。

## 3. Review 后第一步做什么

推荐先批准 **P0 的试点范围/人工边界和 P1 的基线策略**，再开始 P1/P2。
技术可行性与实现成本通过 P2 后再确定工期，不先承诺“几天全部收敛”。

当前文档没有授权运行 build、替换安装版、执行 GUI、安装 SDK、启动付费 agent 或 commit。
这些是后续执行计划，不是本轮已经做过的工作。
