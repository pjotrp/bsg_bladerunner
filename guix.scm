;; BSG Bladerunner HammerBlade packages for Guix
;;
;; Build any package by changing the last line, e.g. hammerblade-hello

(use-modules
  ((guix licenses) #:prefix license:)
  (guix packages) (guix gexp) (guix git-download) (guix utils)
  (guix build-system copy) (guix build-system gnu)
  (gnu packages algebra) (gnu packages autotools) (gnu packages base)
  (gnu packages bison) (gnu packages compression) (gnu packages commencement)
  (gnu packages cross-base)
  (gnu packages curl) (gnu packages flex) (gnu packages gcc)
  (gnu packages gettext) (gnu packages linux) (gnu packages multiprecision)
  (gnu packages perl) (gnu packages python) (gnu packages texinfo)
  (gnu packages version-control) (gnu packages wget))

(define %dir (dirname (current-filename)))

;; Guix cross-compilation tools for riscv32-elf
(define %riscv32-xbinutils (cross-binutils "riscv32-elf"))
(define %riscv32-xgcc (cross-gcc "riscv32-elf"))

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
;;; BSG Manycore source tree (RTL, software, build system)
;;;

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
                      (commit commit)
                      (recursive? #t)))
                (file-name (git-file-name name version))
                (sha256
                 (base32 "0b798fsc480x8fq0arrsfv53y5ara02nflb8cg620iidgjxz3ci9"))))
      (build-system copy-build-system)
      (arguments
       (list
        #:install-plan
        #~'(("v" "share/bsg-manycore/v")
            ("software" "share/bsg-manycore/software")
            ("imports" "share/bsg-manycore/imports")
            ("machines" "share/bsg-manycore/machines")
            ("testbenches" "share/bsg-manycore/testbenches")
            ("Makefile" "share/bsg-manycore/Makefile"))))
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

