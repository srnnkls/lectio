;; -*- mode: eask; lexical-binding: t -*-

(package "lectio"
         "0.1.0"
         "Read markdown as the text shr draws from it")

(website-url "https://github.com/srnnkls/lectio.el")
(license "GPL-3.0-or-later")

(keywords "text" "hypermedia")

(package-file "lectio.el")

(source 'gnu)
(source 'nongnu)
(source 'melpa)

(depends-on "emacs" "29.1")

(load-paths ".")

(files "lectio*.el"
       "LICENSE"
       '(:exclude "lectio-tests.el"))

(defconst lectio-test-file-spec
  '("lectio-tests.el")
  "File spec for ERT suites excluded from the package files.")

(script "test"
        (let* ((default-directory (file-name-directory load-file-name))
               (files (eask-expand-file-specs lectio-test-file-spec)))
          (unless files
            (error "No test file matches %S under %s"
                   lectio-test-file-spec default-directory))
          (mapconcat #'identity
                     (cons "eask test ert"
                           (mapcar #'shell-quote-argument files))
                     " ")))

(add-hook 'eask-before-compile-hook
          (lambda ()
            (setq byte-compile-error-on-warn t)))
