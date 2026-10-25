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

note "Version selection (default newest tag, rollback escape hatches)"
newest="$(git ls-remote --tags --refs https://github.com/fernandoataoldotcom/github_dotfiles | awk -F/ '{print $NF}' | sort -rV | head -1)"
# With a terminal and nothing typed: must not wait for a menu (stdin is /dev/null, so
# a prompt would block until the timeout).
r_def="$(cd "$WORK" && timeout 60 script -qec "DOTFILES_RESOLVE_ONLY=1 zsh '$REPO/install'" /dev/null </dev/null | tr -d '\r' | grep '^REPO_RAW=' || true)"
[ "$r_def" = "REPO_RAW=https://raw.githubusercontent.com/fernandoataoldotcom/github_dotfiles/$newest" ] \
  && pass "with a terminal, installs the newest tag ($newest) without prompting" || fail "default resolution: '$r_def'"
DOTFILES_PICK=1 DOTFILES_RESOLVE_ONLY=1 zsh "$REPO/install" >/dev/null 2>&1 \
  && fail "DOTFILES_PICK without a terminal should refuse" || pass "DOTFILES_PICK without a terminal refuses instead of hanging"
# Rollback: the chosen tag's OWN installer must run, with REPO_RAW pointing at it.
raw="$WORK/raw"; mkdir -p "$raw/fernandoataoldotcom/github_dotfiles/v0.0.1-old"
printf '%s\n' 'print -r -- "OLD-INSTALLER REPO_RAW=$REPO_RAW ARGS=$*"' > "$raw/fernandoataoldotcom/github_dotfiles/v0.0.1-old/install"
out="$(DOTFILES_RAW_BASE="file://$raw" DOTFILES_REF=v0.0.1-old zsh "$REPO/install" 2>&1)"
grep -qx "OLD-INSTALLER REPO_RAW=file://$raw/fernandoataoldotcom/github_dotfiles/v0.0.1-old ARGS=" <<<"$out" \
  && pass "DOTFILES_REF=<tag> runs that tag's installer, pointed at that tag's files" || fail "rollback hand-over: $out"
out="$(DOTFILES_RAW_BASE="file://$raw" zsh -s -- v0.0.1-old < "$REPO/install" 2>&1)"
grep -q "^OLD-INSTALLER REPO_RAW=file://$raw/fernandoataoldotcom/github_dotfiles/v0.0.1-old" <<<"$out" \
  && pass "'zsh -s -- <tag>' does the same" || fail "positional rollback: $out"
DOTFILES_RAW_BASE="file://$raw" DOTFILES_REF=v9.9.9-missing zsh "$REPO/install" >/dev/null 2>&1 \
  && fail "a missing tag should abort" || pass "a tag that does not exist aborts before changing anything"
[ ! -e "$HOME/.oh-my-zsh" ] && pass "none of the above changed \$HOME" || fail "version-selection checks installed something"

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
for f in .zshrc .tmux.conf .tmux-cheatsheet.txt .vimrc .config/htop/htoprc .vim/autoload/plug.vim; do
  check "installed ~/$f" test -s "$HOME/$f"
done
tmux -L cfg -f "$HOME/.tmux.conf" new-session -d 'sleep 30' 2>"$WORK/tmux-cfg.err" \
  && [ ! -s "$WORK/tmux-cfg.err" ] && pass "tmux.conf loads without errors" || fail "tmux.conf: $(cat "$WORK/tmux-cfg.err")"
keys="$(tmux -L cfg list-keys -T prefix)"
grep -q 'prefix *N *command-prompt.*select-pane -T' <<<"$keys" && grep -q -- '-r -T prefix *o ' <<<"$keys" \
  && grep -q 'prefix *? *display-popup.*tmux-cheatsheet' <<<"$keys" \
  && pass "tmux: N names a pane, o repeats, ? opens the cheat sheet" || fail "tmux bindings missing"
