# consult-vulpea

[![MELPA](https://melpa.org/packages/consult-vulpea-badge.svg)](https://melpa.org/#/consult-vulpea)

Use [Consult](https://github.com/minad/consult) in tandem with [Vulpea](https://github.com/d12frosted/vulpea).

## Features

- **Live previews**: When selecting notes via `vulpea-find` or `vulpea-insert`, get a live preview of the note file as you navigate through candidates.
- **Consult-powered grep/find**: Use `consult-vulpea-grep` and `consult-vulpea-find` to search within your vulpea directories with live previews.
- **Consult-buffer integration**: Quickly switch to open vulpea note buffers using `consult-buffer` with narrowing support (default key `v`).

## Installation

consult-vulpea is available on [MELPA](https://melpa.org/#/consult-vulpea).

```elisp
(use-package consult-vulpea
  :ensure t
  :after vulpea
  :config
  (consult-vulpea-mode 1))
```

Or install manually with `M-x package-install RET consult-vulpea RET`.

### Doom Emacs

Add to `packages.el`:

```elisp
(package! consult-vulpea)
```

Add to `config.el`:

```elisp
(use-package! consult-vulpea
  :after vulpea
  :config
  (consult-vulpea-mode 1))
```

> [!IMPORTANT]
> Do not use `:after consult` — this can prevent the package from loading properly at startup.

## Commands

| Command | Description |
|---------|-------------|
| `consult-vulpea-grep` | Search vulpea notes using ripgrep with live preview |
| `consult-vulpea-find` | Find vulpea note files with live preview |

## Customization

| Variable | Default | Description |
|----------|---------|-------------|
| `consult-vulpea-grep-command` | `consult-ripgrep` | Grep command to use (can also be `consult-grep`) |
| `consult-vulpea-find-command` | `consult-find` | Find command to use |
| `consult-vulpea-preview-key` | `consult-preview-key` | Key to trigger preview, defaults to consult's global setting |
| `consult-vulpea-buffer-narrow-key` | `?v` | Narrow key for `consult-buffer` integration |

## How it works

When `consult-vulpea-mode` is enabled, the package:

1. Advises `vulpea-select-from` with a consult-powered replacement. This means all vulpea commands that use the note selection interface (like `vulpea-find` and `vulpea-insert`) automatically gain consult features.
2. Adds a new "Vulpea" source to `consult-buffer-sources`, allowing you to narrow to open vulpea note buffers by pressing `v`.

## Requirements

- Emacs 28.1+
- [vulpea](https://github.com/d12frosted/vulpea) 2.0.0+
- [consult](https://github.com/minad/consult) 2.2+

## Related

- [consult-org-roam](https://github.com/jgru/consult-org-roam) — Similar integration for [org-roam](https://github.com/org-roam/org-roam)
- [consult-denote](https://github.com/protesilaos/consult-denote) — Similar integration for [Denote](https://github.com/protesilaos/denote)

## License

GPL-3.0
