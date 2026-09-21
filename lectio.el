;;; lectio.el --- Read markdown as the text shr draws from it -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Sören Nikolaus

;; Author: Sören Nikolaus <soeren@code17.io>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: text, hypermedia
;; URL: https://github.com/srnnkls/lectio

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Markdown shown as written shows the source of a text rather than the
;; text: the asterisks, the backticks, the fences.  `lectio-render'
;; turns the markdown an agent or a document holds into the text shr
;; draws from it, ready to insert into a buffer.
;;
;; The markdown reaches shr as HTML from a small GFM-ish parser of its
;; own: fenced code, ATX headings, bulleted and numbered lists, quotes,
;; links and the inline spans - code, strong, emphasis.  A fenced block
;; never reaches shr, which would flatten it to running text;
;; `lectio-render' takes an optional CODE callback that is handed the
;; fence's language and body and answers with what to draw in its place.

;;; Code:

(require 'rx)
(require 'seq)
(require 'shr)
(require 'subr-x)

(defgroup lectio nil
  "Rendering markdown as the text shr draws from it."
  :group 'text)

(defconst lectio--fence
  (rx bol (group (>= 3 (in "`~"))) (group (zero-or-more nonl)) "\n"
      (group (minimal-match (zero-or-more anychar)))
      bol (backref 1) (zero-or-more (in " \t")) (or "\n" eos))
  "A fenced code block: its opening run, its info string and its body.
The run is captured so the closing fence has to match the opening one,
and the info string because it names the language the body is in.")

(defface lectio-code
  '((((background light)) :background "#eceef1" :foreground "#8a3d52")
    (((background dark)) :background "#2f333b" :foreground "#e6a1b0"))
  "Face for a code span written between backticks."
  :group 'lectio)

(defconst lectio--heading
  (rx bol (group (repeat 1 6 "#")) (one-or-more " ") (group (one-or-more nonl)))
  "An ATX heading and its level.")

(defun lectio--escape (text)
  "Return TEXT with the four HTML metacharacters spelled out."
  (thread-last text
               (replace-regexp-in-string "&" "&amp;")
               (replace-regexp-in-string "<" "&lt;")
               (replace-regexp-in-string ">" "&gt;")
               (replace-regexp-in-string "\"" "&quot;")))

(defun lectio--spans (text)
  "Return TEXT with its inline markdown turned into HTML.
Code spans are taken first and their contents left alone, since a
backtick is how an agent writes the paths and flags that would
otherwise read as emphasis."
  (let ((parts nil)
        (position 0))
    (while (string-match "`\\([^`\n]+\\)`" text position)
      (push (lectio--emphasis
             (substring text position (match-beginning 0)))
            parts)
      (push (format "<code>%s</code>"
                    (lectio--escape (match-string 1 text)))
            parts)
      (setq position (match-end 0)))
    (push (lectio--emphasis (substring text position)) parts)
    (apply #'concat (nreverse parts))))

(defun lectio--emphasis (text)
  "Return TEXT escaped, with its links and emphasis turned into HTML."
  (thread-last (lectio--escape text)
               (replace-regexp-in-string
                (rx "[" (group (zero-or-more (not (in "]" "\n")))) "]"
                    "(" (group (zero-or-more (not (in ")" "\n")))) ")")
                "<a href=\"\\2\">\\1</a>")
               (replace-regexp-in-string
                (rx (or "**" "__") (group (minimal-match (one-or-more nonl)))
                    (or "**" "__"))
                "<strong>\\1</strong>")
               (replace-regexp-in-string
                (rx (in "*_") (group (minimal-match (one-or-more (not (in "*_")))))
                    (in "*_"))
                "<em>\\1</em>")))

(defun lectio--list-html (lines ordered)
  "Return LINES, each an item's text, as an ORDERED or bulleted list."
  (format "<%s>\n%s\n</%s>"
          (if ordered "ol" "ul")
          (mapconcat (lambda (line)
                       (format "<li>%s</li>" (lectio--spans line)))
                     lines "\n")
          (if ordered "ol" "ul")))

(defun lectio--block-html (block)
  "Return the paragraph, list, heading or quote BLOCK as HTML."
  (let ((lines (split-string block "\n" t "[ \t]+")))
    (cond
     ((null lines) "")
     ((string-match lectio--heading block)
      (format "<h%d>%s</h%d>"
              (length (match-string 1 block))
              (lectio--spans (match-string 2 block))
              (length (match-string 1 block))))
     ((seq-every-p (lambda (line) (string-match-p (rx bos (in "-*+") " ") line))
                   lines)
      (lectio--list-html
       (mapcar (lambda (line) (substring line 2)) lines) nil))
     ((seq-every-p (lambda (line)
                     (string-match-p (rx bos (one-or-more digit) "." " ") line))
                   lines)
      (lectio--list-html
       (mapcar (lambda (line)
                 (replace-regexp-in-string (rx bos (one-or-more digit) ". ") ""
                                           line))
               lines)
       t))
     ((seq-every-p (lambda (line) (string-prefix-p ">" line)) lines)
      (format "<blockquote>\n<p>%s</p>\n</blockquote>"
              (lectio--spans
               (string-join (mapcar (lambda (line)
                                      (string-trim (substring line 1)))
                                    lines)
                            " "))))
     (t (format "<p>%s</p>" (lectio--spans (string-join lines " ")))))))

(defun lectio--to-html (markdown)
  "Return MARKDOWN as HTML.
Fences come out first so nothing inside one is read as markup, and what
is left between them is split into blocks on blank lines."
  (let ((out nil)
        (position 0))
    (while (string-match lectio--fence markdown position)
      (let ((before (substring markdown position (match-beginning 0)))
            (code (match-string 3 markdown))
            (after (match-end 0)))
        (dolist (block (split-string before "\n[ \t]*\n" t))
          (push (lectio--block-html block) out))
        (push (format "<pre><code>%s</code></pre>"
                      (lectio--escape code))
              out)
        (setq position after)))
    (dolist (block (split-string (substring markdown position) "\n[ \t]*\n" t))
      (push (lectio--block-html block) out))
    (string-join (nreverse out) "\n")))

(defalias 'lectio-html #'lectio--to-html
  "Return MARKDOWN as HTML.")

(defcustom lectio-html-function #'lectio--to-html
  "Function turning a markdown string into HTML.
Called with the prose between fenced blocks; the default is the parser
in this file, and a caller with a fuller converter, such as tropos.el
over goldmark, installs its own here."
  :type 'function
  :group 'lectio)

(defun lectio--tag-code (dom)
  "Draw the code span DOM as shr would, marked as the code it is.
shr draws `code' as running text, which loses the one thing the span
was written to say."
  (let ((start (point)))
    (shr-generic dom)
    (add-face-text-property start (point) 'lectio-code t)))

(defun lectio--draw (html)
  "Return the text shr draws from HTML."
  (with-temp-buffer
    (insert html)
    (let ((shr-use-fonts nil)
          (shr-width nil)
          (shr-indentation 0)
          (shr-external-rendering-functions
           (cons '(code . lectio--tag-code)
                 shr-external-rendering-functions)))
      (shr-render-region (point-min) (point-max)))
    (string-trim (buffer-string))))

(defun lectio--plain-code (_language code)
  "Return CODE as it was written, whatever LANGUAGE it is in."
  (string-trim-right code))

(defun lectio-render (markdown &optional code)
  "Return the text shr draws from MARKDOWN, or MARKDOWN when it is empty.
A fenced block never reaches shr, which would flatten it to running
text: CODE is called with the fence's language and body and answers
with what to draw in its place, `lectio--plain-code' by default."
  (if (or (null markdown) (string-empty-p (string-trim markdown)))
      markdown
    (let ((code (or code #'lectio--plain-code))
          (position 0)
          (out nil))
      (while (string-match lectio--fence markdown position)
        (let ((prose (substring markdown position (match-beginning 0)))
              (language (string-trim (match-string 2 markdown)))
              (body (match-string 3 markdown))
              (after (match-end 0)))
          (push (lectio--draw (funcall lectio-html-function prose)) out)
          (push (funcall code language body) out)
          (setq position after)))
      (push (lectio--draw
             (funcall lectio-html-function (substring markdown position)))
            out)
      (string-join (seq-remove #'string-empty-p (nreverse out)) "\n\n"))))

(defun lectio-render-all (markdowns &optional code)
  "Return the text shr draws from each of MARKDOWNS, in order.
Every entry keeps its place, empty ones included, so a caller can zip
the answer back against the records it asked about.  CODE draws the
fenced blocks, as in `lectio-render'."
  (mapcar (lambda (markdown) (lectio-render markdown code)) markdowns))

(provide 'lectio)
;;; lectio.el ends here
