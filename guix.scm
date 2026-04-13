;; BSG Bladerunner HammerBlade packages for Guix
;;
;; Build verilator:        guix build -f guix.scm
;; Build toolchain:        (change last line to bsg-riscv-toolchain)
;; Build hello simulation: (change last line to hammerblade-hello)

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

;;;
;;; HammerBlade hello world simulation
;;;

(define-public hammerblade-hello
  (package
    (name "hammerblade-hello")
    (version "0.1")
    (source
     (local-file %dir
      #:recursive? #t
      #:select? (lambda (file stat)
                  (not (or (string-contains file "/.git/")
                           (string-contains file "/riscv-tools/")
                           ;; Exclude pre-built simulation models
                           (and (string-contains file "/machines/")
                                (string-contains file "/bigblade-verilator/"))
                           ;; Exclude pre-built spmd artifacts
                           (and (string-contains file "/spmd/hello/")
                                (or (string-suffix? ".o" file)
                                    (string-suffix? ".so" file)
                                    (string-suffix? ".riscv" file)
                                    (string-suffix? ".log" file)
                                    (string-suffix? ".csv" file)
                                    (string-suffix? ".txt" file)
                                    (string-suffix? ".json" file)
                                    (string-suffix? "/loader.c" file)
                                    (string-suffix? "bsg_link.ld" file)
                                    (string-suffix? "bsg_manycore_lib.a" file)))
                           (string-contains file "/debug/")
                           (string-contains file "/syn/")
                           (string-contains file "/ci/")
                           ;; Exclude verilator source (use package)
                           (string-contains file "/verilator/src/")
                           (string-contains file "/verilator/test/")
                           ;; Exclude build artifacts from guix-run.sh
                           (string-contains file "/verilator-guix")
                           (string-contains file "/build-hello.log")
                           (string-contains file "/build-toolchain.log")
                           (string-contains file "/guix.scm~"))))))
    (build-system gnu-build-system)
    (native-inputs
     (list verilator-4 bsg-riscv-toolchain gcc-toolchain-12
           bc git-minimal perl python-wrapper which coreutils))
    (inputs (list zlib))
    (arguments
     (list
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (replace 'build
            (lambda* (#:key inputs #:allow-other-keys)
              (let* ((verilator (assoc-ref inputs "verilator"))
                     (toolchain (assoc-ref inputs "bsg-riscv-toolchain"))
                     (srcdir (getcwd))
                     (replicant (string-append srcdir "/bsg_replicant"))
                     (manycore (string-append srcdir "/bsg_manycore"))
                     (basejump (string-append srcdir "/basejump_stl"))
                     (machine-path (string-append replicant
                       "/machines/pod_X1Y1_ruche_X16Y8_hbm_one_pseudo_channel"))
                     (platform-path (string-append replicant
                       "/libraries/platforms/bigblade-verilator"))
                     (vroot (string-append srcdir "/verilator-guix")))
                ;; Create unified verilator directory
                (mkdir-p vroot)
                (symlink (string-append verilator "/bin")
                         (string-append vroot "/bin"))
                (symlink (string-append verilator "/share/verilator/include")
                         (string-append vroot "/include"))
                ;; Init git repos so git rev-parse works
                (setenv "GIT_COMMITTER_NAME" "guix")
                (setenv "GIT_COMMITTER_EMAIL" "guix@guix")
                (setenv "GIT_AUTHOR_NAME" "guix")
                (setenv "GIT_AUTHOR_EMAIL" "guix@guix")
                (for-each
                 (lambda (d)
                   (let ((gitpath (string-append d "/.git")))
                     ;; Remove .git file/dir -- use lstat to avoid
                     ;; broken gitdir references
                     (false-if-exception (delete-file gitpath))
                     (false-if-exception (delete-file-recursively gitpath))
                     (with-directory-excursion d
                       (invoke "git" "init")
                       (invoke "git" "commit" "-m" "init"
                               "--allow-empty"))))
                 (list replicant manycore basejump))
                ;; Set environment
                (setenv "BLADERUNNER_ROOT" srcdir)
                (setenv "BSG_MANYCORE_DIR" manycore)
                (setenv "BASEJUMP_STL_DIR" basejump)
                (setenv "BSG_F1_DIR" replicant)
                (setenv "BSG_PLATFORM" "bigblade-verilator")
                (setenv "VERILATOR_ROOT" vroot)
                (setenv "VERILATOR" (string-append vroot "/bin/verilator"))
                (setenv "RISCV" toolchain)
                (setenv "PATH"
                  (string-append toolchain "/bin:"
                                 vroot "/bin:"
                                 (getenv "PATH")))
                ;; Patch hardware.mk to allow VERILATOR_ROOT override
                (substitute* (string-append platform-path "/hardware.mk")
                  (("^VERILATOR_ROOT = ") "VERILATOR_ROOT ?= ")
                  (("^VERILATOR = ") "VERILATOR ?= "))
                ;; Add VL_THREADED define if not present
                (substitute* (string-append platform-path "/link.mk")
                  (("DEFINES := -DVL_PRINTF=printf$")
                   "DEFINES := -DVL_PRINTF=printf -DVL_THREADED"))
                (setenv "CC" "gcc")
                (setenv "CXX" "g++")
                ;; Symlink RISC-V toolchain to expected location
                (mkdir-p (string-append manycore
                           "/software/riscv-tools"))
                (symlink toolchain
                         (string-append manycore
                           "/software/riscv-tools/riscv-install"))
                ;; Clean pre-built kernel artifacts
                (for-each
                 (lambda (f) (false-if-exception (delete-file f)))
                 (find-files (string-append manycore
                               "/software/spmd/hello")
                             "\\.(o|riscv|a|ld)$"))
                ;; Build the hello example (builds simsc + kernel + host)
                (with-directory-excursion
                    (string-append replicant "/examples/spmd/hello")
                  (invoke "make" "CC=gcc" "CXX=g++"
                          "BSG_PLATFORM=bigblade-verilator"
                          (string-append "BSG_MACHINE_PATH=" machine-path)
                          "exec.log")))))
          (replace 'install
            (lambda* (#:key outputs #:allow-other-keys)
              (let* ((out (assoc-ref outputs "out"))
                     (share (string-append out "/share/hammerblade"))
                     (hello (string-append (getcwd)
                              "/bsg_replicant/examples/spmd/hello")))
                (mkdir-p share)
                (copy-file (string-append hello "/exec.log")
                           (string-append share "/hello-exec.log"))))))))
    (home-page "https://github.com/bespoke-silicon-group/bsg_bladerunner")
    (synopsis "HammerBlade manycore hello world simulation")
    (description "Builds and runs the HammerBlade manycore hello world SPMD
example using Verilator simulation.  The output is a simulation log showing
the RISC-V cores executing on the simulated manycore.")
    (license license:bsd-3)))

hammerblade-hello
