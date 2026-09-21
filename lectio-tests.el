;;; lectio-tests.el --- Tests for the markdown renderer -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Sören Nikolaus

;; Author: Sören Nikolaus <soeren@code17.io>

;;; Commentary:

;; Run with:
;;   emacs -Q --batch -L . -l lectio-tests.el -f ert-run-tests-batch-and-exit
;;
;; The fallback parser is asserted on its HTML rather than on what shr
;; draws from it: shr's line breaking and indentation are its own and
;; change between Emacs releases, while the markup the parser owes it
;; does not.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)

(require 'lectio nil t)

(declare-function lectio--escape "lectio")
(declare-function lectio--to-html "lectio")
(declare-function lectio-html "lectio")
(declare-function lectio-render "lectio")
(declare-function lectio-render-all "lectio")


(defun lectio-tests--html (markdown)
  "Return the fallback parser's HTML for MARKDOWN, whitespace squeezed."
  (string-join (split-string (lectio--to-html markdown)) " "))

(ert-deftest lectio-escapes-html-metacharacters ()
  (should (equal (lectio--escape "a < b & c > d \"e\"")
                 "a &lt; b &amp; c &gt; d &quot;e&quot;")))

(ert-deftest lectio-fenced-code-is-verbatim-and-unparsed ()
  "What is inside a fence is code, including anything that looks like markup."
  (let ((html (lectio-tests--html
               "before\n\n```sh\nrm -rf * # **not bold** <tag>\n```\n\nafter")))
    (should (string-search "<pre><code>rm -rf * # **not bold** &lt;tag&gt;" html))
    (should (string-search "before" html))
    (should (string-search "after" html))))

(ert-deftest lectio-renders-headings-at-their-level ()
  (let ((html (lectio-tests--html "# One\n\n### Three\n")))
    (should (string-search "<h1>One</h1>" html))
    (should (string-search "<h3>Three</h3>" html))))

(ert-deftest lectio-renders-both-kinds-of-list ()
  (let ((bullets (lectio-tests--html "- alpha\n- beta\n"))
        (numbers (lectio-tests--html "1. first\n2. second\n")))
    (should (string-search "<ul> <li>alpha</li> <li>beta</li> </ul>" bullets))
    (should (string-search "<ol> <li>first</li> <li>second</li> </ol>" numbers))))

(ert-deftest lectio-renders-inline-spans ()
  (let ((html (lectio-tests--html
               "a **bold** and *thin* and `code` and [text](https://e.org)")))
    (should (string-search "<strong>bold</strong>" html))
    (should (string-search "<em>thin</em>" html))
    (should (string-search "<code>code</code>" html))
    (should (string-search "<a href=\"https://e.org\">text</a>" html))))

(ert-deftest lectio-does-not-parse-spans-inside-inline-code ()
  "Backticks are what an agent writes a path or a flag in."
  (let ((html (lectio-tests--html "run `ls *.el` and `a_b_c`")))
    (should (string-search "<code>ls *.el</code>" html))
    (should (string-search "<code>a_b_c</code>" html))
    (should-not (string-search "<em>" html))))

(ert-deftest lectio-separates-paragraphs ()
  (let ((html (lectio-tests--html "one\ntwo\n\nthree")))
    (should (string-search "<p>one two</p>" html))
    (should (string-search "<p>three</p>" html))))

(ert-deftest lectio-renders-a-blockquote ()
  (should (string-search "<blockquote> <p>quoted</p> </blockquote>"
                         (lectio-tests--html "> quoted"))))

(ert-deftest lectio-returns-text-shr-drew ()
  "The renderer answers with a string, since a record is inserted into a
buffer the viewer already owns."
  (let ((drawn (lectio-render "# Heading\n\nsome **bold** prose")))
    (should (stringp drawn))
    (should (string-search "Heading" drawn))
    (should (string-search "bold" drawn))
    (should-not (string-search "**" drawn))))

(ert-deftest lectio-of-nothing-is-nothing ()
  (should (equal (lectio-render "") ""))
  (should (equal (lectio-render nil) nil)))

(ert-deftest lectio-batch-answers-one-rendering-per-input ()
  "Records are rendered as a batch so a caller can zip the answer back
against the records it asked about."
  (let ((out (lectio-render-all
              (list "**bold**" "# Heading" "plain prose"))))
    (should (equal (length out) 3))
    (should (string-search "bold" (nth 0 out)))
    (should-not (string-search "**" (nth 0 out)))
    (should (string-search "Heading" (nth 1 out)))
    (should (string-search "plain prose" (nth 2 out)))))

(ert-deftest lectio-batch-keeps-empty-inputs-in-place ()
  "Records without text still hold their position in the answer."
  (let ((out (lectio-render-all (list "**a**" "" "**b**"))))
    (should (equal (length out) 3))
    (should (equal (nth 1 out) ""))
    (should (string-search "a" (nth 0 out)))
    (should (string-search "b" (nth 2 out)))))

(ert-deftest lectio-batch-of-nothing-is-nothing ()
  (should (equal (lectio-render-all nil) nil)))

(ert-deftest lectio-fontifies-a-fence-in-the-language-it-names ()
  "A fence is code and reads as code only in colour, so the caller is
handed its language and its body rather than the flattening shr makes
of a `pre'.  Prose has to come before it: rendering that prose runs a
regexp of its own, which is what loses the fence's groups."
  (let ((seen nil))
    (lectio-render
     "Here is how:\n\n```sh\nls -la\n```\n"
     (lambda (language code) (push (cons language code) seen) "DRAWN"))
    (should (equal seen '(("sh" . "ls -la\n"))))))

(ert-deftest lectio-draws-the-html-the-installed-backend-answers ()
  "Prose reaches shr through `lectio-html-function', not the built-in parser."
  (let ((lectio-html-function (lambda (_markdown) "<p>stub</p>")))
    (should (equal (lectio-render "**not this**") "stub"))))

(ert-deftest lectio-marks-a-code-span-as-code ()
  "shr draws `code' as running text, which loses the one thing the span
was written to say."
  (let ((drawn (lectio-render "use `git rebase` first")))
    (should (string-search "git rebase" drawn))
    (should (memq 'lectio-code
                  (ensure-list
                   (get-text-property (string-search "git" drawn)
                                      'face drawn))))))

(provide 'lectio-tests)
;;; lectio-tests.el ends here
