ifeq ($(findstring clean,$(MAKECMDGOALS)),)
# Makefile.config exports cause recursive invocations to configure to fail
ifeq ($(findstring win-compilers win-zips win-builds,$(MAKECMDGOALS)),)
-include Makefile.config
endif
endif

all: opam-lib opam opam-admin opam-installer
	@

ALWAYS:
	@

opam-lib opam opam-admin opam-installer all: ALWAYS

#backwards-compat
compile with-ocamlbuild: all
	@
install-with-ocamlbuild: install
	@
libinstall-with-ocamlbuild: libinstall
	@

byte:
	$(MAKE) all USE_BYTE=true

src/%:
	$(MAKE) -C src $*

# Disable this rule if the only build targets are cold, download-ext or configure
# to suppress error messages trying to build Makefile.config
ifneq ($(or $(filter-out cold compiler download-ext lib-pkg configure,$(MAKECMDGOALS)),$(filter own-goal,own-$(MAKECMDGOALS)goal)),)
%:
	$(MAKE) -C src $@
endif

lib-ext:
	$(MAKE) -C src_ext lib-ext

lib-pkg:
	$(MAKE) -j -C src_ext lib-pkg

download-ext:
	$(MAKE) -C src_ext archives

download-pkg:
	$(MAKE) -C src_ext archives-pkg

clean-ext:
	$(MAKE) -C src_ext distclean

clean:
	$(MAKE) -C src $@
	$(MAKE) -C doc $@
	rm -f opam-*.zip

distclean: clean clean-ext
	rm -rf autom4te.cache bootstrap
	rm -f META .merlin config.log Makefile.config config.status src/core/opamVersion.ml src/core/opamCoreConfig.ml aclocal.m4

OPAMINSTALLER_FLAGS = --prefix $(DESTDIR)$(prefix)
OPAMINSTALLER_FLAGS += --mandir $(DESTDIR)$(mandir)

# With ocamlfind, prefer to install to the standard directory rather
# than $(prefix) if there are no overrides
ifdef OCAMLFIND
ifndef DESTDIR
ifneq ($(OCAMLFIND),no)
    LIBINSTALL_DIR ?= $(shell $(OCAMLFIND) printconf destdir)
endif
endif
endif

ifneq ($(LIBINSTALL_DIR),)
    OPAMINSTALLER_FLAGS += --libdir $(LIBINSTALL_DIR)
endif

opam-lib.install:
	$(MAKE) -C src ../opam-lib.install

libinstall: opam-lib.install opam-admin.top
	$(if $(wildcard src_ext/lib/*),$(error Installing the opam libraries is incompatible with embedding the dependencies. Run 'make clean-ext' and try again))
	src/opam-installer $(OPAMINSTALLER_FLAGS) opam-lib.install

install:
	src/opam-installer $(OPAMINSTALLER_FLAGS) opam.install

libuninstall:
	src/opam-installer -u $(OPAMINSTALLER_FLAGS) opam-lib.install

uninstall:
	src/opam-installer -u $(OPAMINSTALLER_FLAGS) opam.install

.PHONY: tests tests-local tests-git
tests: opam opam-admin opam-check
	$(MAKE) -C tests all

# tests-local, tests-git
tests-%: opam opam-admin opam-check
	$(MAKE) -C tests $*

.PHONY: doc
doc: all
	$(MAKE) -C doc

.PHONY: man man-html
man man-html: opam opam-admin opam-installer
	$(MAKE) -C doc $@

configure: configure.ac m4/*.m4
	aclocal -I m4
	autoconf

release-tag:
	git tag -d latest || true
	git tag -a latest -m "Latest release"
	git tag -a $(version) -m "Release $(version)"

fastlink:
	@$(foreach b,opam opam-admin opam-installer opam-check,\
	   ln -sf ../_obuild/$b/$b.asm src/$b;)
	@$(foreach l,core format solver repository state client,\
	   $(foreach e,a cma cmxa,ln -sf ../_obuild/opam-$l/opam-$l.$e src/opam-$l.$e;)\
	   ln -sf $(addprefix ../../,\
	        $(foreach e,o cmo cmx cmxs cmi cmt cmti,$(wildcard _obuild/opam-$l/*.$e)))\
	      src/$l/;)

rmartefacts: ALWAYS
	@rm -f $(addprefix src/, opam opam-admin opam-installer opam-check)
	@$(foreach l,core format solver repository state client,\
	   $(foreach e,a cma cmxa,rm -f src/opam-$l.$e;)\
	   $(foreach e,o cmo cmx cmxs cmi cmt cmti,rm -f $(wildcard src/$l/*.$e);))

prefast: rmartefacts src/client/opamGitVersion.ml src/state/opamScript.ml src/core/opamCompat.ml src/core/opamCompat.mli
	@ocp-build -init

fast: prefast
	@ocp-build
	@$(MAKE) fastlink

fastclean: rmartefacts
	@ocp-build -clean 2>/dev/null || ocp-build clean 2>/dev/null

ifeq ($(OCAML_PORT),)
ifneq ($(COMSPEC),)
ifeq ($(shell which gcc 2>/dev/null),)
OCAML_PORT=auto
endif
endif
endif

.PHONY: compiler cold
compiler:
	./shell/bootstrap-ocaml.sh $(OCAML_PORT)

win-compilers: bootstrap/Makefile
	rm -rf bootstrap/{msvc,msvc64,mingw,mingw64,source,archives} bootstrap/source
	$(MAKE) -C bootstrap -j win-compilers

bootstrap/Makefile:
	mkdir -p bootstrap
	ln -sf ../Makefile.win-compilers bootstrap/Makefile

JOBS=$(shell expr 4 \* $(NUMBER_OF_PROCESSORS))

win-builds: bootstrap/Makefile
	rm -rf bootstrap/{msvc,msvc64,mingw,mingw64}/{src,src_ext,opam} bootstrap/source
	$(MAKE) -C bootstrap -j $(JOBS) win-builds

win-zips: bootstrap/Makefile
	$(MAKE) -C bootstrap -j $(JOBS) win-zips

cold: compiler
	env PATH="$$PATH:`pwd`/bootstrap/ocaml/bin" ./configure $(CONFIGURE_ARGS)
	env PATH="$$PATH:`pwd`/bootstrap/ocaml/bin" $(MAKE) lib-ext
	env PATH="$$PATH:`pwd`/bootstrap/ocaml/bin" $(MAKE)
