(in-package :lem)

(defun load-init-file ()
  (flet ((test (path)
           (when (probe-file path)
             (load path)
             (message "Load file: ~a" path)
             t)))
    (let ((home (user-homedir-pathname))
          (*package* (find-package :lem-user)))
      (or (test (merge-pathnames ".lem/init.lisp" home))
          (test (merge-pathnames ".lemrc" home))))))

#+sbcl
(push #'(lambda (x)
          (if x
              (lem x)
              (lem))
          t)
      sb-ext:*ed-functions*)

(setf asdf:*central-registry*
      (union (mapcar #'pathname
                     (mapcar #'directory-namestring
                             (directory
                              (merge-pathnames "**/*.asd"
                                               (merge-pathnames "contrib/"
                                                                (asdf:system-source-directory :lem))))))
             asdf:*central-registry*
             :test #'equal))
