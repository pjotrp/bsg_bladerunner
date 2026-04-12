;; BSG Bladerunner RISC-V toolchain (stage1: GCC + binutils, no newlib)
(use-modules
  ((guix licenses) #:prefix license:)
  (guix packages) (guix gexp) (guix build-system gnu)
  (gnu packages algebra) (gnu packages autotools) (gnu packages base)
  (gnu packages bison) (gnu packages compression) (gnu packages commencement)
  (gnu packages curl) (gnu packages flex) (gnu packages gcc)
  (gnu packages gettext) (gnu packages linux) (gnu packages multiprecision)
  (gnu packages perl) (gnu packages python) (gnu packages texinfo)
  (gnu packages version-control) (gnu packages wget))

(define %dir (dirname (current-filename)))

(define-public bsg-riscv-toolchain
  (package
    (name "bsg-riscv-toolchain")
    (version "0.1")
    (source
     (local-file
      (string-append %dir "/bsg_manycore/software/riscv-tools/riscv-gnu-toolchain")
      #:recursive? #t
      #:select? (lambda (file stat)
                  (not (or (string-contains file "/qemu")
                           (string-contains file "/riscv-gdb")
                           (string-contains file "/riscv-glibc")
                           (string-contains file "/riscv-dejagnu")
                           (string-contains file "/.git/"))))))
    (build-system gnu-build-system)
    (native-inputs
     (list autoconf automake bc bison curl flex gcc-toolchain-11
           gettext-minimal git-minimal `(,gfortran "lib") gmp libtool
           linux-libre-headers perl python texinfo wget which zlib))
    (arguments
     (list
      #:tests? #f
      #:modules '((guix build gnu-build-system)
                  (guix build utils)
                  (ice-9 regex)
                  (ice-9 popen)
                  (ice-9 rdelim))
      #:phases
      #~(modify-phases %standard-phases
          (replace 'configure
            (lambda* (#:key outputs #:allow-other-keys)
              (let ((bash (which "bash"))
                    (out (assoc-ref outputs "out")))
                (setenv "CONFIG_SHELL" bash)
                (setenv "SHELL" bash)
                ;; Strip glibc from include paths before configure
                (for-each
                 (lambda (var)
                   (let ((val (getenv var)))
                     (when val
                       (setenv var
                         (string-join
                          (filter (lambda (p) (not (string-contains p "glibc")))
                                  (string-split val #\:))
                          ":")))))
                 '("C_INCLUDE_PATH" "CPLUS_INCLUDE_PATH" "CPATH"))
                ;; Fix shebangs
                (for-each
                 (lambda (f)
                   (catch #t
                     (lambda () (substitute* f (("/bin/sh") bash) (("/bin/bash") bash)))
                     (lambda _ #t)))
                 (find-files "." "^Makefile"))
                ;; No-op fixincludes
                (with-output-to-file "riscv-gcc/fixincludes/mkfixinc.sh"
                  (lambda ()
                    (display
                     "#!/bin/sh\nmkdir -p \"$1\"\necho '#!/bin/sh' > \"$1/fixinc.sh\"\necho 'exit 0' >> \"$1/fixinc.sh\"\nchmod +x \"$1/fixinc.sh\"\necho '#!/bin/sh' > fixinc.sh\necho 'exit 0' >> fixinc.sh\nchmod +x fixinc.sh\n")))
                (chmod "riscv-gcc/fixincludes/mkfixinc.sh" #o755)
                (invoke bash "configure"
                        (string-append "--prefix=" out)
                        "--disable-linux" "--with-arch=rv32imaf"
                        "--with-abi=ilp32f" "--disable-gdb"
                        "--with-tune=bsg_vanilla_2020" "--without-headers"
                        (string-append "CONFIG_SHELL=" bash)))))
          (replace 'build
            (lambda _
              (let ((bash (which "bash"))
                    (nproc (number->string (parallel-job-count))))
                ;; Fix shebangs in generated Makefiles
                (for-each
                 (lambda (f)
                   (catch #t
                     (lambda () (substitute* f (("/bin/sh") bash)))
                     (lambda _ #t)))
                 (find-files "." "^Makefile$"))
                ;; Build stage1 only (skip newlib)
                (invoke "make" (string-append "SHELL=" bash)
                        (string-append "-j" nproc)
                        "CFLAGS_FOR_TARGET_EXTRA=-fno-common"
                        "stamps/build-gcc-newlib-stage1")))))))
    (home-page "https://github.com/bespoke-silicon-group/bsg_bladerunner")
    (synopsis "BSG RISC-V rv32imaf bare-metal cross-compiler (stage1)")
    (description "RISC-V rv32imaf bare-metal cross-compiler (GCC 9.2 stage1,
binutils 2.32) for the HammerBlade manycore architecture.  This is a stage1
build without newlib; suitable for bare-metal programs with -nostdlib.")
    (license license:gpl3+)))

bsg-riscv-toolchain
