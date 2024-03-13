;;; gleam-ts-mode.el --- Major mode for Gleam -*- lexical-binding: t -*-

;; Copyright © 2023 Louis Pilfold <louis@lpil.uk>
;; Authors: Jonathan Arnett <jonathan.arnett@protonmail.com>
;;
;; URL: https://github.com/gleam-lang/gleam-ts-mode
;; Keywords: languages gleam
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))

;; This file is NOT part of GNU Emacs.

;; This program is licensed under The Apache License¹, Version 2.0 or,
;; at your option, under the terms of the GNU General Public License²
;; as published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.

;; ¹ You may not use this file except in compliance with the License.
;; You may obtain a copy of the License at
;;
;; http://www.apache.org/licenses/LICENSE-2.0
;;
;; Unless required by applicable law or agreed to in writing, software
;; distributed under the License is distributed on an "AS IS" BASIS,
;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;; See the License for the specific language governing permissions and
;; limitations under the License.

;; ² This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this package. If not, see https://www.gnu.org/licenses.

;;; Commentary:

;; Provides syntax highlighting, indentation, and code navigation
;; features for the Gleam programming language.

;;; Code:

(require 'prog-mode)
(require 'treesit)


;;; Customization

(defgroup gleam-ts nil
  "Major mode for editing Gleam."
  :prefix "gleam-ts-"
  :group 'languages)

(defcustom gleam-ts-indent-offset 2
  "Offset used to indent Gleam code."
  :type 'integer
  :safe 'integerp
  :group 'gleam-ts)


;;; Tree-sitter font locking

(defface gleam-ts-constructor-face
  '((t (:inherit font-lock-type-face)))
  "Font used for highlighting Gleam type constructors.")

(defface gleam-ts-module-face
  '((t (:inherit font-lock-variable-name-face)))
  "Font used for highlighting Gleam modules.")

(defvar gleam-ts--font-lock-settings
  (treesit-font-lock-rules
   :feature 'comment
   :language 'gleam
   '((comment) @font-lock-comment-face)

   :feature 'string
   :language 'gleam
   '((string) @font-lock-string-face)

   :feature 'number
   :language 'gleam
   '((integer) @font-lock-number-face
     (float) @font-lock-number-face)

   :feature 'function-name
   :language 'gleam
   '((unqualified_import (identifier) @font-lock-function-name-face)
     (function
      name: (identifier) @font-lock-function-name-face)
     (external_function
      name: (identifier) @font-lock-function-name-face)
     (function_call
      function: (identifier) @font-lock-function-name-face))

   :feature 'variable-name
   :language 'gleam
   '((identifier) @font-lock-variable-name-face)

   :feature 'constructor
   :language 'gleam
   '((unqualified_import (type_identifier) @gleam-ts-constructor-face)
     (constructor_name) @gleam-ts-constructor-face)

   :feature 'type-name
   :language 'gleam
   '((unqualified_import "type" (type_identifier) @font-lock-type-face)
     (remote_type_identifier) @font-lock-type-face
     (type_identifier) @font-lock-type-face)

   :feature 'constant-name
   :language 'gleam
   :override t
   '((constant
      name: (identifier) @font-lock-constant-face))

   :feature 'keyword
   :language 'gleam
   '([
      (visibility_modifier)
      (opacity_modifier)
      "as"
      "assert"
      "case"
      "const"
      ;; Deprecated
      "external"
      "fn"
      "if"
      "import"
      "let"
      "panic"
      "todo"
      "type"
      "use"
      ] @font-lock-keyword-face)

   :feature 'operator
   :language 'gleam
   '((binary_expression operator: _ @font-lock-operator-face)
     (boolean_negation "!" @operator)
     (integer_negation "-" @operator))

   :feature 'property
   :language 'gleam
   '((label) @font-lock-property-name-face
     (tuple_access
      index: (integer) @font-lock-property-name-face))

   :feature 'annotation
   :language 'gleam
   :override t
   '((attribute
      "@" @font-lock-preprocessor-face
      name: (identifier) @font-lock-preprocessor-face))

   :feature 'documentation
   :language 'gleam
   '((module_comment) @font-lock-doc-face
     (statement_comment) @font-lock-doc-face)

   :feature 'module
   :language 'gleam
   :override t
   '((module) @gleam-ts-module-face
     (import alias: (identifier) @gleam-ts-module-face)
     (remote_type_identifier
      module: (identifier) @gleam-ts-module-face)
     (remote_constructor_name
      module: (identifier) @gleam-ts-module-face)
     ;; Unfortunately #is-not? local doesn't work here
     ;; ((field_access
     ;;   record: (identifier) @gleam-ts-module-face)
     ;;  (#is-not? local))
     )

   :feature 'builtin
   :language 'gleam
   :override t
   '((bit_string_segment_option) @font-lock-builtin-face)

   :feature 'bracket
   :language 'gleam
   '([
      "("
      ")"
      "["
      "]"
      "{"
      "}"
      "<<"
      ">>"
      ] @font-lock-bracket-face)

   :feature 'delimiter
   :language 'gleam
   '([
      "."
      ","
      ;; Controversial -- maybe some are operators?
      ":"
      "#"
      "="
      "->"
      ".."
      "-"
      "<-"
      ] @font-lock-delimiter-face)))


;;; Public functions

(defun gleam-ts-install-grammar ()
  "Install the Gleam tree-sitter grammar."
  (interactive)
  (if (and (treesit-available-p) (boundp 'treesit-language-source-alist))
      (let ((treesit-language-source-alist
             (cons
              '(gleam . ("https://github.com/gleam-lang/tree-sitter-gleam"))
              treesit-language-source-alist)))
        (treesit-install-language-grammar 'gleam))
    (display-warning 'treesit "Emacs' treesit package does not appear to be available")))

(defun gleam-ts-format ()
  "Format the current buffer using the `gleam format' command."
  (interactive)
  (if (executable-find "gleam")
      (save-restriction ; Save the user's narrowing, if any
        (widen)         ; Expand scope to the whole, unnarrowed buffer
        (let* ((buf (current-buffer))
               (min (point-min))
               (max (point-max))
               (tmpfile (make-nearby-temp-file "gleam-format")))
          (unwind-protect
              (with-temp-buffer
                (insert-buffer-substring-no-properties buf min max)
                (write-file tmpfile)
                (call-process "gleam" nil nil nil "format" (buffer-file-name))
                (revert-buffer :ignore-autosave :noconfirm)
                (let ((tmpbuf (current-buffer)))
                  (with-current-buffer buf
                    (replace-buffer-contents tmpbuf))))
            (if (file-exists-p tmpfile) (delete-file tmpfile)))
          (message "Formatted!")))
    (display-warning 'gleam-ts "`gleam' executable not found!")))


;;; Major mode definition

(define-derived-mode gleam-ts-mode prog-mode "Gleam"
  "Major mode for editing Gleam.

\\<gleam-ts-mode-map>"
  :group 'gleam-ts

  (cond
   ((treesit-ready-p 'gleam)
    (treesit-parser-create 'gleam)

    (setq-local treesit-font-lock-settings gleam-ts--font-lock-settings)
    (setq-local treesit-font-lock-feature-list
                '((comment string number function-name variable-name constructor type-name)
                  (constant-name keyword operator property)
                  (annotation documentation module builtin bracket delimiter)))
    (treesit-major-mode-setup))
   (t
    (message "Cannot load tree-sitter-gleam.  Try running `gleam-ts-install-grammar' and report a bug if the issue reoccurs."))))

(provide 'gleam-ts-mode)
;;; gleam-ts-mode.el ends here