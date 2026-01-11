;;; consult-vulpea.el --- Use Consult in tandem with Vulpea -*- lexical-binding: t -*-

;; Copyright (C) 2026 Fabrizio Contigiani

;; Author: Fabrizio Contigiani <fabcontigiani@gmail.com>
;; Maintainer: Fabrizio Contigiani <fabcontigiani@gmail.com>
;; URL: https://github.com/fabcontigiani/consult-vulpea
;; Version: 0.2.1
;; Package-Requires: ((emacs "28.1") (vulpea "2.0.0") (consult "2.2"))
;; Keywords: convenience, notes, vulpea

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package integrates `vulpea' with `consult' to provide
;; enhanced minibuffer interactions, most notably live file previews
;; when selecting notes with `vulpea-find' and `vulpea-insert'.
;;
;; To enable, simply turn on `consult-vulpea-mode':
;;
;;   (consult-vulpea-mode 1)
;;
;; Features:
;;
;; 1. **Live previews**: When selecting notes via `vulpea-find' or
;;    `vulpea-insert', you get a live preview of the note file as you
;;    navigate through candidates.
;;
;; 2. **Consult-powered grep/find**: Use `consult-vulpea-grep' and
;;    `consult-vulpea-find' to search within your vulpea directories
;;    with live previews.
;;
;; 3. **Consult-buffer integration**: Quickly switch to open vulpea
;;    note buffers using `consult-buffer' with narrowing support.

;;; Code:

