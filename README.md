# github_dotfiles

Self-serving dotfiles installer for Linux/Debian boxes (SSH / remote VMs /
devcontainers). One command sets up Oh-My-Zsh, zsh plugins, and my config files
(zsh, tmux, vim, htop, and Claude Code).

## Install

```sh
curl setup.<your-domain> | zsh
```

An interactive run prompts you to pick a tagged version (use immutable tags for
reproducible installs). It is safe to re-run — anything it would overwrite is
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

It does **not** install system packages. Install these yourself if missing:

```sh
tmux (>=3.2)  gh  jq  kubectl  vim
```

Claude Code: the installer only places `~/.claude/settings.json`. Install the CLI
separately if you want it.

## Escape hatches / automation

- `REPO_RAW=<url>` — explicit config source (overrides everything; e.g. `file:///repo` for tests).
- `DOTFILES_REF=<tag>` or `zsh -s -- <tag>` — pick a ref non-interactively (no TTY).
- `DOTFILES_RESOLVE_ONLY=1` — dry run: print the resolved `REPO_RAW` and exit.

## Hosting (Cloudflare Pages)

`setup.<your-domain>` serves the `install` script via Cloudflare Pages:

1. **Pages → Create a project → Connect to Git**, select this repo. No build command;
   output directory = repo root (`/`).
2. [`_headers`](_headers) forces `Content-Type: text/plain` so the browser renders the
   script and `curl | zsh` stays clean.
3. [`_redirects`](_redirects) rewrites `/` → `/install` (200) so the root URL serves the
   installer (no path needed).
4. **Custom domains → Set up a domain** → `setup.<your-domain>` (DNS + TLS are automatic
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