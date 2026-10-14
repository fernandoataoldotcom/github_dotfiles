#!/usr/bin/env bash
#
# Integration test for the dotfiles installer.
# (Approach borrowed from venkatamutyala/dotfiles, which this repo was forked from.)
#
# Runs the real installer end-to-end against the local checkout and asserts what a
# fresh VM should end up with, plus a regression check for every bug that has
# reached a VM so far.
#
# Designed to run as root inside a fresh Debian container with the repo mounted
# read-only at /repo -- see tests/run-in-docker.sh and the CI workflow. It uses a
# throwaway $HOME and stubs `claude` and `gh`, so it downloads no Claude binary,
# needs no credentials and never touches real dotfiles.
#
# Env:
#   REPO   path to the repo checkout (default: /repo)

set -euo pipefail

REPO="${REPO:-/repo}"
export DEBIAN_FRONTEND=noninteractive
export TERM="${TERM:-xterm}"
HOME="$(mktemp -d)"; export HOME
WORK="$(mktemp -d)"
unset TMUX CLAUDECODE GH_PAT GITHUB_TOKEN BROWSER

note() { printf '\n\033[1;34m== %s ==\033[0m\n' "$*"; }
pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }
check() { local what="$1"; shift; if "$@"; then pass "$what"; else fail "$what"; fi; }

note "Install prerequisites (zsh git curl tmux vim jq)"
apt-get update -qq
apt-get install -y -qq zsh git curl ca-certificates tmux vim jq bsdutils >/dev/null
printf 'using: '; zsh --version; printf 'using: '; tmux -V

note "Static checks"
for f in install claude-memory-sync zshrc fernandoataoldotcom-functions.zsh; do
  check "zsh -n parses $f" zsh -n "$REPO/$f"
done
check "claude-settings.json is valid JSON" jq -e . "$REPO/claude-settings.json" >/dev/null
check "vscode-machine-settings.json is valid JSON" jq -e . "$REPO/vscode-machine-settings.json" >/dev/null
r_tag="$(env -u REPO_RAW DOTFILES_REF='v9.9.9-test' DOTFILES_RESOLVE_ONLY=1 zsh "$REPO/install" 2>/dev/null | grep '^REPO_RAW=')"
[ "$r_tag" = "REPO_RAW=https://raw.githubusercontent.com/fernandoataoldotcom/github_dotfiles/v9.9.9-test" ] \
  && pass "DOTFILES_REF resolves REPO_RAW to that tag's raw URL" || fail "tag resolution wrong: $r_tag"
r_ovr="$(REPO_RAW="file://$REPO" DOTFILES_REF='v1' DOTFILES_RESOLVE_ONLY=1 zsh "$REPO/install" 2>/dev/null | grep '^REPO_RAW=')"
[ "$r_ovr" = "REPO_RAW=file://$REPO" ] \
  && pass "explicit REPO_RAW overrides DOTFILES_REF" || fail "REPO_RAW override failed: $r_ovr"
[ ! -e "$HOME/.oh-my-zsh" ] && pass "dry run made no changes" || fail "DOTFILES_RESOLVE_ONLY installed something"

note "Stub claude and gh; seed a fake memory remote"
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/claude" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/claude-calls.log"
case "$1 ${2:-}" in
  "auth status") echo '{"loggedIn": true}' ;;
  "--version ")  echo "0.0.0-stub (Claude Code)" ;;
esac
STUB
cat > "$HOME/.local/bin/gh" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/gh-calls.log"
case "$1 ${2:-}" in
  "auth status") exit 0 ;;
  "api user")    echo "ci-user" ;;
  "repo clone")  exec git clone -q "$FAKE_MEMORY_REMOTE" "$4" ;;
  "repo view")   echo PRIVATE ;;
esac
STUB
chmod +x "$HOME/.local/bin/claude" "$HOME/.local/bin/gh"
export PATH="$HOME/.local/bin:$PATH"
export FAKE_MEMORY_REMOTE="$WORK/memory-remote.git"
git init -q --bare -b main "$FAKE_MEMORY_REMOTE"
git config --global user.name null          # what `yolo` writes for a profile with no name
git config --global init.defaultBranch main

# What the VM image already puts in the VS Code machine settings; must survive the merge.
VSM="$HOME/.vscode-server/data/Machine/settings.json"
mkdir -p "${VSM%/*}"
echo '{"workbench.colorTheme": "Dark 2026", "security.workspace.trust.enabled": false}' > "$VSM"

