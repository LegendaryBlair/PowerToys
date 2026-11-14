# 域账户与本地账户的多用户安装/卸载隔离测试

## 范围与前提

可以使用域账户A（`DOMAIN\UserA`）和本地账户B（`.\UserB`）。Entra账户的
`S-1-12-1-...`及域/本地账户的`S-1-5-21-...`均属于当前实现支持的owner SID。
**必须是同一台Windows、两个分别登录的真实用户会话**，才能证明互不影响。
两台独立机器只能分别测试安装/卸载，不能证明同机隔离；对比脚本会拒绝跨机器快照。

- 建议使用经批准的测试机/VM并先做快照。由管理员/IT准备允许登录的本地账户；
  不关闭域策略、Defender或应用控制策略来完成测试。
- B应为标准本地用户。A也在普通、非提升的桌面和终端运行测试，不把“管理员可接管”
  当成ACL失效，也不把另一个普通用户视为Administrators只读访问场景。
- 两个账户都使用同一版本、同一架构的 **PowerToysUserSetup**，不要混入MachineSetup，
  不要右键“以管理员身份运行”外层安装器，也不要直接执行内层MSI。
- 如安装中的UAC需要凭据，可以输入经授权的管理员账户。尤其在B会话输入A的管理员
  凭据时，最后生成的服务/数据/carrier仍必须属于B；这同时覆盖OTS owner绑定。
- 两边先各登录一次以建立真实用户profile；关闭自动下载更新，避免测试期间另有更新。
  在同一次隔离比较期间，不要操作被观察账户的工作区（编辑、保存或启动都会合法改变数据）。
- 本机已有KeepData不要手动删除；不需要为了此测试重置已有epoch。用于破坏性恢复测试
  的账号/VM应另外准备。

本轮缓存回收候选代码与已验证的6015 profile清理不是同一个验收版本。应等新的
private build中对应平台安装器产出并核对版本/签名后使用。SDK job状态与平台产物
分别记录，不把本地未签名测试EXE或ASR阻断当成正式包验收。

## 验证脚本

将以下两个脚本复制到A、B各自可读的位置，**都在被测试账户的普通64位PowerShell 7中运行**：

- `tools\build\Get-ProtectedStorageIsolationSnapshot.ps1`：采集本账户快照；
  可额外验证另一owner的Data读/写/删除/改ACL权限均被拒绝。
- `tools\build\Compare-ProtectedStorageIsolationSnapshot.ps1`：对比本账户前后快照，
  检查机器、owner和VA SID一致，注册/服务/数据是否按预期变化。

脚本不创建服务、任务或账户，不启动PowerToys，不触发Setup/repair，不调用
Win32_Product，不写入/删除业务文件，也不修改ACL。权限探测只是用OPEN_EXISTING
请求访问权后立即关闭句柄，不调用写入/删除API。唯一写入是指定位置的新JSON文件；
已存在的快照不会覆盖。输出不包含工作区名称、应用参数或业务JSON，但包含账户SID、
服务路径和数据hash，不要将这些本机快照提交仓库。

下列命令在各自会话中先设置：

```powershell
$tools = 'C:\Path\To\VerificationScripts'
$capture = Join-Path $tools 'Get-ProtectedStorageIsolationSnapshot.ps1'
$compare = Join-Path $tools 'Compare-ProtectedStorageIsolationSnapshot.ps1'
$out = Join-Path $env:USERPROFILE 'Desktop\PowerToys-Isolation'
$version = '0.101.6016.0' # 必须改成实际待测安装器的完整版本
[Security.Principal.WindowsIdentity]::GetCurrent().Name
[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
```

记录两边的真实SID，分别称为`<A-SID>`和`<B-SID>`。不同SID才是不同业务owner；
用户显示名或管理员输入凭据不是服务归属依据。

## 第一轮：B安装、卸载不得影响已运行的A

### 1. 在A中准备基线

正常安装UserSetup。打开Workspaces，建立并保存至少一个测试工作区，再关闭Editor。
确认UI可以读回；等待约一分钟，让安装后的正常收尾完成。
此后暂停A的工作区操作，直到完成B的安装/卸载比较。

```powershell
& $capture -OutputPath "$out\A-before-B.json" -ExpectedState Installed -ExpectedVersion $version
```

输出必须无错误，`Installed=True`。脚本会验证：
对应A SID的独立服务、NT SERVICE账户、自动启动配置、owner/context2 carrier与主MSI；
实际Bootstrap/Runtime的SID、Session0、路径、进程出生时间与ready一致；
Data稳定可读且普通owner无写/删除/改ACL权限。

### 2. 切换到B安装

使用“切换用户”，不要注销A，也不要结束A的服务。B普通双击同一UserSetup，
按正常UAC流程授权。B打开Workspaces，应看到自己的集合而不是A的工作区；
创建并保存B的测试工作区，关闭Editor。

```powershell
$aSid = '<A-SID>'
& $capture -OutputPath "$out\B-installed.json" -ExpectedState Installed `
    -ExpectedVersion $version -PeerOwnerSid $aSid
