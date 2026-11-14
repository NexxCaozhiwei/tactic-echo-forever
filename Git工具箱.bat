@echo off
setlocal EnableExtensions
title Git 工具箱 2>nul

rem 双击运行时以脚本所在目录作为起始位置，不依赖当前工作目录。
rem 本文件必须保存为 GBK(cp936) + CRLF；添加 chcp 65001 会让 cmd 错切中文行，切勿改回。
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
    echo 请把本文件放在项目仓库中。
    pause
    exit /b 1
)

for /f "delims=" %%D in ('git rev-parse --show-toplevel') do set "REPO_ROOT=%%D"
cd /d "%REPO_ROOT%" || exit /b 1
setlocal EnableDelayedExpansion

:menu
cls
endlocal
set "BRANCH="
for /f "delims=" %%B in ('git branch --show-current 2^>nul') do set "BRANCH=%%B"
setlocal EnableDelayedExpansion
set "DISPLAY_BRANCH=!BRANCH!"
if not defined BRANCH for /f "delims=" %%H in ('git rev-parse --short HEAD 2^>nul') do set "DISPLAY_BRANCH=未检出本地分支（当前提交 %%H）"
echo ========================================
echo              Git 工具箱
echo ========================================
echo 仓库：!REPO_ROOT!
echo 分支：!DISPLAY_BRANCH!
echo.
echo [日常操作]
echo   1. 查看状态和差异
echo   2. 提交改动
echo   3. 同步（整合上游，再推送）
echo.
echo [远端操作]
echo   4. 获取远端更新（仅获取）
echo   5. 拉取上游改动
echo   6. 推送当前分支
echo.
echo [分支和暂存]
echo   7. 查看分支并切换
echo   8. 新建分支
echo   9. 取消暂存（保留文件修改）
echo.
echo   0. 退出
echo.
choice /c 1234567890 /n /m "请选择操作："
if errorlevel 255 exit /b 1
if errorlevel 10 exit /b 0
if errorlevel 9 goto unstage
if errorlevel 8 goto new_branch
if errorlevel 7 goto switch_branch
if errorlevel 6 goto push
if errorlevel 5 goto pull
if errorlevel 4 goto fetch
if errorlevel 3 goto sync
if errorlevel 2 goto commit
if errorlevel 1 goto status
exit /b 0

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
set "SYNC_PUSH=1"
goto integrate

:pull
set "SYNC_PUSH="
goto integrate

:integrate
call :resolve_upstream || goto done
call :check_operation || goto done
set "DIRTY="
git status --porcelain=v1 >nul || goto done
for /f "delims=" %%S in ('git status --porcelain=v1') do set "DIRTY=1"
if defined DIRTY (
    echo 请先处理工作区和暂存区的改动，再执行同步或拉取。
    goto done
)
echo 正在获取远端更新：!REMOTE!
git fetch -- "!REMOTE!"
if errorlevel 1 (
    echo [错误] 获取远端更新失败，本次同步已停止。
    goto done
)
set "AHEAD="
set "BEHIND="
for /f "tokens=1,2" %%A in ('git rev-list --left-right --count HEAD...@{upstream}') do (
    set "AHEAD=%%A"
    set "BEHIND=%%B"
)
if not defined BEHIND (
    echo [错误] 无法比较本地分支与上游分支的提交。
    goto done
)
if !AHEAD! EQU 0 if !BEHIND! EQU 0 (
    echo 本地与上游已一致，无需拉取或推送。
    goto done
)
echo 本地领先 !AHEAD! 个提交，落后 !BEHIND! 个提交。
if !BEHIND! GTR 0 (
    if !AHEAD! EQU 0 (
        git merge --ff-only "@{upstream}"
        if errorlevel 1 (
            echo [错误] 无法快进到上游分支，本次同步已停止。
            goto done
        )
        echo 已快进到上游分支。
    ) else (
        choice /c NY /n /m "本地与上游已分叉。将本地提交变基到上游？[N/Y] "
        if not errorlevel 2 goto done
        if errorlevel 3 goto done
        git rebase "@{upstream}"
        if errorlevel 1 (
            echo 变基未完成。解决冲突后运行 git rebase --continue，或运行 git rebase --abort。
            goto done
        )
    )
)
if not defined SYNC_PUSH goto done
if !AHEAD! EQU 0 goto done
goto confirm_push

:push
call :resolve_upstream || goto done
call :check_operation || goto done
git status --short --branch || goto done