(require 'consult)
(require 'vulpea)
(require 'vulpea-note)
(require 'vulpea-db)
(require 'vulpea-select)

(defgroup consult-vulpea ()
  "Use Consult with Vulpea for enhanced note selection."
  :group 'vulpea
  :group 'consult
  :group 'minibuffer
  :link '(url-link :tag "GitHub" "https://github.com/fabcontigiani/consult-vulpea"))

;;;; User options

(defcustom consult-vulpea-grep-command #'consult-ripgrep
  "Consult-powered grep command to use for `consult-vulpea-grep'.
Common choices are `consult-grep' and `consult-ripgrep'."
  :type 'function
  :group 'consult-vulpea)

(defcustom consult-vulpea-find-command #'consult-find
  "Consult-powered find command to use for `consult-vulpea-find'."
  :type 'function
  :group 'consult-vulpea)

(defcustom consult-vulpea-preview-key consult-preview-key
  "Preview key for vulpea note selection.
Defaults to `consult-preview-key'."
  :type '(choice (const :tag "Any key" any)
                 (const :tag "No preview" nil)
                 key-sequence)
  :group 'consult-vulpea)

(defcustom consult-vulpea-buffer-narrow-key ?v
  "Narrow key for `consult-buffer' integration.
When pressing this key in `consult-buffer', the candidates are
narrowed to only show open vulpea note buffers."
  :type 'character
  :group 'consult-vulpea)

;;;; Helper functions

(defun consult-vulpea--note-preview ()
  "Create a preview function for vulpea notes.
Expects CAND to be a `vulpea-note' object (via :lookup)."
  (let ((open (consult--temporary-files))
        (preview (consult--buffer-preview)))
    (lambda (action cand)
      (when (eq action 'exit)
        (funcall open))
      (when (and (eq action 'preview) (vulpea-note-p cand))
        (funcall preview action
                 (funcall open (vulpea-note-path cand)))))))

(defun consult-vulpea-buffer-p (buffer)
  "Check if BUFFER is a vulpea note buffer.
Returns non-nil if the buffer's file is indexed in the vulpea database."
  (when-let ((file (buffer-file-name buffer)))
    (vulpea-db-get-id-by-file file)))

(defun consult-vulpea-buffer--list ()
  "Return list of currently open vulpea buffers as buffer names."
  (consult--buffer-query
   :sort 'visibility
   :as #'buffer-name
   :predicate #'consult-vulpea-buffer-p))

(defvar consult-vulpea-buffer-source
  `(:name     "Vulpea"
    :narrow   ,consult-vulpea-buffer-narrow-key
    :category buffer
    :face     consult-buffer
    :state    ,#'consult--buffer-state
    :items    ,#'consult-vulpea-buffer--list)
  "Vulpea buffer source for `consult-buffer'.")

;;;; Core selection function

(cl-defun consult-vulpea-select-from (prompt
                                       notes
                                       &key
                                       require-match
                                       initial-prompt
                                       expand-aliases)
  "Select a note from NOTES using consult with preview.

Returns a selected `vulpea-note'. If `vulpea-note-id' is nil, it
means that user selected a non-existing note.

This is a drop-in replacement for `vulpea-select-from' that adds
consult-style live previews.

PROMPT is the message to present.
REQUIRE-MATCH when non-nil means user must select an existing note.
INITIAL-PROMPT is the initial input for the prompt.
EXPAND-ALIASES when non-nil expands note aliases for completion."
  (let* ((expanded-notes (if expand-aliases
                             (seq-mapcat #'vulpea-note-expand-aliases notes)
                           notes))
         ;; Build candidates as alist: (description . note)
         (candidates
          (mapcar
           (lambda (note)
             (cons (vulpea-select-describe note) note))
           expanded-notes))
         ;; Track user's raw input for new note creation
         (user-input nil)
         (note (consult--read
                candidates
                :prompt (concat prompt ": ")
                :require-match require-match
                :initial initial-prompt
                :history 'minibuffer-history
                :state (consult-vulpea--note-preview)
                :preview-key consult-vulpea-preview-key
                :category 'vulpea-note
                :sort t
                ;; :lookup returns the note object from alist, making it
                ;; available to :state for preview and as the return value.
                ;; Also captures raw input for new note creation.
                :lookup (lambda (selected candidates &rest _)
                          (setq user-input selected)
                          (cdr (assoc selected candidates))))))
    (or note
        (let ((title (or (and user-input
                              (not (string-empty-p (string-trim user-input)))
                              (substring-no-properties user-input))
                         (and initial-prompt
                              (not (string-empty-p (string-trim initial-prompt)))
                              (substring-no-properties initial-prompt)))))
          (make-vulpea-note
           :title (or title "")
           :level 0)))))

;;;; Commands

;;;###autoload
(defun consult-vulpea-grep ()
  "Search vulpea notes using grep with live preview.
Uses `consult-vulpea-grep-command'. Searches all directories
in `vulpea-db-sync-directories'."
  (interactive)
  (let ((dir (or (bound-and-true-p vulpea-db-sync-directories)
                 (list org-directory))))
    (funcall-interactively consult-vulpea-grep-command dir)))

;;;###autoload
(defun consult-vulpea-find ()
  "Find vulpea note files using find with live preview.
Uses `consult-vulpea-find-command'. Searches all directories
in `vulpea-db-sync-directories'."
  (interactive)
  (let ((dir (or (bound-and-true-p vulpea-db-sync-directories)
                 (list org-directory))))
    (funcall-interactively consult-vulpea-find-command dir)))

;;;; Minor mode

;;;###autoload
(define-minor-mode consult-vulpea-mode
  "Use Consult in tandem with Vulpea.

When enabled, this mode replaces `vulpea-select-from' with a
consult-powered version that provides live previews when
selecting notes."
  :global t
  :lighter " cv"
  :group 'consult-vulpea
  (if consult-vulpea-mode
      (progn
        ;; Override vulpea-select-from with our consult version
        (advice-add #'vulpea-select-from
                    :override #'consult-vulpea-select-from)
        ;; Add vulpea buffer source to consult-buffer
        (add-to-list 'consult-buffer-sources 'consult-vulpea-buffer-source 'append))
    ;; Remove our advice
    (advice-remove #'vulpea-select-from #'consult-vulpea-select-from)
    ;; Remove buffer source
    (setq consult-buffer-sources
          (delete 'consult-vulpea-buffer-source consult-buffer-sources))))

(provide 'consult-vulpea)
;;; consult-vulpea.el ends here
