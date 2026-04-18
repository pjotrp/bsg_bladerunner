;; BSG Bladerunner HammerBlade packages for Guix
;;
;; Build any package by changing the last line, e.g. hammerblade-hello
;;
;; See ./GUIX.md for full documentation

(use-modules
  ((guix licenses) #:prefix license:)
  (guix packages) (guix gexp) (guix git-download) (guix utils)
  (guix build-system copy) (guix build-system gnu) (guix build-system trivial)
  (gnu packages algebra)          ; bc
  (gnu packages base)             ; coreutils, which
  (gnu packages compression)      ; zlib
  (gnu packages commencement)     ; gcc-toolchain-12
  (gnu packages cross-base)       ; cross-binutils, cross-gcc
  (gnu packages electronics)      ; verilator
  (gnu packages perl)
  (gnu packages python)
  (gnu packages version-control)) ; git-minimal

(define %dir (dirname (current-filename)))

;; Guix cross-compilation tools for riscv32-elf
(define %riscv32-xbinutils (cross-binutils "riscv32-elf"))
(define %riscv32-xgcc (cross-gcc "riscv32-elf"))

;;;
;;; Verilator development snapshot (ba508c0, 2026-04-17)
;;;

(define-public verilator-dev
  (let ((commit "ba508c00d2c8a5a667974638ef93ec75f9d233d2")
        (revision "0"))
    (package
      (inherit verilator)
      (name "verilator-dev")
      (version (git-version "5.047" revision commit))
      (source
       (origin
         (method git-fetch)
         (uri (git-reference
               (url "https://github.com/verilator/verilator")
               (commit commit)))
         (file-name (git-file-name name version))
         (sha256 (base32 "092jzrzxfzcm3m36dzq77lbbn7ik6ajpppk5zxmx39jggb54ccif"))))
      ;; Skip tests for development snapshot
      (arguments
       (substitute-keyword-arguments (package-arguments verilator)
         ((#:test-target _ #f) #f)
         ((#:tests? _ #t) #f))))))

;;;
;;; Cross-GCC for riscv32-elf with BSG Vanilla 2020 pipeline model
;;; Contributed by Andrew Waterman and Tommy Jung (BSG, U of Washington)
;;;

(define-public riscv32-elf-gcc-bsg
  (package
    (inherit %riscv32-xgcc)
    (name "riscv32-elf-gcc-bsg")
    (source
     (origin
       (inherit (package-source %riscv32-xgcc))
       (patches
        (append (origin-patches (package-source %riscv32-xgcc))
                (list (local-file "gcc-bsg-vanilla-2020.patch"))))))))

;;;
;;; Newlib for riscv32-elf (bare-metal C library)
;;;

(define-public riscv32-elf-newlib
  (package
    (name "riscv32-elf-newlib")
    (version "4.1.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/bespoke-silicon-group/bsg_newlib_dramfs")
                    (commit "fa35f8c5afc96e5ba5e213b81111be770affdbb3")))
              (file-name (git-file-name name version))
              (sha256
               (base32 "116cifjdpmrl0z8rnxhzwq5rmyfk9cazaixl7jw15l8pn3hhbkj6"))))
    (build-system gnu-build-system)
    (native-inputs (list riscv32-elf-gcc-bsg %riscv32-xbinutils))
    (arguments
     (list
      #:tests? #f
      #:make-flags
      #~(list (string-append "SHELL=" (assoc-ref %build-inputs "bash")
                             "/bin/bash"))
      #:configure-flags
      #~(let ((bash (string-append (assoc-ref %build-inputs "bash")
                                   "/bin/bash")))
          (list "--target=riscv32-elf"
                (string-append "--prefix=" #$output)
                (string-append "SHELL=" bash)
                (string-append "CONFIG_SHELL=" bash)
                "--disable-newlib-supplied-syscalls"
                "--enable-newlib-reent-small"
                "--disable-newlib-io-float"
                "--enable-lite-exit"
                "--disable-libgloss"
                (string-append "CFLAGS_FOR_TARGET="
                  "-march=rv32imaf -mabi=ilp32f "
                  "-Wno-error=implicit-function-declaration "
                  "-Wno-error=implicit-int "
                  "-Wno-error=int-conversion")))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'set-cross-env
            (lambda _
              (let ((bash (which "bash")))
                (setenv "CONFIG_SHELL" bash)
                (setenv "SHELL" bash)
                ;; Export SHELL so recursive configure/make inherits it
                (setenv "SHELL" bash)
                (setenv "CC_FOR_TARGET" "riscv32-elf-gcc")
                (setenv "AR_FOR_TARGET" "riscv32-elf-ar")
                (setenv "AS_FOR_TARGET" "riscv32-elf-as")
                (setenv "RANLIB_FOR_TARGET" "riscv32-elf-ranlib")
                ;; Old newlib + GCC 14 compatibility
                (setenv "CFLAGS_FOR_TARGET"
                  (string-append
                   "-march=rv32imaf -mabi=ilp32f "
                   "-Wno-error=implicit-function-declaration "
                   "-Wno-error=implicit-int "
                   "-Wno-error=int-conversion")))))
)))
    (home-page "https://sourceware.org/newlib/")
    (synopsis "C library for riscv32-elf bare-metal targets")
    (description "Newlib C library cross-compiled for riscv32-elf with
small reentrant struct, suitable for embedded/manycore targets.")
    (license license:bsd-3)))

