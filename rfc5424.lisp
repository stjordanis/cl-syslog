(in-package #:syslog)

;;; In this file, the section names refer to sections of the RFC 5424
;;; of March 2009.
;;;
;;; For all WRITE-* functions, and for most format-checking predicate
;;; functions, refer to Section 6 "Syslog Message Format", which has
;;; the ABNF grammar for the messages.

(declaim (inline ascii-char-p))
(defun ascii-char-p (c)
  (<= 0 (char-code c) 127))

(declaim (inline ascii-control-char-p))
(defun ascii-control-char-p (c)
  (let ((code (char-code c)))
    (or (= code 32)
        (= code 127))))

(declaim (inline ascii-graphic-char-p))
(defun ascii-graphic-char-p (c)
  (not (ascii-control-char-p c)))

(declaim (inline ascii-graphic-string-p))
(defun ascii-graphic-string-p (x)
  (and (stringp x)
       (every #'ascii-graphic-char-p x)))

(declaim (ascii-whitespace-char-p))
(defun ascii-whitespace-char-p (c)
  (and (member c '(#\Tab #\Newline #\Linefeed #\Page #\Return #\Space))
       t))

;;; Section 6.2. HEADER

;;; Section 6.2.1. PRI

(deftype rfc5424-pri ()
  ;; A <PRI> value is constructed by the formula
  ;;
  ;;     PRIORITY(0-7) + 8 * FACILITY(0-23)
  ;;
  ;; which means there are 8 * 24 possible choices.
  `(integer 0 (,(* 8 24))))

(defun valid-pri-p (thing)
  (typep thing 'rfc5424-pri))

(defun write-pri (stream pri)
  (format stream "<~D>" pri))


;;; Section 6.2.2. VERSION
;;;
;;; The version is just "1".
(defun write-version (stream)
  (write-char #\1 stream))


;;; Section 6.2.3. TIMESTAMP
(defun write-two-digit-number (stream number)
  (format stream "~2,'0D" number))

(defun valid-year-p (x)
  ;; A year must be a 4-digit integer.
  (typep x '(integer 1000 9999)))

(defun valid-month-p (x)
  (typep x '(integer 1 12)))

(defun valid-day-p (x)
  (typep x '(integer 1 31)))

(defun write-date (stream year month day)
  (format stream "~D" year)
  (write-char #\- stream)
  (write-two-digit-number stream month)
  (write-char #\- stream)
  (write-two-digit-number stream day))

(defun valid-hour-p (x)
  (typep x '(integer 0 23)))

(defun valid-minute-p (x)
  (typep x '(integer 0 59)))

(defun valid-second-p (x)
  (typep x '(integer 0 59)))

(defun valid-fraction-of-a-second-p (x)
  (typep x '(or null (real 0 (1)))))

(defun write-time (stream hour minute second fraction-of-a-second)
  (write-two-digit-number stream hour)
  (write-char #\: stream)
  (write-two-digit-number stream minute)
  (write-char #\: stream)
  (write-two-digit-number stream second)
  (when fraction-of-a-second
    (write-char #\. stream)
    ;; six digits are allowed!
    (format stream "~D" (floor (* fraction-of-a-second #.(expt 10 6)))))
  nil)

;;; RFC 5424 cross-references RFC 3339 for the meaning of timestamps.
(defun write-utc-timestamp (stream year month day hour minute second fraction-of-a-second)
  (write-date stream year month day)
  (write-char #\T stream)
  (write-time (stream hour minute second fraction-of-a-second))
  ;; We *ALWAYS* require UTC time. RFC 5424 allows any time offset,
  ;; but we'd prefer to be conservative here.
  (write-char #\Z stream)
  nil)


;;; Section 6.2.4. HOSTNAME
;;;
;;; RFC 5424 cross-references RFC 1034 for the format of a domain
;;; name, but it's only a SHOULD-requirement. It does mandate,
;;; however, that the string is no more than 255 characters in length.
(defun valid-hostname-p (thing)
  (or (null thing)
      (and (ascii-graphic-string-p thing)
           (<= 1 (length thing) 255))))

(defun write-hostname (stream hostname)
  (when hostname
    (write-string hostname stream))
  nil)


;;; Section 6.2.5. APP-NAME

(defun valid-app-name-p (thing)
  (or (null thing)
      (and (ascii-graphic-string-p thing)
           (<= 1 (length thing) 48))))

(defun write-app-name (stream app-name)
  (when app-name
    (write-string app-name stream))
  nil)


;;; Section 6.2.6. PROCID

(defun valid-procid-p (thing)
  (or (null thing)
      (and (ascii-graphic-string-p thing)
           (<= 1 (length thing) 128))))

(defun write-procid (stream procid)
  (when procid
    (write-string procid stream))
  nil)



;;; Section 6.2.7. MSGID

(defun valid-msgid-p (thing)
  (or (null thing)
      (and (ascii-graphic-string-p thing)
           (<= 1 (length thing) 32))))

(defun write-msgid (stream msgid)
  (when msgid
    (write-string msgid stream))
  nil)


;;; Section 6.3. STRUCTURED-DATA
;;;
;;; This is quite a complicated section, because it allows arbitrary,
;;; categorized key-values pairs to be present in the message. Some of
;;; the pairs are IETF-standardized, some aren't, and there's
;;; syntactic distinction.

(defstruct structured-data-field-description
  "A description of a field of structured data."
  ;; The printable name of the field.
  (name nil :type alexandria:string-designator :read-only t)
  ;; Are repetitions of this field allowed?
  (repetitions-allowed-p nil :type boolean :read-only t)
  ;; What is the Lisp type that describes the allowed length of the
  ;; field? By default, this is any non-negative integer.
  (length-type 'unsigned-byte :read-only t)
  ;; A function to validate the field. The function should take a
  ;; value as input, and return T if the value is valid, and NIL
  ;; otherwise. By default, T is always returned. (Note that this
  ;; function does not have to check if the input is a string. This
  ;; will be done at a higher level.)
  (validator (constantly t) :type function :read-only t))

;;; Enterprise numbers are defined in Section 7.2.2.
(defun valid-enterprise-number-p (string)
  "Is the string STRING a valid enterprise number?"
  (check-type string string)
  (prog ((length (length string))
         (i 0))
     ;; The string must have contents.
     (when (zerop length)
       (return nil))

     ;; Fall-through to expecting a digit.

   :EXPECT-DIGIT
     (unless (digit-char-p (char string i))
       (return nil))
     (when (= i (1- length))
       (return t))
     (incf i)
     (go :EXPECT-DIGIT-OR-DOT)

   :EXPECT-DOT
     (when (or (not (char= #\. (char string i)))
               (= i (1- length)))
       (return nil))
     (incf i)
     (go :EXPECT-DIGIT)

   :EXPECT-DIGIT-OR-DOT
     (cond
       ((char= #\. (char string i))
        (go :EXPECT-DOT))
       ((digit-char-p (char string i))
        (go :EXPECT-DIGIT))
       (t
        (return nil)))))

;;; This is the SD-NAME
(defun valid-sd-name-p (string)
  (flet ((valid-char-p (char)
           (and (ascii-char-p char)
                (not (ascii-control-char-p char))
                (not (ascii-whitespace-char-p char))
                (not (member char '(#\@ #\= #\] #\"))))))
    (declare (inline valid-char-p))
    (and (<= 1 (length string) 32)
         (every #'valid-char-p string))))

(defun valid-sd-id-p (x)
  "Is X a valid structured data ID? Roughly, these are either:

    1. A bare ASCII name, in which case it's an IETF-reserved name.

    2. An ASCII name, followed by '@', followed by a number (which may have dots)."
  (flet ((split (string-designator)
           (let* ((string (string string-designator))
                  (position (position #\@ string)))
             (if (null position)
                 (values string nil)
                 (values (subseq string 0 position)
                         (subseq string (1+ position)))))))
    (declare (inline split))
    (and (typep x 'alexandria:string-designator)
         (multiple-value-bind (before after) (split x)
           (and (valid-sd-name-p before)
                (or (null after)
                    (valid-enterprise-number-p after)))))))

(defstruct structured-data-description
  "A description of structured data."
  ;; Section 6.3.2. SD-ID
  (id nil :type alexandria:string-designator :read-only t)
  (allow-other-params t :type boolean :read-only t))


;;; Section 6.3.3. SD-PARAM

(defun write-param-name (stream string)
  "Write out the PARAM-NAME STRING to the stream STREAM."
  (check-type string string)
  (write-string string stream)
  nil)

(defun write-param-value (stream string)
  "Write out the PARAM-VALUE STRING to the stream STREAM."
  (check-type string string)
  (loop :for c :of-type character :across string
        :do (case c
              ((#\" #\\ #\])            ; Required escape characters.
               (write-char #\\ stream)
               (write-char c stream))
              (otherwise
               (write-char c stream))))
  nil)

;;; Section 6.3.1. SD-ELEMENT
;;;
;;; We don't use any fancy data structures for the actual SD-ELEMENTs
;;; since they'll be frequently allocated and thrown away. Lisp is
;;; good at lists, so let it do its thing.
;;;
;;; These functions should be used *after* the contents have been
;;; validated by the requisite *-DESCRIPTION data structures.

(declaim (inline make-param param-name param-value))
(defun make-param (name value) (cons name value))
(defun param-name (param) (car param))
(defun param-value (param) (cdr param))
(defun valid-param-p (p)
  (and (consp p)
       (valid-sd-name-p (param-name p))
       ;; FIXME: stringp might need to be more specific. The RFC says
       ;; it should be a UTF8 string.
       (stringp (param-value p))))

(declaim (inline make-sd-element sd-element-id sd-element-params))
(defun make-sd-element (id &rest params) (list* id params))
(defun sd-element-id (elt) (first elt))
(defun sd-element-params (elt) (rest elt))
(defun valid-sd-element-p (e)
  (and (alexandria:proper-list-p e)
       (valid-sd-id-p (sd-element-id e))
       (every #'valid-sd-element-param-p (sd-element-params e))))

(defun write-sd-element (stream elt)
  (write-char #\[ stream)
  (write-string (sd-element-id elt) stream)
  (dolist (param (sd-element-params elt))
    (write-char #\Space stream)
    (write-param-name stream (param-name param))
    (write-char #\= stream)
    (write-param-value (param-value param)))
  (write-char #\] stream)
  nil)

(defun write-sd-elements (stream elts)
  (dolist (elt elts)
    (write-sd-element stream elt)))


;;; Section 7. Structure Data IDs

(defmacro define-structured-data-id (name args &body body)
  (declare (ignore name args body))
  nil)

(define-structured-data-id |timeQuality| ()
  |tzKnown|
  |isSynced|
  |syncAccuracy|)

(define-structured-data-id |origin| ()
  |ip|
  |enterpriseId|
  |software|
  |swVersion|)

(define-structured-data-id |meta| ()
  |sequenceId|
  |sysUpTime|
  |language|)


;;; Section 6.4. MSG
;;;
;;; This is the user-supplied message. The RFC asks for the message to
;;; be Unicode, formatted as UTF-8, but does not require it.

(defun write-msg (stream string)
  ;; TODO: Deal with the BOM for UTF8 payload.
  (write-string string stream))


;;; Back to Section 6, to bring it all together.

(defun write-rfc5424-syslog-message-unsafe (stream
                                            pri
                                            year
                                            month
                                            day
                                            hour
                                            minute
                                            second
                                            fractions-of-a-second
                                            hostname
                                            app-name
                                            procid
                                            msgid
                                            sd-elements
                                            msg)
  ;; All of this comprises a SYSLOG-MSG.

  ;; HEADER
  (write-pri stream pri)
  (write-version stream)                ; Not configurable.
  (write-char #\Space stream)
  (write-utc-timestamp stream year month day hour minute second fractions-of-a-second)
  (write-char #\Space stream)
  (write-hostname stream hostname)
  (write-char #\Space stream)
  (write-app-name stream app-name)
  (write-char #\Space stream)
  (write-procid stream procid)
  (write-char #\Space stream)
  (write-msgid stream msgid)
  
  ;; Done with HEADER. Back up to SYSLOG-MSG.
  (write-char #\Space stream)
  
  ;; STRUCTURED-DATA
  (write-sd-elements stream sd-elements)

  ;; Done with STRUCTURED-DATA. Back up to SYSLOG-MSG.
  ;;
  ;; Only write a space if we have a MSG.
  (when msg
    (write-char #\Space stream)
    (write-msg stream msg))
  
  ;; Done. Don't return anything useful.
  nil)

(define-condition malformed-rfc5424-input (error)
  ()
  (:report (lambda (condition stream)
             (format stream "Malformed input for RFC 5424 syslog message."))))

(defmacro assert-rfc5424 (thing)
  `(unless ,thing
     (error 'malformed-rfc5424-input)))

(defun write-rfc5424-syslog-message (stream
                                     pri
                                     year
                                     month
                                     day
                                     hour
                                     minute
                                     second
                                     fraction-of-a-second
                                     hostname
                                     app-name
                                     procid
                                     msgid
                                     sd-elements
                                     msg)
  "Write the RFC 5424-compliant syslog message to the stream STREAM."
  (check-type stream stream)
  (assert-rfc5424 (valid-pri-p pri))
  (assert-rfc5424 (valid-year-p year))
  (assert-rfc5424 (valid-month-p month))
  (assert-rfc5424 (valid-day-p day))
  (assert-rfc5424 (valid-hour-p) hour)
  (assert-rfc5424 (valid-minute-p minute))
  (assert-rfc5424 (valid-second-p second))
  (assert-rfc5424 (valid-fraction-of-a-second-p fraction-of-a-second))
  (assert-rfc5424 (valid-hostname-p hostname))
  (assert-rfc5424 (valid-app-name-p app-name))
  (assert-rfc5424 (valid-procid-p procid))
  (assert-rfc5424 (valid-msgid-p msgid))
  (assert-rfc5424 (every #'valid-sd-element-p sd-elements))
  ;; TODO: fix this. Should be either a collection of octets or a UTF8
  ;; string.
  (assert-rfc5424 (stringp msg))
  (write-rfc5424-syslog-message-unsafe stream
                                       pri
                                       year
                                       month
                                       day
                                       hour
                                       minute
                                       second
                                       fraction-of-a-second
                                       hostname
                                       app-name
                                       procid
                                       msgid
                                       sd-elements
                                       msg))