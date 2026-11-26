# Changelog

## [2.9.1](https://github.com/fernandoataoldotcom/github_dotfiles/compare/v2.9.0...v2.9.1) (2026-11-26)


### Bug Fixes

* **install:** do not hand the pinned REPO_RAW and DOTFILES_REF to the new shell ([3b5d8ea](https://github.com/fernandoataoldotcom/github_dotfiles/commit/3b5d8eaa8d187ef55377bccbd8a73326fb5c57b9))
* installer env leak on reinstall, and point the session-start priority check at the Time log ([6be75e6](https://github.com/fernandoataoldotcom/github_dotfiles/commit/6be75e691df8b83f7c35e18b0aac00ccf0bca5b6))
* **memory:** point sessions at the day's priority instead of reading a Date line ([bc080ab](https://github.com/fernandoataoldotcom/github_dotfiles/commit/bc080abf6fa1901bd0d71fe62fd5cb7b5bd6710a))

## [2.9.0](https://github.com/fernandoataoldotcom/github_dotfiles/compare/v2.8.0...v2.9.0) (2026-11-23)


### Features

* **memory:** ask again after midnight and when the standing priority is uncertain ([d9fe92d](https://github.com/fernandoataoldotcom/github_dotfiles/commit/d9fe92d3ccd7da715a879d418ea6d023261bfb4d))
* **memory:** tell the session to ask for today's priority when it is not set ([ff76390](https://github.com/fernandoataoldotcom/github_dotfiles/commit/ff76390f982a2aaa0a96cdd6c64d1fe11c65bea6))
* **memory:** tell the session to ask for today's priority when it is not set ([352521d](https://github.com/fernandoataoldotcom/github_dotfiles/commit/352521de22c5c0ebcb7f48ffe174f3a551f37260))


### Bug Fixes

* **memory:** print the priority first, validate its time zone, tolerate formatting ([4c8f956](https://github.com/fernandoataoldotcom/github_dotfiles/commit/4c8f95644e3b55bdb87a38592c36c0751a0378d2))

## [2.8.0](https://github.com/fernandoataoldotcom/github_dotfiles/compare/v2.7.0...v2.8.0) (2026-11-21)


### Features

* **memory:** load project notes when a session first works in a repo ([03be432](https://github.com/fernandoataoldotcom/github_dotfiles/commit/03be4325b4abea8b6946f8564e562941a72fbc15))
* **memory:** load project notes when a session first works in a repo ([d9cf990](https://github.com/fernandoataoldotcom/github_dotfiles/commit/d9cf9908624b251052c44b34169d46bc4e12e4c3))

## [2.7.0](https://github.com/fernandoataoldotcom/github_dotfiles/compare/v2.6.0...v2.7.0) (2026-11-20)


### Features

* **claude:** default to auto mode and turn off unused synced skills in Code ([3ad7e64](https://github.com/fernandoataoldotcom/github_dotfiles/commit/3ad7e64328fa9f65c69e9d10b4c0b458eebced24))
* **claude:** default to auto mode and turn off unused synced skills in Code ([1aa7e65](https://github.com/fernandoataoldotcom/github_dotfiles/commit/1aa7e65add1314ff060fa96e3c67467eee2dbdc9))

## [2.6.0](https://github.com/fernandoataoldotcom/github_dotfiles/compare/v2.5.0...v2.6.0) (2026-11-13)


### Features

* **memory:** sync commits name the Claude surface that made them ([31c0764](https://github.com/fernandoataoldotcom/github_dotfiles/commit/31c07645b49b57b66d1da8dbf4281790cc555c2c))

## [2.5.0](https://github.com/fernandoataoldotcom/github_dotfiles/compare/v2.4.0...v2.5.0) (2026-11-11)


### Features

* **claude:** give each new session a color no other session uses ([8db39b7](https://github.com/fernandoataoldotcom/github_dotfiles/commit/8db39b74621c65066ed16c60569d8f4e0b0ecb19))

## [2.4.0](https://github.com/fernandoataoldotcom/github_dotfiles/compare/v2.3.1...v2.4.0) (2026-11-11)


### Features

* **tmux:** turn on focus-events so programs see focus changes ([22d8327](https://github.com/fernandoataoldotcom/github_dotfiles/commit/22d8327ac74af6f7ed5d1fc02c5022e7b4d71b77))


### Bug Fixes

* **memory:** hint only when the clone says the repo is not visible ([44882aa](https://github.com/fernandoataoldotcom/github_dotfiles/commit/44882aaa1e4db2910cfacb2e3f65cd7af285745b))
* **memory:** say why the memory repo clone failed ([b6db9fe](https://github.com/fernandoataoldotcom/github_dotfiles/commit/b6db9fe8493cac8d26769aa48c16b639334bd560))

## [2.3.1](https://github.com/fernandoataoldotcom/github_dotfiles/compare/v2.3.0...v2.3.1) (2026-10-25)


### Bug Fixes

* **gh:** stop the login warning about a missing clipboard tool ([d6f5a2a](https://github.com/fernandoataoldotcom/github_dotfiles/commit/d6f5a2a425b791a47ad683213b8116e7322bb32a)), closes [#16](https://github.com/fernandoataoldotcom/github_dotfiles/issues/16)
