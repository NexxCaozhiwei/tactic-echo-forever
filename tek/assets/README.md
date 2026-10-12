# TEK图标资源

将TEK桌面图标源文件放在此目录，名称如下：

```text
tek.png
tek.ico
TEK_BLUE.png
TEK_GREY.png
TEK_RED.png
TEK_YELLOW.png
```

存在 `tek.ico` 时，`scripts/build-tek-exe.ps1` 将其用作Windows可执行文件图标。托盘程序也优先使用 `tek.ico` 或 `tek.png`，并叠加当前TEK状态颜色。

存在状态PNG时，托盘程序直接使用：

- `TEK_GREY.png`：已停止或工作进程未运行。
- `TEK_BLUE.png`：模拟运行和已就绪；没有专用绿色资源前，已就绪使用蓝色。
- `TEK_YELLOW.png`：已暂停或AwaitingStartToggle。
- `TEK_RED.png`：阻断、ErrorLocked或工作进程错误。
