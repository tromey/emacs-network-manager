;;; NetworkManager.el - NetworkManager interface via D-Bus. -*- lexical-binding:t-*-

;; Copyright (C) 2014 Tom Tromey

;; Author: Tom Tromey <tom@tromey.com>
;; Keywords: lisp, comm, unix, hardware

;;; Commentary:

;; This code interfaces to NetworkManager via dbus.  It has no
;; user-visible features but instead is just a library intended for
;; use by other Emacs Lisp programs.  It exports a simple
;; callback-based interface so that a program can be notified when the
;; network is connected or disconnected.

;;; Code:

(require 'dbus)

;; A few constants from the protocol.
;; See https://developer.gnome.org/NetworkManager/unstable/spec.html.
;; This lists them all but the current code only requires one.
(defconst NetworkManager-state-unknown 0)
(defconst NetworkManager-state-asleep 10)
(defconst NetworkManager-state-disconnected 20)
(defconst NetworkManager-state-disconnecting 30)
(defconst NetworkManager-state-connecting 40)
(defconst NetworkManager-state-connected-local 50)
(defconst NetworkManager-state-connected-site 60)
(defconst NetworkManager-state-connected-global 70)

;; Some constants for finding NetworkManager on dbus.  Perhaps some of
;; these should be found via introspection.
(defconst NetworkManager-bus :system)
(defconst NetworkManager-service "org.freedesktop.NetworkManager")
(defconst NetworkManager-path "/org/freedesktop/NetworkManager")
(defconst NetworkManager-interface "org.freedesktop.NetworkManager")
(defconst NetworkManager-state-property "State")
(defconst NetworkManager-state-signal "StateChanged")

;; Current listeners.
(defvar NetworkManager--listeners nil)

;; The last-checked state.  nil for disconnected, t for connected, and
;; something else for not yet initialized.
(defvar NetworkManager--was-connected :uninitialized)

;; The dbus connection object.
(defvar NetworkManager--signal-object nil)

(defun NetworkManager-connected-p ()
  "Return t if the network is currently connected, nil if not.

This will currently return nil if the appropriate dbus service is
not active."
  ;; Note that we only consider the globally-connected state to mean
  ;; "connected".
  (eq (dbus-get-property NetworkManager-bus NetworkManager-service
			 NetworkManager-path NetworkManager-interface
			 NetworkManager-state-property)
      NetworkManager-state-connected-global))

;; Check the current state and set the saved state.
(defun NetworkManager--check-connected ()
  (setf NetworkManager--was-connected (NetworkManager-connected-p)))

;; Called by dbus when the network state changes.  If the state has
;; changed from our previous computed state, run the hooks.
(defun NetworkManager--signaled (new-state)
  ;; Only run the hook if the state actually changed.
  (let ((is-connected (eq new-state NetworkManager-state-connected-global)))
    (unless (eq is-connected NetworkManager--was-connected)
      (run-hook-with-args 'NetworkManager--listeners is-connected)
      (setf NetworkManager--was-connected is-connected))))

(defun NetworkManager-add-listener (callback)
  "Add CALLBACK as listener to be called when the network status changes.

CALLBACK is a function that is called with one argument.  This
argument is t if the network has changed to the connected state,
and nil if the network has become disconnected.

CALLBACK is called immediately by `NetworkManager-add-listener'
with the current state of the network connection as an argument."
  (unless NetworkManager--signal-object
    (NetworkManager--check-connected)
    (setf NetworkManager--signal-object
	  (dbus-register-signal NetworkManager-bus NetworkManager-service
				NetworkManager-path NetworkManager-interface
				NetworkManager-state-signal
				#'NetworkManager--signaled)))
  (add-hook 'NetworkManager--listeners callback)
  ;; Immediately run the new function with the current state.
  (funcall callback NetworkManager--was-connected))

(defun NetworkManager-remove-listener (callback)
  "Remove CALLBACK as a network-state listener.

This is the inverse of `NetworkManager-add-listener'."
  (remove-hook 'NetworkManager--listeners callback)
  (unless NetworkManager--listeners
    (dbus-unregister-object NetworkManager--signal-object)
    (setf NetworkManager--signal-object nil)))

(provide 'NetworkManager)

;;; NetworkManager.el ends here
