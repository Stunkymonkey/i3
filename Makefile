TOPDIR=$(shell pwd)

include $(TOPDIR)/common.mk

# Depend on the object files of all source-files in src/*.c and on all header files
AUTOGENERATED:=src/cfgparse.tab.c src/cfgparse.yy.c src/cmdparse.tab.c src/cmdparse.yy.c
FILES:=src/ipc.c src/main.c src/log.c src/util.c src/tree.c src/xcb.c src/manage.c src/workspace.c src/x.c src/floating.c src/click.c src/config.c src/handlers.c src/randr.c src/xinerama.c src/con.c src/load_layout.c src/render.c src/window.c src/match.c src/xcursor.c src/resize.c src/sighandler.c src/move.c src/output.c
FILES:=$(FILES:.c=.o)
HEADERS:=$(filter-out include/loglevels.h,$(wildcard include/*.h))

# Recursively generate loglevels.h by explicitly calling make
# We need this step because we need to ensure that loglevels.h will be
# updated if necessary, but we also want to save rebuilds of the object
# files, so we cannot let the object files depend on loglevels.h.
ifeq ($(MAKECMDGOALS),loglevels.h)
#UNUSED:=$(warning Generating loglevels.h)
else
UNUSED:=$(shell $(MAKE) loglevels.h)
endif

# Depend on the specific file (.c for each .o) and on all headers
src/%.o: src/%.c ${HEADERS}
	echo "CC $<"
	$(CC) $(CFLAGS) -DLOGLEVEL="((uint64_t)1 << $(shell awk '/$(shell basename $< .c)/ { print NR; exit 0; }' loglevels.tmp))" -c -o $@ $<

all: src/cfgparse.y.o src/cfgparse.yy.o src/cmdparse.y.o src/cmdparse.yy.o ${FILES}
	echo "LINK i3"
	$(CC) -o i3 $^ $(LDFLAGS)

loglevels.h:
	echo "LOGLEVELS"
	for file in $$(ls src/*.c src/*.y src/*.l | grep -v 'cfgparse.\(tab\|yy\).c'); \
	do \
		echo $$(basename $$file .c); \
	done > loglevels.tmp
	(echo "char *loglevels[] = {"; for file in $$(cat loglevels.tmp); \
	do \
		echo "\"$$file\", "; \
	done; \
	echo "};") > include/loglevels.h;

src/cfgparse.yy.o: src/cfgparse.l src/cfgparse.y.o ${HEADERS}
	echo "LEX $<"
	flex -i -o$(@:.o=.c) $<
	$(CC) $(CFLAGS) -DLOGLEVEL="(1 << $(shell awk '/cfgparse.l/ { print NR }' loglevels.tmp))" -c -o $@ $(@:.o=.c)

src/cmdparse.yy.o: src/cmdparse.l src/cmdparse.y.o ${HEADERS}
	echo "LEX $<"
	flex -Pcmdyy -i -o$(@:.o=.c) $<
	$(CC) $(CFLAGS) -DLOGLEVEL="(1 << $(shell awk '/cmdparse.l/ { print NR }' loglevels.tmp))" -c -o $@ $(@:.o=.c)


src/cfgparse.y.o: src/cfgparse.y ${HEADERS}
	echo "YACC $<"
	bison --debug --verbose -b $(basename $< .y) -d $<
	$(CC) $(CFLAGS) -DLOGLEVEL="(1 << $(shell awk '/cfgparse.y/ { print NR }' loglevels.tmp))" -c -o $@ $(<:.y=.tab.c)

src/cmdparse.y.o: src/cmdparse.y ${HEADERS}
	echo "YACC $<"
	bison -p cmdyy --debug --verbose -b $(basename $< .y) -d $<
	$(CC) $(CFLAGS) -DLOGLEVEL="(1 << $(shell awk '/cmdparse.y/ { print NR }' loglevels.tmp))" -c -o $@ $(<:.y=.tab.c)


install: all
	echo "INSTALL"
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/bin
	$(INSTALL) -d -m 0755 $(DESTDIR)$(SYSCONFDIR)/i3
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/include/i3
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/share/xsessions
	$(INSTALL) -m 0755 i3 $(DESTDIR)$(PREFIX)/bin/
	test -e $(DESTDIR)$(SYSCONFDIR)/i3/config || $(INSTALL) -m 0644 i3.config $(DESTDIR)$(SYSCONFDIR)/i3/config
	$(INSTALL) -m 0644 i3.welcome $(DESTDIR)$(SYSCONFDIR)/i3/welcome
	$(INSTALL) -m 0644 i3.desktop $(DESTDIR)$(PREFIX)/share/xsessions/
	$(INSTALL) -m 0644 include/i3/ipc.h $(DESTDIR)$(PREFIX)/include/i3/
	$(MAKE) TOPDIR=$(TOPDIR) -C i3-msg install
	$(MAKE) TOPDIR=$(TOPDIR) -C i3-input install

dist: distclean
	[ ! -d i3-${VERSION} ] || rm -rf i3-${VERSION}
	[ ! -e i3-${VERSION}.tar.bz2 ] || rm i3-${VERSION}.tar.bz2
	mkdir i3-${VERSION}
	cp DEPENDS GOALS LICENSE PACKAGE-MAINTAINER TODO RELEASE-NOTES-${VERSION} i3.config i3.desktop i3.welcome pseudo-doc.doxygen Makefile i3-${VERSION}
	cp -r src i3-msg include man i3-${VERSION}
	# Only copy toplevel documentation (important stuff)
	mkdir i3-${VERSION}/docs
	find docs -maxdepth 1 -type f ! -name "*.xcf" -exec cp '{}' i3-${VERSION}/docs \;
	# Only copy source code from i3-input
	mkdir i3-${VERSION}/i3-input
	find i3-input -maxdepth 1 -type f \( -name "*.c" -or -name "*.h" -or -name "Makefile" \) -exec cp '{}' i3-${VERSION}/i3-input \;
	sed -e 's/^GIT_VERSION:=\(.*\)/GIT_VERSION:=$(shell echo '${GIT_VERSION}' | sed 's/\\/\\\\/g')/g;s/^VERSION:=\(.*\)/VERSION:=${VERSION}/g' common.mk > i3-${VERSION}/common.mk
	# Pre-generate a manpage to allow distributors to skip this step and save some dependencies
	make -C man
	cp man/*.1 i3-${VERSION}/man/
	tar cfj i3-${VERSION}.tar.bz2 i3-${VERSION}
	rm -rf i3-${VERSION}

clean:
	rm -f src/*.o src/cfgparse.tab.{c,h} src/cfgparse.yy.c loglevels.tmp include/loglevels.h
	$(MAKE) -C docs clean
	$(MAKE) -C man clean
	$(MAKE) TOPDIR=$(TOPDIR) -C i3-msg clean
	$(MAKE) TOPDIR=$(TOPDIR) -C i3-input clean

distclean: clean
	rm -f i3
	$(MAKE) TOPDIR=$(TOPDIR) -C i3-msg distclean
	$(MAKE) TOPDIR=$(TOPDIR) -C i3-input distclean
