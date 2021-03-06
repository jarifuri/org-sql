;;; org-sql-doc.el --- Build documentation for org-sql -*- lexical-binding: t; -*-

;; Copyright (C) 2020 Nathan Dwarshuis

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; These functions build parts of the document for org-sql. The readme template
;; is used as a base, and information that depends precisely on code is compiled
;; to documentation here

;;; Code:

(defvar org-sql-dev-path
  (directory-file-name (file-name-directory load-file-name))
  "Path to development directory.")

(defvar org-sql-dev-root-path
  (directory-file-name (file-name-directory org-sql-dev-path))
  "Path to root directory.")

(add-to-list 'load-path org-sql-dev-root-path)
(add-to-list 'load-path org-sql-dev-path)

(require 'package)
(require 'dash)
(require 's)
(require 'org-sql)

(defun org-sql-get-package-version ()
  "Get version of om package."
  (with-current-buffer (find-file-noselect "org-sql.el")
    (->> (package-buffer-info)
         (package-desc-version)
         (-map 'number-to-string)
         (s-join version-separator))))

;; (let ((public-syms (alist-get 'public org-ml-dev-defined-names))
;;       (example-syms (->> (-remove #'stringp org-ml-dev-examples-list)
;;                          (-map #'car))))
;;   (-some->> (-difference public-syms example-syms)
;;             (-map #'symbol-name)
;;             (--remove (s-ends-with? "*" it))
;;             (--remove (s-starts-with? "org-ml-update-this-" it))
;;             (--remove (s-starts-with? "org-ml-parse-this-" it))
;;             (--map (format "  %s" it))
;;             (s-join "\n")
;;             (format "The following functions don't have examples:\n%s")
;;             (print)))

(defun org-sql-doc-format-quotes (s)
  (s-replace-regexp "`\\([^[:space:]]+\\)'" "`\\1`" s))

(defun org-sql-doc-format-table-row (members)
  (format "| %s |" (s-join " | " members)))

(defun org-sql-doc-format-allowed-values (members)
  (when members
    (-let* ((members* (--map (format "`%s`" it) members))
            ((rest last) (-split-at (1- (length members*)) members*))
            (rest* (s-join ", " rest)))
      (format "%s, or %s" rest* (car last)))))

(defun org-sql-doc-format-foreign (column-name constraints-meta)
  (cl-flet
      ((find-format
        (foreign-meta)
        (-let (((&plist :ref :keys :parent-keys) foreign-meta))
          (-some--> (--find-index (eq it column-name) keys)
            (nth it parent-keys)
            (org-sql--format-mql-column-name it)
            (format "%s - %s" it ref)))))
    (->> (--filter (eq 'foreign (car it)) constraints-meta)
         (--map (find-format (cdr it)))
         (-non-nil)
         (s-join ", "))))

(defun org-sql-doc-format-type (mql-column)
  (let ((sqlite-type (org-sql--format-mql-schema-type '(sqlite) "" mql-column))
        (postgres-type
         (--> (org-sql--format-mql-schema-type '(postgres) "" mql-column)
              (if (s-starts-with? "enum" it) "ENUM" it))))
    (format "%s / %s" sqlite-type postgres-type)))

(defun org-sql-doc-format-column (column-meta constraints-meta)
  (-let* (((column-name . (&plist :desc :type :constraints :allowed)) column-meta)
          ((&alist 'primary) constraints-meta)
          (primary-keys (plist-get primary :keys))
          (column-name* (org-sql--format-mql-column-name column-name))
          (is-primary (if (memq column-name primary-keys) "x" ""))
          (null-allowed (if (or (memq 'notnull constraints)
                                (memq column-name primary-keys))
                            ""
                          "x"))
          (foreign (org-sql-doc-format-foreign column-name constraints-meta))
          (type* (org-sql-doc-format-type column-meta))
          (allowed* (org-sql-doc-format-allowed-values allowed))
          (desc* (org-sql-doc-format-quotes desc))
          (desc-full (if allowed* (format "%s (%s)" desc* allowed*) desc*)))
    (->> (list column-name* is-primary foreign null-allowed type* desc-full)
         (org-sql-doc-format-table-row))))

(defun org-sql-doc-format-schema (table-meta)
  (-let* (((table-name . meta) table-meta)
          ((&alist 'desc 'columns 'constraints) meta)
          (header (->> (symbol-name table-name)
                       (format "### %s")))
          (table-headers (list "Column"
                               "Is Primary"
                               "Foreign Keys (parent - table)"
                               "NULL Allowed"
                               "Type (SQLite / Postgres)"
                               "Description"))
          (table-line (->> (-repeat (length table-headers) " - ")
                           (org-sql-doc-format-table-row)))
          (table-headers* (org-sql-doc-format-table-row table-headers))
          (table-rows (->> columns
                           (--map (org-sql-doc-format-column it constraints))
                           (s-join "\n"))))
    (->> (list header
               ""
               desc
               ""
               table-headers*
               table-line
               table-rows)
         (s-join "\n"))))

(defun goto-and-replace-all (s replacement)
  (while (progn (goto-char (point-min)) (search-forward s nil t))
    (delete-char (- (length s)))
    (insert replacement)))

(defun goto-and-remove (s)
  (goto-char (point-min))
  (search-forward s)
  (delete-char (- (length s))))

(defun create-docs-file ()
  (with-temp-file "./README.md"
    (insert-file-contents-literally "./readme-template.md")

    (goto-and-remove "[[ schema-docs ]]")
    (insert (->> org-sql--mql-schema
                 (-map #'org-sql-doc-format-schema)
                 (s-join "\n\n")))

    (goto-and-replace-all "[[ version ]]" (org-sql-get-package-version))))

;;; org-sql-doc.el ends here
