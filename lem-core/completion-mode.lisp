(defpackage :lem.completion-mode
  (:use :cl :lem)
  (:export :make-completion-item
           :run-completion))
(in-package :lem.completion-mode)

(defstruct completion-item
  (label "" :read-only t :type string)
  (detail "" :read-only t :type string)
  (start nil :read-only t :type (or null point))
  (end nil :read-only t :type (or null point))
  (apply-fn nil :read-only t :type (or null function)))

(defvar *completion-mode-keymap* (make-keymap :name '*completion-mode-keymap*
                                              :undef-hook 'completion-self-insert))
(define-minor-mode completion-mode
    (:name "completion"
     :keymap *completion-mode-keymap*))

(define-key *completion-mode-keymap* 'next-line 'completion-next-line)
(define-key *completion-mode-keymap* "M-n"    'completion-next-line)
(define-key *completion-mode-keymap* "C-i"    'completion-next-line)
(define-key *completion-mode-keymap* 'previous-line 'completion-previous-line)
(define-key *completion-mode-keymap* "M-p"    'completion-previous-line)
(define-key *completion-mode-keymap* 'move-to-end-of-buffer 'completion-end-of-buffer)
(define-key *completion-mode-keymap* 'move-to-beginning-of-buffer 'completion-beginning-of-buffer)
(define-key *completion-mode-keymap* "C-m"    'completion-select)
(define-key *completion-mode-keymap* "Space"    'completion-insert-space-and-cancel)
(define-key *completion-mode-keymap* 'delete-previous-char 'completion-delete-prevous-char)

(define-attribute completion-attribute
  (t :foreground "blue" :background "white" :reverse-p t))
(define-attribute non-focus-completion-attribute
  (t))

(defvar *completion-overlay* nil)
(defvar *completion-window* nil)
(defvar *completion-buffer* nil)
(defvar *completion-restart-function* nil)

(defun completion-buffer ()
  *completion-buffer*)

(defun completion-buffer-point ()
  (let ((buffer (completion-buffer)))
    (when buffer
      (buffer-point buffer))))

(defun update-completion-overlay (point)
  (when *completion-overlay*
    (delete-overlay *completion-overlay*))
  (when point
    (with-point ((start point)
                 (end point))
      (setf *completion-overlay*
            (make-overlay (line-start start)
                          (line-end end)
                          'completion-attribute)))))

(defun completion-end ()
  (when *completion-overlay*
    (delete-overlay *completion-overlay*))
  (completion-mode nil)
  (quit-balloon *completion-window*)
  (let ((buffer (completion-buffer)))
    (when buffer
      (delete-buffer buffer)
      (setf *completion-buffer* nil))))

(defun completion-again ()
  (when *completion-restart-function*
    (run-completion-1 *completion-restart-function* t)))

(define-command completion-self-insert () ()
  (let ((c (insertion-key-p (last-read-key-sequence))))
    (cond (c (insert-character (current-point) c)
             (completion-again))
          (t (unread-key-sequence (last-read-key-sequence))
             (completion-end)))))

(define-command completion-delete-prevous-char (n) ("p")
  (delete-previous-char n)
  (completion-again))

(define-command completion-next-line () ()
  (alexandria:when-let ((point (completion-buffer-point)))
    (unless (line-offset point 1)
      (buffer-start point))
    (window-see *completion-window*)
    (update-completion-overlay point)))

(define-command completion-previous-line () ()
  (alexandria:when-let ((point (completion-buffer-point)))
    (unless (line-offset point -1)
      (buffer-end point))
    (window-see *completion-window*)
    (update-completion-overlay point)))

(define-command completion-end-of-buffer () ()
  (alexandria:when-let ((point (completion-buffer-point)))
    (buffer-end point)
    (window-see *completion-window*)
    (update-completion-overlay point)))

(define-command completion-beginning-of-buffer () ()
  (alexandria:when-let ((point (completion-buffer-point)))
    (buffer-start point)
    (window-see *completion-window*)
    (update-completion-overlay point)))

(define-command completion-select () ()
  (let* ((completion-point (completion-buffer-point))
         (item (when completion-point
                 (text-property-at (line-start completion-point) :item))))
    (completion-insert (current-point) item)
    (completion-end)))

(define-command completion-insert-space-and-cancel () ()
  (insert-character (current-point) #\space)
  (completion-end))

(defun start-completion-mode (buffer restart-function)
  (setf *completion-restart-function* restart-function)
  (completion-mode t)
  (update-completion-overlay (buffer-point buffer)))

(defun completion-insert (point item)
  (when item
    (cond ((completion-item-apply-fn item)
           (funcall (completion-item-apply-fn item)
                    point))
          ((and (completion-item-start item)
                (completion-item-end item))
           (move-point point (completion-item-start item))
           (delete-between-points (completion-item-start item)
                                  (completion-item-end item))
           (insert-string point (completion-item-label item)))
          (t
           (with-point ((start point))
             (skip-chars-backward start #'syntax-symbol-char-p)
             (delete-between-points start point)
             (insert-string start (completion-item-label item)))))))

(defun create-completion-buffer (items back-attribute)
  (let ((buffer (or (completion-buffer)
                    (make-buffer "*Completion*" :enable-undo-p nil :temporary t))))
    (setf *completion-buffer* buffer)
    (erase-buffer buffer)
    (setf (variable-value 'truncate-lines :buffer buffer) nil)
    (let ((point (buffer-point buffer))
          (max-column 0)
          (label-end-column
            (reduce (lambda (max item)
                      (max max (1+ (string-width (completion-item-label item)))))
                    items
                    :initial-value 0)))
      (loop :for rest-items :on items
            :for item := (car rest-items)
            :do (insert-string point (completion-item-label item))
                (move-to-column point label-end-column t)
                (insert-string point (completion-item-detail item))
                (setf max-column (max max-column (point-column point)))
                (with-point ((start (line-start (copy-point point :temporary))))
                  (put-text-property start point :item item))
                (when (cdr rest-items)
                  (insert-character point #\newline)))
      (buffer-start point)
      (when back-attribute
        (put-text-property (buffer-start-point buffer)
                           (buffer-end-point buffer)
                           :attribute 'non-focus-completion-attribute))
      (buffer-start point)
      (values buffer max-column))))

(defun run-completion-1 (function repeat)
  (let ((items (funcall function)))
    (cond ((null items)
           (when repeat (completion-end)))
          ((and (not repeat) (null (rest items)))
           (completion-insert (current-point) (first items)))
          (t
           (multiple-value-bind (buffer max-column)
               (create-completion-buffer items 'non-focus-completion-attribute)
             (cond (repeat
                    (update-completion-overlay (buffer-point buffer))
                    (balloon (current-window)
                             buffer
                             max-column
                             (min 20 (length items))
                             *completion-window*))
                   (t
                    (setf *completion-window*
                          (balloon (current-window)
                                   buffer
                                   max-column
                                   (min 20 (length items))))
                    (start-completion-mode buffer function))))))))

(defun run-completion (function)
  (run-completion-1 function nil))

(defun minibuffer-completion (comp-f start)
  (run-completion
   (lambda ()
     (with-point ((start start)
                  (end (current-point)))
       (let ((items (funcall comp-f
                             (points-to-string start
                                               (buffer-end-point (point-buffer end))))))
         (loop :for item? :in items
               :for item := (typecase item?
                              (string
                               (make-completion-item :label item?
                                                     :start start
                                                     :end end))
                              (completion-item
                               item?))
               :when item
               :collect item))))))

(setf *minibuffer-completion-function* 'minibuffer-completion)


(defun pathname-name* (pathname)
  (enough-namestring
   pathname
   (if (uiop:directory-pathname-p pathname)
       (uiop:pathname-parent-directory-pathname pathname)
       (uiop:pathname-directory-pathname pathname))))

(defun minibuffer-file-complete (str directory)
  (mapcar (lambda (filename)
            (make-completion-item :label (pathname-name* filename)
                                  :apply-fn (lambda (p)
                                              (move-point p (lem::minibuffer-start-point))
                                              (delete-between-points
                                               p (line-end (copy-point p :temporary)))
                                              (insert-string p filename))))
          (completion-file str directory)))

(setf *minibuffer-file-complete-function* 'minibuffer-file-complete)
