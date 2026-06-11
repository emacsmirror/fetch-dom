;;; fetch-dom.el --- Fetch HTML -*- lexical-binding: t -*-

;; Copyright (C) 2026 Lars Ingebrigtsen.

;; Author: Lars Magne Ingebrigtsen <larsi@gnus.org>

;; fetch-dom is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; fetch-dom is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.

;;; Commentary:

;; `fetch-dom' is the main entry function in this package.  It will
;; try to fetch URL by using three methods:

;; 1) First try to fetch URL using the normal, fast method.

;; 2) If this fails, use Selenium headless.  This involves spinning up
;;    a web browser and then dumping the resulting DOM.

;; 3) If this fails, spin up Selenium and a web browser window.  This
;;    will allow the user to click around a bit, answering any
;;    challenges.

;; In 2) and 3), `fetch-dom' will save and reuse cookies, so that
;; hopefully 3) doesn't happen as much, and 1) and 2) will be
;; successful more often.

;;; Code:

(require 'cl-lib)

(defvar fetch-dom-user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
  "User-Agent used when fetching data.")

(defvar fetch-dom-wait-period-headless 0
  "Number of seconds to wait before returning result when headless.")

(defvar fetch-dom-wait-period-popup 10
  "Number of seconds to wait before returning result when popping up window.")

(defvar fetch-dom-cookie-file "~/.emacs.d/fetch-dom.pickle"
  "The Pickle file used to save cookies.")

(defvar fetch-dom--host-values (make-hash-table :test #'equal))

(cl-defun fetch-dom (url &key wait-period-headless wait-period-popup
			 user-agent (type 'dom))
  "Fetch URL.

By default, the DOM is returned, but this is controlled by the
`:type' keyword.  Values are `dom' (the default),
`string' (return the results as a string) and `buffer' (return a
buffer containing the data)."
  (let ((fetch-dom-user-agent (or user-agent fetch-dom-user-agent))
	(host (url-host (url-generic-parse-url url))))
    (or
     ;; First try to fetch using url.el.
     (and
      (memq (gethash host fetch-dom--host-values) '(nil internal))
      (with-current-buffer (fetch-dom--internal url)
	(goto-char (point-min))
	(when (search-forward "\n\n" nil t)
	  (delete-region (point-min) (point))
	  (when (fetch-dom--got-result-p)
	    (setf (gethash host fetch-dom--host-values) 'internal)
	    (fetch-dom--return-result type)))))
     (and
      (memq (gethash host fetch-dom--host-values) '(internal headless popup))
      (with-current-buffer (fetch-dom--selenium
			    url "headless"
			    (or wait-period-headless
				fetch-dom-wait-period-headless))
	(when (fetch-dom--got-result-p)
	  (setf (gethash host fetch-dom--host-values) 'headless)
	  (fetch-dom--return-result type))))
     (with-current-buffer (fetch-dom--selenium
			    url "popup"
			    (or wait-period-popup
				fetch-dom-wait-period-popup))
       (when (fetch-dom--got-result-p)
	 (setf (gethash host fetch-dom--host-values) 'popup)
	 (fetch-dom--return-result type))))))

(defun fetch-dom--got-result-p ()
  (and (> (buffer-size) 10)
       (libxml-parse-html-region (point-min) (point-max))))

(defun fetch-dom--return-result (type)
  (pcase type
    (`dom (prog1
	      (libxml-parse-html-region (point-min) (point-max))
	    (kill-buffer (current-buffer))))
    (`string (prog1
		 (buffer-string)
	       (kill-buffer (current-buffer))))
    (`buffer (current-buffer))))

(defun fetch-dom--internal (url)
  (let ((cookies
	 (with-temp-buffer
	   (let ((default-directory (file-name-directory
				     (locate-library "fetch-dom"))))
	     (call-process (expand-file-name "print-cookies.py") nil t nil
			   (expand-file-name fetch-dom-cookie-file))
	     (goto-char (point-min))
	     (json-parse-buffer :object-type 'plist))))
	;; Don't overwrite the user's real cookies.
	(url-cookie-secure-storage nil)
	(url-cookie-storage nil))
    (cl-loop for cookie across cookies
	     do (url-cookie-store
		 (plist-get cookie 'name)
		 (plist-get cookie 'value)
		 (plist-get cookie 'expiry)
		 (plist-get cookie 'domain)
		 (plist-get cookie 'path)
		 (plist-get cookie 'secure)))
    (url-retrieve-synchronously url t nil fetch-dom-wait-period-popup)))

(defun fetch-dom--selenium (url headless wait-period)
  (with-current-buffer (generate-new-buffer "*fetch-dom*")
    (let ((default-directory (file-name-directory
			      (locate-library "fetch-dom"))))
      (call-process (expand-file-name "get-html.py") nil t nil
		    url
		    headless
		    fetch-dom-user-agent
		    (format "%d" wait-period)
		    (expand-file-name fetch-dom-cookie-file)))
    (current-buffer)))

(provide 'fetch-dom)

;;; fetch-dom.el ends here