;;;
;;; Unified BSG RISC-V toolchain directory
;;; Creates the riscv32-unknown-elf-dramfs-* symlink tree that the BSG
;;; build system expects, pointing to the Guix cross-gcc/binutils/newlib.
;;;

(define-public bsg-riscv-toolchain
  (package
    (name "bsg-riscv-toolchain")
    (version "14.3.0")
    (source #f)
    (build-system trivial-build-system)
    (native-inputs
     (list riscv32-elf-gcc-bsg `(,riscv32-elf-gcc-bsg "lib")
           riscv32-elf-newlib %riscv32-xbinutils))
    (arguments
     (list
      #:modules '((guix build utils) (ice-9 ftw))
      #:builder
      #~(begin
          (use-modules (guix build utils) (ice-9 ftw))
          (let* ((xgcc (assoc-ref %build-inputs "riscv32-elf-gcc-bsg"))
                 (newlib (assoc-ref %build-inputs "riscv32-elf-newlib"))
                 (xbinutils (assoc-ref %build-inputs "binutils-cross-riscv32-elf"))
                 (out #$output)
                 (bin (string-append out "/bin")))
            (mkdir-p bin)
            ;; Symlink gcc/g++/cpp (both riscv32-elf-* and dramfs-* names)
            (for-each
             (lambda (tool)
               (let ((src (string-append xgcc "/bin/riscv32-elf-" tool)))
                 (when (file-exists? src)
                   (symlink src (string-append bin "/riscv32-elf-" tool))
                   (symlink src (string-append bin "/riscv32-unknown-elf-dramfs-" tool)))))
             '("gcc" "g++" "cpp"))
            ;; Symlink binutils (both riscv32-elf-* and dramfs-* names)
            (for-each
             (lambda (tool)
               (let ((src (string-append xbinutils "/bin/riscv32-elf-" tool)))
                 (when (file-exists? src)
                   (symlink src (string-append bin "/riscv32-elf-" tool))
                   (symlink src (string-append bin "/riscv32-unknown-elf-dramfs-" tool)))))
             '("ar" "as" "ld" "nm" "objcopy" "objdump" "ranlib"
               "readelf" "size" "strings" "strip"))
            ;; Set up lib/include dirs so gcc finds newlib + libgcc
            (let* ((gcc-lib-dir
                    (let loop ((ins %build-inputs))
                      (if (null? ins) #f
                          (let ((dir (string-append (cdar ins)
                                       "/lib/gcc/riscv32-elf")))
                            (if (file-exists? dir) (cdar ins)
                                (loop (cdr ins)))))))
                   (gcc-ver
                    (car (scandir
                      (string-append gcc-lib-dir "/lib/gcc/riscv32-elf")
                      (lambda (f) (not (member f '("." ".."))))))))
              (mkdir-p (string-append out "/lib/gcc/riscv32-unknown-elf-dramfs"))
              (symlink (string-append gcc-lib-dir "/lib/gcc/riscv32-elf/" gcc-ver)
                (string-append out "/lib/gcc/riscv32-unknown-elf-dramfs/" gcc-ver))
              (mkdir-p (string-append out "/riscv32-unknown-elf-dramfs"))
              (symlink (string-append newlib "/riscv32-elf/lib")
                (string-append out "/riscv32-unknown-elf-dramfs/lib"))
              (symlink (string-append newlib "/riscv32-elf/include")
                (string-append out "/riscv32-unknown-elf-dramfs/include")))))))
    (home-page "https://github.com/bespoke-silicon-group/bsg_bladerunner")
    (synopsis "BSG RISC-V toolchain wrapper (dramfs prefix symlinks)")
    (description "Creates a unified toolchain directory with
riscv32-unknown-elf-dramfs-* symlinks pointing to Guix cross-gcc,
cross-binutils, and newlib.  The BSG Manycore build system expects
this naming convention.")
    (license license:bsd-3)))

;;;
;;; BSG Manycore source tree (RTL, software, build system)
;;;

(define hardfloat-source
  (let ((commit "5b7d5fe2df7e297b5ba095b3eb8a9517dc2e9d88"))
    (origin
      (method git-fetch)
      (uri (git-reference
            (url "https://github.com/bsg-external/HardFloat")
            (commit commit)))
      (file-name (git-file-name "hardfloat" commit))
      (sha256 (base32 "0zwic2i89ngqb9fa0hcihq3c3794y12qlfdzbrai7aclwydqgjhw")))))

(define-public bsg-manycore
  (let ((commit "bfe582b2e9b22cfb55076465ad3bba8f243bd5d4")
        (revision "0"))
    (package
      (name "bsg-manycore")
      (version (git-version "0.0.0" revision commit))
      (source (origin
                (method git-fetch)
                (uri (git-reference
                      (url "https://github.com/bespoke-silicon-group/bsg_manycore")
                      (commit commit)))
                (file-name (git-file-name name version))
                (sha256
                 (base32 "0d58v1qm195r4a3a9fsddqvfizldasjapd2xwa8d15ghzmx5j1lw"))))
      (build-system copy-build-system)
      (arguments
       (list
        #:install-plan
        #~'(("v" "share/bsg-manycore/v")
            ("software" "share/bsg-manycore/software")
            ("imports" "share/bsg-manycore/imports")
            ("machines" "share/bsg-manycore/machines")
            ("testbenches" "share/bsg-manycore/testbenches")
            ("Makefile" "share/bsg-manycore/Makefile"))
        #:phases
        #~(modify-phases %standard-phases
            (add-after 'unpack 'add-hardfloat
              (lambda _
                (copy-recursively #$hardfloat-source "imports/HardFloat"))))))
      (home-page "https://github.com/bespoke-silicon-group/bsg_manycore")
      (synopsis "BSG Manycore RTL and software for HammerBlade")
      (description "SystemVerilog RTL, software libraries, and build
infrastructure for the BSG Manycore processor used in HammerBlade.")
      (license license:bsd-3))))

;;;
;;; HammerBlade simulation platform (verilated model + shared libraries)
;;;

(define bsg-replicant-source
  (origin
    (method git-fetch)
    (uri (git-reference
          (url "https://github.com/bespoke-silicon-group/bsg_replicant")
          (commit "83e2441b3bab646a69159fa9dee80de2af9b24ae")))
    (file-name "bsg-replicant-checkout")
    (sha256 (base32 "1kbalc5yav6jxrwwk1pbf8dr3hrhnml49jkxg2zh11zwab0s1gzf"))))

(define dramsim3-source
  (let ((commit "f3edf85a2303ac05fbecdc4b304a300e40b527e2"))
    (origin
      (method git-fetch)
      (uri (git-reference
            (url "https://github.com/bsg-external/DRAMsim3")
            (commit commit)))
      (file-name (git-file-name "dramsim3" commit))
      (sha256 (base32 "0jldzzj1fg6p1wjwl0z1774vshrdwcm4rgz8w76izcw25qhbzf4d")))))

(define basejump-stl-source
  (let ((commit "5c66f9dea8c866393dc9de948563c61d81651571"))
    (origin
      (method git-fetch)
      (uri (git-reference
            (url "https://github.com/bespoke-silicon-group/basejump_stl")
            (commit commit)))
      (file-name "basejump-stl-checkout")
      (sha256 (base32 "1g47m96ifjcbgqxhj5j39rk8yqrnjsjcmmf14nz2xbh6kpdi26kr")))))

;; Source-only packages so users can access these via `guix shell`
;; (for example, to build their own SPMD kernels outside bsg_bladerunner).
(define-public bsg-replicant
  (package
    (name "bsg-replicant")
    (version "0.0.0-0.83e2441")
    (source bsg-replicant-source)
    (build-system copy-build-system)
    (arguments
     (list #:install-plan #~'(("." "share/bsg-replicant"))))
    (home-page "https://github.com/bespoke-silicon-group/bsg_replicant")
    (synopsis "HammerBlade host driver + simulation harness source tree")
    (description "Source tree for bsg_replicant: host-side libraries,
simulation platforms, and SPMD example infrastructure.")
    (license license:bsd-3)))

(define-public basejump-stl
  (package
    (name "basejump-stl")
    (version "0.0.0-0.5c66f9d")
    (source basejump-stl-source)
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan #~'(("." "share/basejump-stl"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'add-dramsim3
            (lambda _
              (copy-recursively #$dramsim3-source "imports/DRAMSim3"))))))
    (home-page "https://github.com/bespoke-silicon-group/basejump_stl")
    (synopsis "BaseJump STL standard library + DRAMSim3 for HammerBlade")
    (description "SystemVerilog standard library (FIFOs, muxes, caches,
etc.) and DRAMSim3 DRAM simulator source tree used by HammerBlade.")
    (license license:bsd-3)))

;; Shared helper: set up the BSG build tree from packages.
;; Returns an alist of (name . path) for use by callers.
(define %hammerblade-setup-phase
  #~(lambda* (#:key inputs #:allow-other-keys)
      (let* ((verilator (assoc-ref inputs "verilator-dev"))
             (bsg-mc (assoc-ref inputs "bsg-manycore"))
             (srcdir (getcwd))
             (replicant (string-append srcdir "/bsg_replicant"))
             (manycore (string-append srcdir "/bsg_manycore"))
             (basejump (string-append srcdir "/basejump_stl"))
             (machine-path (string-append replicant
               "/machines/bigblade_pod_X1Y1_ruche_X16Y8_hbm_one_pseudo_channel"))
             (platform-path (string-append replicant
               "/libraries/platforms/bigblade-verilator"))
             ;; Verilator 5 requires VERILATOR_ROOT to be the actual
             ;; install root (where bin/ and include/ live together).
             ;; In Guix that's <verilator>/share/verilator.
             (vroot (string-append verilator "/share/verilator")))
        ;; Copy bsg_manycore from package (needs to be writable)
        (copy-recursively
         (string-append bsg-mc "/share/bsg-manycore")
         manycore)
        ;; Init git repos so git rev-parse works
        (setenv "GIT_COMMITTER_NAME" "guix")
        (setenv "GIT_COMMITTER_EMAIL" "guix@guix")
        (setenv "GIT_AUTHOR_NAME" "guix")
        (setenv "GIT_AUTHOR_EMAIL" "guix@guix")
        (for-each
         (lambda (d)
           (let ((gitpath (string-append d "/.git")))
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
        (setenv "CC" "gcc")
        (setenv "CXX" "g++")
        ;; Patch hardware.mk to allow VERILATOR_ROOT override
        (substitute* (string-append platform-path "/hardware.mk")
          (("^VERILATOR_ROOT = ") "VERILATOR_ROOT ?= ")
          (("^VERILATOR = ") "VERILATOR ?= "))
        ;; Add VL_THREADED define for verilator objects and
        ;; simulator object (both need it for verilated_threads.h)
        (substitute* (string-append platform-path "/link.mk")
          (("DEFINES := -DVL_PRINTF=printf")
           "DEFINES := -DVL_PRINTF=printf -DVL_THREADED")
          (("\\$\\(SIMOS\\): CXXFLAGS := ")
           "$(SIMOS): CXXFLAGS := -DVL_THREADED "))
        ;; Clean pre-built shared libraries (have hardcoded paths)
        (for-each
         (lambda (f) (false-if-exception (delete-file f)))
         (find-files replicant "\\.so(\\..*)?$")))))

;; Shared helper for SPMD example packages: sets up the full build
;; environment (BSG tree, toolchain, pre-built sim, patched makefiles,
;; DRAMSim3 symlink, LD_LIBRARY_PATH).  Returns an alist of key paths.
(define %hammerblade-spmd-setup
  #~(lambda* (#:key inputs #:allow-other-keys)
      (use-modules (ice-9 popen) (ice-9 rdelim) (ice-9 ftw))
      ;; Base BSG tree setup (git init, env vars, verilator root)
      (#$%hammerblade-setup-phase #:inputs inputs)
      (let* ((sim (assoc-ref inputs "hammerblade-sim"))
             (sim-dir (string-append sim "/share/hammerblade-sim"))
             (tc-dir (assoc-ref inputs "bsg-riscv-toolchain"))
             (newlib (assoc-ref inputs "riscv32-elf-newlib"))
             (srcdir (getcwd))
             (replicant (string-append srcdir "/bsg_replicant"))
             (manycore (string-append srcdir "/bsg_manycore"))
             (machine-path (string-append replicant
               "/machines/bigblade_pod_X1Y1_ruche_X16Y8_hbm_one_pseudo_channel"))
             (exec-dir (string-append machine-path
                         "/bigblade-verilator/exec"))
             (link-mk (string-append replicant
               "/libraries/platforms/bigblade-verilator/link.mk")))
        ;; Toolchain
        (setenv "RISCV" tc-dir)
        (setenv "PATH"
          (string-append tc-dir "/bin:"
                         (assoc-ref inputs "verilator-dev") "/bin:"
                         (getenv "PATH")))
        (mkdir-p (string-append manycore "/software/riscv-tools"))
        (symlink tc-dir
                 (string-append manycore "/software/riscv-tools/riscv-install"))
        ;; Patch Makefile.builddefs for GCC 14 (ilp32f, no-inline)
        (substitute* (string-append manycore "/software/mk/Makefile.builddefs")
          (("-march=\\$\\(ARCH_OP\\) -static")
           "-march=$(ARCH_OP) -mabi=ilp32f -fno-inline-functions -static")
          (("RISCV_LINK_OPTS \\+= -march=\\$\\(ARCH_OP\\)")
           (string-append "RISCV_LINK_OPTS += -march=$(ARCH_OP) -mabi=ilp32f"
             " -L" newlib "/riscv32-elf/lib")))
        ;; Copy pre-built simsc + create make dependency stubs
        (copy-recursively (string-append sim-dir "/exec") exec-dir)
        (for-each
         (lambda (f) (false-if-exception (make-file-writable f)))
         (find-files exec-dir "." #:directories? #t))
        (for-each
         (lambda (name)
           (with-output-to-file (string-append exec-dir "/" name)
             (lambda () (display (if (string-suffix? ".mk" name) "# stub\n" "")))))
         '("Vreplicant_tb_top__ALL.a" "Vreplicant_tb_top.mk"
           "bsg_manycore_simulator.o"))
        ;; Copy .so files preserving tree layout
        (for-each
         (lambda (f)
           (let ((dest (string-append replicant
                         (string-drop f (string-length sim-dir)))))
             (mkdir-p (dirname dest))
             (copy-file f dest)))
         (find-files (string-append sim-dir "/libraries") "\\.so$"))
        ;; Patch link.mk to skip verilator/compile/link
        (substitute* link-mk
          (("@\\$\\(VERILATOR\\) -Mdir")
           "@echo 'skipping verilator (pre-built)' # $(VERILATOR) -Mdir")
          (("\\$\\(MAKE\\) OPT_FAST=\"-O2 -march=native\" -C \\$\\(dir \\$@\\) -f \\$\\(notdir \\$<\\) default")
           "echo 'skipping C++ compile (pre-built)'")
          (("\\$\\(LD\\) -o \\$@ \\$\\(LDFLAGS\\) \\$\\^")
           "echo 'skipping link (pre-built)'")
          (("\\$\\(CXX\\) -c \\$\\(CXXFLAGS\\) -I\\$\\(dir \\$@\\) \\$\\^ -o \\$@")
           "echo 'skipping simulator.o compile (pre-built)'"))
        ;; DRAMSim3 config path symlink: libdramsim3.so has a
        ;; compile-time hardcoded BASEJUMP_STL_DIR from the sim build.
        ;; Create a symlink at that path so configs are found at runtime.
        (let* ((sim-lib (string-append sim "/lib"))
               (dramsim-so (string-append sim-lib "/libdramsim3.so"))
               (pipe (open-pipe*
                       OPEN_READ "grep" "-ao"
                       "/tmp/guix-build-hammerblade-sim[^[:space:]]*/source"
                       dramsim-so))
               (sim-source (read-line pipe)))
          (close-pipe pipe)
          (when (and (string? sim-source)
                     (string-prefix? "/tmp/" sim-source))
            (mkdir-p sim-source)
            (symlink (string-append srcdir "/basejump_stl")
                     (string-append sim-source "/basejump_stl"))))
        ;; LD_LIBRARY_PATH: sim package installs all .so to lib/
        (setenv "LD_LIBRARY_PATH"
          (string-append sim "/lib"))
        ;; Return key paths
        `((replicant . ,replicant)
          (manycore . ,manycore)
          (machine-path . ,machine-path)))))

(define %bsg-bladerunner-commit "8100e9726654a00f11b40b9cf4a2c9a510f77dbb")
(define %bsg-bladerunner-revision "0")

(define bsg-bladerunner-source
  (origin
    (method git-fetch)
    (uri (git-reference
          (url "https://github.com/bespoke-silicon-group/bsg_bladerunner")
          (commit %bsg-bladerunner-commit)))
    (file-name (git-file-name "bsg-bladerunner" %bsg-bladerunner-commit))
    (sha256
     (base32 "1hmrmcngmm049jpsy8n9wl9z5yy4dbn68z7dfilr93v0az2v1yhd"))
    (modules '((guix build utils)))
    (snippet
     '(for-each delete-file-recursively
                (filter file-exists?
                        '("bsg_manycore" "aws-fpga" "verilator"))))))

(define-public hammerblade-sim
  (package
    (name "hammerblade-sim")
    (version (git-version "0.0.0" %bsg-bladerunner-revision
                          %bsg-bladerunner-commit))
    (source bsg-bladerunner-source)
    (build-system gnu-build-system)
    (native-inputs
     (list verilator-dev bsg-manycore gcc-toolchain-12
           bc git-minimal perl python-wrapper which coreutils))
    (inputs (list zlib))
    (arguments
     (list
      #:tests? #f
      ;; .so files have build-time rpaths from the BSG make system
      #:validate-runpath? #f
      #:modules '((guix build gnu-build-system)
                  (guix build utils)
                  (ice-9 match))
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (add-after 'unpack 'populate-submodules
            (lambda _
              (for-each
               (match-lambda
                 ((src . dest)
                  (copy-recursively src dest)
                  (for-each
                   (lambda (f) (false-if-exception (make-file-writable f)))
                   (find-files dest "." #:directories? #t))))
               (list (cons #$bsg-replicant-source "bsg_replicant")
                     (cons #$basejump-stl-source "basejump_stl")
                     (cons #$dramsim3-source "basejump_stl/imports/DRAMSim3")))))
          (replace 'build
            (lambda* (#:key inputs #:allow-other-keys)
              ;; Set up the BSG build tree
              (#$%hammerblade-setup-phase #:inputs inputs)
              (let* ((srcdir (getcwd))
                     (replicant (string-append srcdir "/bsg_replicant"))
                     (machine-path (string-append replicant
                       "/machines/bigblade_pod_X1Y1_ruche_X16Y8_hbm_one_pseudo_channel")))
                ;; Build only simsc + platform libraries (the slow part)
                (with-directory-excursion
                    (string-append replicant "/examples/spmd/hello")
                  (invoke "make" "CC=gcc" "CXX=g++"
                          "BSG_PLATFORM=bigblade-verilator"
                          (string-append "BSG_MACHINE_PATH=" machine-path)
                          (string-append machine-path
                            "/bigblade-verilator/exec/simsc"))))))
          (replace 'install
            (lambda* (#:key outputs #:allow-other-keys)
              (let* ((out (assoc-ref outputs "out"))
                     (srcdir (getcwd))
                     (replicant (string-append srcdir "/bsg_replicant"))
                     (machine-path (string-append replicant
                       "/machines/bigblade_pod_X1Y1_ruche_X16Y8_hbm_one_pseudo_channel"))
                     (dest (string-append out "/share/hammerblade-sim")))
                ;; Install only simsc binary.  The verilator
                ;; .cpp/.o/.a/.mk files are not needed:
                ;; downstream patches link.mk to skip verilator/compile/
                ;; link entirely; make sees pre-built simsc as the target.
                (mkdir-p (string-append dest "/exec"))
                (copy-file
                 (string-append machine-path
                   "/bigblade-verilator/exec/simsc")
                 (string-append dest "/exec/simsc"))
                (chmod (string-append dest "/exec/simsc") #o755)
                ;; Install shared libraries to lib/ (standard location)
                ;; and preserve tree layout under share/ for build system
                (let ((lib (string-append out "/lib")))
                  (mkdir-p lib)
                  (for-each
                   (lambda (f)
                     (let* ((name (basename f))
                            (dest-lib (string-append lib "/" name))
                            (rel (string-drop f (string-length replicant))))
                       ;; Copy to share/ tree (for BSG build system)
                       (mkdir-p (dirname (string-append dest rel)))
                       (copy-file f (string-append dest rel))
                       ;; Symlink to lib/ (for LD_LIBRARY_PATH)
                       (symlink (string-append dest rel) dest-lib)
                       ;; Create .so.1 symlink if SONAME requires it
                       (when (not (file-exists?
                                   (string-append lib "/" name ".1")))
                         (symlink dest-lib
                                  (string-append lib "/" name ".1")))))
                   (find-files (string-append replicant "/libraries")
                               "\\.so$")))
                ;; Install machine config files
                (copy-recursively machine-path
                  (string-append dest "/machine")
                  #:select? (lambda (f s)
                    (or (eq? 'directory (stat:type s))
                        (string-suffix? ".rom" f)
                        (string-suffix? ".sv" f)
                        (string-suffix? ".json" f)
                        (string-suffix? ".cfg" f)
                        (string-suffix? ".tr" f))))))))))
    (home-page "https://github.com/bespoke-silicon-group/bsg_bladerunner")
    (synopsis "HammerBlade verilated simulation platform")
    (description "Verilated simulation binary (simsc) and platform shared
libraries for the HammerBlade manycore.  This is the slow build (~20 min
with Verilator 5) that compiles the verilated RTL model.  Example
packages like hammerblade-hello use this as an input.")
    (license license:bsd-3)))

;;;
;;; HammerBlade hello world example
;;;
;; This package cross-compiles and runs the BSG "hello world" SPMD kernel
;; on the verilated 128-core HammerBlade simulator.  Here is what happens:
;;
;; 1. Source: fetch bsg_bladerunner (minus bundled submodules).
;; 2. Populate submodules: copy bsg_replicant, basejump_stl, and DRAMSim3
;;    from their separate Guix packages into the expected directory layout.
;; 3. Build setup (%hammerblade-spmd-setup):
;;    - Copy bsg_manycore source tree (RTL + software, needs to be writable).
;;    - Init fake git repos (BSG Makefiles call git rev-parse).
;;    - Set environment (VERILATOR_ROOT, BSG_MANYCORE_DIR, etc.).
;;    - Set up the RISC-V cross-toolchain (bsg-riscv-toolchain symlinks).
;;    - Patch Makefile.builddefs for GCC 14 (-mabi=ilp32f, -fno-inline).
;;    - Copy pre-built simsc + .so files from hammerblade-sim.
;;    - Create stubs so make skips verilator/C++ compile/link.
;;    - Symlink DRAMSim3 configs for libdramsim3.so.
;;    - Set LD_LIBRARY_PATH for simsc.
;; 4. Build: cross-compile main.c -> main.riscv, build host driver main.so,
;;    run simulation: simsc main.so main.riscv hello 1 1
;; 5. No install phase (build-only test).

(define-public hammerblade-hello
  (package
    (name "hammerblade-hello")
    (version (git-version "0.0.0" %bsg-bladerunner-revision
                          %bsg-bladerunner-commit))
    (source bsg-bladerunner-source)
    (build-system gnu-build-system)
    (native-inputs (list hammerblade-dev))
    (inputs (list zlib))
    (arguments
     (list
      #:tests? #f
      #:modules '((guix build gnu-build-system)
                  (guix build utils)
                  (ice-9 ftw)
                  (ice-9 match)
                  (ice-9 popen)
                  (ice-9 rdelim))
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (add-after 'unpack 'populate-submodules
            (lambda _
              (for-each
               (match-lambda
                 ((src . dest)
                  (copy-recursively src dest)
                  (for-each
                   (lambda (f) (false-if-exception (make-file-writable f)))
                   (find-files dest "." #:directories? #t))))
               (list (cons #$bsg-replicant-source "bsg_replicant")
                     (cons #$basejump-stl-source "basejump_stl")
                     (cons #$dramsim3-source "basejump_stl/imports/DRAMSim3")))))
          (replace 'build
            (lambda* (#:key inputs #:allow-other-keys)
              (let* ((env (#$%hammerblade-spmd-setup #:inputs inputs))
                     (replicant (assq-ref env 'replicant))
                     (manycore (assq-ref env 'manycore))
                     (machine-path (assq-ref env 'machine-path)))
                ;; Clean pre-built kernel artifacts
                (for-each
                 (lambda (f) (false-if-exception (delete-file f)))
                 (find-files (string-append manycore "/software/spmd/hello")
                             "\\.(o|riscv|a|ld)$"))
                ;; Build hello (kernel + host only, simsc is pre-built)
                (with-directory-excursion
                    (string-append replicant "/examples/spmd/hello")
                  (invoke "make" "CC=gcc" "CXX=g++"
                          "BSG_PLATFORM=bigblade-verilator"
                          (string-append "BSG_MACHINE_PATH=" machine-path)
                          "exec.log")))))
          (delete 'install))))
    (home-page "https://github.com/bespoke-silicon-group/bsg_bladerunner")
    (synopsis "HammerBlade manycore hello world simulation")
    (description "Builds and runs the HammerBlade manycore hello world SPMD
example using Verilator simulation.")
    (license license:bsd-3)))

;;;
;;; HammerBlade examples (builds simsc once, runs multiple SPMD examples)
;;;

(define-public hammerblade-examples
  (package
    (inherit hammerblade-hello)
    (name "hammerblade-examples")
    (arguments
     (substitute-keyword-arguments (package-arguments hammerblade-hello)
       ((#:phases phases)
        #~(modify-phases #$phases
            (replace 'build
              (lambda* (#:key inputs #:allow-other-keys)
                (let* ((env (#$%hammerblade-spmd-setup #:inputs inputs))
                       (replicant (assq-ref env 'replicant))
                       (manycore (assq-ref env 'manycore))
                       (machine-path (assq-ref env 'machine-path))
                       (examples '("hello" "bsg_scalar_print"
                                   "fib" "mul_div")))
                  ;; Patch slow examples for faster simulation
                  (substitute*
                    (string-append manycore "/software/spmd/fib/main.c")
                    (("#define N 15") "#define N 5")
                    (("#define ANSWER 986") "#define ANSWER 7")
                    (("bsg_printf\\(\"fib\\[%d\\] = %d\\\\r\\\\n\", i, my_fib\\[i\\]\\);")
                     "/* printf removed for fast sim */"))
                  ;; Clean pre-built kernel artifacts
                  (for-each
                   (lambda (name)
                     (let ((spmd (string-append manycore
                                   "/software/spmd/" name)))
                       (when (file-exists? spmd)
                         (for-each
                          (lambda (f) (false-if-exception (delete-file f)))
                          (find-files spmd "\\.(o|riscv|a|ld)$")))))
                   examples)
                  ;; Build all examples (simsc is pre-built, each
                  ;; example only cross-compiles kernel + host driver)
                  (for-each
                   (lambda (name)
                     (format #t "~%=== Building example: ~a ===~%" name)
                     (with-directory-excursion
                         (string-append replicant "/examples/spmd/" name)
                       (invoke "make" "CC=gcc" "CXX=g++"
                               "BSG_PLATFORM=bigblade-verilator"
                               (string-append "BSG_MACHINE_PATH="
                                 machine-path)
                               "exec.log")))
                   examples))))
            ;; Regression test: hash binaries + check runtime vs baseline
            (add-after 'build 'check-regression
              (lambda _
                (let ((srcdir (getcwd)))
                  (invoke "sh" #$(local-file "test/check-regression.sh")
                          (string-append srcdir "/bsg_manycore")
                          (string-append srcdir "/bsg_replicant")))))
            (delete 'install)))))
    (synopsis "HammerBlade manycore SPMD examples")
    (description "Builds and runs multiple HammerBlade manycore SPMD examples
using Verilator simulation.  The verilated model is built once (~20 min) and
reused across all examples.  Includes: hello, bsg_scalar_print, fib, mul_div.
Some examples are patched to reduce iteration counts for faster simulation.")))

;;;
;;; HammerBlade development environment
;;;
;; Meta-package that propagates all tools needed to build and run custom
;; SPMD kernels outside bsg_bladerunner.  Use with:
;;   guix shell hammerblade-dev -- make run

(define-public hammerblade-dev
  (package
    (name "hammerblade-dev")
    (version (git-version "0.0.0" %bsg-bladerunner-revision
                          %bsg-bladerunner-commit))
    (source #f)
    (build-system trivial-build-system)
    (arguments
     (list #:modules '((guix build utils))
           #:builder #~(begin
                         (use-modules (guix build utils))
                         (mkdir-p #$output))))
    (propagated-inputs
     (list hammerblade-sim
           bsg-manycore
           bsg-replicant
           basejump-stl
           bsg-riscv-toolchain
           riscv32-elf-newlib
           verilator-dev
           gcc-toolchain-12
           bc git-minimal perl python-wrapper which coreutils
           gnu-make))
    (home-page "https://github.com/bespoke-silicon-group/bsg_bladerunner")
    (synopsis "HammerBlade development environment")
    (description "Meta-package providing all tools needed to build and run
custom HammerBlade manycore SPMD programs: RISC-V cross-compiler (GCC 14.3
with BSG Vanilla 2020 tuning), newlib, pre-built verilated simulator (simsc),
host C/C++ compiler, and BSG source trees.")
    (license license:bsd-3)))

hammerblade-examples
