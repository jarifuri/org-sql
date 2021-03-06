;;; org-sql-test-stateless.el --- Stateless tests for org-sql -*- lexical-binding: t; -*-

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

;; This spec tests the stateless functions in org-sql

;;; Code:

(require 'org-sql)
(require 's)
(require 'buttercup)

(defmacro list-to-lines (in)
  "Convert IN to string.
If IN is a string, return IN. If IN is a list starting with
list then join the cdr of IN with newlines."
  (cond
   ((stringp in) in)
   ((consp in) `(s-join "\n" ,in))
   (t (error "String or list of strings expected"))))

(defun org-ts-to-unixtime (timestamp-string)
  "Convert TIMESTAMP-STRING to unixtime."
  (let ((decoded (org-parse-time-string timestamp-string)))
    (->> (-snoc decoded (current-time-zone))
         (apply #'encode-time)
         (float-time)
         (round))))

(defconst testing-filepath "/tmp/dummy")

(defconst testing-md5 "123456")

(defconst testing-files-sml
  `(files :file_path ,testing-filepath
          :md5 ,testing-md5
          :size nil))

(defmacro expect-sql* (in tbl res-form)
  `(progn
     (insert (list-to-lines ,in))
     (let ((res ,res-form))
       (expect res :to-equal ,tbl))))

(defun buffer-get-sml ()
  (->> (org-ml-parse-this-buffer)
       (org-sql--to-fstate testing-filepath testing-md5 nil
                           org-log-note-headings '("TODO" "DONE"))
       (org-sql--fstate-to-mql-insert)))

(defmacro expect-sql (in tbl)
  (declare (indent 1))
  `(expect-sql* ,in ,tbl (buffer-get-sml)))

(defmacro expect-sql-tbls (names in tbl)
  (declare (indent 2))
  `(expect-sql* ,in ,tbl (->> (buffer-get-sml)
                              (--filter (member (car it) ',names)))))

(defmacro expect-sql-tbls-multi (names in &rest forms)
  (declare (indent 2))
  (unless (= 0 (mod (length forms) 3))
    (error "Missing form"))
  (let ((specs
         (->> (-partition 3 forms)
              (--map (-let (((title let-forms tbl) it))
                       `(it ,title
                          (let (,@let-forms)
                            (expect-sql-tbls ,names ,in ,tbl))))))))
    `(progn ,@specs)))

(defmacro expect-sql-logbook-item (in log-note-headings entry)
  (declare (indent 2))
  `(progn
     (insert (list-to-lines ,in))
     (cl-flet
         ((props-to-string
           (props e)
           (->> (cdr e)
                (-partition 2)
                (--map-when (memq (car it) props)
                            (list (car it)
                                  (-some-> (cadr it)
                                    (org-ml-to-trimmed-string))))
                (apply #'append)
                (cons (car e)))))
       (let* ((item (org-ml-parse-item-at 1))
              (fstate (org-sql--to-fstate testing-filepath testing-md5 nil
                                          ,log-note-headings '("TODO" "DONE") nil))
              (entry (->> (org-sql--item-to-entry fstate 1 item)
                          (props-to-string (list :ts
                                                 :ts-active
                                                 :short-ts
                                                 :short-ts-active
                                                 :old-ts
                                                 :new-ts)))))
         (should (equal entry ,entry))))))

(describe "logbook entry spec"
  ;; don't test clocks here since they are way simpler
  (before-all
    (org-mode))

  (before-each
    (erase-buffer))

  (it "default -  none"
    (expect-sql-logbook-item (list "- logbook item \\\\"
                                   "  fancy note")
        org-log-note-headings
      `(none :file-path ,testing-filepath
             :entry-offset 1
             :headline-offset 1
             :header-text "logbook item"
             :note-text "fancy note"
             :user nil
             :user-full nil
             :ts nil
             :ts-active nil
             :short-ts nil
             :short-ts-active nil
             :old-ts nil
             :new-ts nil
             :old-state nil
             :new-state nil)))

  (it "default -  state"
    (let* ((ts "[2112-01-03 Sun]")
           (h (format "State \"DONE\" from \"TODO\" %s" ts)))
      (expect-sql-logbook-item (list (format "- %s \\\\" h) "  fancy note")
          org-log-note-headings
        `(state :file-path ,testing-filepath
                :entry-offset 1
                :headline-offset 1
                :header-text ,h
                :note-text "fancy note"
                :user nil
                :user-full nil
                :ts ,ts
                :ts-active nil
                :short-ts nil
                :short-ts-active nil
                :old-ts nil
                :new-ts nil
                :old-state "TODO"
                :new-state "DONE"))))

  (it "default -  refile"
    (let* ((ts "[2112-01-03 Sun]")
           (h (format "Refiled on %s" ts)))
      (expect-sql-logbook-item (list (format "- %s \\\\" h) "  fancy note")
          org-log-note-headings
        `(refile :file-path ,testing-filepath
                 :entry-offset 1
                 :headline-offset 1
                 :header-text ,h
                 :note-text "fancy note"
                 :user nil
                 :user-full nil
                 :ts ,ts
                 :ts-active nil
                 :short-ts nil
                 :short-ts-active nil
                 :old-ts nil
                 :new-ts nil
                 :old-state nil
                 :new-state nil))))

  (it "default -  note"
    (let* ((ts "[2112-01-03 Sun]")
           (h (format "Note taken on %s" ts)))
      (expect-sql-logbook-item (list (format "- %s \\\\" h) "  fancy note")
          org-log-note-headings
        `(note :file-path ,testing-filepath
               :entry-offset 1
               :headline-offset 1
               :header-text ,h
               :note-text "fancy note"
               :user nil
               :user-full nil
               :ts ,ts
               :ts-active nil
               :short-ts nil
               :short-ts-active nil
               :old-ts nil
               :new-ts nil
               :old-state nil
               :new-state nil))))

  (it "default -  done"
    (let* ((ts "[2112-01-03 Sun]")
           (h (format "CLOSING NOTE %s" ts)))
      (expect-sql-logbook-item (list (format "- %s \\\\" h) "  fancy note")
          org-log-note-headings
        `(done :file-path ,testing-filepath
               :entry-offset 1
               :headline-offset 1
               :header-text ,h
               :note-text "fancy note"
               :user nil
               :user-full nil
               :ts ,ts
               :ts-active nil
               :short-ts nil
               :short-ts-active nil
               :old-ts nil
               :new-ts nil
               :old-state nil
               :new-state nil))))

  (it "default -  reschedule"
    (let* ((ts "[2112-01-03 Sun]")
           (ts0 "[2112-01-04 Mon]")
           (h (format "Rescheduled from \"%s\" on %s" ts0 ts)))
      (expect-sql-logbook-item (list (format "- %s \\\\" h) "  fancy note")
          org-log-note-headings
        `(reschedule :file-path ,testing-filepath
                     :entry-offset 1
                     :headline-offset 1
                     :header-text ,h
                     :note-text "fancy note"
                     :user nil
                     :user-full nil
                     :ts ,ts
                     :ts-active nil
                     :short-ts nil
                     :short-ts-active nil
                     :old-ts ,ts0
                     :new-ts nil
                     :old-state nil
                     :new-state nil))))

  (it "default -  delschedule"
    (let* ((ts "[2112-01-03 Sun]")
           (ts0 "[2112-01-04 Mon]")
           (h (format "Not scheduled, was \"%s\" on %s" ts0 ts)))
      (expect-sql-logbook-item (list (format "- %s \\\\" h) "  fancy note")
          org-log-note-headings
        `(delschedule :file-path ,testing-filepath
                      :entry-offset 1
                      :headline-offset 1
                      :header-text ,h
                      :note-text "fancy note"
                      :user nil
                      :user-full nil
                      :ts ,ts
                      :ts-active nil
                      :short-ts nil
                      :short-ts-active nil
                      :old-ts ,ts0
                      :new-ts nil
                      :old-state nil
                      :new-state nil))))

  (it "default - redeadline"
    (let* ((ts "[2112-01-03 Sun]")
           (ts0 "[2112-01-04 Mon]")
           (h (format "New deadline from \"%s\" on %s" ts0 ts)))
      (expect-sql-logbook-item (list (format "- %s \\\\" h) "  fancy note")
          org-log-note-headings
        `(redeadline :file-path ,testing-filepath
                     :entry-offset 1
                     :headline-offset 1
                     :header-text ,h
                     :note-text "fancy note"
                     :user nil
                     :user-full nil
                     :ts ,ts
                     :ts-active nil
                     :short-ts nil
                     :short-ts-active nil
                     :old-ts ,ts0
                     :new-ts nil
                     :old-state nil
                     :new-state nil))))

  (it "default - deldeadline"
    (let* ((ts "[2112-01-03 Sun]")
           (ts0 "[2112-01-04 Mon]")
           (h (format "Removed deadline, was \"%s\" on %s" ts0 ts)))
      (expect-sql-logbook-item (list (format "- %s \\\\" h) "  fancy note")
          org-log-note-headings
        `(deldeadline :file-path ,testing-filepath
                      :entry-offset 1
                      :headline-offset 1
                      :header-text ,h
                      :note-text "fancy note"
                      :user nil
                      :user-full nil
                      :ts ,ts
                      :ts-active nil
                      :short-ts nil
                      :short-ts-active nil
                      :old-ts ,ts0
                      :new-ts nil
                      :old-state nil
                      :new-state nil))))

  (it "custom - user"
    (let* ((user "eddie666")
           (h (format "User %s is the best user" user)))
      (expect-sql-logbook-item (list (format "- %s \\\\" h) "  fancy note")
          '((user . "User %u is the best user"))
        `(user :file-path ,testing-filepath
               :entry-offset 1
               :headline-offset 1
               :header-text ,h
               :note-text "fancy note"
               :user ,user
               :user-full nil
               :ts nil
               :ts-active nil
               :short-ts nil
               :short-ts-active nil
               :old-ts nil
               :new-ts nil
               :old-state nil
               :new-state nil))))

  (it "custom - user full"
    ;; TODO this variable can have spaces and such, which will currently not
    ;; be matched
    (let* ((userfull "FullName")
           (h (format "User %s is the best user" userfull)))
      (expect-sql-logbook-item (list (format "- %s \\\\" h) "  fancy note")
          '((userfull . "User %u is the best user"))
        `(userfull :file-path ,testing-filepath
                   :entry-offset 1
                   :headline-offset 1
                   :header-text ,h
                   :note-text "fancy note"
                   :user ,userfull
                   :user-full nil
                   :ts nil
                   :ts-active nil
                   :short-ts nil
                   :short-ts-active nil
                   :old-ts nil
                   :new-ts nil
                   :old-state nil
                   :new-state nil))))

  (it "custom - active timestamp"
    (let* ((ts "<2112-01-01 Fri 00:00>")
           (h (format "I'm active now: %s" ts)))
      (expect-sql-logbook-item (list (format "- %s \\\\" h) "  fancy note")
          '((activets . "I'm active now: %T"))
        `(activets :file-path ,testing-filepath
                   :entry-offset 1
                   :headline-offset 1
                   :header-text ,h
                   :note-text "fancy note"
                   :user nil
                   :user-full nil
                   :ts nil
                   :ts-active ,ts
                   :short-ts nil
                   :short-ts-active nil
                   :old-ts nil
                   :new-ts nil
                   :old-state nil
                   :new-state nil))))

  (it "custom - short timestamp"
    (let* ((ts "[2112-01-01 Fri]")
           (h (format "Life feels short now: %s" ts)))
      (expect-sql-logbook-item (list (format "- %s \\\\" h) "  fancy note")
          '((shortts . "Life feels short now: %d"))
        `(shortts :file-path ,testing-filepath
                  :entry-offset 1
                  :headline-offset 1
                  :header-text ,h
                  :note-text "fancy note"
                  :user nil
                  :user-full nil
                  :ts nil
                  :ts-active nil
                  :short-ts ,ts
                  :short-ts-active nil
                  :old-ts nil
                  :new-ts nil
                  :old-state nil
                  :new-state nil))))

  (it "custom - short active timestamp"
    (let* ((ts "<2112-01-01 Fri>")
           (h (format "Life feels short now: %s" ts)))
      (expect-sql-logbook-item (list (format "- %s \\\\" h) "  fancy note")
          '((shortts . "Life feels short now: %D"))
        `(shortts :file-path ,testing-filepath
                  :entry-offset 1
                  :headline-offset 1
                  :header-text ,h
                  :note-text "fancy note"
                  :user nil
                  :user-full nil
                  :ts nil
                  :ts-active nil
                  :short-ts nil
                  :short-ts-active ,ts
                  :old-ts nil
                  :new-ts nil
                  :old-state nil
                  :new-state nil))))

  (it "custom - old/new timestamps"
    (let* ((ts0 "[2112-01-01 Fri]")
           (ts1 "[2112-01-02 Sat]")
           (h (format "Fake clock: \"%s\"--\"%s\"" ts0 ts1)))
      (expect-sql-logbook-item (list (format "- %s \\\\" h) "  fancy note")
          '((fakeclock . "Fake clock: %S--%s"))
        `(fakeclock :file-path ,testing-filepath
                    :entry-offset 1
                    :headline-offset 1
                    :header-text ,h
                    :note-text "fancy note"
                    :user nil
                    :user-full nil
                    :ts nil
                    :ts-active nil
                    :short-ts nil
                    :short-ts-active nil
                    :old-ts ,ts0
                    :new-ts ,ts1
                    :old-state nil
                    :new-state nil)))))

(describe "meta-query language insert spec"
  (before-all
    (org-mode))

  (before-each
    (erase-buffer))

  ;; headlines table

  (it "single headline"
    (expect-sql "* headline"
      `(,testing-files-sml
        (headlines :file_path ,testing-filepath
                   :headline_offset 1
                   :headline_text "headline"
                   :keyword nil
                   :effort nil
                   :priority nil
                   :is_archived 0
                   :is_commented 0
                   :content nil)
        (headline_closures :file_path ,testing-filepath
                           :headline_offset 1
                           :parent_offset 1
                           :depth 0))))

  (it "two headlines"
    (expect-sql (list "* headline"
                      "* another headline")
      `(,testing-files-sml
        (headlines :file_path ,testing-filepath
                   :headline_offset 1
                   :headline_text "headline"
                   :keyword nil
                   :effort nil
                   :priority nil
                   :is_archived 0
                   :is_commented 0
                   :content nil)
        (headline_closures :file_path ,testing-filepath
                           :headline_offset 1
                           :parent_offset 1
                           :depth 0)
        (headlines :file_path ,testing-filepath
                   :headline_offset 12
                   :headline_text "another headline"
                   :keyword nil
                   :effort nil
                   :priority nil
                   :is_archived 0
                   :is_commented 0
                   :content nil)
        (headline_closures :file_path ,testing-filepath
                           :headline_offset 12
                           :parent_offset 12
                           :depth 0))))

  (it "fancy headline"
    (expect-sql (list "* TODO [#A] COMMENT another headline"
                      ":PROPERTIES:"
                      ":Effort: 0:30"
                      ":END:"
                      "this /should/ appear")
      `(,testing-files-sml
        (headlines :file_path ,testing-filepath
                   :headline_offset 1
                   :headline_text "another headline"
                   :keyword "TODO"
                   :effort 30
                   :priority "A"
                   :is_archived 0
                   :is_commented 1
                   :content "this /should/ appear\n")
        (headline_closures :file_path ,testing-filepath
                           :headline_offset 1
                           :parent_offset 1
                           :depth 0))))

  (it "nested headline"
    (expect-sql (list "* headline"
                      "** nested headline")
      `(,testing-files-sml
        (headlines :file_path ,testing-filepath
                   :headline_offset 1
                   :headline_text "headline"
                   :keyword nil
                   :effort nil
                   :priority nil
                   :is_archived 0
                   :is_commented 0
                   :content nil)
        (headline_closures :file_path ,testing-filepath
                           :headline_offset 1
                           :parent_offset 1
                           :depth 0)
        (headlines :file_path ,testing-filepath
                   :headline_offset 12
                   :headline_text "nested headline"
                   :keyword nil
                   :effort nil
                   :priority nil
                   :is_archived 0
                   :is_commented 0
                   :content nil)
        (headline_closures :file_path ,testing-filepath
                           :headline_offset 12
                           :parent_offset 1
                           :depth 1)
        (headline_closures :file_path ,testing-filepath
                           :headline_offset 12
                           :parent_offset 12
                           :depth 0))))


  (it "archived headline"
    (expect-sql "* headline :ARCHIVE:"
      `(,testing-files-sml
        (headlines :file_path ,testing-filepath
                   :headline_offset 1
                   :headline_text "headline"
                   :keyword nil
                   :effort nil
                   :priority nil
                   :is_archived 1
                   :is_commented 0
                   :content nil)
        (headline_closures :file_path ,testing-filepath
                           :headline_offset 1
                           :parent_offset 1
                           :depth 0))))

  ;; planning entries

  (let ((ts0 "<2112-01-01 Thu>")
        (ts1 "<2112-01-02 Fri>")
        (ts2 "[2112-01-03 Sat]"))
    (expect-sql-tbls-multi (planning_entries timestamps)
        (list "* headline"
              (format "SCHEDULED: %s DEADLINE: %s CLOSED: %s" ts0 ts1 ts2))
      "multiple planning entries (included)"
      nil
      `((timestamps :file_path ,testing-filepath
                    :headline_offset 1
                    :timestamp_offset 75
                    :is_active 0
                    :warning_type nil
                    :warning_value nil
                    :warning_unit nil
                    :repeat_type nil
                    :repeat_value nil
                    :repeat_unit nil
                    :time_start ,(org-ts-to-unixtime ts2)
                    :start_is_long 0
                    :time_end nil
                    :end_is_long nil
                    :raw_value ,ts2)
        (planning_entries :file_path ,testing-filepath
                          :headline_offset 1
                          :planning_type closed
                          :timestamp_offset 75)
        (timestamps :file_path ,testing-filepath
                    :headline_offset 1
                    :timestamp_offset 50
                    :is_active 1
                    :warning_type nil
                    :warning_value nil
                    :warning_unit nil
                    :repeat_type nil
                    :repeat_value nil
                    :repeat_unit nil
                    :time_start ,(org-ts-to-unixtime ts1)
                    :start_is_long 0
                    :time_end nil
                    :end_is_long nil
                    :raw_value ,ts1)
        (planning_entries :file_path ,testing-filepath
                          :headline_offset 1
                          :planning_type deadline
                          :timestamp_offset 50)
        (timestamps :file_path ,testing-filepath
                    :headline_offset 1
                    :timestamp_offset 23
                    :is_active 1
                    :warning_type nil
                    :warning_value nil
                    :warning_unit nil
                    :repeat_type nil
                    :repeat_value nil
                    :repeat_unit nil
                    :time_start ,(org-ts-to-unixtime ts0)
                    :start_is_long 0
                    :time_end nil
                    :end_is_long nil
                    :raw_value ,ts0)
        (planning_entries :file_path ,testing-filepath
                          :headline_offset 1
                          :planning_type scheduled
                          :timestamp_offset 23))

      "multiple planning entries (exclude some)"
      ((org-sql-excluded-headline-planning-types '(:closed)))
      `((timestamps :file_path ,testing-filepath
                    :headline_offset 1
                    :timestamp_offset 50
                    :is_active 1
                    :warning_type nil
                    :warning_value nil
                    :warning_unit nil
                    :repeat_type nil
                    :repeat_value nil
                    :repeat_unit nil
                    :time_start ,(org-ts-to-unixtime ts1)
                    :start_is_long 0
                    :time_end nil
                    :end_is_long nil
                    :raw_value ,ts1)
        (planning_entries :file_path ,testing-filepath
                          :headline_offset 1
                          :planning_type deadline
                          :timestamp_offset 50)
        (timestamps :file_path ,testing-filepath
                    :headline_offset 1
                    :timestamp_offset 23
                    :is_active 1
                    :warning_type nil
                    :warning_value nil
                    :warning_unit nil
                    :repeat_type nil
                    :repeat_value nil
                    :repeat_unit nil
                    :time_start ,(org-ts-to-unixtime ts0)
                    :start_is_long 0
                    :time_end nil
                    :end_is_long nil
                    :raw_value ,ts0)
        (planning_entries :file_path ,testing-filepath
                          :headline_offset 1
                          :planning_type scheduled
                          :timestamp_offset 23))

      "multiple planning entries (exclude all)"
      ((org-sql-excluded-headline-planning-types '(:closed :scheduled :deadline)))
      nil))

  ;; headline tags

  (expect-sql-tbls-multi (headline_tags) (list "* headline :onetag:"
                                               "* headline :twotag:")
    "multiple tags (included)"
    nil
    `((headline_tags :file_path ,testing-filepath
                     :headline_offset 1
                     :tag "onetag"
                     :is_inherited 0)
      (headline_tags :file_path ,testing-filepath
                     :headline_offset 21
                     :tag "twotag"
                     :is_inherited 0))

    "multiple tags (exclude one)"
    ((org-sql-excluded-tags '("onetag")))
    `((headline_tags :file_path ,testing-filepath
                     :headline_offset 21
                     :tag "twotag"
                     :is_inherited 0))

    "multiple tags (exclude all)"
    ((org-sql-excluded-tags 'all))
    nil)

  (it "single tag (child headline)"
    (setq org-sql-use-tag-inheritance t)
    (expect-sql-tbls (headline_tags) (list "* parent :onetag:"
                                           "** nested")
      `((headline_tags :file_path ,testing-filepath
                       :headline_offset 1
                       :tag "onetag"
                       :is_inherited 0))))

  (expect-sql-tbls-multi (headline_tags) (list "* parent"
                                               ":PROPERTIES:"
                                               ":ARCHIVE_ITAGS: sometag"
                                               ":END:")
    "inherited tag (included)"
    nil
    `((headline_tags :file_path ,testing-filepath
                     :headline_offset 1
                     :tag "sometag"
                     :is_inherited 1))

    "inherited tag (excluded)"
    ((org-sql-exclude-inherited-tags t))
    nil)

  ;; file tags
  
  (it "single file tag"
    (expect-sql-tbls (file_tags) (list "#+FILETAGS: foo"
                                       "* headline")
      `((file_tags :file_path ,testing-filepath
                   :tag "foo"))))

  (it "multiple file tags"
    (expect-sql-tbls (file_tags) (list "#+FILETAGS: foo bar"
                                       "#+FILETAGS: bang"
                                       "#+FILETAGS: bar"
                                       "* headline")
      `((file_tags :file_path ,testing-filepath
                   :tag "foo")
        (file_tags :file_path ,testing-filepath
                   :tag "bar")
        (file_tags :file_path ,testing-filepath
                   :tag "bang"))))

  ;; timestamp table

  (it "closed timestamp"
    (let* ((ts "<2112-01-01 Thu>")
           (planning (format "CLOSED: %s" ts)))
      (expect-sql-tbls (timestamps) (list "* parent"
                                          planning)
        `((timestamps :file_path ,testing-filepath
                      :headline_offset 1
                      :timestamp_offset 18
                      :is_active 1
                      :warning_type nil
                      :warning_value nil
                      :warning_unit nil
                      :repeat_type nil
                      :repeat_value nil
                      :repeat_unit nil
                      :time_start ,(org-ts-to-unixtime ts)
                      :start_is_long 0
                      :time_end nil
                      :end_is_long nil
                      :raw_value ,ts)))))

  (it "closed timestamp (long)"
    (let* ((ts "<2112-01-01 Thu 00:00>")
           (planning (format "CLOSED: %s" ts)))
      (expect-sql-tbls (timestamps) (list "* parent"
                                          planning)
        `((timestamps :file_path ,testing-filepath
                      :headline_offset 1
                      :timestamp_offset 18
                      :is_active 1
                      :warning_type nil
                      :warning_value nil
                      :warning_unit nil
                      :repeat_type nil
                      :repeat_value nil
                      :repeat_unit nil
                      :time_start ,(org-ts-to-unixtime ts)
                      :start_is_long 1
                      :time_end nil
                      :end_is_long nil
                      :raw_value ,ts)))))

  (it "timestamp deadline (repeater)"
    (let* ((ts "<2112-01-01 Thu +2d>")
           (planning (format "DEADLINE: %s" ts)))
      (expect-sql-tbls (timestamps) (list "* parent"
                                          planning)
        `((timestamps :file_path ,testing-filepath
                      :headline_offset 1
                      :timestamp_offset 20
                      :is_active 1
                      :warning_type nil
                      :warning_value nil
                      :warning_unit nil
                      :repeat_type cumulate
                      :repeat_value 2
                      :repeat_unit day
                      :time_start ,(org-ts-to-unixtime ts)
                      :start_is_long 0
                      :time_end nil
                      :end_is_long nil
                      :raw_value ,ts)))))

  (it "timestamp deadline (warning)"
    (let* ((ts "<2112-01-01 Thu -2d>")
           (planning (format "DEADLINE: %s" ts)))
      (expect-sql-tbls (timestamps) (list "* parent"
                                          planning)
        `((timestamps :file_path ,testing-filepath
                      :headline_offset 1
                      :timestamp_offset 20
                      :is_active 1
                      :warning_type all
                      :warning_value 2
                      :warning_unit day
                      :repeat_type nil
                      :repeat_value nil
                      :repeat_unit nil
                      :time_start ,(org-ts-to-unixtime ts)
                      :start_is_long 0
                      :time_end nil
                      :end_is_long nil
                      :raw_value ,ts)))))

  (let* ((ts1 "<2112-01-01 Thu>")
         (ts2 "[2112-01-02 Fri]"))
    (expect-sql-tbls-multi (timestamps) (list "* parent"
                                              ts1
                                              ts2)
      "content timestamps (included)"
      nil
      `((timestamps :file_path ,testing-filepath
                    :headline_offset 1
                    :timestamp_offset 10
                    :is_active 1
                    :warning_type nil
                    :warning_value nil
                    :warning_unit nil
                    :repeat_type nil
                    :repeat_value nil
                    :repeat_unit nil
                    :time_start ,(org-ts-to-unixtime ts1)
                    :start_is_long 0
                    :time_end nil
                    :end_is_long nil
                    :raw_value ,ts1)
        (timestamps :file_path ,testing-filepath
                    :headline_offset 1
                    :timestamp_offset 27
                    :is_active 0
                    :warning_type nil
                    :warning_value nil
                    :warning_unit nil
                    :repeat_type nil
                    :repeat_value nil
                    :repeat_unit nil
                    :time_start ,(org-ts-to-unixtime ts2)
                    :start_is_long 0
                    :time_end nil
                    :end_is_long nil
                    :raw_value ,ts2))

      "content timestamps (exclude some)"
      ((org-sql-excluded-contents-timestamp-types '(inactive)))
      `((timestamps :file_path ,testing-filepath
                    :headline_offset 1
                    :timestamp_offset 10
                    :is_active 1
                    :warning_type nil
                    :warning_value nil
                    :warning_unit nil
                    :repeat_type nil
                    :repeat_value nil
                    :repeat_unit nil
                    :time_start ,(org-ts-to-unixtime ts1)
                    :start_is_long 0
                    :time_end nil
                    :end_is_long nil
                    :raw_value ,ts1))

      "content timestamps (exclude all)"
      ((org-sql-excluded-contents-timestamp-types 'all))
      nil))

  (it "timestamp (content-nested)"
    (let* ((ts "<2112-01-01 Thu>"))
      (expect-sql-tbls (timestamps) (list "* parent"
                                          "** child"
                                          ts)
        `((timestamps :file_path ,testing-filepath
                      :headline_offset 10
                      :timestamp_offset 19
                      :is_active 1
                      :warning_type nil
                      :warning_value nil
                      :warning_unit nil
                      :repeat_type nil
                      :repeat_value nil
                      :repeat_unit nil
                      :time_start ,(org-ts-to-unixtime ts)
                      :start_is_long 0
                      :time_end nil
                      :end_is_long nil
                      :raw_value ,ts)))))

  (it "timestamp  (content-ranged)"
    (let* ((ts0 "<2112-01-01 Thu>")
           (ts1 "<2112-01-02 Fri>")
           (ts (format "%s--%s" ts0 ts1)))
      (expect-sql-tbls (timestamps) (list "* parent"
                                          ts)
        `((timestamps :file_path ,testing-filepath
                      :headline_offset 1
                      :timestamp_offset 10
                      :is_active 1
                      :warning_type nil
                      :warning_value nil
                      :warning_unit nil
                      :repeat_type nil
                      :repeat_value nil
                      :repeat_unit nil
                      :time_start ,(org-ts-to-unixtime ts0)
                      :start_is_long 0
                      :time_end ,(org-ts-to-unixtime ts1)
                      :end_is_long 0
                      :raw_value ,ts)))))

  ;; link table

  (expect-sql-tbls-multi (links) (list "* parent"
                                       "https://example.org"
                                       "file:///the/glass/prison")
    "multiple links (included)"
    nil
    `((links :file_path ,testing-filepath
             :headline_offset 1
             :link_offset 10
             :link_path "//example.org"
             :link_text ""
             :link_type "https")
      (links :file_path ,testing-filepath
             :headline_offset 1
             :link_offset 30
             :link_path "/the/glass/prison"
             :link_text ""
             :link_type "file"))

    "multiple links (exclude some)"
    ((org-sql-excluded-link-types '("file")))
    `((links :file_path ,testing-filepath
             :headline_offset 1
             :link_offset 10
             :link_path "//example.org"
             :link_text ""
             :link_type "https"))

    "multiple links (exclude all)"
    ((org-sql-excluded-link-types 'all))
    nil)

  (it "single link (nested)"
    (expect-sql-tbls (links) (list "* parent"
                                   "** child"
                                   "https://example.com")
      `((links :file_path ,testing-filepath
               :headline_offset 10
               :link_offset 19
               :link_path "//example.com"
               :link_text ""
               :link_type "https"))))
  
  (it "link with description"
    (expect-sql-tbls (links) (list "* parent"
                                   "[[https://example.org][relevant]]")
      `((links :file_path ,testing-filepath
               :headline_offset 1
               :link_offset 10
               :link_path "//example.org"
               :link_text "relevant"
               :link_type "https"))))

  ;; property table

  (it "single property"
    (expect-sql-tbls (properties headline_properties)
        (list "* parent"
              ":PROPERTIES:"
              ":key: val"
              ":END:")
      `((properties :file_path ,testing-filepath
                    :property_offset 23
                    :key_text "key"
                    :val_text "val")
        (headline_properties :file_path ,testing-filepath
                             :headline_offset 1
                             :property_offset 23))))

  (it "multiple properties"
    (expect-sql-tbls (properties headline_properties)
        (list "* parent"
              ":PROPERTIES:"
              ":p1: ragtime dandies"
              ":p2: this time its personal"
              ":END:")
      `((properties :file_path ,testing-filepath
                    :property_offset 23
                    :key_text "p1"
                    :val_text "ragtime dandies")
        (headline_properties :file_path ,testing-filepath
                             :headline_offset 1
                             :property_offset 23)
        (properties :file_path ,testing-filepath
                    :property_offset 44
                    :key_text "p2"
                    :val_text "this time its personal")
        (headline_properties :file_path ,testing-filepath
                             :headline_offset 1
                             :property_offset 44))))

  (it "single file property"
    (expect-sql-tbls (properties file_properties)
        (list "#+PROPERTY: FOO bar"
              "* parent")
      `((properties :file_path ,testing-filepath
                    :property_offset 1
                    :key_text "FOO"
                    :val_text "bar")
        (file_properties :file_path ,testing-filepath
                         :property_offset 1))))

  ;; ;; TODO add inherited properties once they exist

  (it "single clock (closed)"
    (let* ((org-log-into-drawer "LOGBOOK")
           (ts0 "[2112-01-01 Fri 00:00]")
           (ts1 "[2112-01-02 Sat 01:00]")
           (clock (format "CLOCK: %s--%s => 1:00" ts0 ts1)))
      (expect-sql-tbls (clocks) (list "* parent"
                                      ":LOGBOOK:"
                                      clock
                                      ":END:")
        ;; TODO what happens if we join tables and names collide?
        `((clocks :file_path ,testing-filepath
                  :headline_offset 1
                  :clock_offset 20
                  :time_start ,(org-ts-to-unixtime ts0)
                  :time_end ,(org-ts-to-unixtime ts1)
                  :clock_note nil)))))

  (it "single clock (open)"
    (let* ((org-log-into-drawer "LOGBOOK")
           (ts "[2112-01-01 Fri 00:00]")
           (clock (format "CLOCK: %s" ts)))
      (expect-sql-tbls (clocks) (list "* parent"
                                      ":LOGBOOK:"
                                      clock
                                      ":END:")
        `((clocks :file_path ,testing-filepath
                  :headline_offset 1
                  :clock_offset 20
                  :time_start ,(org-ts-to-unixtime ts)
                  :time_end nil
                  :clock_note nil)))))

    (let* ((ts "[2112-01-01 Fri 00:00]")
           (clock (format "CLOCK: %s" ts)))
      (expect-sql-tbls-multi (clocks) (list "* parent"
                                            ":LOGBOOK:"
                                            clock
                                            "- random"
                                            ":END:") 
        "single clock (note - included)"
        ((org-log-into-drawer "LOGBOOK"))
        `((clocks :file_path ,testing-filepath
                  :headline_offset 1
                  :clock_offset 20
                  :time_start ,(org-ts-to-unixtime ts)
                  :time_end nil
                  :clock_note "random"))

        "single clock (note - excluded)"
        ((org-log-into-drawer "LOGBOOK")
         (org-sql-exclude-clock-notes t))
        `((clocks :file_path ,testing-filepath
                  :headline_offset 1
                  :clock_offset 20
                  :time_start ,(org-ts-to-unixtime ts)
                  :time_end nil
                  :clock_note nil))))

  (it "multiple clocks"
    (let* ((org-log-into-drawer "LOGBOOK")
           (ts0 "[2112-01-01 Fri 00:00]")
           (ts1 "[2112-01-01 Fri 01:00]")
           (clock0 (format "CLOCK: %s" ts0))
           (clock1 (format "CLOCK: %s" ts1)))
      (expect-sql-tbls (clocks) (list "* parent"
                                      ":LOGBOOK:"
                                      clock0
                                      clock1
                                      ":END:")
        `((clocks :file_path ,testing-filepath
                  :headline_offset 1
                  :clock_offset 20
                  :time_start ,(org-ts-to-unixtime ts0)
                  :time_end nil
                  :clock_note nil)
          (clocks :file_path ,testing-filepath
                  :headline_offset 1
                  :clock_offset 50
                  :time_start ,(org-ts-to-unixtime ts1)
                  :time_end nil
                  :clock_note nil)))))

  (let* ((ts "[2112-01-01 Fri 00:00]")
         (header (format "Note taken on %s" ts))
         (note "fancy note"))
    (expect-sql-tbls-multi (logbook_entries) (list "* parent"
                                                   ":LOGBOOK:"
                                                   (format "- %s \\\\" header)
                                                   (format "  %s" note)
                                                   ":END:")
      "logbook item (note - included)"
      ((org-log-into-drawer "LOGBOOK"))
      `((logbook_entries :file_path ,testing-filepath
                         :headline_offset 1
                         :entry_offset 20
                         :entry_type "note"
                         :time_logged ,(org-ts-to-unixtime ts)
                         :header ,header
                         :note ,note))

      "logbook item (note - exclude)"
      ((org-log-into-drawer "LOGBOOK")
       (org-sql-excluded-logbook-types '(note)))
      nil))

  (let* ((ts "[2112-01-01 Fri 00:00]")
         (header (format "State \"DONE\"       from \"TODO\"       %s" ts)))
    (expect-sql-tbls-multi (logbook_entries state_changes)
        (list "* parent"
              ":LOGBOOK:"
              (format "- %s" header)
              ":END:")
      "logbook item (state change - included)"
      ((org-log-into-drawer "LOGBOOK"))
      `((logbook_entries :file_path ,testing-filepath
                         :headline_offset 1
                         :entry_offset 20
                         :entry_type "state"
                         :time_logged ,(org-ts-to-unixtime ts)
                         :header ,header
                         :note nil)
        (state_changes :file_path ,testing-filepath
                       :entry_offset 20
                       :state_old "TODO"
                       :state_new "DONE"))

      "logbook item (state change - excluded)"
      ((org-log-into-drawer "LOGBOOK")
       (org-sql-excluded-logbook-types '(state)))
      nil))

  (let* ((ts0 "[2112-01-01 Fri 00:00]")
         (ts1 "[2112-01-01 Fri 01:00]")
         (header (format "Rescheduled from \"%s\" on %s" ts0 ts1)))
    (expect-sql-tbls-multi (logbook_entries timestamps planning_changes)
        (list "* parent"
              ":LOGBOOK:"
              (format "- %s" header)
              ":END:")
      "logbook item (rescheduled - included)"
      ((org-log-into-drawer "LOGBOOK"))
      `((logbook_entries :file_path ,testing-filepath
                           :headline_offset 1
                           :entry_offset 20
                           :entry_type "reschedule"
                           :time_logged ,(org-ts-to-unixtime ts1)
                           :header ,header
                           :note nil)
          (timestamps :file_path ,testing-filepath
                      :headline_offset 1
                      :timestamp_offset 40
                      :is_active 0
                      :warning_type nil
                      :warning_value nil
                      :warning_unit nil
                      :repeat_type nil
                      :repeat_value nil
                      :repeat_unit nil
                      :time_start ,(org-ts-to-unixtime ts0)
                      :start_is_long 1
                      :time_end nil
                      :end_is_long nil
                      :raw_value ,ts0)
          (planning_changes :file_path ,testing-filepath
                            :entry_offset 20
                            :timestamp_offset 40))

      "logbook item (rescheduled - excluded)"
      ((org-log-into-drawer "LOGBOOK")
       (org-sql-excluded-logbook-types '(reschedule)))
      nil))

  (let* ((ts0 "[2112-01-01 Fri 00:00]")
         (ts1 "[2112-01-01 Fri 01:00]")
         (header (format "New deadline from \"%s\" on %s" ts0 ts1)))
    (expect-sql-tbls-multi (logbook_entries timestamps planning_changes)
        (list "* parent"
              ":LOGBOOK:"
              (format "- %s" header)
              ":END:")
      "logbook item (redeadline - included)"
      ((org-log-into-drawer "LOGBOOK"))
      `((logbook_entries :file_path ,testing-filepath
                         :headline_offset 1
                         :entry_offset 20
                         :entry_type "redeadline"
                         :time_logged ,(org-ts-to-unixtime ts1)
                         :header ,header
                         :note nil)
        (timestamps :file_path ,testing-filepath
                    :headline_offset 1
                    :timestamp_offset 41
                    :is_active 0
                    :warning_type nil
                    :warning_value nil
                    :warning_unit nil
                    :repeat_type nil
                    :repeat_value nil
                    :repeat_unit nil
                    :time_start ,(org-ts-to-unixtime ts0)
                    :start_is_long 1
                    :time_end nil
                    :end_is_long nil
                    :raw_value ,ts0)
        (planning_changes :file_path ,testing-filepath
                          :entry_offset 20
                          :timestamp_offset 41))

      "logbook item (redeadline - excluded)"
      ((org-log-into-drawer "LOGBOOK")
       (org-sql-excluded-logbook-types '(redeadline)))
      nil))

  (let* ((ts0 "[2112-01-01 Fri 00:00]")
         (ts1 "[2112-01-01 Fri 01:00]")
         (header (format "Not scheduled, was \"%s\" on %s" ts0 ts1)))
    (expect-sql-tbls-multi (logbook_entries timestamps planning_changes)
        (list "* parent"
              ":LOGBOOK:"
              (format "- %s" header)
              ":END:")
      "logbook item (delschedule - included)"
      ((org-log-into-drawer "LOGBOOK"))
      `((logbook_entries :file_path ,testing-filepath
                         :headline_offset 1
                         :entry_offset 20
                         :entry_type "delschedule"
                         :time_logged ,(org-ts-to-unixtime ts1)
                         :header ,header
                         :note nil)
        (timestamps :file_path ,testing-filepath
                    :headline_offset 1
                    :timestamp_offset 42
                    :is_active 0
                    :warning_type nil
                    :warning_value nil
                    :warning_unit nil
                    :repeat_type nil
                    :repeat_value nil
                    :repeat_unit nil
                    :time_start ,(org-ts-to-unixtime ts0)
                    :start_is_long 1
                    :time_end nil
                    :end_is_long nil
                    :raw_value ,ts0)
        (planning_changes :file_path ,testing-filepath
                          :entry_offset 20
                          :timestamp_offset 42))

      "logbook item (delschedule - excluded)"
      ((org-log-into-drawer "LOGBOOK")
       (org-sql-excluded-logbook-types '(delschedule)))
      nil))

  (let* ((ts0 "[2112-01-01 Fri 00:00]")
         (ts1 "[2112-01-01 Fri 01:00]")
         (header (format "Removed deadline, was \"%s\" on %s" ts0 ts1)))
    (expect-sql-tbls-multi (logbook_entries timestamps planning_changes)
        (list "* parent"
              ":LOGBOOK:"
              (format "- %s" header)
              ":END:")
      "logbook item (deldeadline - included)"
      ((org-log-into-drawer "LOGBOOK"))
      `((logbook_entries :file_path ,testing-filepath
                         :headline_offset 1
                         :entry_offset 20
                         :entry_type "deldeadline"
                         :time_logged ,(org-ts-to-unixtime ts1)
                         :header ,header
                         :note nil)
        (timestamps :file_path ,testing-filepath
                    :headline_offset 1
                    :timestamp_offset 45
                    :is_active 0
                    :warning_type nil
                    :warning_value nil
                    :warning_unit nil
                    :repeat_type nil
                    :repeat_value nil
                    :repeat_unit nil
                    :time_start ,(org-ts-to-unixtime ts0)
                    :start_is_long 1
                    :time_end nil
                    :end_is_long nil
                    :raw_value ,ts0)
        (planning_changes :file_path ,testing-filepath
                          :entry_offset 20
                          :timestamp_offset 45))

      "logbook item (deldeadline - excluded)"
      ((org-log-into-drawer "LOGBOOK")
       (org-sql-excluded-logbook-types '(deldeadline)))
      nil))

  (let* ((ts "[2112-01-01 Fri 00:00]")
         (header (format "Refiled on %s" ts)))
    (expect-sql-tbls-multi (logbook_entries) (list "* parent"
                                                   ":LOGBOOK:"
                                                   (format "- %s" header)
                                                   ":END:")
      "logbook item (refile - included)"
      ((org-log-into-drawer "LOGBOOK"))
      `((logbook_entries :file_path ,testing-filepath
                         :headline_offset 1
                         :entry_offset 20
                         :entry_type "refile"
                         :time_logged ,(org-ts-to-unixtime ts)
                         :header ,header
                         :note nil))

      "logbook item (refile - excluded)"
      ((org-log-into-drawer "LOGBOOK")
       (org-sql-excluded-logbook-types '(refile)))
      nil))

  (let* ((ts "[2112-01-01 Fri 00:00]")
         (header (format "CLOSING NOTE %s" ts)))
    (expect-sql-tbls-multi (logbook_entries) (list "* parent"
                                                   ":LOGBOOK:"
                                                   (format "- %s" header)
                                                   ":END:")
      "logbook item (done - included)"
      ((org-log-into-drawer "LOGBOOK"))
      `((logbook_entries :file_path ,testing-filepath
                         :headline_offset 1
                         :entry_offset 20
                         :entry_type "done"
                         :time_logged ,(org-ts-to-unixtime ts)
                         :header ,header
                         :note nil))

      "logbook item (done - excluded)"
      ((org-log-into-drawer "LOGBOOK")
       (org-sql-excluded-logbook-types '(done)))
      nil))

  (it "logbook item (clock + non-note)"
    (let* ((org-log-into-drawer "LOGBOOK")
           (ts "[2112-01-01 Fri 00:00]")
           (header (format "CLOSING NOTE %s" ts))
           (ts0 "[2112-01-01 Fri 00:00]")
           (ts1 "[2112-01-02 Sat 01:00]")
           (clock (format "CLOCK: %s--%s => 1:00" ts0 ts1)))
      (expect-sql-tbls (clocks logbook_entries) (list "* parent"
                                               ":LOGBOOK:"
                                               clock
                                               (format "- %s" header)
                                               ":END:")
        `((clocks :file_path ,testing-filepath
                  :headline_offset 1
                  :clock_offset 20
                  :time_start ,(org-ts-to-unixtime ts0)
                  :time_end ,(org-ts-to-unixtime ts1)
                  :clock_note nil)
          (logbook_entries :file_path ,testing-filepath
                           :headline_offset 1
                           :entry_offset 82
                           :entry_type "done"
                           :time_logged ,(org-ts-to-unixtime ts)
                           :header ,header
                           :note nil)))))

  (it "logbook item (clock + note + non-note)"
    (let* ((org-log-into-drawer "LOGBOOK")
           (ts "[2112-01-01 Fri 00:00]")
           (header (format "CLOSING NOTE %s" ts))
           (ts0 "[2112-01-01 Fri 00:00]")
           (ts1 "[2112-01-02 Sat 01:00]")
           (clock (format "CLOCK: %s--%s => 1:00" ts0 ts1)))
      (expect-sql-tbls (clocks logbook_entries) (list "* parent"
                                               ":LOGBOOK:"
                                               clock
                                               " - this is a clock note"
                                               (format "- %s" header)
                                               ":END:")
        `((clocks :file_path ,testing-filepath
                  :headline_offset 1
                  :clock_offset 20
                  :time_start ,(org-ts-to-unixtime ts0)
                  :time_end ,(org-ts-to-unixtime ts1)
                  :clock_note "this is a clock note")
          (logbook_entries :file_path ,testing-filepath
                           :headline_offset 1
                           :entry_offset 106
                           :entry_type "done"
                           :time_logged ,(org-ts-to-unixtime ts)
                           :header ,header
                           :note nil)))))

  (it "logbook item (non-note + clock)"
    (let* ((org-log-into-drawer "LOGBOOK")
           (ts "[2112-01-01 Fri 00:00]")
           (header (format "CLOSING NOTE %s" ts))
           (ts0 "[2112-01-01 Fri 00:00]")
           (ts1 "[2112-01-02 Sat 01:00]")
           (clock (format "CLOCK: %s--%s => 1:00" ts0 ts1)))
      (expect-sql-tbls (clocks logbook_entries) (list "* parent"
                                               ":LOGBOOK:"
                                               (format "- %s" header)
                                               clock
                                               ":END:")
        `((logbook_entries :file_path ,testing-filepath
                           :headline_offset 1
                           :entry_offset 20
                           :entry_type "done"
                           :time_logged ,(org-ts-to-unixtime ts)
                           :header ,header
                           :note nil)
          (clocks :file_path ,testing-filepath
                  :headline_offset 1
                  :clock_offset 58
                  :time_start ,(org-ts-to-unixtime ts0)
                  :time_end ,(org-ts-to-unixtime ts1)
                  :clock_note nil)))))

  (it "logbook item (non-note + clock + clock note)"
    (let* ((org-log-into-drawer "LOGBOOK")
           (ts "[2112-01-01 Fri 00:00]")
           (header (format "CLOSING NOTE %s" ts))
           (ts0 "[2112-01-01 Fri 00:00]")
           (ts1 "[2112-01-02 Sat 01:00]")
           (clock (format "CLOCK: %s--%s => 1:00" ts0 ts1)))
      (expect-sql-tbls (clocks logbook_entries) (list "* parent"
                                               ":LOGBOOK:"
                                               (format "- %s" header)
                                               clock
                                               "- this is a clock note"
                                               ":END:")
        `((logbook_entries :file_path ,testing-filepath
                           :headline_offset 1
                           :entry_offset 20
                           :entry_type "done"
                           :time_logged ,(org-ts-to-unixtime ts)
                           :header ,header
                           :note nil)
          (clocks :file_path ,testing-filepath
                  :headline_offset 1
                  :clock_offset 58
                  :time_start ,(org-ts-to-unixtime ts0)
                  :time_end ,(org-ts-to-unixtime ts1)
                  :clock_note "this is a clock note"))))))

(defun format-with (mode type value)
  (funcall (org-sql--compile-mql-format-function mode type) value))

(defun format-with-sqlite (type value)
  (format-with 'sqlite type value))

(defun expect-formatter (type input &rest value-plist)
  (declare (indent 2))
  (-let (((&plist :sqlite :postgres) value-plist))
    (expect (format-with 'sqlite type input) :to-equal sqlite)
    (expect (format-with 'postgres type input) :to-equal postgres)))

(describe "meta-query language type formatting spec"
  (it "boolean (NULL)"
    (expect-formatter 'boolean nil :sqlite "NULL" :postgres "NULL"))

  (it "boolean (TRUE)"
    (expect-formatter 'boolean 1 :sqlite "1" :postgres "TRUE"))

  (it "boolean (FALSE)"
    (expect-formatter 'boolean 0 :sqlite "0" :postgres "FALSE"))

  (it "enum (NULL)"
    (expect-formatter 'enum nil :sqlite "NULL" :postgres "NULL"))

  (it "enum (defined)"
    (expect-formatter 'enum 'foo :sqlite "'foo'" :postgres "'foo'"))

  (it "integer (NULL)"
    (expect-formatter 'integer nil :sqlite "NULL" :postgres "NULL"))

  (it "integer (defined)"
    (expect-formatter 'integer 123456 :sqlite "123456" :postgres "123456"))

  (it "text (NULL)"
    (expect-formatter 'text nil :sqlite "NULL" :postgres "NULL"))

  (it "text (plain)"
    (expect-formatter 'text "foo" :sqlite "'foo'" :postgres "'foo'"))
  
  (it "text (newlines)"
    (expect-formatter 'text "foo\nbar"
      :sqlite "'foo'||char(10)||'bar'"
      :postgres "'foo'||chr(10)||'bar'"))

  (it "text (quotes)"
    (expect-formatter 'text "'foo'" :sqlite "'''foo'''" :postgres "'''foo'''")))

(describe "meta-query language statement formatting spec"
  (before-all
    (setq test-schema
          '((table-foo
             (columns
              (:bool :type boolean)
              (:enum :type enum :allowed (bim bam boo))
              (:int :type integer)
              (:text :type text))
             (constraints
              (primary :keys (:int))))
            (table-bar
             (columns
              (:intone :type integer)
              (:inttwo :type integer))
             (constraints
              (primary :keys (:intone))
              (foreign :ref table-foo
                       :keys (:inttwo)
                       :parent-keys (:int)
                       :on_update cascade
                       :on_delete cascade)))))
    (setq formatter-alist
          (->> test-schema
               (--map (org-sql--compile-mql-schema-formatter-alist 'sqlite it)))))

  ;; TODO use function to make this list, but the one now has hardcoded
  ;; schema checking
  (it "insert"
    (let ((mql-insert '(table-foo :bool 0
                                  :enum bim
                                  :int 666
                                  :text "hello")))
      (expect (org-sql--format-mql-insert formatter-alist mql-insert)
              :to-equal "INSERT INTO table-foo (bool,enum,int,text) VALUES (0,'bim',666,'hello');")))

  (it "update"
    (let ((mql-insert '(table-foo (set :bool 0)
                                  (where :enum bim))))
      (expect (org-sql--format-mql-update formatter-alist mql-insert)
              :to-equal "UPDATE table-foo SET bool=0 WHERE enum='bim';")))

  (it "delete"
    (let ((mql-delete '(table-foo)))
      (expect (org-sql--format-mql-delete formatter-alist mql-delete)
              :to-equal "DELETE FROM table-foo;")))

  (it "delete (where)"
    (let ((mql-delete '(table-foo (where :enum bim))))
      (expect (org-sql--format-mql-delete formatter-alist mql-delete)
              :to-equal "DELETE FROM table-foo WHERE enum='bim';")))

  (it "select"
    (let ((mql-select '(table-foo (columns :bool))))
      (expect (org-sql--format-mql-select formatter-alist mql-select)
              :to-equal "SELECT bool FROM table-foo;")))

  (it "select (all columns)"
    (let ((mql-select '(table-foo)))
      (expect (org-sql--format-mql-select formatter-alist mql-select)
              :to-equal "SELECT * FROM table-foo;")))

  (it "select (where)"
    (let ((mql-select '(table-foo (columns :bool) (where :enum bim))))
      (expect (org-sql--format-mql-select formatter-alist mql-select)
              :to-equal "SELECT bool FROM table-foo WHERE enum='bim';")))

  (it "create table (SQLite)"
    (let ((config '(sqlite)))
      (expect
       (org-sql--format-mql-schema config test-schema)
       :to-equal
       (concat
        "CREATE TABLE IF NOT EXISTS table-foo (bool INTEGER,enum TEXT,int INTEGER,text TEXT,PRIMARY KEY (int));"
        "CREATE TABLE IF NOT EXISTS table-bar (intone INTEGER,inttwo INTEGER,PRIMARY KEY (intone),FOREIGN KEY (inttwo) REFERENCES table-foo (int) ON DELETE CASCADE ON UPDATE CASCADE);"))))

  (it "create table (postgres)"
    (let ((config '(postgres)))
      (expect
       (org-sql--format-mql-schema config test-schema)
       :to-equal
       (concat
        "CREATE TYPE enum_table-foo_enum AS ENUM ('bim','bam','boo');"
        "CREATE TABLE IF NOT EXISTS table-foo (bool BOOLEAN,enum enum_table-foo_enum,int INTEGER,text TEXT,PRIMARY KEY (int));"
        "CREATE TABLE IF NOT EXISTS table-bar (intone INTEGER,inttwo INTEGER,PRIMARY KEY (intone),FOREIGN KEY (inttwo) REFERENCES table-foo (int) ON DELETE CASCADE ON UPDATE CASCADE);"))))

  (it "transaction (sqlite)"
    (let ((mode 'sqlite)
          (statements (list "INSERT INTO foo (bar) values (1);")))
      (expect
       (org-sql--format-sql-transaction mode statements)
       :to-equal
       "PRAGMA foreign_keys = ON;BEGIN TRANSACTION;INSERT INTO foo (bar) values (1);COMMIT;")))

  (it "transaction (postgres)"
    (let ((mode 'postgres)
          (statements (list "INSERT INTO foo (bar) values (1);")))
      (expect
       (org-sql--format-sql-transaction mode statements)
       :to-equal
       "BEGIN TRANSACTION;INSERT INTO foo (bar) values (1);COMMIT;"))))

(describe "file metadata spec"
  (it "classify file metadata"
    (let ((on-disk (list (org-sql--to-fmeta "/bar.org" nil "123")
                         (org-sql--to-fmeta "/bam.org" nil "654")
                         (org-sql--to-fmeta "/foo.org" nil "456")))
          (in-db (list (org-sql--to-fmeta nil "/bar.org" "123")
                       (org-sql--to-fmeta nil "/bam0.org" "654")
                       (org-sql--to-fmeta nil "/foo0.org" "789"))))
      (expect (org-sql--classify-fmeta on-disk in-db)
              :to-equal
              `((deletes
                 ,(org-sql--to-fmeta nil "/foo0.org" "789"))
                (updates
                 ,(org-sql--to-fmeta "/bam.org" "/bam0.org" "654"))
                (inserts
                 ,(org-sql--to-fmeta "/foo.org" nil "456"))
                (noops
                 ,(org-sql--to-fmeta "/bar.org" "/bar.org" "123")))))))

;;; org-sql-test-stateless.el ends here

