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

An interactive run prompts you to pick a tagged version (use immutable tags for
reproducible installs), then signs in to Claude and GitHub, clones the Claude memory repo and
drops you into the new shell. It is safe to re-run — anything it would overwrite is
copied to `~/.dotfiles-backup-<timestamp>/` first.

## What it does

- Installs **Oh-My-Zsh** pinned to a commit SHA (no piping an upstream installer to `sh`).
- Installs zsh plugins, each cloned by tag and **verified against a pinned commit SHA**
  (detects moved/tampered tags): `zsh-syntax-highlighting`, `zsh-autosuggestions`,
  `you-should-use`. `git` and `kubectl` are built-in Oh-My-Zsh plugins.
- Fetches config files for this ref: `zshrc` → `~/.zshrc`, `fernandoataoldotcom-functions.zsh`
  (custom functions, e.g. `go-rebase`), `tmux.conf`, `vimrc` (+ vim-plug), `htoprc`,
  and `claude-settings.json` → `~/.claude/settings.json`.
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

It does **not** install system packages. Install these yourself if missing:

```sh
tmux (>=3.2)  gh  jq  kubectl  vim
```

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
after each turn and at session end. Create the repo once:

```sh
gh repo create fernandoataoldotcom/claude-memory --private
```

**Project notes without a `CLAUDE.md`.** For repos whose owners don't want one
committed, put what it would say in `~/.claude-memory/projects/<owner>/<repo>.md`.
The session-start hook prints that file into Claude's context when you start
`claude` inside a clone of that repo, or in a folder that holds several clones (it
then prints the notes for each), so nothing is written to the project. Ask
Claude to "update the project notes" instead of running `/init`.

Keep it private: memories can hold project details and are read back into every
session. If the clone is missing, sync is a no-op and memory stays VM-local.

## Escape hatches / automation

- `REPO_RAW=<url>` — explicit config source (overrides everything; e.g. `file:///repo` for tests).
- `DOTFILES_REF=<tag>` or `zsh -s -- <tag>` — pick a ref non-interactively (no TTY).
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

## Versioning

Cut a tag to enable the version picker and reproducible installs:

```sh
git tag v1 && git push --tags
```

## Security notes

This repo is public and the deployed files are public by design (a bootstrap script
is fetched unauthenticated). **Never commit secrets.** `~/.zshrc` references
`GH_PAT`/`GITHUB_TOKEN` by environment variable only — no values are stored here.
Dependencies are version-pinned for supply-chain safety; bump them deliberately.