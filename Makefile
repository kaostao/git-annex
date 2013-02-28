mans=git-annex.1 git-annex-shell.1
all=git-annex $(mans) docs

GHC?=ghc
GHCMAKE=$(GHC) $(GHCFLAGS) --make
PREFIX=/usr

# Am I typing :make in vim? Do a fast build.
ifdef VIM
all=fast
endif

build: $(all)

# We bypass cabal, and only run the main ghc --make command for a
# fast development built. Note: Does not rebuild C libraries.
fast: dist/caballog
	@$$(grep 'ghc --make' dist/caballog | head -n 1)
	@ln -sf dist/build/git-annex/git-annex git-annex

dist/caballog:
	cabal configure -f"-Production" -O0
	cabal build -v2 | tee $@

Build/SysConfig.hs: configure.hs Build/TestConfig.hs Build/Configure.hs
	cabal configure

git-annex: Build/SysConfig.hs
	cabal build
	ln -sf dist/build/git-annex/git-annex git-annex

git-annex.1: doc/git-annex.mdwn
	./Build/mdwn2man git-annex 1 doc/git-annex.mdwn > git-annex.1
git-annex-shell.1: doc/git-annex-shell.mdwn
	./Build/mdwn2man git-annex-shell 1 doc/git-annex-shell.mdwn > git-annex-shell.1
git-union-merge.1: doc/git-union-merge.mdwn
	./Build/mdwn2man git-union-merge 1 doc/git-union-merge.mdwn > git-union-merge.1

install-mans: $(mans)
	install -d $(DESTDIR)$(PREFIX)/share/man/man1
	install -m 0644 $(mans) $(DESTDIR)$(PREFIX)/share/man/man1

install-docs: docs install-mans
	install -d $(DESTDIR)$(PREFIX)/share/doc/git-annex
	if [ -d html ]; then \
		rsync -a --delete html/ $(DESTDIR)$(PREFIX)/share/doc/git-annex/html/; \
	fi

install: build install-docs
	install -d $(DESTDIR)$(PREFIX)/bin
	install git-annex $(DESTDIR)$(PREFIX)/bin
	ln -sf git-annex $(DESTDIR)$(PREFIX)/bin/git-annex-shell
	runghc Build/InstallDesktopFile.hs $(PREFIX)/bin/git-annex || true

test: git-annex
	./git-annex test

# hothasktags chokes on some tempolate haskell etc, so ignore errors
tags:
	find . | grep -v /.git/ | grep -v /doc/ | egrep '\.hs$$' | xargs hothasktags > tags 2>&1

# If ikiwiki is available, build static html docs suitable for being
# shipped in the software package.
ifeq ($(shell which ikiwiki),)
IKIWIKI=@echo "** ikiwiki not found, skipping building docs" >&2; true
else
IKIWIKI=ikiwiki
endif

docs: $(mans)
	$(IKIWIKI) doc html -v --wikiname git-annex --plugin=goodstuff \
		--no-usedirs --disable-plugin=openid --plugin=sidebar \
		--underlaydir=/dev/null --disable-plugin=shortcut \
		--disable-plugin=smiley \
		--plugin=comments --set comments_pagespec="*" \
		--exclude='news/.*' --exclude='design/assistant/blog/*' \
		--exclude='bugs/*' --exclude='todo/*' --exclude='forum/*'

clean:
	rm -rf tmp dist git-annex $(mans) configure  *.tix .hpc \
		doc/.ikiwiki html dist tags Build/SysConfig.hs

sdist: clean $(mans)
	./Build/make-sdist.sh

