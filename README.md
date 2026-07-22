<div align="center">

# 🧙 jedi.vim

**Blazing-fast, fully asynchronous Python intelligence for pure Vim — powered by [jedi](https://github.com/davidhalter/jedi).**

**为原生 Vim 打造的极速、全异步 Python 智能插件 —— 由 [jedi](https://github.com/davidhalter/jedi) 强力驱动。**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Vim 8.0+](https://img.shields.io/badge/Vim-8.0%2B-019733.svg)](https://www.vim.org/)
[![jedi](https://img.shields.io/badge/powered%20by-jedi-blue.svg)](https://github.com/davidhalter/jedi)

[English](#-features) · [中文](#-特性)

</div>

---

No LSP server. No Node.js. No Neovim required. Just Vim 8, Python, and jedi — completion, signature help, documentation and navigation, all asynchronous, all out of the box.

不需要 LSP server，不需要 Node.js，也不需要 Neovim。只要 Vim 8 + Python + jedi，补全、签名提示、文档、跳转，全异步，开箱即用。

## ✨ Features

- **🚀 Truly asynchronous completion** — candidates stream in as you type (and after every `.`); Vim never freezes waiting for jedi. Debounced, stale-response-proof.
- **✍️ Call signature help** — pops up *above* the cursor while you type `(` and `,`, highlights the active parameter, never overlaps the completion menu.
- **📖 Floating documentation** — press `K` on any symbol; scroll with `C-f` / `C-b`, close with `q` or `Esc`.
- **🧭 Jump to definition** — `gd`, with a location list when there are multiple candidates.
- **🐍 Zero-config virtualenvs** — automatically discovers `.venv`, `.env`, `venv` or `env` in your project root and feeds it to jedi.
- **🪶 Pure Vimscript** — a single long-running jedi process behind Vim's `job` + `channel` + JSON-RPC. Fast startup, tiny footprint.

## 📦 Requirements

- Vim 8.0+ with `+job`, `+channel`, `+json` (`+popupwin` for floating windows)
- Python 3 with `jedi` installed:

```bash
pip install jedi
```

## 🔧 Installation

Using [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'r1cardohj/jedi.vim'
```

Then make sure `jedi` is importable by `g:jedi#python_executable` (default: `python3`).

## 🚀 Usage

Open any Python file. Everything works out of the box:

| Key            | Action                                                        |
|----------------|---------------------------------------------------------------|
| *(typing)*     | Async completion menu appears as you type and after `.`       |
| `(` / `,`      | Signature help pops up, active parameter marked `*like_this*` |
| `)` / `Esc`    | Signature help closes                                         |
| `gd`           | Jump to definition                                            |
| `K`            | Floating documentation (`C-f`/`C-b` scroll, `q` closes)       |
| `gs`           | Show call signature on demand                                 |
| `C-X C-O`      | Manual (synchronous) omni completion                          |

Commands:

```vim
:JediEnable [virtual_env_path]
:JediDisable
:JediGoto
:JediDoc
:JediSignature
```

## ⚙️ Configuration

All optional, in your `.vimrc`:

```vim
" Explicit virtualenv (always wins over auto-discovery)
let g:jedi#virtual_env = expand('~/venv/my-project')

" Turn off automatic completion as you type (default: 1)
let g:jedi#autocomplete = 0

" Debounce delays in ms (defaults: 100 / 100; 0 = immediate)
let g:jedi#complete_delay = 100
let g:jedi#signature_delay = 100

" Completion menu behavior
let g:jedi#completeopt = 'menuone,noselect,preview'

" Python running the jedi server
let g:jedi#python_executable = 'python3'

" Disable the whole plugin
let g:jedi#enabled = 0
```

See `:help jedi` for the full reference.

## 🏗️ Architecture

```text
┌─────────────┐   JSON-RPC over channel (async)   ┌──────────────────┐
│  Vim (you)  │ ◄──────────────────────────────► │  jedi_server.py  │
│  Vimscript  │      job + channel + timers      │  jedi (Python)   │
└─────────────┘                                   └──────────────────┘
```

```text
jedi.vim/
├── plugin/jedi.vim           " commands & default options
├── autoload/jedi.vim         " core: RPC, async completion, popups, navigation
├── ftplugin/python/jedi.vim  " python buffer guard
├── python/jedi_server.py     " persistent jedi JSON-RPC backend
└── doc/jedi.txt              " :help jedi
```

---

<div align="center">

# 🧙 jedi.vim（中文）

</div>

## ✨ 特性

- **🚀 真·全异步补全** —— 边输入边出候选（包括 `.` 之后），Vim 绝不卡顿等待 jedi。带防抖，自动丢弃过期响应。
- **✍️ 函数签名提示** —— 输入 `(` 和 `,` 时在光标**上方**浮出，高亮当前参数，绝不遮挡补全菜单。
- **📖 悬浮文档** —— 光标停在任意符号上按 `K`,`C-f` / `C-b` 翻页，`q` 或 `Esc` 关闭。
- **🧭 跳转定义** —— `gd`，多个候选时打开 location list。
- **🐍 零配置虚拟环境** —— 自动发现项目根目录下的 `.venv`、`.env`、`venv`、`env`，自动喂给 jedi。
- **🪶 纯 Vimscript** —— 单个常驻 jedi 进程，基于 Vim 的 `job` + `channel` + JSON-RPC。启动快，占用小。

## 📦 依赖

- Vim 8.0+（需 `+job`、`+channel`、`+json`，悬浮窗需 `+popupwin`）
- Python 3 且已安装 `jedi`:

```bash
pip install jedi
```

## 🔧 安装

使用 [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'you/jedi.vim'
```

并确保 `g:jedi#python_executable`（默认 `python3`）能 `import jedi`。

## 🚀 使用

打开任意 Python 文件，开箱即用：

| 按键           | 功能                                              |
|----------------|---------------------------------------------------|
| *（直接输入）* | 异步补全菜单随输入和 `.` 自动弹出                  |
| `(` / `,`      | 签名提示浮出，当前参数标记为 `*这样*`              |
| `)` / `Esc`    | 关闭签名提示                                       |
| `gd`           | 跳转到定义                                         |
| `K`            | 悬浮文档（`C-f`/`C-b` 翻页，`q` 关闭）            |
| `gs`           | 手动查看函数签名                                   |
| `C-X C-O`      | 手动（同步）omni 补全                              |

命令：

```vim
:JediEnable [virtual_env_path]
:JediDisable
:JediGoto
:JediDoc
:JediSignature
```

## ⚙️ 配置

全部可选，写在 `.vimrc` 中：

```vim
" 显式指定虚拟环境（优先于自动发现）
let g:jedi#virtual_env = expand('~/venv/my-project')

" 关闭输入时自动补全（默认: 1）
let g:jedi#autocomplete = 0

" 防抖延迟（毫秒，默认 100 / 100；0 = 立即）
let g:jedi#complete_delay = 100
let g:jedi#signature_delay = 100

" 补全菜单行为
let g:jedi#completeopt = 'menuone,noselect,preview'

" 运行 jedi server 的 Python
let g:jedi#python_executable = 'python3'

" 完全禁用插件
let g:jedi#enabled = 0
```

完整文档见 `:help jedi`。

## 📄 License

MIT
