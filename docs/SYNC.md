# Working across two machines (Mac + Windows)

This project syncs between machines through **git** — GitHub holds the single
source of truth, and each machine keeps its own clone. You `push` before you
leave a machine and `pull` when you sit down at the other. Installed tools and
the Python venv are **not** in git (they're machine-specific and gitignored),
which is why setup is a once-per-machine step, not something that travels with
the repo.

## One-time setup, per machine

Do this exactly once on each computer.

### macOS

```bash
git clone https://github.com/Jazz0009/tensor-mac.git
cd tensor-mac
./setup-mac.sh        # Homebrew installs the toolchain + cocotb venv
./run.sh doctor       # confirm every tool is green
```

### Windows (WSL / Ubuntu)

```bash
sudo apt update
sudo apt install -y iverilog verilator yosys z3 gtkwave python3-venv git
git clone https://github.com/YosysHQ/sby && (cd sby && sudo make install)

git clone https://github.com/Jazz0009/tensor-mac.git
cd tensor-mac
python3 -m venv ~/.venvs/cocotb
~/.venvs/cocotb/bin/pip install -r requirements.txt
./run.sh doctor
```

Re-running `setup-mac.sh` (or the apt/pip steps) later is safe — it just
updates/repairs the toolchain.

## The switch-machines routine

**Before you leave the machine you're on:**

```bash
git add -A
git commit -m "wip: what I just changed"
git push
```

**When you arrive at the other machine:**

```bash
git pull
./run.sh sim mac        # tools already installed — no re-setup
```

That's the whole loop: **push before you stand up, pull before you start.**

## Notes & gotchas

- **Same commands everywhere.** `./run.sh lint|sim|cocotb|formal <name>` behaves
  identically on macOS, Linux, and Windows. `./run.sh doctor` reports the local
  toolchain state.
- **Folder location doesn't need to match** across machines — clone wherever you
  like on each; nothing hard-codes a path.
- **Line endings are handled.** `.gitattributes` forces LF on scripts/HDL/text,
  so files don't corrupt round-tripping between Windows and macOS.
- **Forgot to push before switching?** The newer work is stranded on the machine
  you left — remote in and push, or redo the small bit. Make `git push` a reflex
  when you stop. Stashes are local, so prefer a `wip:` commit over `git stash`
  when you want to carry unfinished work across machines.
- **Python versions stay in lockstep** via `requirements.txt` (the shared pin).
  Bump a version there and re-run setup on every machine so they stay identical.
