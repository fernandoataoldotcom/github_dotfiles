# github_dotfiles

Self-serving dotfiles installer for Linux/Debian boxes (SSH / remote VMs /
devcontainers). One command sets up Oh-My-Zsh, zsh plugins, and my config files
(zsh, tmux, vim, htop, and Claude Code).

## Install

```sh
curl -f https://setup.decentturing.com|zsh
```

Keep `https://` (plain http only redirects, and that first hop is unauthenticated)
and `-f` (fail instead of piping an error page into zsh). Nothing else is needed;
getting shorter than this takes a shorter domain.

If `setup.decentturing.com` is down, fetch the same script from GitHub. Cloudflare
Pages only serves this entry script; the installer fetches everything else from
GitHub anyway, so the result is identical:

```sh
curl -f https://raw.githubusercontent.com/fernandoataoldotcom/github_dotfiles/main/install|zsh
```

It installs the newest tagged version without asking (the tag's own installer runs,
so a tag pins the whole install), then signs in to Claude and GitHub, clones the Claude memory repo and
drops you into the new shell. It is safe to re-run — anything it would overwrite is
copied to `~/.dotfiles-backup-<timestamp>/` first.

## What it does

- Installs **Oh-My-Zsh** pinned to a commit SHA (no piping an upstream installer to `sh`).
- Installs zsh plugins, each cloned by tag and **verified against a pinned commit SHA**
  (detects moved/tampered tags): `zsh-syntax-highlighting`, `zsh-autosuggestions`,
  `you-should-use`. `git` and `kubectl` are built-in Oh-My-Zsh plugins.
- Fetches config files for this ref: `zshrc` → `~/.zshrc`, `fernandoataoldotcom-functions.zsh`
  (custom functions, e.g. `go-rebase`), `tmux.conf` (+ `tmux-cheatsheet.txt`, shown by
  prefix `?`), `vimrc` (+ vim-plug), `htoprc`,
  and `claude-settings.json` → `~/.claude/settings.json`.
- Merges `vscode-machine-settings.json` into the VS Code server's machine settings
  (`~/.vscode-server/data/Machine/settings.json`). Today that only hides the chat
  (Copilot) sidebar by default. It adds keys and keeps the ones already there,
  backs the file up first, and skips a file that has comments (JSONC) with a warning.
  This is needed because under `code serve-web` your user settings live in the browser,
  so they don't carry over to a new VM.
- Runs `vim +PlugInstall` if `vim` is present.
- Installs the **Claude Code CLI** from the `stable` channel via Anthropic's official
  native installer (user-local, no Node/sudo, SHA256-verified). If the image already
  ships `claude`, it is moved to current stable with `claude install stable`. Run `claude` once afterwards to authenticate.
- With a terminal attached: signs in to **Claude** (`claude auth login` with
  `BROWSER` unset, so you get the paste-a-code URL instead of a tab that redirects
  to localhost on the VM; `claude-login` does the same later), logs in to **GitHub** (`yolo` if the image has it, else
  `gh auth login`), repairs a `null` git `user.name`, and clones the private
  **Claude memory** repo (see below). Then `exec`s the new shell
  (`DOTFILES_NO_EXEC=1` to opt out).

It does **not** install system packages. It expects `tmux` (>=3.2), `gh`, `jq`,
`kubectl`, `vim` and `docker`, and prints a warning naming any that are missing; when they
are all there it says nothing.

## Claude Code

The installer places `~/.claude/settings.json`, installs the `claude` CLI and, with
a terminal attached, runs `claude auth login` (one browser step per VM). The
native installer is fetched with `curl ... | bash`; if you'd rather not run a
remote installer, install the CLI yourself and the script will only run `claude install` on it.

**Updates.** Every installer run puts Claude on the `stable` channel (fresh install,
or `claude install stable` over a version baked into the image), and `autoUpdatesChannel: stable`
in the settings keeps auto-update on it (about a week behind `latest`, skipping
releases with regressions). For a one-off, `CLAUDE_CHANNEL=latest` or
`CLAUDE_CHANNEL=2.1.294` picks another channel or an exact version at install time.

**Memory that survives the VM.** `autoMemoryDirectory` points Claude at
`~/.claude-memory/memory`, a clone of a **private** repo (`MEMORY_REPO`, default
`fernandoataoldotcom/claude-memory`) shared by every VM. Hooks run
[`claude-memory-sync`](claude-memory-sync): pull at session start, commit + push
after each turn and at session end. At session start it also compares
`claude --version` with the newest version any VM has seen (`claude-code-version`
in the memory repo). The first session on a newer version asks Claude to read the
changelog since the old one and report only changes that touch this setup (settings
keys, hooks, permissions, status line, memory, attribution), since a renamed setting
fails silently. Create the repo once:

```sh
gh repo create fernandoataoldotcom/claude-memory --private
```

**Project notes without a `CLAUDE.md`.** For repos whose owners don't want one
committed, put what it would say in `~/.claude-memory/projects/<owner>/<repo>.md`
(owner and repo in lowercase).
The session-start hook prints that file into Claude's context when you start
`claude` inside a clone of that repo, or in a folder that holds several clones up
to two levels down (it then prints the notes for each), so nothing is written to the project. Ask
Claude to "update the project notes" instead of running `/init`.