(define basejump-stl-source
  (let ((commit "5c66f9dea8c866393dc9de948563c61d81651571"))
    (origin
      (method git-fetch)
      (uri (git-reference
            (url "https://github.com/bespoke-silicon-group/basejump_stl")
            (commit commit)
            (recursive? #t)))
      (file-name "basejump-stl-checkout")
      (sha256 (base32 "187zwc4z5rbpfddssn84xp7bv2akwz8nz4vkzka7vils16gpq219")))))

;; Shared helper: set up the BSG build tree from packages.
;; Returns an alist of (name . path) for use by callers.
(define %hammerblade-setup-phase
  #~(lambda* (#:key inputs #:allow-other-keys)
      (let* ((verilator (assoc-ref inputs "verilator"))
             (bsg-mc (assoc-ref inputs "bsg-manycore"))
             (srcdir (getcwd))
             (replicant (string-append srcdir "/bsg_replicant"))
             (manycore (string-append srcdir "/bsg_manycore"))
             (basejump (string-append srcdir "/basejump_stl"))
             (machine-path (string-append replicant
               "/machines/pod_X1Y1_ruche_X16Y8_hbm_one_pseudo_channel"))
             (platform-path (string-append replicant
               "/libraries/platforms/bigblade-verilator"))
             (vroot (string-append srcdir "/verilator-guix")))
        ;; Copy bsg_manycore from package (needs to be writable)
        (copy-recursively
         (string-append bsg-mc "/share/bsg-manycore")
         manycore)
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

(define-public hammerblade-sim
  (let ((commit "8100e9726654a00f11b40b9cf4a2c9a510f77dbb")
        (revision "0"))
  (package
    (name "hammerblade-sim")
    (version (git-version "0.0.0" revision commit))
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/bespoke-silicon-group/bsg_bladerunner")
                    (commit commit)))
              (file-name (git-file-name name version))
              (sha256
               (base32 "1hmrmcngmm049jpsy8n9wl9z5yy4dbn68z7dfilr93v0az2v1yhd"))
              (modules '((guix build utils)))
              (snippet
               '(for-each delete-file-recursively
                          (filter file-exists?
                                  '("bsg_manycore" "aws-fpga" "verilator"))))))
    (build-system gnu-build-system)
    (native-inputs
     (list verilator-4 bsg-manycore gcc-toolchain-12
           bc git-minimal perl python-wrapper which coreutils))
    (inputs (list zlib))
    (arguments
     (list
      #:tests? #f
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (add-after 'unpack 'populate-submodules
            (lambda _
              (for-each
               (lambda (pair)
                 (copy-recursively (car pair) (cdr pair))
                 (for-each
                  (lambda (f)
                    (false-if-exception (make-file-writable f)))
                  (find-files (cdr pair) "." #:directories? #t)))
               (list (cons #$bsg-replicant-source "bsg_replicant")
                     (cons #$basejump-stl-source "basejump_stl")))))
          (replace 'build
            (lambda* (#:key inputs #:allow-other-keys)
              ;; Set up the BSG build tree
              (#$%hammerblade-setup-phase #:inputs inputs)
              (let* ((srcdir (getcwd))
                     (replicant (string-append srcdir "/bsg_replicant"))
                     (machine-path (string-append replicant
                       "/machines/pod_X1Y1_ruche_X16Y8_hbm_one_pseudo_channel")))
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
                       "/machines/pod_X1Y1_ruche_X16Y8_hbm_one_pseudo_channel"))
                     (dest (string-append out "/share/hammerblade-sim")))
                ;; Install only simsc binary (~65 MB).  The ~1.5 GB of
                ;; verilator .cpp/.o/.a/.mk files are not needed:
                ;; downstream patches link.mk to skip verilator/compile/
                ;; link entirely; make sees pre-built simsc as the target.
                (mkdir-p (string-append dest "/exec"))
                (copy-file
                 (string-append machine-path
                   "/bigblade-verilator/exec/simsc")
                 (string-append dest "/exec/simsc"))
                (chmod (string-append dest "/exec/simsc") #o755)
                ;; Install platform shared libraries in their tree layout
                (for-each
                 (lambda (f)
                   (let ((rel (string-drop f (string-length replicant))))
                     (mkdir-p (dirname (string-append dest rel)))
                     (copy-file f (string-append dest rel))))
                 (find-files (string-append replicant "/libraries")
                             "\\.so$"))
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
libraries for the HammerBlade manycore.  This is the slow build (~78 min)
that compiles ~600 C++ files from the verilated RTL model.  Example
packages like hammerblade-hello use this as an input.")
    (license license:bsd-3))))

;;;
;;; HammerBlade hello world example
;;;

(define-public hammerblade-hello
  (let ((commit "8100e9726654a00f11b40b9cf4a2c9a510f77dbb")
        (revision "0"))
  (package
    (name "hammerblade-hello")
    (version (git-version "0.0.0" revision commit))
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/bespoke-silicon-group/bsg_bladerunner")
                    (commit commit)))
              (file-name (git-file-name name version))
              (sha256
               (base32 "1hmrmcngmm049jpsy8n9wl9z5yy4dbn68z7dfilr93v0az2v1yhd"))
              (modules '((guix build utils)))
              (snippet
               '(for-each delete-file-recursively
                          (filter file-exists?
                                  '("bsg_manycore" "aws-fpga" "verilator"))))))
    (build-system gnu-build-system)
    (native-inputs
     (list hammerblade-sim verilator-4 bsg-manycore
           riscv32-elf-gcc-bsg `(,riscv32-elf-gcc-bsg "lib")
           riscv32-elf-newlib %riscv32-xbinutils
           gcc-toolchain-12
           bc git-minimal perl python-wrapper which coreutils))
    (inputs (list zlib))
    (arguments
     (list
      #:tests? #f
      #:modules '((guix build gnu-build-system)
                  (guix build utils)
                  (ice-9 ftw)
                  (ice-9 popen)
                  (ice-9 rdelim))
      #:phases
      #~(modify-phases %standard-phases
          (delete 'configure)
          (add-after 'unpack 'populate-submodules
            (lambda _
              (for-each
               (lambda (pair)
                 (copy-recursively (car pair) (cdr pair))
                 (for-each
                  (lambda (f)
                    (false-if-exception (make-file-writable f)))
                  (find-files (cdr pair) "." #:directories? #t)))
               (list (cons #$bsg-replicant-source "bsg_replicant")
                     (cons #$basejump-stl-source "basejump_stl")))))
          (replace 'build
            (lambda* (#:key inputs #:allow-other-keys)
              ;; Set up the BSG build tree
              (#$%hammerblade-setup-phase #:inputs inputs)
              (let* ((sim (assoc-ref inputs "hammerblade-sim"))
                     (sim-dir (string-append sim "/share/hammerblade-sim"))
                     (xgcc (assoc-ref inputs "riscv32-elf-gcc-bsg"))
                     (newlib (assoc-ref inputs "riscv32-elf-newlib"))
                     (xbinutils (assoc-ref inputs "binutils-cross-riscv32-elf"))
                     (srcdir (getcwd))
                     (replicant (string-append srcdir "/bsg_replicant"))
                     (manycore (string-append srcdir "/bsg_manycore"))
                     (machine-path (string-append replicant
                       "/machines/pod_X1Y1_ruche_X16Y8_hbm_one_pseudo_channel"))
                     (exec-dir (string-append machine-path
                                 "/bigblade-verilator/exec"))
                     (link-mk (string-append replicant
                       "/libraries/platforms/bigblade-verilator/link.mk"))
                     ;; Create a unified toolchain directory with
                     ;; riscv32-unknown-elf-dramfs-* symlinks pointing
                     ;; to riscv32-elf-* binaries (BSG build system
                     ;; expects the dramfs prefix)
                     (tc-dir (string-append srcdir "/riscv-toolchain")))
                (mkdir-p (string-append tc-dir "/bin"))
                ;; Symlink gcc and g++ with BSG tuning wrapper scripts
                (for-each
                 (lambda (tool)
                   (let ((src (string-append xgcc "/bin/riscv32-elf-" tool))
                         (dst (string-append tc-dir "/bin/riscv32-unknown-elf-dramfs-" tool)))
                     (when (file-exists? src)
                       (symlink src dst))))
                 '("gcc" "g++" "cpp"))
                ;; Symlink binutils
                (for-each
                 (lambda (tool)
                   (let ((src (string-append xbinutils "/bin/riscv32-elf-" tool))
                         (dst (string-append tc-dir "/bin/riscv32-unknown-elf-dramfs-" tool)))
                     (when (file-exists? src)
                       (symlink src dst))))
                 '("ar" "as" "ld" "nm" "objcopy" "objdump" "ranlib"
                   "readelf" "size" "strings" "strip"))
                ;; Set up lib/include dirs so gcc finds newlib + libgcc
                ;; Find the gcc lib output by scanning inputs
                (let* ((gcc-lib-dir
                        (let loop ((ins inputs))
                          (if (null? ins) #f
                              (let ((dir (string-append (cdar ins)
                                           "/lib/gcc/riscv32-elf")))
                                (if (file-exists? dir) (cdar ins)
                                    (loop (cdr ins)))))))
                       (gcc-ver
                        (car (scandir
                          (string-append gcc-lib-dir "/lib/gcc/riscv32-elf")
                          (lambda (f) (not (member f '("." ".."))))))))
                  (mkdir-p (string-append tc-dir "/lib/gcc/riscv32-unknown-elf-dramfs"))
                  (symlink (string-append gcc-lib-dir "/lib/gcc/riscv32-elf/" gcc-ver)
                    (string-append tc-dir "/lib/gcc/riscv32-unknown-elf-dramfs/" gcc-ver))
                  (mkdir-p (string-append tc-dir "/riscv32-unknown-elf-dramfs"))
                  (symlink (string-append newlib "/riscv32-elf/lib")
                    (string-append tc-dir "/riscv32-unknown-elf-dramfs/lib"))
                  (symlink (string-append newlib "/riscv32-elf/include")
                    (string-append tc-dir "/riscv32-unknown-elf-dramfs/include")))
                (setenv "RISCV" tc-dir)
                (setenv "PATH"
                  (string-append tc-dir "/bin:"
                                 srcdir "/verilator-guix/bin:"
                                 (getenv "PATH")))
                ;; Symlink RISC-V toolchain to expected location
                (mkdir-p (string-append manycore "/software/riscv-tools"))
                (symlink tc-dir
                         (string-append manycore
                           "/software/riscv-tools/riscv-install"))
                ;; Patch Makefile.builddefs to drop -mtune=bsg_vanilla_2020
                ;; Add -mabi=ilp32f (GCC 14 defaults to ilp32d) and
                ;; remove -mtune=bsg_vanilla_2020 (triggers ICE in GCC 14
                ;; scheduler; the pipeline model needs updates for GCC 14)
                (substitute* (string-append manycore
                  "/software/mk/Makefile.builddefs")
                  (("-march=\\$\\(ARCH_OP\\) -static")
                   ;; -fno-inline-functions: keep code size close to GCC 9.2
                   ;; (GCC 14 is more aggressive with fn inlining, hurts icache)
                   "-march=$(ARCH_OP) -mabi=ilp32f -fno-inline-functions -static")
                  (("-mtune=bsg_vanilla_2020") "")
                  ;; Add newlib lib path to link opts
                  (("RISCV_LINK_OPTS \\+= -march=\\$\\(ARCH_OP\\)")
                   (string-append "RISCV_LINK_OPTS += -march=$(ARCH_OP) -mabi=ilp32f"
                     " -L" newlib "/riscv32-elf/lib")))
                ;; Copy pre-built simsc from hammerblade-sim and create
                ;; empty stubs for .a and .mk (make dependencies)
                (copy-recursively (string-append sim-dir "/exec") exec-dir)
                (for-each
                 (lambda (f) (false-if-exception (make-file-writable f)))
                 (find-files exec-dir "." #:directories? #t))
                (with-output-to-file
                  (string-append exec-dir "/Vreplicant_tb_top__ALL.a")
                  (lambda () (display "")))
                (with-output-to-file
                  (string-append exec-dir "/Vreplicant_tb_top.mk")
                  (lambda () (display "# stub\n")))
                (with-output-to-file
                  (string-append exec-dir "/bsg_manycore_simulator.o")
                  (lambda () (display "")))
                ;; Copy .so files preserving tree layout
                (for-each
                 (lambda (f)
                   (let ((dest (string-append replicant
                                 (string-drop f (string-length sim-dir)))))
                     (mkdir-p (dirname dest))
                     (copy-file f dest)))
                 (find-files (string-append sim-dir "/libraries")
                             "\\.so$"))
                ;; Patch link.mk to skip verilator and C++ compilation.
                ;; Replace the FRAGS recipe (verilator), LIBS recipe
                ;; (C++ compile), and SIMSCS recipe (link) with no-ops.
                ;; The pre-built simsc is already in place.
                (substitute* link-mk
                  (("@\\$\\(VERILATOR\\) -Mdir")
                   "@echo 'skipping verilator (pre-built)' # $(VERILATOR) -Mdir")
                  (("\\$\\(MAKE\\) OPT_FAST=\"-O2 -march=native\" -C \\$\\(dir \\$@\\) -f \\$\\(notdir \\$<\\) default")
                   "echo 'skipping C++ compile (pre-built)'")
                  (("\\$\\(LD\\) -o \\$@ \\$\\(LDFLAGS\\) \\$\\^")
                   "echo 'skipping link (pre-built)'")
                  (("\\$\\(CXX\\) -c \\$\\(CXXFLAGS\\) -I\\$\\(dir \\$@\\) \\$\\^ -o \\$@")
                   "echo 'skipping simulator.o compile (pre-built)'"))
                ;; Clean pre-built kernel artifacts
                (for-each
                 (lambda (f) (false-if-exception (delete-file f)))
                 (find-files (string-append manycore "/software/spmd/hello")
                             "\\.(o|riscv|a|ld)$"))
                ;; Create symlink for DRAMSim3 config path hardcoded
                ;; in libdramsim3.so from the hammerblade-sim build.
                ;; Find the sim build path in the .so binary and create
                ;; the expected directory structure.
                ;; Use grep to extract the sim build path from the .so
                (let* ((dramsim-so
                        (car (find-files
                              (string-append replicant "/libraries")
                              "libdramsim3\\.so$")))
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
                ;; Set LD_LIBRARY_PATH so simsc finds its .so files
                (setenv "LD_LIBRARY_PATH"
                  (string-join
                   (map dirname
                     (find-files (string-append replicant "/libraries")
                                 "\\.so$"))
                   ":"))
                ;; Build hello (kernel + host only, simsc is pre-built)
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
example using Verilator simulation.")
    (license license:bsd-3))))

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
                ;; Set up the BSG build tree (from hammerblade-hello)
                (#$%hammerblade-setup-phase #:inputs inputs)
                (let* ((sim (assoc-ref inputs "hammerblade-sim"))
                       (sim-dir (string-append sim "/share/hammerblade-sim"))
                       (xgcc (assoc-ref inputs "riscv32-elf-gcc-bsg"))
                       (newlib (assoc-ref inputs "riscv32-elf-newlib"))
                       (xbinutils (assoc-ref inputs "binutils-cross-riscv32-elf"))
                       (srcdir (getcwd))
                       (replicant (string-append srcdir "/bsg_replicant"))
                       (manycore (string-append srcdir "/bsg_manycore"))
                       (machine-path (string-append replicant
                         "/machines/pod_X1Y1_ruche_X16Y8_hbm_one_pseudo_channel"))
                       (exec-dir (string-append machine-path
                                   "/bigblade-verilator/exec"))
                       (link-mk (string-append replicant
                         "/libraries/platforms/bigblade-verilator/link.mk"))
                       (tc-dir (string-append srcdir "/riscv-toolchain"))
                       (examples '("hello" "bsg_scalar_print"
                                   "fib" "mul_div")))
                  ;; Create toolchain wrapper (same as hammerblade-hello)
                  (mkdir-p (string-append tc-dir "/bin"))
                  (for-each
                   (lambda (tool)
                     (let ((src (string-append xgcc "/bin/riscv32-elf-" tool))
                           (dst (string-append tc-dir "/bin/riscv32-unknown-elf-dramfs-" tool)))
                       (when (file-exists? src) (symlink src dst))))
                   '("gcc" "g++" "cpp"))
                  (for-each
                   (lambda (tool)
                     (let ((src (string-append xbinutils "/bin/riscv32-elf-" tool))
                           (dst (string-append tc-dir "/bin/riscv32-unknown-elf-dramfs-" tool)))
                       (when (file-exists? src) (symlink src dst))))
                   '("ar" "as" "ld" "nm" "objcopy" "objdump" "ranlib"
                     "readelf" "size" "strings" "strip"))
                  (let* ((gcc-lib-dir
                          (let loop ((ins inputs))
                            (if (null? ins) #f
                                (let ((dir (string-append (cdar ins)
                                             "/lib/gcc/riscv32-elf")))
                                  (if (file-exists? dir) (cdar ins)
                                      (loop (cdr ins)))))))
                         (gcc-ver
                          (car (scandir
                            (string-append gcc-lib-dir "/lib/gcc/riscv32-elf")
                            (lambda (f) (not (member f '("." ".."))))))))
                    (mkdir-p (string-append tc-dir "/lib/gcc/riscv32-unknown-elf-dramfs"))
                    (symlink (string-append gcc-lib-dir "/lib/gcc/riscv32-elf/" gcc-ver)
                      (string-append tc-dir "/lib/gcc/riscv32-unknown-elf-dramfs/" gcc-ver))
                    (mkdir-p (string-append tc-dir "/riscv32-unknown-elf-dramfs"))
                    (symlink (string-append newlib "/riscv32-elf/lib")
                      (string-append tc-dir "/riscv32-unknown-elf-dramfs/lib"))
                    (symlink (string-append newlib "/riscv32-elf/include")
                      (string-append tc-dir "/riscv32-unknown-elf-dramfs/include")))
                  (setenv "RISCV" tc-dir)
                  (setenv "PATH"
                    (string-append tc-dir "/bin:"
                                   srcdir "/verilator-guix/bin:"
                                   (getenv "PATH")))
                  ;; Symlink RISC-V toolchain to expected location
                  (mkdir-p (string-append manycore "/software/riscv-tools"))
                  (symlink tc-dir
                           (string-append manycore
                             "/software/riscv-tools/riscv-install"))
                  ;; Patch build defs for GCC 14 compatibility
                  (substitute* (string-append manycore
                    "/software/mk/Makefile.builddefs")
                    (("-march=\\$\\(ARCH_OP\\) -static")
                     "-march=$(ARCH_OP) -mabi=ilp32f -fno-inline-functions -static")
                    (("-mtune=bsg_vanilla_2020") "")
                    (("RISCV_LINK_OPTS \\+= -march=\\$\\(ARCH_OP\\)")
                     (string-append "RISCV_LINK_OPTS += -march=$(ARCH_OP) -mabi=ilp32f"
                       " -L" newlib "/riscv32-elf/lib")))
                  ;; Copy pre-built simsc and create make dep stubs
                  (copy-recursively (string-append sim-dir "/exec") exec-dir)
                  (for-each
                   (lambda (f) (false-if-exception (make-file-writable f)))
                   (find-files exec-dir "." #:directories? #t))
                  (with-output-to-file
                    (string-append exec-dir "/Vreplicant_tb_top__ALL.a")
                    (lambda () (display "")))
                  (with-output-to-file
                    (string-append exec-dir "/Vreplicant_tb_top.mk")
                    (lambda () (display "# stub\n")))
                  (with-output-to-file
                    (string-append exec-dir "/bsg_manycore_simulator.o")
                    (lambda () (display "")))
                  ;; Copy .so files preserving tree layout
                  (for-each
                   (lambda (f)
                     (let ((dest (string-append replicant
                                   (string-drop f (string-length sim-dir)))))
                       (mkdir-p (dirname dest))
                       (copy-file f dest)))
                   (find-files (string-append sim-dir "/libraries")
                               "\\.so$"))
                  ;; Patch link.mk to skip verilator/compile/link
                  (substitute* link-mk
                    (("@\\$\\(VERILATOR\\) -Mdir")
                     "@echo 'skipping verilator' # $(VERILATOR) -Mdir")
                    (("\\$\\(MAKE\\) OPT_FAST=\"-O2 -march=native\" -C \\$\\(dir \\$@\\) -f \\$\\(notdir \\$<\\) default")
                     "echo 'skipping C++ compile'")
                    (("\\$\\(LD\\) -o \\$@ \\$\\(LDFLAGS\\) \\$\\^")
                     "echo 'skipping link'"))
                  ;; Create symlink for DRAMSim3 config path
                  (let* ((dramsim-so
                          (car (find-files
                                (string-append replicant "/libraries")
                                "libdramsim3\\.so$")))
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
                  ;; Set LD_LIBRARY_PATH
                  (setenv "LD_LIBRARY_PATH"
                    (string-join
                     (map dirname
                       (find-files (string-append replicant "/libraries")
                                   "\\.so$"))
                     ":"))
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
              (lambda* (#:key inputs #:allow-other-keys)
                (let* ((srcdir (getcwd))
                       (replicant (string-append srcdir "/bsg_replicant"))
                       (manycore (string-append srcdir "/bsg_manycore"))
                       ;; Baseline cycle counts from the confirmed-working
                       ;; riscv32-elf-gcc-bsg + -fno-inline-functions build
                       (baselines '(("hello"            . 4060602)
                                    ("bsg_scalar_print" . 747918)
                                    ("fib"              . 866466)
                                    ("mul_div"          . 966366)))
                       (threshold 1.20)
                       (failures '()))
                  (format #t "~%========================================~%")
                  (format #t "REGRESSION TEST: binary hash + cycles~%")
                  (format #t "========================================~%")
                  (format #t "~a  ~a  ~a  ~a  ~a~%"
                    (string-pad-right "example" 20)
                    (string-pad-right "sha256[0:16]" 18)
                    (string-pad-right "cycles" 10)
                    (string-pad-right "baseline" 10)
                    "ratio")
                  (for-each
                   (lambda (pair)
                     (let* ((name (car pair))
                            (base (cdr pair))
                            (riscv-bin (string-append manycore
                                         "/software/spmd/" name
                                         "/main.riscv"))
                            (exec-log (string-append replicant
                                        "/examples/spmd/" name
                                        "/exec.log"))
                            ;; Hash binary
                            (hash
                             (if (file-exists? riscv-bin)
                                 (let* ((p (open-pipe*
                                             OPEN_READ "sha256sum"
                                             riscv-bin))
                                        (line (read-line p)))
                                   (close-pipe p)
                                   (if (string? line)
                                       (substring line 0 16)
                                       "missing"))
                                 "missing"))
                            ;; Extract cycle count
                            (cycles
                             (if (file-exists? exec-log)
                                 (let* ((p (open-pipe
                                             (string-append
                                               "grep -oE 'Unfreezing tile t=[0-9]+' "
                                               exec-log
                                               " | head -1 | grep -oE '[0-9]+$'")
                                             OPEN_READ))
                                        (line (read-line p)))
                                   (close-pipe p)
                                   (if (string? line)
                                       (string->number line) #f))
                                 #f))
                            (ratio (if cycles (/ cycles base 1.0) 0.0)))
                       (format #t "~a  ~a  ~a  ~a  ~6,3f~a~%"
                         (string-pad-right name 20)
                         (string-pad-right hash 18)
                         (string-pad-right
                           (if cycles (number->string cycles) "?") 10)
                         (string-pad-right (number->string base) 10)
                         ratio
                         (cond
                           ((not cycles) " (MISSING!)")
                           ((> ratio threshold) " (FAIL: >20% slower)")
                           (else "")))
                       (when (or (not cycles) (> ratio threshold))
                         (set! failures (cons name failures)))))
                   baselines)
                  (format #t "========================================~%")
                  (unless (null? failures)
                    (error "Regression test failed for:" failures)))))
            (replace 'install
              (lambda* (#:key outputs #:allow-other-keys)
                (let* ((out (assoc-ref outputs "out"))
                       (share (string-append out "/share/hammerblade"))
                       (replicant (string-append (getcwd) "/bsg_replicant"))
                       (manycore (string-append (getcwd) "/bsg_manycore"))
                       (examples '("hello" "bsg_scalar_print"
                                   "fib" "mul_div")))
                  (mkdir-p share)
                  (for-each
                   (lambda (name)
                     (let ((log (string-append replicant
                                  "/examples/spmd/" name "/exec.log"))
                           (bin (string-append manycore
                                  "/software/spmd/" name "/main.riscv")))
                       (when (file-exists? log)
                         (copy-file log
                           (string-append share "/" name "-exec.log")))
                       (when (file-exists? bin)
                         (copy-file bin
                           (string-append share "/" name ".riscv")))))
                   examples))))))))
    (synopsis "HammerBlade manycore SPMD examples")
    (description "Builds and runs multiple HammerBlade manycore SPMD examples
using Verilator simulation.  The verilated model is built once (~78 min) and
reused across all examples.  Includes: hello, bsg_scalar_print, fib, mul_div.
Some examples are patched to reduce iteration counts for faster simulation.")))

hammerblade-hello
