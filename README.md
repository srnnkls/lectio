# lectio

*lectiō • a reading*

> From Latin *lectiō* ("a reading"), from *legō* ("to gather, to read")
>
> Pronunciation: /ˈlek.ti.oː/

## About

lectio turns a markdown string into the text a reader would see: `**bold**` comes out bold, a
backticked span comes out in a code face, a link comes out as a clickable shr link, and the
asterisks, backticks and brackets are gone. The answer is a propertized string, ready to insert
into any buffer. No mode, buffer or window is involved.

A small GFM-style parser writes the markdown as HTML, and shr, the HTML renderer built into
Emacs, draws it. Fenced code blocks never reach shr, which would flatten them into running text.
A callback of yours receives each fence's language and body and returns the text to show in its
place, so you can fontify code with the major mode of your choice or leave it as written.

Reach for lectio when a package shows markdown it did not write, such as agent messages, issue
bodies or commit descriptions, and wants it read rather than shown as source.
[memex.el](https://github.com/srnnkls/memex.el), to search indexed agent conversation history,
renders an agent's markdown through lectio. [limen](https://github.com/srnnkls/limen), an Emacs
interface for agents, renders messages as markdown when lectio is installed.

## Installation

lectio needs Emacs 29.1 or newer.

On Emacs 30 or newer, install it with `use-package`:

```emacs-lisp
(use-package lectio
  :vc (:url "https://github.com/srnnkls/lectio" :rev :newest))
```

On Emacs 29, run:

```
M-x package-vc-install RET https://github.com/srnnkls/lectio RET
```

On Doom Emacs, add this to `packages.el`:

```emacs-lisp
(package! lectio :recipe (:host github :repo "srnnkls/lectio"))
```

A package that uses lectio loads it with `(require 'lectio)`.

## Getting started

Evaluate this in `*scratch*`:

````emacs-lisp
(with-current-buffer (get-buffer-create "*lectio*")
  (erase-buffer)
  (insert (lectio-render "## Setup

Run `make` **once**, then read [the guide](https://example.org).

- one
- two

```sh
make install
```"))
  (pop-to-buffer (current-buffer)))
````

The `*lectio*` buffer shows:

```
Setup

Run make once, then read the guide.

* one
* two

make install
```

`make` is drawn in the `lectio-code` face, `once` in bold, and `the guide` is a link that `RET`
follows. The fenced block comes back as written, since no callback was given.

To draw fences yourself, pass a function of the language and the body:

```emacs-lisp
(lectio-render text
               (lambda (language body)
                 (format "[%s]\n%s" language (string-trim-right body))))
```

## Functions

| Symbol | Does |
| --- | --- |
| `(lectio-render MARKDOWN &optional CODE)` | return the text shr draws from `MARKDOWN` |
| `(lectio-render-all MARKDOWNS &optional CODE)` | render a list, keeping every entry in its place |
| `(lectio-html MARKDOWN)` | return the HTML the built-in parser writes for `MARKDOWN` |
| `lectio-html-function` | user option: the function that turns prose into HTML |
| `lectio-code` | face: code spans written between backticks |

`lectio-render` returns `MARKDOWN` unchanged when it is nil, empty or only whitespace. Otherwise
it splits `MARKDOWN` at its fenced blocks, draws each stretch of prose through
`lectio-html-function` and shr, calls `CODE` with each fence's language (the trimmed info string,
possibly empty) and body, and joins the non-empty pieces with a blank line. Without `CODE`, a
fence's body comes back with trailing whitespace removed. What `CODE` returns is inserted as it
is, so it may carry text properties.

`lectio-render-all` calls `lectio-render` on each element of `MARKDOWNS` with the same `CODE`.
Nil and empty entries come back unchanged, so the answer lines up with the list it was given.

`lectio-html` is the built-in parser. Unlike `lectio-render`, it also writes fenced blocks, as
`<pre><code>` with their bodies escaped.

`lectio-html-function` defaults to the built-in parser. It is called with the prose between
fenced blocks and returns HTML. Set it to a fuller markdown converter to replace the parser while
keeping shr and the code callback. Type: `function`. Group: `lectio`.

`lectio-code` has a light and a dark variant, each a tinted foreground on a grey background.

## What the parser reads

The built-in parser covers the markdown that agents and short documents write:

| Markdown | Drawn as |
| --- | --- |
| a fence of three or more `` ` `` or `~` | handed to `CODE`; the closing fence repeats the opening run |
| `#` to `######` headings | shr's heading at that level |
| `-`, `*` or `+` items | a bulleted list |
| `1.` items | a numbered list |
| `>` lines | a block quote, joined into one paragraph |
| `` `code` `` | the `lectio-code` face, contents left alone |
| `**strong**`, `__strong__` | bold |
| `*emphasis*`, `_emphasis_` | italic |
| `[text](url)` | an shr link |
| anything else | a paragraph, its lines joined |

Blank lines separate blocks, and a block is a list or a quote only when every one of its lines is
an item or a quoted line. Give a heading its own block: other lines in the same block are
dropped. Nested lists, tables, images, raw HTML and reference links are not read and come out as
paragraph text. `shr-use-fonts` and `shr-width` are nil while drawing, so the text uses the
default font and is not filled to a width.

## Concepts

| Term | Meaning |
| --- | --- |
| *prose* | the markdown between fenced blocks, drawn through HTML and shr |
| *fence* | a fenced code block, never parsed as markdown and never seen by shr |
| *code callback* | the `CODE` function that returns the text drawn in place of each fence |

## Development

To work on lectio, clone it and put the checkout on your `load-path`:

```sh
git clone https://github.com/srnnkls/lectio.git
```

```emacs-lisp
(add-to-list 'load-path "/path/to/lectio")
(require 'lectio)
```

Tests and lint run through [Eask](https://emacs-eask.github.io/):

```sh
eask compile                  # byte-compile; warnings are errors
eask run script test          # ERT suite in lectio-tests.el
eask lint checkdoc --strict
eask lint package --strict
```

CI also runs `eask lint declare`, `indent`, `regexps` and `keywords`, each with `--strict`.

Where the code lives:

- `lectio.el`: the parser, the shr drawing and the public functions.
- `lectio-tests.el`: the ERT suite, which asserts the parser's HTML rather than shr's layout.
