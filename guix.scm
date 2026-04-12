;; BSG Bladerunner packages for Guix
;;
;; Build with:
;;   guix build -f guix.scm
;;
;; The toolchain is a custom rv32imaf bare-metal GCC cross-compiler.
;; Verilator comes from Guix (v5.x).

(use-modules
  ((guix licenses) #:prefix license:)
  (guix packages)
  (guix gexp)
  (guix git-download)
  (guix build-system gnu)
  (guix build-system copy)
  (gnu packages algebra)
  (gnu packages autotools)
  (gnu packages base)
  (gnu packages bison)
  (gnu packages compression)
  (gnu packages commencement)
  (gnu packages curl)
  (gnu packages electronics)
  (gnu packages flex)
  (gnu packages gcc)
  (gnu packages linux)
  (gnu packages multiprecision)
  (gnu packages perl)
  (gnu packages python)
  (gnu packages texinfo)
  (gnu packages version-control)
  (gnu packages wget))

(define %bladerunner-dir (dirname (current-filename)))

;;;
;;; Package 1: BSG RISC-V cross-compiler toolchain
;;; Only the riscv-gnu-toolchain components needed for bare-metal
;;;

(define-public bsg-riscv-toolchain
  (package
    (name "bsg-riscv-toolchain")
    (version "0.1")
    (source (local-file
              (string-append %bladerunner-dir
                "/bsg_manycore/software/riscv-tools/riscv-gnu-toolchain")
              #:recursive? #t
              #:select? (lambda (file stat)
                          ;; Only keep what's needed for the toolchain
                          (not (or (string-contains file "/qemu")
                                   (string-contains file "/riscv-gdb")
                                   (string-contains file "/riscv-glibc")
                                   (string-contains file "/riscv-dejagnu")
                                   (string-contains file "/.git/"))))))
    (build-system gnu-build-system)
    (native-inputs
     (list autoconf automake bc bison curl flex
           gcc-toolchain-11 git-minimal
           `(,gfortran "lib") gmp libtool
           linux-libre-headers perl python texinfo wget which zlib))
    (arguments
     (list
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (replace 'configure
            (lambda _
              (let ((bash (which "bash")))
                (setenv "CONFIG_SHELL" bash)
                (setenv "SHELL" bash)
                ;; Fix /bin/sh in all Makefiles
                (for-each (lambda (f)
                            (catch #t
                              (lambda ()
                                (substitute* f
                                  (("/bin/sh") bash)
                                  (("/bin/bash") bash)))
                              (lambda args #t)))
                          (find-files "." "^Makefile"))
                ;; Replace mkfixinc.sh to prevent host header leakage
                (with-output-to-file "riscv-gcc/fixincludes/mkfixinc.sh"
                  (lambda ()
                    (display (string-append
                      "#!/bin/sh\nmkdir -p \"$1\"\n"
                      "cat > \"$1/fixinc.sh\" <<'NOOP'\n"
                      "#!/bin/sh\nexit 0\nNOOP\n"
                      "chmod +x \"$1/fixinc.sh\"\n"))))
                (chmod "riscv-gcc/fixincludes/mkfixinc.sh" #o755)
                (invoke bash "configure"
                        (string-append "--prefix=" #$output)
                        "--disable-linux"
                        "--with-arch=rv32imaf"
                        "--with-abi=ilp32f"
                        "--disable-gdb"
                        "--with-tune=bsg_vanilla_2020"
                        (string-append "CONFIG_SHELL=" bash)))))
          (replace 'build
            (lambda _
              (let ((bash (which "bash")))
                ;; Fix /bin/sh in generated Makefiles
                (for-each (lambda (f)
                            (catch #t
                              (lambda ()
                                (substitute* f
                                  (("/bin/sh") bash)))
                              (lambda args #t)))
                          (find-files "." "^Makefile$"))
                (invoke "make" (string-append "SHELL=" bash)
                        "-j1"
                        "CFLAGS_FOR_TARGET_EXTRA=-fno-common")))))))
    (home-page "https://github.com/bespoke-silicon-group/bsg_bladerunner")
    (synopsis "BSG RISC-V rv32imaf bare-metal cross-compiler")
    (description "RISC-V rv32imaf bare-metal cross-compiler toolchain
(GCC 9.2, binutils, newlib) for the HammerBlade manycore architecture.")
    (license license:gpl3+)))

;;;
;;; Package 2: basejump_stl - HDL standard library (header-only)
;;;

(define-public basejump-stl
  (package
    (name "basejump-stl")
    (version "0.1")
    (source (local-file
              (string-append %bladerunner-dir "/basejump_stl")
              #:recursive? #t
              #:select? (lambda (file stat)
                          (not (string-contains file "/.git/")))))
    (build-system copy-build-system)
    (arguments
     (list #:install-plan
           #~'(("." "share/basejump_stl/"))))
    (home-page "https://github.com/bespoke-silicon-group/basejump_stl")
    (synopsis "BaseJump STL - standard template library for SystemVerilog")
    (description "A standard template library for SystemVerilog, providing
reusable hardware components for digital design.")
    (license license:bsd-3)))

;;;
;;; Package 3: bsg_manycore - HammerBlade manycore HDL
;;;

(define-public bsg-manycore
  (package
    (name "bsg-manycore")
    (version "0.1")
    (source (local-file
              (string-append %bladerunner-dir "/bsg_manycore")
              #:recursive? #t
              #:select? (lambda (file stat)
                          (not (or (string-contains file "/.git/")
                                   (string-contains file "/riscv-tools/"))))))
    (build-system copy-build-system)
    (arguments
     (list #:install-plan
           #~'(("." "share/bsg_manycore/"))))
    (home-page "https://github.com/bespoke-silicon-group/bsg_manycore")
    (synopsis "HammerBlade manycore architecture HDL")
    (description "SystemVerilog RTL for the HammerBlade manycore architecture,
including tile array, network, and memory system.")
    (license license:bsd-3)))

;;;
;;; Package 4: bsg_replicant - runtime and examples
;;;

(define-public bsg-replicant
  (package
    (name "bsg-replicant")
    (version "0.1")
    (source (local-file
              (string-append %bladerunner-dir "/bsg_replicant")
              #:recursive? #t
              #:select? (lambda (file stat)
                          (not (string-contains file "/.git/")))))
    (build-system copy-build-system)
    (arguments
     (list #:install-plan
           #~'(("." "share/bsg_replicant/"))))
    (propagated-inputs
     (list bsg-riscv-toolchain
           basejump-stl
           bsg-manycore
           verilator))
    (home-page "https://github.com/bespoke-silicon-group/bsg_replicant")
    (synopsis "HammerBlade runtime, libraries, and examples")
    (description "Runtime libraries, cosimulation infrastructure, and example
programs for the HammerBlade manycore architecture.  Includes CUDA-Lite
examples and Snakemake workflows.")
    (license license:bsd-3)))

bsg-riscv-toolchain