note "Run the installer against the LOCAL checkout (no terminal attached)"
REPO_RAW="file://$REPO" zsh "$REPO/install" 2>&1 | tee "$WORK/install.log"

note "Post-install: shell, plugins, pins"
check "oh-my-zsh installed" test -d "$HOME/.oh-my-zsh"
omz_ref="$(grep -E '^OMZ_REF=' "$REPO/install" | head -1 | cut -d'"' -f2)"
[ "$(git -C "$HOME/.oh-my-zsh" rev-parse HEAD)" = "$omz_ref" ] \
  && pass "Oh-My-Zsh pinned at $omz_ref" || fail "Oh-My-Zsh not at pinned ref"
for p in zsh-syntax-highlighting zsh-autosuggestions you-should-use; do
  check "zsh plugin cloned: $p" test -d "$HOME/.oh-my-zsh/custom/plugins/$p/.git"
done
ysu_want="$(grep -oE 'YOU_SHOULD_USE_SHA="[0-9a-f]{40}"' "$REPO/install" | grep -oE '[0-9a-f]{40}')"
[ "$(git -C "$HOME/.oh-my-zsh/custom/plugins/you-should-use" rev-parse HEAD)" = "$ysu_want" ] \
  && pass "you-should-use verified at pinned SHA" || fail "you-should-use SHA mismatch"
for f in .zshrc .tmux.conf .vimrc .config/htop/htoprc .vim/autoload/plug.vim; do
  check "installed ~/$f" test -s "$HOME/$f"
done
zsh -ic 'echo interactive-ok' 2>/dev/null | grep -qx interactive-ok \
  && pass "interactive zsh loads cleanly with the new config" || fail "interactive zsh failed to load"

note "Post-install: Claude Code"
grep -qx 'install stable' "$HOME/claude-calls.log" \
  && pass "preinstalled claude is moved to the stable channel" || fail "installer did not run 'claude install stable'"
grep -q '^auth login' "$HOME/claude-calls.log" \
  && fail "installer tried to sign in although already signed in" || pass "sign-in skipped when already signed in"
s="$HOME/.claude/settings.json"
[ "$(jq -r .autoUpdatesChannel "$s")" = stable ] && pass "settings: autoUpdatesChannel=stable" || fail "autoUpdatesChannel not stable"
[ "$(jq -r .autoMemoryDirectory "$s")" = '~/.claude-memory/memory' ] && pass "settings: autoMemoryDirectory set" || fail "autoMemoryDirectory wrong"
[ "$(jq -r 'has("model")' "$s")" = false ] && pass "settings: no pinned model" || fail "settings pin a model"
for r in 'Read(~/.snowflake/**)' 'Edit(~/.snowflake/**)'; do
  jq -e --arg r "$r" '.permissions.deny | index($r)' "$s" >/dev/null \
    && pass "settings: deny $r" || fail "settings: $r not denied"
done
for h in SessionStart Stop SessionEnd; do
  jq -e --arg h "$h" '.hooks[$h][0].hooks[0].command | test("claude-memory-sync")' "$s" >/dev/null \
    && pass "settings: $h hook runs claude-memory-sync" || fail "$h hook missing"
done
check "claude-memory-sync installed and executable" test -x "$HOME/.local/bin/claude-memory-sync"

note "Post-install: GitHub-dependent steps"
[ "$(git config --global user.name)" = ci-user ] \
  && pass "git user.name 'null' repaired from the GitHub login" || fail "user.name is '$(git config --global user.name)'"
check "memory repo cloned to ~/.claude-memory" test -d "$HOME/.claude-memory/.git"
check "memory/ directory created" test -d "$HOME/.claude-memory/memory"
grep -qx 'MEMORY.md merge=union' "$HOME/.claude-memory/.gitattributes" \
  && pass "MEMORY.md is union-merged" || fail ".gitattributes missing"

note "Dependency check (silent unless something is missing)"
grep -q 'Missing tools on this VM.*kubectl' "$WORK/install.log" \
  && pass "reports kubectl as missing in this container" || fail "missing kubectl was not reported"
grep 'Missing tools on this VM' "$WORK/install.log" | grep -qE '(: |, )(vim|jq|gh)(,|$)' \
  && fail "reported a tool that is present" || pass "does not report tools that are present"
