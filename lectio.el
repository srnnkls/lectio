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

(require 'dom)
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

(defconst lectio--table-rule
  (rx bos (opt "|") (zero-or-more (in " \t"))
      (opt ":") (one-or-more "-") (opt ":")
      (zero-or-more (zero-or-more (in " \t")) "|" (zero-or-more (in " \t"))
                    (opt ":") (one-or-more "-") (opt ":"))
      (zero-or-more (in " \t")) (opt "|") eos)
  "The delimiter row under a table's header, one run of dashes a column.")

(defun lectio--table-cells (line)
  "Return the cells of the table row LINE, its outer pipes dropped.
A pipe escaped with a backslash, or written inside a code span, stays in
its cell: a code span is where an agent puts a shell pipeline."
  (let* ((line (string-remove-prefix "|" (string-trim line)))
         (line (if (string-suffix-p "\\|" line)
                   line
                 (string-remove-suffix "|" line)))
         (cells nil)
         (cell nil)
         (code nil)
         (index 0))
    (while (< index (length line))
      (let ((char (aref line index)))
        (cond
         ((and (eq char ?\\) (< (1+ index) (length line))
               (eq (aref line (1+ index)) ?|))
          (push ?| cell)
          (setq index (1+ index)))
         ((and (eq char ?|) (not code))
          (push (string-trim (concat (nreverse cell))) cells)
          (setq cell nil))
         (t
          (when (eq char ?`) (setq code (not code)))
          (push char cell))))
      (setq index (1+ index)))
    (push (string-trim (concat (nreverse cell))) cells)
    (nreverse cells)))

(defun lectio--table-html (header rule rows)
  "Return the table under the HEADER line, its RULE and its ROWS as HTML.
Every row is fitted to the header's columns, as GFM has it."
  (let* ((columns (length (lectio--table-cells header)))
         (aligns (mapcar (lambda (dashes)
                           (cond ((and (string-prefix-p ":" dashes)
                                       (string-suffix-p ":" dashes))
                                  "center")
                                 ((string-suffix-p ":" dashes) "right")
                                 ((string-prefix-p ":" dashes) "left")))
                         (lectio--table-cells rule)))
         (row (lambda (tag line)
                (let ((cells (lectio--table-cells line)))
                  (format "<tr>%s</tr>"
                          (mapconcat
                           (lambda (column)
                             (let ((align (nth column aligns)))
                               (format "<%s%s>%s</%s>" tag
                                       (if align (format " align=\"%s\"" align) "")
                                       (lectio--spans (or (nth column cells) ""))
                                       tag)))
                           (number-sequence 0 (1- columns))
                           ""))))))
    (format "<table>\n<thead>\n%s\n</thead>\n<tbody>\n%s\n</tbody>\n</table>"
            (funcall row "th" header)
            (mapconcat (lambda (line) (funcall row "td" line)) rows "\n"))))

(defun lectio--table-split (lines)
  "Return LINES as (BEFORE HEADER RULE ROWS AFTER) when they hold a table.
The table may follow prose without a blank line between; it ends at the
first line without a pipe."
  (let ((index 1)
        (found nil))
    (while (and (not found) (< index (length lines)))
      (when (and (string-search "|" (nth (1- index) lines))
                 (string-search "|" (nth index lines))
                 (string-match-p lectio--table-rule (nth index lines)))
        (setq found index))
      (setq index (1+ index)))
    (when found
      (let* ((rest (nthcdr (1+ found) lines))
             (rows (seq-take-while (lambda (line) (string-search "|" line)) rest)))
        (list (seq-take lines (1- found))
              (nth (1- found) lines)
              (nth found lines)
              rows
              (nthcdr (length rows) rest))))))

(defun lectio--block-html (block)
  "Return the paragraph, list, heading, quote or table BLOCK as HTML."
  (let* ((lines (split-string block "\n" t "[ \t]+"))
         (table (lectio--table-split lines)))
    (cond
     ((null lines) "")
     (table
      (pcase-let ((`(,before ,header ,rule ,rows ,after) table))
        (string-join
         (seq-remove #'string-empty-p
                     (list (lectio--block-html (string-join before "\n"))
                           (lectio--table-html header rule rows)
                           (lectio--block-html (string-join after "\n"))))
         "\n")))
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

(defconst lectio--table-gap "  "
  "What stands between two columns of a drawn table.")

(defun lectio--inline-text (dom)
  "Return the text of the inline DOM, its spans in the faces they stand for."
  (if (stringp dom)
      dom
    (let ((text (mapconcat #'lectio--inline-text (dom-children dom) ""))
          (face (pcase (dom-tag dom)
                  ((or 'strong 'b) 'bold)
                  ((or 'em 'i) 'italic)
                  ('code 'lectio-code)
                  ('a 'shr-link))))
      (when face
        (add-face-text-property 0 (length text) face t text))
      text)))

(defun lectio--cell (dom)
  "Return the table cell DOM as its text on one line and its alignment."
  (cons (string-trim (replace-regexp-in-string
                      "[ \t\n]+" " " (lectio--inline-text dom)))
        (or (dom-attr dom 'align)
            (when-let* ((style (dom-attr dom 'style))
                        ((string-match (rx "text-align" (* space) ":" (* space)
                                           (group (+ alpha)))
                                       style)))
              (match-string 1 style)))))

(defun lectio--table-rows (dom)
  "Return the rows of the table DOM, each a list of its cell DOMs."
  (let ((rows nil))
    (dolist (child (dom-children dom))
      (pcase (and (consp child) (dom-tag child))
        ('tr (push child rows))
        ((or 'thead 'tbody 'tfoot)
         (dolist (row (dom-by-tag child 'tr))
           (push row rows)))))
    (mapcar (lambda (row)
              (seq-filter (lambda (cell)
                            (and (consp cell) (memq (dom-tag cell) '(th td))))
                          (dom-children row)))
            (nreverse rows))))

(defun lectio--pad (text width align)
  "Return TEXT set in WIDTH columns, as ALIGN places it."
  (let ((gap (max 0 (- width (string-width text)))))
    (pcase align
      ("right" (concat (make-string gap ?\s) text))
      ("center" (concat (make-string (/ gap 2) ?\s) text
                        (make-string (- gap (/ gap 2)) ?\s)))
      (_ (concat text (make-string gap ?\s))))))

(defun lectio--tag-table (dom)
  "Draw the table DOM as columns padded out in the text itself.
shr lines its columns up with `:align-to', which counts from the window
edge and so goes astray under a line prefix or an indent.  A header row
is drawn bold and ruled off from the rows under it."
  (let* ((rows (mapcar (lambda (cells) (mapcar #'lectio--cell cells))
                       (lectio--table-rows dom)))
         (header (and rows
                      (seq-every-p (lambda (cell) (eq (dom-tag cell) 'th))
                                   (car (lectio--table-rows dom)))))
         (widths (mapcar (lambda (column)
                           (apply #'max 3
                                  (mapcar (lambda (row)
                                            (string-width
                                             (or (car (nth column row)) "")))
                                          rows)))
                         (number-sequence
                          0 (1- (apply #'max 0 (mapcar #'length rows))))))
         (aligns (mapcar (lambda (column)
                           (seq-some (lambda (row) (cdr (nth column row))) rows))
                         (number-sequence 0 (1- (length widths))))))
    (when rows
      (shr-ensure-paragraph)
      (seq-do-indexed
       (lambda (row index)
         (let ((line (string-trim-right
                      (string-join
                       (seq-map-indexed
                        (lambda (width column)
                          (lectio--pad (or (car (nth column row)) "") width
                                       (or (cdr (nth column row))
                                           (nth column aligns))))
                        widths)
                       lectio--table-gap))))
           (when (and header (zerop index))
             (add-face-text-property 0 (length line) 'bold t line))
           (insert line "\n")
           (when (and header (zerop index))
             (insert (propertize (mapconcat (lambda (width)
                                              (make-string width ?─))
                                            widths lectio--table-gap)
                                 'face 'shadow)
                     "\n"))))
       rows)
      (shr-ensure-paragraph))))

(defun lectio--draw (html)
  "Return the text shr draws from HTML."
  (with-temp-buffer
    (insert html)
    (let ((shr-use-fonts nil)
          (shr-width nil)
          (shr-indentation 0)
          (shr-external-rendering-functions
           (append '((code . lectio--tag-code)
                     (table . lectio--tag-table))
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
