;; BSG Bladerunner HammerBlade packages for Guix
;;
;; Build verilator:    guix build -f guix.scm
;; Build toolchain:    guix build -f guix.scm -e bsg-riscv-toolchain
;; Run hello example:  bash guix-run.sh hello

(use-modules
  ((guix licenses) #:prefix license:)
  (guix packages) (guix gexp) (guix git-download) (guix build-system gnu)
  (gnu packages algebra) (gnu packages autotools) (gnu packages base)
  (gnu packages bison) (gnu packages compression) (gnu packages commencement)
  (gnu packages curl) (gnu packages flex) (gnu packages gcc)
  (gnu packages gettext) (gnu packages linux) (gnu packages multiprecision)
  (gnu packages perl) (gnu packages python) (gnu packages texinfo)
  (gnu packages version-control) (gnu packages wget))

(define %dir (dirname (current-filename)))

;;;
;;; Verilator 4.228
;;;

(define-public verilator-4
  (package
    (name "verilator")
    (version "4.228")
    (source (origin
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
          (replace 'bootstrap (lambda _ (invoke "autoconf")))
          (add-after 'unpack 'adjust-source
            (lambda _ (substitute* "bin/verilator"
                        (("/bin/echo") "echo")))))))
    (home-page "https://www.veripool.org/verilator/")
    (synopsis "Fast Verilog/SystemVerilog simulator (v4.x)")
    (description "Verilator 4.228 for BSG Bladerunner HammerBlade simulation.")
    (license license:lgpl3+)))

;;;
;;; BSG RISC-V rv32imaf cross-compiler with newlib + libgcc
;;;

(define-public bsg-riscv-toolchain
  (package
    (name "bsg-riscv-toolchain")
    (version "0.1")
    (source
     (local-file
      (string-append %dir
        "/bsg_manycore/software/riscv-tools/riscv-gnu-toolchain")
      #:recursive? #t
      #:select? (lambda (file stat)
                  (not (or (string-contains file "/qemu")
                           (string-contains file "/riscv-gdb")
                           (string-contains file "/riscv-glibc")
                           (string-contains file "/riscv-dejagnu")
                           (string-contains file "/.git/")
                           (string-contains file "/build-")
                           (string-contains file "/stamps/")
                           (string-contains file "/riscv-install")
                           (string-contains file "/install-newlib")
                           (string-contains file "/limits-fix"))))))
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
            (lambda* (#:key outputs inputs #:allow-other-keys)
              (let ((bash (which "bash"))
                    (out (assoc-ref outputs "out"))
                    (linux (assoc-ref inputs "linux-libre-headers")))
                (setenv "CONFIG_SHELL" bash)
                (setenv "SHELL" bash)
                ;; KEY FIX: set C_INCLUDE_PATH to ONLY linux-libre-headers
                ;; + zlib (needed for lto-compress). This prevents glibc
                ;; headers from leaking into the cross-compiler.
                (let ((zlib (assoc-ref inputs "zlib")))
                  (setenv "C_INCLUDE_PATH"
                          (string-append linux "/include:"
                                         zlib "/include"))
                  (setenv "CPLUS_INCLUDE_PATH"
                          (getenv "C_INCLUDE_PATH"))
                  (unsetenv "CPATH"))
                ;; Fix shebangs in source Makefiles only
                ;; (skip build-* dirs which have correct store paths)
                (for-each
                 (lambda (f)
                   (unless (string-contains f "/build-")
                     (catch #t
                       (lambda ()
                         (substitute* f
                           (("^SHELL[ \t]*=[ \t]*/bin/sh" all)
                            (string-append "SHELL = " bash))
                           (("#!/bin/sh") (string-append "#!" bash))
                           (("#!/bin/bash") (string-append "#!" bash))))
                       (lambda _ #t))))
                 (find-files "." "^Makefile"))
                ;; No-op fixincludes to prevent host header copying
                (with-output-to-file
                    "riscv-gcc/fixincludes/mkfixinc.sh"
                  (lambda ()
                    (display (string-append
                      "#!/bin/sh\nmkdir -p \"$1\"\n"
                      "printf '#!/bin/sh\\nexit 0\\n' > \"$1/fixinc.sh\"\n"
                      "chmod +x \"$1/fixinc.sh\"\n"
                      "printf '#!/bin/sh\\nexit 0\\n' > fixinc.sh\n"
                      "chmod +x fixinc.sh\n"))))
                (chmod "riscv-gcc/fixincludes/mkfixinc.sh" #o755)
                ;; Create minimal include-fixed/limits.h for bare-metal
                (mkdir-p "limits-fix")
                (with-output-to-file "limits-fix/limits.h"
                  (lambda ()
                    (display
"#ifndef _GCC_LIMITS_H_
#define _GCC_LIMITS_H_
#define CHAR_BIT __CHAR_BIT__
#ifndef MB_LEN_MAX
#define MB_LEN_MAX 1
#endif
#define SCHAR_MIN (-SCHAR_MAX - 1)
#define SCHAR_MAX __SCHAR_MAX__
#define UCHAR_MAX (SCHAR_MAX * 2U + 1U)
#define CHAR_MIN SCHAR_MIN
#define CHAR_MAX SCHAR_MAX
#define SHRT_MIN (-SHRT_MAX - 1)
#define SHRT_MAX __SHRT_MAX__
#define USHRT_MAX (SHRT_MAX * 2U + 1U)
#define INT_MIN (-INT_MAX - 1)
#define INT_MAX __INT_MAX__
#define UINT_MAX (INT_MAX * 2U + 1U)
#define LONG_MIN (-LONG_MAX - 1L)
#define LONG_MAX __LONG_MAX__
#define ULONG_MAX (LONG_MAX * 2UL + 1UL)
#define LLONG_MIN (-LLONG_MAX - 1LL)
#define LLONG_MAX __LONG_LONG_MAX__
#define ULLONG_MAX (LLONG_MAX * 2ULL + 1ULL)
#define LONG_LONG_MIN LLONG_MIN
#define LONG_LONG_MAX LLONG_MAX
#define ULONG_LONG_MAX ULLONG_MAX
#endif
")))
                (invoke bash "configure"
                        (string-append "--prefix=" out)
                        "--disable-linux" "--with-arch=rv32imaf"
                        "--with-abi=ilp32f" "--disable-gdb"
                        "--with-tune=bsg_vanilla_2020"
                        "--without-headers"
                        (string-append "CONFIG_SHELL=" bash)))))
          (replace 'build
            (lambda* (#:key outputs #:allow-other-keys)
              (let ((bash (which "bash"))
                    (nproc (number->string (parallel-job-count)))
                    (out (assoc-ref outputs "out")))
                ;; Fix shebangs in source Makefiles only
                ;; (skip build-* dirs - configure already set correct paths)
                (for-each
                 (lambda (f)
                   (unless (string-contains f "/build-")
                     (catch #t
                       (lambda ()
                         (substitute* f
                           (("^SHELL[ \t]*=[ \t]*/bin/sh" all)
                            (string-append "SHELL = " bash))
                           (("#!/bin/sh") (string-append "#!" bash))))
                       (lambda _ #t))))
                 (find-files "." "^Makefile$"))
                ;; 1. Build stage1 GCC + binutils
                ;; First pass: configure + build binutils
                (invoke "make" (string-append "SHELL=" bash)
                        (string-append "-j" nproc)
                        "CFLAGS_FOR_TARGET_EXTRA=-fno-common"
                        "stamps/build-binutils-newlib")
                ;; Touch s-tm-texi to skip the texi regeneration check
                ;; (fails when source shebangs are patched by Guix)
                (when (file-exists?
                       "build-gcc-newlib-stage1/gcc/s-tm-texi")
                  (utime "build-gcc-newlib-stage1/gcc/s-tm-texi"
                         (current-time) (current-time)))
                ;; Now build GCC stage1 (binutils stamp already done)
                (system* "make" (string-append "SHELL=" bash)
                         (string-append "-j" nproc)
                         "CFLAGS_FOR_TARGET_EXTRA=-fno-common"
                         "stamps/build-gcc-newlib-stage1")
                ;; If it failed due to tm.texi, touch and retry
                (unless (file-exists? "stamps/build-gcc-newlib-stage1")
                  (for-each
                   (lambda (d)
                     (let ((f (string-append d "/gcc/s-tm-texi")))
                       (when (file-exists? f) (utime f))))
                   (find-files "." "^build-gcc" #:directories? #t))
                  (invoke "make" (string-append "SHELL=" bash)
                          (string-append "-j" nproc)
                          "CFLAGS_FOR_TARGET_EXTRA=-fno-common"
                          "stamps/build-gcc-newlib-stage1"))
                ;; 2. Install GCC internal headers manually
                ;;    (install-gcc fails due to tm.texi check)
                (let ((dest (string-append out
                              "/lib/gcc/riscv32-unknown-elf-dramfs/9.2.0")))
                  (mkdir-p (string-append dest "/include"))
                  (mkdir-p (string-append dest "/include-fixed"))
                  (for-each
                   (lambda (h)
                     (copy-file h (string-append dest "/include/"
                                                 (basename h))))
                   (find-files "build-gcc-newlib-stage1/gcc/include"
                               "\\.h$"))
                  ;; Install our minimal limits.h
                  (copy-file "limits-fix/limits.h"
                             (string-append dest
                                            "/include-fixed/limits.h")))
                ;; 3. Build newlib + newlib-nano
                (invoke "make" (string-append "SHELL=" bash)
                        (string-append "-j" nproc)
                        "CFLAGS_FOR_TARGET_EXTRA=-fno-common"
                        "stamps/build-newlib")
                (invoke "make" (string-append "SHELL=" bash)
                        (string-append "-j" nproc)
                        "CFLAGS_FOR_TARGET_EXTRA=-fno-common"
                        "stamps/build-newlib-nano")
                (invoke "make" (string-append "SHELL=" bash)
                        (string-append "-j" nproc)
                        "stamps/merge-newlib-nano")
                ;; 4. Build libgcc via stage2
                ;; Touch tm.texi stamps if they exist
                (when (file-exists? "build-gcc-newlib-stage1/gcc/s-tm-texi")
                  (invoke "touch" "build-gcc-newlib-stage1/gcc/s-tm-texi"))
                ;; Use top-level make to configure+build stage2
                (invoke "make" (string-append "SHELL=" bash)
                        (string-append "-j" nproc)
                        "stamps/build-gcc-newlib-stage2")
                (copy-file
                 "build-gcc-newlib-stage2/gcc/libgcc.a"
                 (string-append out
                   "/lib/gcc/riscv32-unknown-elf-dramfs/9.2.0/libgcc.a"))
                ))))))
    (home-page "https://github.com/bespoke-silicon-group/bsg_bladerunner")
    (synopsis "BSG RISC-V rv32imaf cross-compiler for HammerBlade")
    (description "RISC-V rv32imaf bare-metal cross-compiler (GCC 9.2,
binutils 2.32, newlib, libgcc) for the HammerBlade manycore architecture.")
    (license license:gpl3+)))

bsg-riscv-toolchain