grep -q 'Install deps yourself' "$WORK/install.log" \
  && fail "old unconditional deps line is back" || pass "no unconditional deps line"

note "zshrc regressions"
[ "$(zsh -ic 't -V' 2>/dev/null)" = "$(tmux -V)" ] \
  && pass "'t <args>' is plain tmux (v2.0.0 turned 't ls' into a new session)" || fail "'t -V' is not 'tmux -V'"
[ -n "$(zsh -ic 'cd /tmp' 2>/dev/null)" ] && pass "cd lists the directory for a human" || fail "cd no longer lists"
[ -z "$(CLAUDECODE=1 zsh -ic 'cd /tmp' 2>/dev/null)" ] \
  && pass "cd prints nothing inside Claude Code" || fail "cd lists inside Claude Code"
[ "$(zsh -ic 'cd /nonexistent-dir 2>/dev/null; echo $?' 2>/dev/null | tail -1)" = 1 ] \
  && pass "cd keeps its exit status" || fail "cd lost its exit status"

note "Shell hand-off under a terminal, script piped on stdin (as curl|zsh does)"
# The commands on script's stdin are typed into the pty and read by the shell the
# installer execs. v2.0.0 gave that shell /dev/tty as stdin, which tmux refuses.
tmux -L handoff new-session -d -s probe 'sleep 120'
printf '%s\n' 'tty > "$HOME/handoff-tty"' \
  'TERM=xterm tmux -L handoff attach -t probe \; detach-client >/dev/null 2>"$HOME/handoff-tmux-err"; echo $? > "$HOME/handoff-tmux-rc"' \
  'exit' \
  | timeout 600 script -qec "cat '$REPO/install' | REPO_RAW='file://$REPO' zsh" /dev/null >"$WORK/handoff.log" 2>&1 \
  || { tail -20 "$WORK/handoff.log"; fail "installer under a terminal did not finish"; }
tmux -L handoff kill-server 2>/dev/null || true
case "$(cat "$HOME/handoff-tty" 2>/dev/null)" in
  /dev/pts/*) pass "handed-off shell has the real terminal on stdin ($(cat "$HOME/handoff-tty"))" ;;
  *) fail "handed-off shell stdin is '$(cat "$HOME/handoff-tty" 2>/dev/null)'" ;;
esac
[ "$(cat "$HOME/handoff-tmux-rc" 2>/dev/null)" = 0 ] \
  && pass "tmux attaches from the handed-off shell" || fail "tmux failed: $(cat "$HOME/handoff-tmux-err" 2>/dev/null)"

note "VS Code machine settings"
[ "$(jq -r '."workbench.secondarySideBar.defaultVisibility"' "$VSM")" = hidden ] \
  && pass "chat sidebar hidden by default" || fail "defaultVisibility is not hidden: $(cat "$VSM")"
[ "$(jq -r '."workbench.colorTheme"' "$VSM")" = "Dark 2026" ] && [ "$(jq -r '."security.workspace.trust.enabled"' "$VSM")" = false ] \
  && pass "keys already in the file are kept" || fail "existing VS Code settings lost: $(cat "$VSM")"
ls "$HOME"/.dotfiles-backup-*/.vscode-server/data/Machine/settings.json >/dev/null 2>&1 \
  && pass "original VS Code settings backed up" || fail "VS Code settings not backed up"

note "Idempotency and backups"
before="$(sha256sum "$HOME/.zshrc" "$HOME/.claude/settings.json" "$VSM")"
REPO_RAW="file://$REPO" zsh "$REPO/install" >/dev/null 2>&1 || fail "re-run failed"
[ "$before" = "$(sha256sum "$HOME/.zshrc" "$HOME/.claude/settings.json" "$VSM")" ] \
  && pass "re-run leaves ~/.zshrc, settings.json and VS Code settings identical" || fail "re-run changed config files"
ls -d "$HOME"/.dotfiles-backup-* >/dev/null 2>&1 && pass "timestamped backup directory created" || fail "no backup directory"
check "re-run keeps the memory clone" test -d "$HOME/.claude-memory/.git"
printf '{\n  // a comment makes this JSONC\n  "editor.fontSize": 14,\n}\n' > "$VSM"; jsonc="$(sha256sum "$VSM")"
REPO_RAW="file://$REPO" zsh "$REPO/install" >"$WORK/jsonc.log" 2>&1 || fail "re-run with JSONC VS Code settings failed"
[ "$jsonc" = "$(sha256sum "$VSM")" ] && grep -q "is not plain JSON" "$WORK/jsonc.log" \
  && pass "JSONC VS Code settings left alone, with a warning" || fail "JSONC VS Code settings were changed or not warned about"

