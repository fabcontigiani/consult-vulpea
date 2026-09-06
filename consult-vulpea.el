;;; consult-vulpea.el --- Use Consult in tandem with Vulpea -*- lexical-binding: t -*-

;; Copyright (C) 2026 Fabrizio Contigiani

;; Author: Fabrizio Contigiani <fabcontigiani@gmail.com>
;; Maintainer: Fabrizio Contigiani <fabcontigiani@gmail.com>
;; URL: https://github.com/fabcontigiani/consult-vulpea
;; Version: 0.3.1
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


(defface consult-vulpea-preview-face
  '((t :inherit match))
  "Face used for consult vulpea previews.")


(defvar consult-vulpea--overlays nil "List of overlays added during preview.

This is added when previewing note backlinks, and cleared when preview finishes.")


(defvar consult-vulpea--current-note-id nil "ID of the current note when previewing backlinks.")


(defvar consult-vulpea--current-backlink-index nil "Index of the current centered backlink.")

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

(defcustom consult-vulpea-expand-aliases-default nil
  "Default value for expanding note aliases in completion.
When non-nil, notes with aliases will appear multiple times in the
selection list - once for the title and once for each alias.
This can be overridden per-call with the :expand-aliases parameter."
  :type 'boolean
  :group 'consult-vulpea)

(defcustom consult-vulpea-narrow-heading-note nil
  "Narrow heading note while previewing.

This is useful when previewing heading notes, as it will narrow the
buffer to the heading note and its children, making it easier to read."
  :type 'boolean
  :group 'consult-vulpea)

;;;; Helper functions

(defun consult-vulpea--get-link-at-point-bounds (&optional point)
  "Get the bounds of the link at POINT (or current point if nil).

Returns a cons cell (BEGIN . END) of the link's bounds, or nil if
no link is found."
  (when (derived-mode-p 'org-mode)
    (save-excursion
      (when point
        (goto-char point))
      (let* ((element (org-element-context))
             (type (org-element-type element)))
        (when (eq type 'link)
          (cons
           (org-element-property :begin element)
           (org-element-property :end element)))))))

(defun consult-vulpea--highlight-link (link)
  "Create an overlay for the given LINK in the current buffer.

The created overlay is added to `consult-vulpea--overlays' for later
cleaning."
  (when link
    (when-let* ((link-pos (plist-get link :pos))
                (link-bounds
                 (consult-vulpea--get-link-at-point-bounds link-pos))
                (overlay (make-overlay (car link-bounds) (cdr link-bounds))))
      (overlay-put overlay 'face 'consult-vulpea-preview-face)
      overlay)))


(defun consult-vulpea--create-backlinks-overlays (backlink-links)
  "Create an overlay in every backlink in BACKLINK-LINKS.

BACKLINK-LINKS is a list of links, similar to what is returned by
`vulpea-note-links'."

  ;; Create the overlays in each backlink and save the overlays in
  ;; `consult-vulpea--overlays'
  (setq consult-vulpea--overlays
        (mapcar #'consult-vulpea--highlight-link backlink-links)))


(defun consult-vulpea--clear-backlinks-overlays ()
  "Delete all backlink overlays."
  (mapc #'delete-overlay consult-vulpea--overlays)
  (setq consult-vulpea--overlays nil)
  (setq consult-vulpea--current-backlink-index nil))


(defun consult-vulpea-go-to-next-backlink-overlay (&optional invert)
  "Move point to the next backlink.

If INVERT is t, move to the previous backlink."
  (interactive)
  (when-let* ((all-overlays consult-vulpea--overlays)
              (num-overlays (length all-overlays))
              (index
               (if consult-vulpea--current-backlink-index
                   (if invert
                       (mod
                        (1- consult-vulpea--current-backlink-index)
                        num-overlays)
                     (mod
                      (1+ consult-vulpea--current-backlink-index) num-overlays))
                 0))
              (ov (nth index all-overlays))
              (buffer (overlay-buffer ov))
              (pos (overlay-start ov)))

    (setq consult-vulpea--current-backlink-index index)

    (with-current-buffer buffer
      (when-let* ((window (get-buffer-window buffer)))
        (with-selected-window window
          (consult--minibuffer-message
           (format "Centered in backlink %s of %s" (1+ index) num-overlays))
          (goto-char pos)
          (recenter)
          (org-show-entry))))))


(defun consult-vulpea-go-to-previous-backlink-overlay ()
  "Move point to the previous backlink."
  (interactive)
  (consult-vulpea-go-to-next-backlink-overlay t))


(defun consult-vulpea--before-find-backlink ()
  "Advice that will be added before `vulpea-find-backlink'.

This advice only role is to store the ID of the current note in
`consult-vulpea--current-note-id' before calling the original
`vulpea-find-backlink' function."
  (when (derived-mode-p 'org-mode)
    (when-let* ((id (org-entry-get nil "ID" t)))
      (setq consult-vulpea--current-note-id id))))

(defun consult-vulpea--note-preview ()
  "Create a preview function for vulpea notes.
Expects CAND to be a `vulpea-note' object (via :lookup)."
  (let ((open (consult--temporary-files))
        (preview (consult--buffer-preview)))
    (lambda (action cand)
      (when (eq action 'exit)
        (funcall open)
        (consult-vulpea--clear-backlinks-overlays)
        (setq consult-vulpea--current-note-id nil))
      (when (and (eq action 'preview) (vulpea-note-p cand))
        (setq consult-vulpea--current-backlink-index nil)
        (let* ((buffer (funcall open (vulpea-note-path cand))))
          (funcall preview action buffer)

          ;; If the level of the note is > 0, it means the note is a heading
          ;; note. Make sure we center around the heading note during preview
          ;; and expand any folded sections to make sure the heading is visible.
          (when (> (vulpea-note-level cand) 0)
            (with-current-buffer buffer
              (goto-char (vulpea-note-pos cand))
              (org-show-entry)
              (recenter)
              (when consult-vulpea-narrow-heading-note
                (org-narrow-to-subtree))))

          ;; If consult-vulpea--current-note-id is non nil, it means we are
          ;; previewing backlinks. Let's add overlays to mark the backlinks
          (when consult-vulpea--current-note-id
            (let* ((links (vulpea-note-links cand))
                   (backlink-links
                    (seq-filter
                     (lambda (link)
                       (and (equal (plist-get link :type) "id")
                            (equal
                             (plist-get link :dest)
                             consult-vulpea--current-note-id)))
                     links)))
              ;; Highlight backlinks in the preview buffer
              (with-current-buffer buffer
                (consult-vulpea--create-backlinks-overlays backlink-links)

                ;; Center around the first backlink and expand any folded
                ;; sections to make sure the backlink is visible
                (consult-vulpea-go-to-next-backlink-overlay)))))))))

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
EXPAND-ALIASES when non-nil expands note aliases for completion.
If not specified, defaults to `consult-vulpea-expand-aliases-default'."
  (let* ((should-expand (if expand-aliases
                            expand-aliases
                          consult-vulpea-expand-aliases-default))
         (expanded-notes (if should-expand
                             (seq-mapcat #'vulpea-note-expand-aliases notes)
                           notes))
         (context (when vulpea-select-dyncontext-fn
                    (funcall vulpea-select-dyncontext-fn expanded-notes)))
         (completions (seq-map
                       (lambda (n)
                         (cons (vulpea-select-describe n context)
                               n))
                       expanded-notes))
         (candidates-table (vulpea-select--completion-table completions))
         (metadata (funcall candidates-table nil nil 'metadata))
         (category (alist-get 'category metadata))
         (annotation-function (alist-get 'annotation-function metadata))

         ;; Track user's raw input for new note creation.
         (user-input (or initial-prompt ""))
         ;; `vulpea-select-from' guarantees that point, buffer and
         ;; narrowing survive the prompt: previewing a candidate that
         ;; lives in the file being edited moves point in that live
         ;; buffer, and whatever the caller does at point next would
         ;; land in the previewed heading (d12frosted/vulpea#491).
         (note (save-excursion
                 (save-restriction
                   (consult--read
                    completions
                    :prompt (concat prompt ": ")
                    :require-match require-match
                    :initial initial-prompt
                    :history 'minibuffer-history
                    :state (consult-vulpea--note-preview)
                    :preview-key consult-vulpea-preview-key
                    :sort t
                    :category category
                    :annotate annotation-function
                    ;; :lookup returns the note object from alist, making it
                    ;; available to :state for preview and as the return value.
                    ;; Also captures raw input for new note creation.
                    :lookup (lambda (selected completions &rest _)
                              (setq user-input selected)
                              (cdr (assoc selected completions))))))))
    (or note
        (make-vulpea-note
         :title (substring-no-properties user-input)
         :level 0))))

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
        (advice-add #'vulpea-find-backlink :before #'consult-vulpea--before-find-backlink))
    ;; Remove our advice
    (advice-remove #'vulpea-select-from #'consult-vulpea-select-from)
    (advice-remove #'vulpea-find-backlink #'consult-vulpea--before-find-backlink)))


(provide 'consult-vulpea)
;;; consult-vulpea.el ends here