[ "$(tmux -L cfg show -gv pane-border-status)" = top ] && pass "tmux: pane titles on the borders" || fail "pane-border-status not top"
tmux -L cfg kill-server
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
for r in 'Read(~/.snowflake/**)' 'Edit(~/.snowflake/**)' 'Read(~/.ssh/**)' 'Edit(~/.ssh/**)' \
         'Read(~/.claude/.credentials.json)' 'Read(~/.git-credentials)' 'Bash(gh auth token)' \
         'Bash(gh auth token *)' 'Bash(kubectl *get *secret*)' 'Bash(kubectl *describe *secret*)'; do
  jq -e --arg r "$r" '.permissions.deny | index($r)' "$s" >/dev/null \
    && pass "settings: deny $r" || fail "settings: $r not denied"
done
for r in 'Read(//**/.env)' 'Edit(//**/.env)'; do
  jq -e --arg r "$r" '.permissions.ask | index($r)' "$s" >/dev/null \
    && pass "settings: ask before $r" || fail "settings: $r does not ask"
done
for h in SessionStart Stop SessionEnd; do
  jq -e --arg h "$h" '.hooks[$h][0].hooks[0].command | test("claude-memory-sync")' "$s" >/dev/null \
    && pass "settings: $h hook runs claude-memory-sync" || fail "$h hook missing"
done
check "claude-memory-sync installed and executable" test -x "$HOME/.local/bin/claude-memory-sync"
jq -e '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[0].command | test("gitleaks-guard")' "$s" >/dev/null \
  && pass "settings: PreToolUse(Bash) hook runs the gitleaks guard" || fail "gitleaks PreToolUse hook missing"
check "gitleaks guard installed and executable" test -x "$HOME/.claude/hooks/gitleaks-guard.sh"
[ "$(jq -r .statusLine.command "$s")" = '"$HOME/.claude/statusline.sh"' ] && pass "settings: status line wired" || fail "statusLine not wired"
sl="$WORK/sl-repo"; git init -q -b feat/x "$sl"
out="$(jq -n --arg d "$sl" '{model: {display_name: "Opus"}, workspace: {current_dir: $d}, context_window: {used_percentage: 42.7}}' | "$HOME/.claude/statusline.sh")"
[ "$out" = "Opus | sl-repo (feat/x) | ctx 42%" ] && pass "status line: model | dir (branch) | ctx %" || fail "status line printed: $out"
out="$(jq -n '{model: {display_name: "Opus"}, workspace: {current_dir: "/tmp"}, context_window: {used_percentage: null}}' | "$HOME/.claude/statusline.sh")"
[ "$out" = "Opus | tmp" ] && pass "status line: no branch or ctx when absent" || fail "status line printed: $out"
grep -qx '@~/.claude-memory/context/preferences.md' "$HOME/.claude/CLAUDE.md" \
  && pass "personal ~/.claude/CLAUDE.md imports the shared preferences" || fail "~/.claude/CLAUDE.md missing or without the import"

note "Post-install: GitHub-dependent steps"
[ "$(git config --global user.name)" = ci-user ] \
  && pass "git user.name 'null' repaired from the GitHub login" || fail "user.name is '$(git config --global user.name)'"
check "memory repo cloned to ~/.claude-memory" test -d "$HOME/.claude-memory/.git"
check "memory/ directory created" test -d "$HOME/.claude-memory/memory"
grep -qx 'MEMORY.md merge=union' "$HOME/.claude-memory/.gitattributes" \
  && pass "MEMORY.md is union-merged" || fail ".gitattributes missing"
grep -qx 'claude-code-version merge=union' "$HOME/.claude-memory/.gitattributes" \
  && pass "claude-code-version is union-merged" || fail "claude-code-version not union-merged"

note "Dependency check (silent unless something is missing)"
grep -q 'Missing tools on this VM.*kubectl' "$WORK/install.log" \
  && pass "reports kubectl as missing in this container" || fail "missing kubectl was not reported"
grep 'Missing tools on this VM' "$WORK/install.log" | grep -qE '(: |, )(vim|jq|gh)(,|$)' \
  && fail "reported a tool that is present" || pass "does not report tools that are present"
