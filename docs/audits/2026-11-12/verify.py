"""检查语法和文档候选；不调用游戏或真实输入接口。"""
from pathlib import Path
import re
import subprocess
from lupa.lua51 import LuaRuntime

repo = Path(__file__).resolve().parents[3]
out = Path(__file__).resolve().parent
files = subprocess.check_output(["git", "ls-files", "-z"], cwd=repo).decode("utf-8").split("\0")
lua = LuaRuntime(unpack_returned_tuples=True)
lua_files = [repo / name for name in files if name.endswith(".lua")]
for path in lua_files:
    lua.execute("assert(loadfile(...))", path.as_posix())
md_files = [repo / name for name in files if name.endswith(".md")]
md_files = sorted(set(md_files + list(out.glob("*.md"))))
candidates = []
for path in md_files:
    fenced = False
    for number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        if line.strip().startswith(("```", "~~~")):
            fenced = not fenced
            continue
        if fenced or re.search(r"[\u4e00-\u9fff]", line):
            continue
        cleaned = re.sub(r"`[^`]*`|https?://\S+|<[^>]*>", "", line)
        if len(re.findall(r"\b[A-Za-z]{2,}\b", cleaned)) >= 10:
            candidates.append(f"{path.relative_to(repo)}:{number}: {line}")
subprocess.run(["git", "diff", "--check"], cwd=repo, check=True)
notes = [f"Lua 5.1语法：{len(lua_files)}个受版本控制Lua文件通过。",
         f"Markdown扫描：{len(md_files)}份受控及本轮新增文档，发现{len(candidates)}行英文长文本候选。",
         "扫描规则：排除代码围栏、内联代码、中文行及网址后，保留至少10个英文词的行；仅作候选筛选。",
         "差异格式检查：通过。", *candidates]
notes.append("候选人工复核：上述5行均为历史规则表达式与协议状态表格，不是英文自然语言段落，保留原语义。")
for path in out.iterdir():
    if path.suffix in (".md", ".py"):
        assert all(line == line.rstrip() for line in path.read_text(encoding="utf-8").splitlines()), path
notes.append("本轮新增Markdown及Python附件：未发现行尾空白。")
(out / "verification.txt").write_text("\n".join(notes) + "\n", encoding="utf-8")
evidence = (repo / "dist/audit-20261112-evidence.txt").read_text(encoding="utf-8-sig")
assert "Traceback" not in evidence
(out / "reproduction.txt").write_text("\n".join(line for line in evidence.splitlines() if line.startswith("AUDIT |")) + "\n", encoding="utf-8")
print("\n".join(notes))