note "claude-memory-sync: two VMs, one remote"
SYNC="$HOME/.local/bin/claude-memory-sync"
A="$HOME/.claude-memory"; B="$WORK/vmB"
git clone -q "$FAKE_MEMORY_REMOTE" "$B" 2>/dev/null; mkdir -p "$B/memory"
echo 'MEMORY.md merge=union' > "$B/.gitattributes"
echo '- a' > "$A/memory/MEMORY.md"; echo a > "$A/memory/a.md"
CLAUDE_MEMORY_DIR="$A" "$SYNC" push
[ "$(git -C "$FAKE_MEMORY_REMOTE" rev-list --count main)" = 1 ] \
  && pass "first push to an empty remote" || fail "first push did not reach the remote"
echo '- b' > "$B/memory/MEMORY.md"; echo b > "$B/memory/b.md"
out="$(CLAUDE_MEMORY_DIR="$B" "$SYNC" pull)"; CLAUDE_MEMORY_DIR="$B" "$SYNC" push
[ -z "$out" ] && pass "pull prints nothing on stdout" || fail "pull printed: $out"
CLAUDE_MEMORY_DIR="$A" "$SYNC" pull
[ "$(sort "$A/memory/MEMORY.md" | tr '\n' ' ')" = '- a - b ' ] \
  && pass "concurrent MEMORY.md edits merge without conflict" || fail "MEMORY.md is: $(cat "$A/memory/MEMORY.md")"
check "the other VM's memory arrives" test -f "$A/memory/b.md"
echo c > "$A/memory/c.md"; CLAUDE_MEMORY_DIR="$A" "$SYNC" push-async
for _ in $(seq 20); do git -C "$FAKE_MEMORY_REMOTE" cat-file -e main:memory/c.md 2>/dev/null && break; sleep 0.5; done
git -C "$FAKE_MEMORY_REMOTE" cat-file -e main:memory/c.md 2>/dev/null \
  && pass "push-async pushes in the background" || fail "push-async did not push"
[ -z "$(CLAUDE_MEMORY_DIR="$WORK/absent" "$SYNC" start)" ] && pass "no clone: silent no-op" || fail "printed without a clone"

note "claude-memory-sync: project notes"
ws="$WORK/ws"
mk() { git init -q "$ws/$1"; git -C "$ws/$1" remote add origin "$2"; }
mk website                          https://github.com/GlueOps-marketing/website.git
mk lead-capture                     https://github.com/glueops-marketing/lead-capture.git
mk tenant/deployment-configurations git@github.com:tenant-glueops/deployment-configurations.git
mk a/b/too-deep                     https://github.com/x/too-deep.git
mkdir -p "$A/projects/glueops-marketing" "$A/projects/tenant-glueops"
echo 'website notes' > "$A/projects/glueops-marketing/website.md"
echo 'deploy notes'  > "$A/projects/tenant-glueops/deployment-configurations.md"
n="$(cd "$ws" && "$SYNC" notes)"
grep -q 'website notes' <<<"$n" && pass "workspace folder: notes for a top-level clone (mixed-case owner -> lowercase key)" || fail "website notes missing"
grep -q 'deploy notes' <<<"$n"  && pass "workspace folder: notes for a clone nested under an owner folder" || fail "nested notes missing"
grep -q 'No notes yet for: .*glueops-marketing/lead-capture' <<<"$n" && pass "lists repos without notes" || fail "missing-notes line wrong"
grep -q 'too-deep' <<<"$n" && fail "looked three levels deep" || pass "ignores clones three levels down"
n="$(cd "$ws/tenant/deployment-configurations" && "$SYNC" notes)"
grep -q 'deploy notes' <<<"$n" && ! grep -q 'website notes' <<<"$n" \
  && pass "inside a clone: only that repo's notes" || fail "inside-clone notes wrong"
[ -z "$(cd "$WORK" && mkdir -p empty && cd empty && "$SYNC" notes)" ] && pass "folder without clones: prints nothing" || fail "printed for an empty folder"

note "ALL CHECKS PASSED"
