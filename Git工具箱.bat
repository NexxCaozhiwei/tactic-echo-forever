@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>nul
title Git 工具箱 2>nul

rem 双击运行时以脚本所在目录作为起始位置，不依赖当前工作目录。
cd /d "%~dp0" 2>nul
if errorlevel 1 (
    echo [错误] 无法进入脚本所在目录：%~dp0
    pause
    exit /b 1
)

where git >nul 2>nul
if errorlevel 1 (
    echo [错误] 未找到 Git，请先安装 Git for Windows 并重新打开此窗口。
    pause
    exit /b 1
)

git rev-parse --show-toplevel >nul 2>nul
if errorlevel 1 (
    echo [错误] 当前目录不是 Git 仓库。
    echo 请把本文件放在项目仓库中，或从仓库目录运行。
    pause
    exit /b 1
)

:menu
cls
for /f "delims=" %%D in ('git rev-parse --show-toplevel 2^>nul') do set "REPO_ROOT=%%D"
for /f "delims=" %%B in ('git branch --show-current 2^>nul') do set "BRANCH=%%B"
echo ========================================
echo              Git 工具箱
echo ========================================
echo 仓库：%REPO_ROOT%
echo 分支：%BRANCH%
echo.
echo   1. 查看状态和差异
echo   2. 同步（先拉取，再推送）
echo   3. 拉取（优先使用 rebase）
echo   4. 推送当前分支
echo   5. 暂存并提交
echo   6. 获取远端更新（fetch）
echo   7. 查看分支并切换
echo   8. 新建分支
echo   9. 取消暂存（保留文件修改）
echo   0. 退出
echo.
set "CHOICE="
set /p "CHOICE=请选择操作："

if "%CHOICE%"=="1" goto status
if "%CHOICE%"=="2" goto sync
if "%CHOICE%"=="3" goto pull
if "%CHOICE%"=="4" goto push
if "%CHOICE%"=="5" goto commit
if "%CHOICE%"=="6" goto fetch
if "%CHOICE%"=="7" goto switch_branch
if "%CHOICE%"=="8" goto new_branch
if "%CHOICE%"=="9" goto unstage
if "%CHOICE%"=="0" exit /b 0
echo 无效选项。
pause
goto menu

:status
echo.
git status --short --branch
echo.
git diff --stat
echo.
git diff --cached --stat
pause
goto menu

:sync
echo.
echo 即将对当前分支执行拉取（rebase）并在成功后推送。
set "CONFIRM="
set /p "CONFIRM=继续？(y/N)："
if /i not "%CONFIRM%"=="y" goto menu
git pull --rebase
if errorlevel 1 (
    echo 拉取未完成。请检查冲突、本地修改或当前分支是否已设置上游；修复后再继续。
    pause
    goto menu
)
git push
if errorlevel 1 echo 推送失败，请检查远端、权限、分支保护规则，或先为新分支设置上游。
pause
goto menu

:pull
echo.
git pull --rebase
if errorlevel 1 echo 拉取未完成。请检查冲突、本地修改或当前分支是否已设置上游。
pause
goto menu

:push
echo.
git status --short --branch
set "CONFIRM="
set /p "CONFIRM=推送当前分支到其跟踪的远端？(y/N)："
if /i not "%CONFIRM%"=="y" goto menu
git push
if errorlevel 1 echo 推送失败，请检查远端、权限、分支保护规则，或先为新分支设置上游。
pause
goto menu

:commit
echo.
git status --short
echo.
echo 注意：下一个步骤会暂存当前仓库中的所有修改和未跟踪文件。
set "CONFIRM="
set /p "CONFIRM=继续暂存全部文件？(y/N)："
if /i not "%CONFIRM%"=="y" goto menu
git add -A
if errorlevel 1 (
    echo 暂存失败。
    pause
    goto menu
)
git status --short
echo.
set "COMMIT_MSG="
set /p "COMMIT_MSG=请输入提交说明："
if not defined COMMIT_MSG (
    echo 提交说明不能为空，文件仍保留在暂存区。
    pause
    goto menu
)
git commit -m "%COMMIT_MSG%"
if errorlevel 1 echo 提交未完成；请检查暂存内容、Git 用户配置或提交钩子。
pause
goto menu

:fetch
echo.
git fetch --all --prune
if errorlevel 1 echo 获取远端更新失败，请检查网络和远端配置。
pause
goto menu

:switch_branch
echo.
git branch -a
echo.
set "TARGET_BRANCH="
set /p "TARGET_BRANCH=输入要切换的本地分支名："
if not defined TARGET_BRANCH goto menu
git switch "%TARGET_BRANCH%"
if errorlevel 1 echo 切换失败。未跟踪的远端分支请先 fetch，再用 git switch --track 创建本地跟踪分支。
pause
goto menu

:new_branch
echo.
set "NEW_BRANCH="
set /p "NEW_BRANCH=输入新分支名："
if not defined NEW_BRANCH goto menu
git switch -c "%NEW_BRANCH%"
if errorlevel 1 echo 创建或切换分支失败，请检查分支名及工作区状态。
pause
goto menu

:unstage
echo.
echo 取消暂存不会删除文件修改。
git status --short
set "CONFIRM="
set /p "CONFIRM=取消全部已暂存内容？(y/N)："
if /i not "%CONFIRM%"=="y" goto menu
git restore --staged .
if errorlevel 1 echo 取消暂存失败。
pause
goto menu
