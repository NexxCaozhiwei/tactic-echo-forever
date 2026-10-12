# 本地项目拆分 — 2026-10-12

以下路径、版本与数量是拆分当时的历史记录，不代表当前安装路径。

- 拆分源提交：`3e57b9d1713ad3c9d821b416dc073452289c2691`。
- 原共享仓库/正式服TE路径：`G:\Desktop\CODES\tactic-echo`。
- 新本地相邻TEF路径：`G:\Desktop\CODES\Tactic Echo Forever`。
- 回滚标签：`pre-te-tef-split`，对应源HEAD；未提交文件另行保存。
- 安全备份：`G:\Desktop\CODES\_project-split-backups\tactic-echo-20261012-084826`。
- 完整备份核验1,310个文件；克隆后覆盖31个已修改或未跟踪源文件。
- 保留本地分支codex/tef、main及既有标签，不重写历史。

TE范围：正式服插件、HUD主推荐、特殊模式、AutoInjection、自有TEK及正式服测试/工具/文档；退役反应模块保持退役。
TEF范围：Infinite/Forever、经典60级职业/天赋/已学等级、APL、Secret Value、固定序列、自有TEK和TEF测试/工具/文档。

拆分时将TEK复制到两个项目。此后两者独立演进，不自动同步代码，不共享核心、子模块、符号链接或目录连接；运行时不访问另一个检出。source远端只作Git来源追溯，禁用推送URL；原TE的origin不变。

TEAP使用TE和TEF逻辑命名空间；v3线格式不变，不标识项目。一次只启用一个信号源。构建、追踪与状态元数据区分TEF，不改变输入授权。

TEF主机状态目录为 `%LOCALAPPDATA%/TacticEchoForever`，标题TEF TEK，可执行文件TEK-TEF.exe。设置/配置迁移只读旧目录，备份原设置并重置启用状态、缓存和SavedVariables导入。正式服状态仍在 `%LOCALAPPDATA%/TacticEcho`；未停止任何活动主机。

正式服SavedVariables为TacticEchoDB，TEF为TEF_DB，保持独立。拆分时版本未变：TE 1.5.12、TEF 1.0.1；本次拆分只增加元数据。

删除清单和分类见split-file-classification.json。TEF克隆中移除370个已确认正式服专用文件。TE侧仅在TEF加载、APL/Runtime/Dispatch/Transport及本地TEK测试通过后移除140个TEF专用源码、文档、测试和工具文件。
继承的目录、协议和解析器测试数据是本地兼容资源，不构成相邻插件或运行依赖。其他跨产品提及均为历史。UNRESOLVED_SHARED_FILES：无。

拆分时没有.github工作流。TEF构建检查本项目TOC/Lua测试和本地TEK测试集，正式服打包脚本已移除；包名使用TEF。构建/启动成功不替代实机输入验收。拆分操作未推送远端。

## 独立开发起点的验证

通过：327项Lua 5.1用例；235项pytest和17项子测试；229项TEK unittest；2项模拟验收；37个Lua语法文件；独立基线和compileall。
迁移测试将源码复制到隔离临时项目，移除PYTHONPATH后通过基线和Lua/TEK互操作检查。独立TEK-TEF.exe构建及插件源码打包通过。
未执行：可执行文件启动冒烟及真实Windows/游戏输入；为保留活动主机和用户现状，未启动程序。
不存在.git对象共享替代目录；TEK源码是物理独立副本。

最终分类修正：颜色/伽马测试属于共享本地编解码测试数据，并非TEF专用。正式服以中性文件名保留全部7项。原共享结构审计和最终分类均保存在外部备份。

## 独立GitHub仓库 — 2026-10-12

TEF origin为 https://github.com/NexxCaozhiwei/tactic-echo-forever （私有仓库）。Forever源码发布在自有main分支。source远端仅作来源追溯，禁用推送URL。默认推送origin，原TE仓库不是上传目标。