:confirm_push
echo 推送目标：!REMOTE! !UPSTREAM_REF!
choice /c NY /n /m "确认推送？[N/Y] "
if not errorlevel 2 goto menu
if errorlevel 3 goto sync
git push -- "!REMOTE!" "HEAD:!UPSTREAM_REF!"
if errorlevel 1 (echo 推送失败，请检查上游更新、权限或分支保护规则。) else (echo 推送完成。)
goto done

:commit
call :check_operation || goto done
git status --short || goto done
set "STAGE_ALL="
choice /c 012 /n /m "0 返回，1 仅提交已暂存，2 暂存全部并提交："
if errorlevel 4 goto fetch
if not errorlevel 2 goto menu
if errorlevel 3 set "STAGE_ALL=1"
set "COMMIT_MSG="
set /p "COMMIT_MSG=请输入提交说明（留空返回）："
if not defined COMMIT_MSG goto menu
if defined STAGE_ALL (
    git add -A || goto done
)
git --no-pager diff --cached --stat || goto done
git diff --cached --quiet
if errorlevel 2 goto commit
if not errorlevel 1 (
    echo 暂存区没有可提交的改动。
    goto done
)
choice /c NY /n /m "确认提交以上暂存内容？[N/Y] "
if not errorlevel 2 goto menu
if errorlevel 3 goto sync
rem 通过临时文件传递说明，避免将文字放进 Git 命令参数。
set "MSG_FILE=!TEMP!\tef-git-!RANDOM!-!RANDOM!.msg"
pwsh.exe -NoLogo -NoProfile -Command "[IO.File]::WriteAllText($env:MSG_FILE, $env:COMMIT_MSG)"
if errorlevel 1 goto status
git -c i18n.commitEncoding=UTF-8 commit -F "!MSG_FILE!"
if errorlevel 1 (echo 提交未完成，请检查暂存区、Git 用户配置或提交钩子。) else (echo 提交完成。)
del /q "!MSG_FILE!"
goto done

:resolve_upstream
if not defined BRANCH (
    echo 当前未检出本地分支，无法同步或推送。请先切换到本地分支。
    exit /b 1
)
set "REMOTE="
set "UPSTREAM_REF="
for /f "tokens=1,2" %%R in ('pwsh.exe -NoLogo -NoProfile -Command "$ref = git symbolic-ref HEAD; if ($LASTEXITCODE -eq 0) { git for-each-ref --format='%%(upstream:remotename) %%(upstream:remoteref)' -- $ref }"') do (
    set "REMOTE=%%R"
    set "UPSTREAM_REF=%%S"
)
if not defined REMOTE goto missing_upstream
if "!REMOTE!"=="." goto missing_upstream
if not "!UPSTREAM_REF:~0,11!"=="refs/heads/" goto missing_upstream
exit /b 0

:missing_upstream
echo 当前分支没有可推送的远端上游，请先设置跟踪分支。
exit /b 1

:check_operation
for %%O in (rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD sequencer) do (
    for /f "delims=" %%P in ('git rev-parse --git-path %%O') do if exist "%%P" (
        echo 请先完成或取消正在进行的 Git 操作：%%O
        exit /b 1
    )
)
exit /b 0

:done
pause
goto menu

:fetch
echo.
git fetch --all --prune
if errorlevel 1 (echo 获取远端更新失败，请检查网络和远端配置。) else (echo 已获取远端更新。)
pause
goto menu

:switch_branch
echo.
git branch -a
echo.
set "TARGET_BRANCH="
set /p "TARGET_BRANCH=输入要切换的本地分支名："
if not defined TARGET_BRANCH goto menu
git show-ref --verify --quiet "refs/heads/!TARGET_BRANCH!" || goto invalid_branch
git switch -- "!TARGET_BRANCH!"
if errorlevel 1 echo 切换失败。如需切换到远端分支，请先获取远端更新，再用 git switch --track 创建本地跟踪分支。
pause
goto menu

:invalid_branch
echo 未找到该本地分支。
goto done

:new_branch
echo.
set "NEW_BRANCH="
set /p "NEW_BRANCH=输入新分支名："
if not defined NEW_BRANCH goto menu
if "!NEW_BRANCH:~0,1!"=="-" goto done
git check-ref-format "refs/heads/!NEW_BRANCH!" || goto done
git switch -c "!NEW_BRANCH!"
if errorlevel 1 echo 创建或切换分支失败，请检查分支名及工作区状态。
pause
goto menu

:unstage
echo.
echo 取消暂存不会删除文件修改。
git status --short
choice /c NY /n /m "取消全部已暂存内容？[N/Y] "
if not errorlevel 2 goto menu
if errorlevel 3 goto sync
git restore --staged -- .
if errorlevel 1 (echo 取消暂存失败。) else (echo 已取消暂存，文件修改已保留。)
goto done