grep -q 'Install deps yourself' "$WORK/install.log" \
  && fail "old unconditional deps line is back" || pass "no unconditional deps line"

note "gitleaks guard (PreToolUse hook; docker stubbed)"
GUARD="$HOME/.claude/hooks/gitleaks-guard.sh"
gl="$WORK/gl"; git init -q "$gl"; git -C "$gl" config user.email ci@example.com
git -C "$gl" commit -q --allow-empty -m init
hook() { jq -n --arg c "$1" --arg d "$gl" '{tool_input: {command: $c}, cwd: $d}' | "$GUARD" 2>"$WORK/guard.err"; }
echo clean > "$gl/clean.txt"; git -C "$gl" add clean.txt
hook 'git commit -m x' && fail "committed without docker" \
  || { grep -q 'needs docker' "$WORK/guard.err" && pass "no docker: commit is blocked, not waved through" || fail "no-docker message: $(cat "$WORK/guard.err")"; }
# Stub gitleaks: any added line containing FAKE_SECRET is a finding at that line.
cat > "$HOME/.local/bin/docker" <<'STUB'
#!/bin/sh
n="$(awk '/FAKE_SECRET/ { print NR; exit }')"
[ -z "$n" ] && { echo '[]'; exit 0; }
echo "[{\"StartLine\": $n, \"RuleID\": \"fake-rule\"}]"; exit 1
STUB
chmod +x "$HOME/.local/bin/docker"
hook 'ls -la' && pass "non-git commands pass" || fail "blocked a non-git command"
hook 'git commit -m x' && pass "clean staged change: commit allowed" || fail "blocked a clean commit: $(cat "$WORK/guard.err")"
echo 'token=FAKE_SECRET' > "$gl/leak.txt"
hook 'git commit -m x' && pass "untracked file not scanned by a plain commit" || fail "plain commit scanned an untracked file"
hook 'git add -A && git commit -m x' && fail "git add -A && commit with a secret was allowed" \
  || { grep -q 'leak.txt (fake-rule)' "$WORK/guard.err" && pass "add + commit: blocked, names the file and rule" || fail "block message: $(cat "$WORK/guard.err")"; }
git -C "$gl" add leak.txt
hook "cd /tmp && git -C $gl commit -m x" && fail "git -C <repo> commit with a staged secret was allowed" || pass "follows cd and git -C to the right repo"
git -C "$gl" commit -q -m leak; git -C "$gl" remote add origin "$WORK/gl-remote.git"
hook 'git push' && fail "push of an unpushed secret was allowed" || pass "push: unpushed commits are scanned"
rm "$HOME/.local/bin/docker"

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
# Keep them on ONE line: the shell reads a whole line before running it, but while
# tmux is attached it reads the pty too and can swallow a later line, leaving the
# shell waiting for an `exit` it never gets (flaked once on bookworm in CI).
tmux -L handoff new-session -d -s probe 'sleep 120'
printf '%s\n' 'tty > "$HOME/handoff-tty"; TERM=xterm tmux -L handoff attach -t probe \; detach-client >/dev/null 2>"$HOME/handoff-tmux-err"; echo $? > "$HOME/handoff-tmux-rc"; exit' \
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

note "Older refs without the newer files"
# A ref from before claude-memory-sync / claude-CLAUDE.md existed must install with a
# warning for each, never claim it fetched them, and never chmod a missing file.
old_ref="$WORK/old-ref"; mkdir -p "$old_ref"
for f in zshrc fernandoataoldotcom-functions.zsh tmux.conf htoprc vimrc claude-settings.json; do cp "$REPO/$f" "$old_ref/"; done
mv "$HOME/.local/bin/claude-memory-sync" "$WORK/claude-memory-sync.saved"
REPO_RAW="file://$old_ref" zsh "$REPO/install" >"$WORK/old-ref.log" 2>&1 \
  && pass "install from a ref without the new files completes" || { tail -5 "$WORK/old-ref.log"; fail "install from an older ref aborted"; }
