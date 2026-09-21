# lectio

Read markdown as the text shr draws from it.

A small GFM-ish parser turns fenced code, ATX headings, bulleted and
numbered lists, quotes, links and the inline spans into HTML, and shr
draws that into a propertized string ready to insert into a buffer.
Fenced blocks never reach shr: a callback decides what stands in for
each of them.

## Entry points

```elisp
(lectio-render MARKDOWN &optional CODE)
```

Return the text shr draws from MARKDOWN, or MARKDOWN itself when it is
empty.  CODE is called with a fence's language and body and answers with
the text to draw in its place; the default returns the body as written.

```elisp
(lectio-render-all MARKDOWNS &optional CODE)
```

Render each of MARKDOWNS in order, keeping empty entries in place so the
answer zips back against what was asked.

`lectio-html` returns the intermediate HTML.  Code spans are
drawn in the `lectio-code` face.

## Install

Put the directory on `load-path` and `(require 'lectio)`.

## Tests

```sh
eask install-deps --dev
eask run script test
```