**Personal preferences in every session.** `claude-CLAUDE.md` is installed as
`~/.claude/CLAUDE.md` and only imports `~/.claude-memory/context/preferences.md`,
which chat sessions maintain. Code loads it in every session and project; edit the
preferences in the memory repo, not here.

Keep it private: memories can hold project details and are read back into every
session. If the clone is missing, sync is a no-op and memory stays VM-local.

**Keys stay out of the conversation.** The settings deny Claude's `Read` and `Edit`
tools on `~/.snowflake/**`, where Snowflake private keys live (e.g. for a
data project's diagnostics tool), and on `~/.ssh/**`; `Read` on
`~/.claude/.credentials.json` and `~/.git-credentials`; and the Bash commands
`gh auth token`, `gh auth status -t` and `kubectl get`/`describe` on secrets.
Reading or editing any `.env` file asks first. Tools that use the keys still work;
Claude just can't open the files and pull a key into a transcript. The file rules
block the Read and Edit tools only, not a `cat` run through Bash.

**Secret scan before Claude commits or pushes.** A `PreToolUse` hook,
[`claude-gitleaks-guard`](claude-gitleaks-guard) (from venkatamutyala/dotfiles,
installed as `~/.claude/hooks/gitleaks-guard.sh`), runs pinned gitleaks in Docker
over what a `git commit` or `git push` would send: staged and unstaged changes to
tracked files (plus untracked files when the same command runs `git add`), or HEAD,
branches and tags not on any remote. It blocks the command and names the file and
rule, never the secret. It reads the command text, so `bash -c`, `xargs` and `sudo`
wrappers are not followed. The diff goes to gitleaks on stdin, so it works where the Docker daemon
can't bind-mount the repo. Without Docker, Claude's commits and pushes are blocked.
It only sees git commands Claude runs, not yours.

**Status line.** [`claude-statusline`](claude-statusline) (from venkatamutyala/dotfiles,
installed as `~/.claude/statusline.sh`) shows `model | dir (branch) | ctx N%` under
the prompt, so you can see when the context is filling up.

## Rolling back

If a new tag breaks VMs, install a known-good one; its own installer runs, not
main's:

```sh
curl -f https://setup.decentturing.com|DOTFILES_REF=v2.0.4 zsh    # a specific tag
curl -f https://setup.decentturing.com|DOTFILES_PICK=1 zsh        # choose from a menu
```

## Escape hatches / automation

- `REPO_RAW=<url>` — explicit config source (overrides everything; e.g. `file:///repo` for tests).
- `DOTFILES_REF=<tag>` or `zsh -s -- <tag>` — install that tag (or `refs/heads/main`); `DOTFILES_PICK=1` — menu.
- `DOTFILES_RESOLVE_ONLY=1` — dry run: print the resolved `REPO_RAW` and exit.
- `CLAUDE_CHANNEL=<stable|latest|X.Y.Z>`, `MEMORY_REPO=<owner/repo>`, `DOTFILES_NO_EXEC=1` — see above.

## Hosting (Cloudflare Pages)

`setup.decentturing.com` serves the `install` script via Cloudflare Pages:

1. **Pages → Create a project → Connect to Git**, select this repo. No build command;
   output directory = repo root (`/`).
2. [`_headers`](_headers) forces `Content-Type: text/plain` so the browser renders the
   script and `curl | zsh` stays clean.
3. [`_redirects`](_redirects) rewrites `/` → `/install` (200) so the root URL serves the
   installer (no path needed).
4. **Custom domains → Set up a domain** → `setup.decentturing.com` (DNS + TLS are automatic
   since the zone is on Cloudflare).

## Testing

```sh
tests/run-in-docker.sh            # debian:bookworm
tests/run-in-docker.sh trixie
```

Runs the real installer in a throwaway Debian container against the local checkout
(`claude` and `gh` are stubbed, so no credentials or Claude download), then checks
the result and exercises `claude-memory-sync` against a local remote. CI runs the
same test on every PR and on `main`. Add a check there for every bug that reaches a
VM.

## Versioning

New VMs install the newest tag, so a merge reaches them only once it is tagged.
[release-please](.github/workflows/release-please.yml) does the tagging: after each
merge to `main` it opens or updates a release PR that bumps the version from the
[Conventional Commits](https://www.conventionalcommits.org/) since the last release
(`feat` → minor, `fix` → patch, `feat!`/`BREAKING CHANGE` → major; `docs`, `test`,
`ci`, `chore` alone don't release) and updates `CHANGELOG.md`. Merging that PR tags
`vX.Y.Z` and publishes a GitHub Release, which is when VMs get it. Don't tag by hand.
Repo setting it needs: Settings → Actions → General → "Allow GitHub Actions to
create and approve pull requests". Release PRs don't run CI (GitHub doesn't trigger
workflows from its own token), but they only change `CHANGELOG.md`,
`version.txt` and the manifest, and `main` was tested on merge.

## Security notes

This repo is public and the deployed files are public by design (a bootstrap script
is fetched unauthenticated). **Never commit secrets.** `~/.zshrc` references
`GH_PAT`/`GITHUB_TOKEN` by environment variable only — no values are stored here.
Dependencies are version-pinned for supply-chain safety; bump them deliberately.