```

确认B的安装、service和carrier均绑定B，且访问A的index返回原生错误5。
错误2/3（文件不存在）不算隔离通过；必须先确保A仍已安装且数据已初始化。

### 3. 切换回A验证未被B安装影响

不要先打开/启动工作区，先取快照：

```powershell
$bSid = '<B-SID>'
& $capture -OutputPath "$out\A-after-B-install.json" -ExpectedState Installed `
    -ExpectedVersion $version -PeerOwnerSid $bSid
& $compare -Before "$out\A-before-B.json" -After "$out\A-after-B-install.json" -Mode Unchanged
```

必须PASS：A的注册/服务配置、两个实际进程的PID及出生时间、Data字节和epoch/
初始化状态均不变。B安装不应通过重启A服务来“最终恢复正常”。

### 4. 切换到B正常卸载

在B的“已安装的应用”卸载PowerToys，默认KeepData。不要手动删服务/profile/目录。
完成后：

```powershell
& $capture -OutputPath "$out\B-removed.json" -ExpectedState RemovedKeepData
& $compare -Before "$out\B-installed.json" -After "$out\B-removed.json" -Mode RemovedKeepData
```

B主程序、主MSI/carrier、服务和运行Code应不存在；Data字节/epoch/init ID保持。
VA profile因占用尚未删除时，这一步允许显示`ProfileRemoved=False`，留到重启后验证，
不能把它误写为“已经完全清理”。

### 5. 回到A，再验证B卸载未影响A

```powershell
& $capture -OutputPath "$out\A-after-B-remove.json" -ExpectedState Installed -ExpectedVersion $version
& $compare -Before "$out\A-after-B-install.json" -After "$out\A-after-B-remove.json" -Mode Unchanged
```

必须PASS。随后可在A的UI做一次读回/保存验证；如果做了这些操作，**先采新基线**
再进行后面的数据比较，不能把合法新提交误报为隔离失败。

### 6. 重启后的收尾

若未操作A的工作区，重启并等待约一分钟。两边分别登录：

```powershell
# A：重启会合法改变进程PID，使用Restarted，而不是Unchanged
& $capture -OutputPath "$out\A-after-reboot.json" -ExpectedState Installed -ExpectedVersion $version
& $compare -Before "$out\A-after-B-remove.json" -After "$out\A-after-reboot.json" -Mode Restarted

# B：以下命令在B会话执行，$out是B自己的路径
& $capture -OutputPath "$out\B-after-reboot.json" -ExpectedState RemovedKeepData -RequireProfileRemoved
& $compare -Before "$out\B-installed.json" -After "$out\B-after-reboot.json" `
    -Mode RemovedKeepData -RequireProfileRemoved
```

B的profile注册/hive/目录及profile pending标记应消失，A应正常启动且Data不变。
若profile原路径带`.000`等后缀，而删除后快照只能推导默认路径，对比脚本会要求
额外检查原来的确切路径，不会把默认路径不存在当作旧profile必然已删。
清理任务及安装暂存文件的完整回收另按缓存回收用例核对；此脚本不是全盘残留扫描。

## 第二轮：交换方向

在B重新安装同版本，先不编辑/启动工作区：

```powershell
& $capture -OutputPath "$out\B-reinstalled.json" -ExpectedState Installed -ExpectedVersion $version
& $compare -Before "$out\B-after-reboot.json" -After "$out\B-reinstalled.json" -Mode ReinstalledKeepData
```

验证B原工作区可读回，VA SID、数据和初始化不变。若继续编辑，另取
`B-before-A-remove.json`作为新基线。保持B运行，切换到A正常卸载，再返回B：

```powershell
# B中的命令：A卸载前后分别运行，不要在中间修改B的工作区
& $capture -OutputPath "$out\B-before-A-remove.json" -ExpectedState Installed -ExpectedVersion $version
# 切换到A执行卸载，再切回B
& $capture -OutputPath "$out\B-after-A-remove.json" -ExpectedState Installed -ExpectedVersion $version
& $compare -Before "$out\B-before-A-remove.json" -After "$out\B-after-A-remove.json" -Mode Unchanged
```

A也按第一轮B的方式保存卸载/重启快照。两个方向都通过，才记录这组A/B安装卸载
互不影响；单方向通过不外推为全scope通过。

## 结果与失败处理

- 脚本退出0及PASS只覆盖其列出的检查点。UI集合正确、正常保存/启动、UAC中原owner
  绑定过程仍需人工观察，不能仅凭服务最终存在就假定整个授权过程正确。
- 快照或对比报错时保留JSON和安装日志，不先repair、重装或手动清理来抹掉现场。
  `native5`可能表示确实被拒绝或无法观察，必须结合字段：peer权限探测预期5，
  服务/目录“已移除”检查则必须是明确的1060/2/3等，不能用5代替不存在。
- 普通双用户通过后，再补取消UAC、另一owner离线、真正配置并发冲突和事务结果未知。
  per-machine卸载有不同scope，不能直接使用本UserSetup的单owner删除预期。