# Upload to hackage.
hackage: sdist
	@cabal upload dist/*.tar.gz

LINUXSTANDALONE_DEST=tmp/git-annex.linux
linuxstandalone:
	$(MAKE) git-annex

	rm -rf "$(LINUXSTANDALONE_DEST)"
	mkdir -p tmp
	cp -R standalone/linux "$(LINUXSTANDALONE_DEST)"

	install -d "$(LINUXSTANDALONE_DEST)/bin"
	cp git-annex "$(LINUXSTANDALONE_DEST)/bin/"
	strip "$(LINUXSTANDALONE_DEST)/bin/git-annex"
	ln -sf git-annex "$(LINUXSTANDALONE_DEST)/bin/git-annex-shell"
	zcat standalone/licences.gz > $(LINUXSTANDALONE_DEST)/LICENSE

	runghc Build/Standalone.hs "$(LINUXSTANDALONE_DEST)"
	
	install -d "$(LINUXSTANDALONE_DEST)/git-core"
	(cd "$(shell git --exec-path)" && tar c .) | (cd "$(LINUXSTANDALONE_DEST)"/git-core && tar x)
	install -d "$(LINUXSTANDALONE_DEST)/templates"
	
	touch "$(LINUXSTANDALONE_DEST)/libdirs.tmp"
	for lib in $$(ldd "$(LINUXSTANDALONE_DEST)"/bin/* $$(find "$(LINUXSTANDALONE_DEST)"/git-core/ -type f) | grep -v -f standalone/linux/glibc-libs | grep -v "not a dynamic executable" | egrep '^	' | sed 's/^\t//' | sed 's/.*=> //' | cut -d ' ' -f 1 | sort | uniq); do \
		dir=$$(dirname "$$lib"); \
		install -d "$(LINUXSTANDALONE_DEST)/$$dir"; \
		echo "$$dir" >> "$(LINUXSTANDALONE_DEST)/libdirs.tmp"; \
		cp "$$lib" "$(LINUXSTANDALONE_DEST)/$$dir"; \
		if [ -L "$lib" ]; then \
			link=$$(readlink -f "$$lib"); \
			cp "$$link" "$(LINUXSTANDALONE_DEST)/$$(dirname "$$link")"; \
		fi; \
	done
	sort "$(LINUXSTANDALONE_DEST)/libdirs.tmp" | uniq > "$(LINUXSTANDALONE_DEST)/libdirs"
	rm -f "$(LINUXSTANDALONE_DEST)/libdirs.tmp"

	cd tmp && tar czf git-annex-standalone-$(shell dpkg --print-architecture).tar.gz git-annex.linux

OSXAPP_DEST=tmp/build-dmg/git-annex.app
OSXAPP_BASE=$(OSXAPP_DEST)/Contents/MacOS
osxapp:
	$(MAKE) git-annex

	rm -rf "$(OSXAPP_DEST)"
	install -d tmp/build-dmg
	cp -R standalone/osx/git-annex.app "$(OSXAPP_DEST)"

	install -d "$(OSXAPP_BASE)"
	cp git-annex "$(OSXAPP_BASE)"
	strip "$(OSXAPP_BASE)/git-annex"
	ln -sf git-annex "$(OSXAPP_BASE)/git-annex-shell"
	gzcat standalone/licences.gz > $(OSXAPP_BASE)/LICENSE
	cp $(OSXAPP_BASE)/LICENSE tmp/build-dmg/LICENSE.txt

	runghc Build/Standalone.hs $(OSXAPP_BASE)

	(cd "$(shell git --exec-path)" && tar c .) | (cd "$(OSXAPP_BASE)" && tar x)
	install -d "$(OSXAPP_BASE)/templates"

	runghc Build/OSXMkLibs.hs $(OSXAPP_BASE)
	rm -f tmp/git-annex.dmg
	hdiutil create -size 640m -format UDRW -srcfolder tmp/build-dmg \
		-volname git-annex -o tmp/git-annex.dmg
	rm -f tmp/git-annex.dmg.bz2
	bzip2 --fast tmp/git-annex.dmg

# Cross compile for Android.
# Uses https://github.com/neurocyte/ghc-android
android:
	cabal configure
# cabal cannot cross compile with custom build type, so workaround
	sed -i 's/Build-type: Custom/Build-type: Simple/' git-annex.cabal
	$$HOME/.ghc/android-14/arm-linux-androideabi-4.7/arm-linux-androideabi/bin/cabal configure -f'Android Assistant -Pairing -Webapp'
	$(MAKE) git-annex
	sed -i 's/Build-type: Simple/Build-type: Custom/' git-annex.cabal

androidapp:
	$(MAKE) android
	$(MAKE) -C standalone/android
	mkdir -p tmp
	cp standalone/android/source/term/bin/Term-debug.apk tmp/git-annex.apk

.PHONY: git-annex tags