grep -q 'claude-memory-sync is not in this ref' "$WORK/old-ref.log" && grep -q 'claude-CLAUDE.md is not in this ref' "$WORK/old-ref.log" \
  && pass "warns about each missing file" || fail "missing-file warnings absent: $(grep -i warn "$WORK/old-ref.log")"
grep -qE 'fetched: .*(claude-memory-sync|CLAUDE\.md)' "$WORK/old-ref.log" \
  && fail "logged 'fetched' for a file that was not fetched" || pass "does not log 'fetched' for missing files"
grep -q 'chmod' "$WORK/old-ref.log" && fail "chmod ran against a missing file" || pass "no chmod against a missing file"
mv "$WORK/claude-memory-sync.saved" "$HOME/.local/bin/claude-memory-sync"
REPO_RAW="file://$REPO" zsh "$REPO/install" >/dev/null 2>&1 || fail "reinstall from the checkout failed"

note "claude-memory-sync: two VMs, one remote"
SYNC="$HOME/.local/bin/claude-memory-sync"
A="$HOME/.claude-memory"; B="$WORK/vmB"
git clone -q "$FAKE_MEMORY_REMOTE" "$B" 2>/dev/null; mkdir -p "$B/memory"
cp "$A/.gitattributes" "$B/.gitattributes"
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

note "claude-memory-sync: Claude Code version check"
vbin="$WORK/vbin"; mkdir -p "$vbin" "$WORK/novcs"
printf '#!/bin/sh\necho "$FAKE_CLAUDE_VERSION (Claude Code)"\n' > "$vbin/claude"; chmod +x "$vbin/claude"
vstart() { (cd "$WORK/novcs" && PATH="$vbin:$PATH" FAKE_CLAUDE_VERSION="$1" CLAUDE_MEMORY_DIR="$A" "$SYNC" start); }
rm -f "$A/claude-code-version"
[ -z "$(vstart 2.1.300)" ] && [ "$(cat "$A/claude-code-version")" = 2.1.300 ] \
  && pass "first run records the version silently" || fail "first run: $(cat "$A/claude-code-version" 2>/dev/null)"
[ -z "$(vstart 2.1.300)" ] && pass "same version: silent" || fail "same version printed"
out="$(vstart 2.1.310)"
grep -q 'updated from 2.1.300 to 2.1.310' <<<"$out" && [ "$(cat "$A/claude-code-version")" = 2.1.310 ] \
  && pass "newer version: asks for a changelog check and records it" || fail "newer version: $out"
[ -z "$(vstart 2.1.305)" ] && [ "$(cat "$A/claude-code-version")" = 2.1.310 ] \
  && pass "older version (a VM not yet updated): silent, keeps the newest" || fail "older version changed the record"
[ -z "$(vstart 2.1.310)" ] && pass "after reporting, silent again" || fail "reported the same update twice"
CLAUDE_MEMORY_DIR="$A" "$SYNC" push; CLAUDE_MEMORY_DIR="$B" "$SYNC" pull
(cd "$WORK/novcs" && PATH="$vbin:$PATH" FAKE_CLAUDE_VERSION=2.1.320 CLAUDE_MEMORY_DIR="$A" "$SYNC" start >/dev/null)
(cd "$WORK/novcs" && PATH="$vbin:$PATH" FAKE_CLAUDE_VERSION=2.1.330 CLAUDE_MEMORY_DIR="$B" "$SYNC" start >/dev/null)
CLAUDE_MEMORY_DIR="$A" "$SYNC" push; CLAUDE_MEMORY_DIR="$B" "$SYNC" push
[ "$(git -C "$B" rev-list --count '@{u}..HEAD')" = 0 ] && ! git -C "$B" status --porcelain | grep -q . \
  && pass "two VMs recording different versions at once: no conflict, both pushed" || fail "version file conflict blocked the push"
[ -z "$(vstart 2.1.330)" ] && pass "after the merge, the newest version (2.1.330) counts" || fail "merged version file misread: $(cat "$A/claude-code-version")"

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
