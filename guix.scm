;; BSG Bladerunner HammerBlade packages for Guix
;;
;; Usage:
;;   guix build -f guix.scm                    # builds verilator-4
;;   guix build -f guix.scm -e verilator-4     # same
;;
;; For the full simulation, use guix-run.sh (see below)

(use-modules
  ((guix licenses) #:prefix license:)
  (guix packages) (guix gexp) (guix git-download) (guix build-system gnu)
  (gnu packages autotools) (gnu packages base) (gnu packages bison)
  (gnu packages flex) (gnu packages gettext) (gnu packages perl)
  (gnu packages python))

;;;
;;; Verilator 4.228 -- BSG Bladerunner needs v4.x (v5.x API incompatible)
;;;

(define-public verilator-4
  (package
    (name "verilator")
    (version "4.228")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/verilator/verilator")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "1ahxwldlyxd0kandxia5dinxg33v08zbjpwfib65s11gqxvim1jf"))))
    (build-system gnu-build-system)
    (native-inputs
     (list autoconf automake bison flex gettext-minimal perl python which))
    (inputs (list perl python))
    (arguments
     (list
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (replace 'bootstrap
            (lambda _ (invoke "autoconf")))
          (add-after 'unpack 'adjust-source
            (lambda _
              (substitute* "bin/verilator"
                (("/bin/echo") "echo")))))))
    (home-page "https://www.veripool.org/verilator/")
    (synopsis "Fast Verilog/SystemVerilog simulator (v4.x)")
    (description "Verilator compiles synthesizable Verilog and SystemVerilog
into C++ or SystemC code.  This is version 4.228, needed for BSG Bladerunner
HammerBlade simulation.")
    (license license:lgpl3+)))

verilator-4
