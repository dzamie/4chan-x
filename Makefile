ifdef ComSpec
  BIN := $(subst /,\,node_modules/.bin/)
  RMDIR := -rmdir /s /q
  RM := -del
  CAT = type $(subst /,\,$1) > $(subst /,\,$2)
  MKDIR = -mkdir $(subst /,\,$@)
  QUOTE = $(patsubst %,"%",$1)
else
  BIN := node_modules/.bin/
  RMDIR := rm -rf
  RM := rm -rf
  CAT = cat $1 > $2
  MKDIR = mkdir -p $@
  QUOTE = $(patsubst %,'%',$1)
endif
CP = $(call CAT,$<,$@)

npgoals := clean cleanrel cleanweb cleanfull withtests tag $(foreach i,1 2 3 4,bump$(i)) beta stable web update updatehard
ifneq "$(filter $(npgoals) npm-shrinkwrap.json,$(MAKECMDGOALS))" ""
.NOTPARALLEL :
endif

coffee := $(BIN)coffee -c --no-header
coffee_deps := node_modules/coffee-script/package.json
template := node tools/template.js
template_deps := package.json tools/template.js node_modules/lodash.template/package.json node_modules/esprima/package.json

# read name meta_name meta_distBranch meta_awsBucket
$(eval $(shell node tools/pkgvars.js))

# must be read in when needed to prevent out-of-date version
version = $(shell node -p "JSON.parse(require('fs').readFileSync('version.json')).version")

capitalized = $(filter-out a,$(foreach x,$1,$(subst a $(x),,$(sort a $(x)))))

parts := \
 globals config css platform classes \
 $(sort $(call capitalized, \
  $(subst src/,,$(wildcard src/*)) \
 )) \
 main

# remove extension when sorting so X.coffee comes before X.Y.coffee
sources_part = \
 $(subst !c,.coffee,$(subst !j,.js,$(sort $(subst .coffee,!c,$(subst .js,!j, \
  $(wildcard src/$1/*.coffee src/$1/*.js))))))

sources := $(foreach p,$(parts),$(call sources_part,$(p)))

part_of = $(patsubst src/%/,%,$(dir $1))

uses_tests_enabled := \
 src/classes/Post.coffee \
 src/General/Build.Test.coffee \
 src/Linkification/Linkify.coffee \
 src/Miscellaneous/Keybinds.coffee \
 src/Monitoring/Unread.coffee \
 src/main/Main.coffee

imports_src/globals/globals.js := \
 version.json
imports_src/config/Config.coffee := \
 src/Archive/archives.json
imports_src/css/CSS.js := \
 node_modules/font-awesome/package.json
imports_src/Monitoring/Favicon.coffee := \
 src/meta/icon128.png

imports = \
 $(filter-out %.coffee %.js,$(wildcard $(dir $1)*.*)) \
 $(wildcard $(basename $1)/*.*) \
 $(if $(filter $(uses_tests_enabled),$1),.tests_enabled) \
 $(imports_$1)

dests_platform = $(addprefix tmp/,$(subst /,-,$(patsubst src/%,%.js,$(subst platform,platform_$2,$1))))

dests_of = $(sort $(call dests_platform,$1,crx) $(call dests_platform,$1,userscript))

dests := $(foreach s,$(sources),$(call dests_of,$(s)))

updates := $(subst tmp/,.events/,$(dests))

pieces = \
 tmp/LICENSE \
 tmp/meta-newline.js \
 tmp/meta-fbegin.js \
 tmp/meta-newline.js \
 tmp/declaration.js \
 tmp/meta-newline.js \
 $(foreach s,$(sources),$(call dests_platform,$(s),$1)) \
 tmp/meta-fend.js

crx_contents := script.js eventPage.js icon16.png icon48.png icon128.png manifest.json

release := \
 $(foreach f, \
  $(foreach c,. -beta.,$(name)$(c)crx updates$(c)xml $(name)$(c)user.js $(name)$(c)meta.js) \
  $(name)-noupdate.crx \
  $(name)-noupdate.user.js \
  $(name).zip \
 ,builds/$(f))

script := $(foreach f,$(filter-out %.crx %.zip,$(release)),test$(f)) $(foreach t,crx crx-beta crx-noupdate,$(foreach f,$(crx_contents),testbuilds/$(t)/$(f)))

crx := $(foreach f,$(filter %.crx %.zip,$(release)),test$(f))

default : script jshint install

all : default release

.events .events2 tmp testbuilds builds :
	$(MKDIR)

ifneq "$(wildcard npm-shrinkwrap.json)" ""

.events/npm : npm-shrinkwrap.json | .events
	npm install
	echo -> $@

node_modules/%/package.json : .events/npm
	$(if $(wildcard $@),,npm install && echo -> $<)

else

node_modules/%/package.json :
	npm install $*

endif

.tests_enabled :
	echo false> .tests_enabled

.events/declare : $(wildcard src/*/*.coffee) tools/declare.js | .events tmp
	node tools/declare.js
	echo -> $@

tmp/declaration.js : .events/declare
	$(if $(wildcard $@),,node tools/declare.js && echo -> $<)

define check_source
$$(subst tmp/,.events/,$(call dests_of,$1)) : $1 $$(call imports,$1) | .events
	echo -> $$(call QUOTE,$$@)
endef

$(foreach s,$(sources),$(eval $(call check_source,$(subst $$,$$$$,$(s)))))

.events/compile : $(updates) $(template_deps) $(coffee_deps) tools/chain.js
	node tools/chain.js $(call QUOTE, \
	  $(subst .events/,tmp/, \
	   $(if $(filter-out $(updates),$?), \
	    $(updates), \
	    $(filter $(updates),$?) \
	   ) \
	  ) \
	 )
	echo -> $@

$(dests) : .events/compile
	$(if $(wildcard $@),, \
	 node tools/chain.js $(filter-out $(wildcard $(dests)),$(dests)) \
	 && echo -> $< \
	)

tmp/eventPage.js : src/meta/eventPage.coffee $(coffee_deps) | tmp
	$(coffee) -o tmp src/meta/eventPage.coffee

tmp/LICENSE : LICENSE tools/newlinefix.js | tmp
	node tools/newlinefix.js $< $@

tmp/meta-%.js : src/meta/%.js tools/newlinefix.js | tmp
	node tools/newlinefix.js $< $@

define rules_channel

testbuilds/crx$1 :
	$$(MKDIR)

testbuilds/crx$1/script.js : $$(call pieces,crx) | testbuilds/crx$1 .events/compile
	$$(call CAT,$$(call QUOTE,$$(call pieces,crx)),$$@)

testbuilds/crx$1/eventPage.js : tmp/eventPage.js | testbuilds/crx$1
	$$(CP)

testbuilds/crx$1/icon%.png : src/meta/icon%.png | testbuilds/crx$1
	$$(CP)

testbuilds/crx$1/manifest.json : src/meta/manifest.json version.json $(template_deps) | testbuilds/crx$1
	$(template) $$< $$@ type=crx channel=$1

testbuilds/updates$1.xml : src/meta/updates.xml version.json $(template_deps) | testbuilds/crx$1
	$(template) $$< $$@ type=crx channel=$1

testbuilds/$(name)$1.crx.zip : \
 $(foreach f,$(crx_contents),testbuilds/crx$1/$(f)) \
 package.json version.json tools/zip-crx.js node_modules/jszip/package.json
	node tools/zip-crx.js $1

testbuilds/$(name)$1.crx : testbuilds/$(name)$1.crx.zip package.json tools/sign.js node_modules/crx/package.json
	node tools/sign.js $1

testbuilds/$(name)$1.meta.js : src/meta/metadata.js src/meta/icon48.png version.json $(template_deps) | testbuilds
	$(template) $$< $$@ type=userscript channel=$1

testbuilds/$(name)$1.user.js : testbuilds/$(name)$1.meta.js tmp/meta-newline.js $$(call pieces,userscript) | .events/compile
	$$(call CAT,testbuilds/$(name)$1.meta.js tmp/meta-newline.js $$(call QUOTE,$$(call pieces,userscript)),$$@)

endef

$(eval $(call rules_channel,))
$(eval $(call rules_channel,-beta))
$(eval $(call rules_channel,-noupdate))

testbuilds/$(name).zip : testbuilds/$(name)-noupdate.crx.zip
	$(CP)

builds/% : testbuilds/% | builds
	$(CP)

test.html : README.md template.jst tools/markdown.js node_modules/marked/package.json node_modules/lodash.template/package.json
	node tools/markdown.js

index.html : test.html
	$(CP)

tmp/.jshintrc : src/meta/jshint.json tmp/declaration.js src/globals/globals.js $(template_deps) | tmp
	$(template) $< $@

.events/jshint : $(dests) tmp/.jshintrc node_modules/jshint/package.json
	$(BIN)jshint $(call QUOTE, \
	 $(if $(filter-out $(dests),$?), \
	  $(dests), \
	  $(filter $(dests),$?) \
	 ) \
	)
	echo -> $@

install.json :
	echo {}> $@

.events/install : $(script) install.json tools/install.js | .events
	node tools/install.js
	echo -> $@

.events/CHANGELOG : version.json | .events node_modules/dateformat/package.json
	node tools/updcl.js
	echo -> $@

dist :
	git worktree add $@ $(meta_distBranch)

$(wildcard dist/* dist/*/*) : dist
	@

distready : dist $(wildcard dist/* dist/*/*)
	cd dist && git checkout $(meta_distBranch)
	cd dist && git pull

.events2/push-git : .git/refs/heads .git/refs/tags $(wildcard .git/refs/heads/* .git/refs/tags/*) | .events2 distready
	git push origin --tags -f
	git push origin --all
	echo -> $@

.events2/push-web : .git/refs/heads/$(meta_distBranch) | .events2 distready
	aws s3 cp builds/ s3://$(meta_awsBucket)/builds/ --recursive --exclude "*" --include "*.js" --cache-control "max-age=600" --content-type "application/javascript; charset=utf-8"
	aws s3 cp builds/ s3://$(meta_awsBucket)/builds/ --recursive --exclude "*" --include "*.crx" --cache-control "max-age=600" --content-type "application/x-chrome-extension"
	aws s3 cp builds/ s3://$(meta_awsBucket)/builds/ --recursive --exclude "*" --include "*.xml" --cache-control "max-age=600" --content-type "text/xml; charset=utf-8"
	aws s3 cp builds/ s3://$(meta_awsBucket)/builds/ --recursive --exclude "*" --include "*.zip" --cache-control "max-age=600" --content-type "application/zip"
	aws s3 cp img/ s3://$(meta_awsBucket)/img/ --recursive --cache-control "max-age=600"
	aws s3 cp index.html s3://$(meta_awsBucket) --cache-control "max-age=600" --content-type "text/html; charset=utf-8"
	aws s3 cp web.css s3://$(meta_awsBucket) --cache-control "max-age=600" --content-type "text/css; charset=utf-8"
	echo -> $@

.events2/push-store : .git/refs/tags/stable | .events2 distready node_modules/webstore-upload/package.json
	node tools/webstore.js
	echo -> $@

.SECONDARY :

.PHONY: default all distready script crx release jshint install push captchas $(npgoals)

script : $(script)

crx : $(crx)

release : $(release)

jshint : .events/jshint

install : .events/install

push : .events2/push-git .events2/push-web .events2/push-store

captchas : redirect.html $(template_deps)
	$(template) redirect.html captchas.html url="$(url)"
	aws s3 cp captchas.html s3://$(meta_awsBucket) --cache-control "max-age=0" --content-type "text/html; charset=utf-8"

clean :
	$(RMDIR) tmp testbuilds .events
	$(RM) .tests_enabled

cleanrel : clean
	$(RMDIR) builds

cleanweb :
	$(RM) test.html captchas.html

cleanfull : clean cleanweb
	$(RMDIR) .events2 dist node_modules
	$(RM) npm-shrinkwrap.json
	git worktree prune

withtests :
	echo true> .tests_enabled
	-$(MAKE)
	echo false> .tests_enabled

ifneq "$(wildcard npm-shrinkwrap.json)" ""

tag : .events/CHANGELOG jshint release
	git commit -am "Release $(meta_name) v$(version)."
	git tag -a $(version) -m "$(meta_name) v$(version)."

else

npm-shrinkwrap.json : src/meta/npm-shrinkwrap.json
	$(CP)

endif

$(foreach i,1 2 3 4,bump$(i)) : cleanrel
	$(MAKE) npm-shrinkwrap.json
	npm install
	node tools/bump.js $(subst bump,,$@)
	$(MAKE) all
	$(MAKE) tag

beta : distready
	git tag -af beta -m "$(meta_name) v$(version)."
	cd dist && git merge --no-commit -s ours beta
	cd dist && git checkout beta "builds/*-beta.*" LICENSE CHANGELOG.md img .gitignore .gitattributes
	cd dist && git commit -am "Move $(meta_name) v$(version) to beta channel."

stable : distready
	git push . HEAD:bstable
	git tag -af stable -m "$(meta_name) v$(version)."
	cd dist && git merge --no-commit -s ours stable
	cd dist && git checkout stable "builds/$(name).*" builds/updates.xml
	cd dist && git commit -am "Move $(meta_name) v$(version) to stable channel."

web : index.html distready
	-git commit -am "Build web page."
	cd dist && git merge --no-commit -s ours master
	cd dist && git checkout master README.md index.html web.css img
	cd dist && git commit -am "Update web page."

update :
	npm install --save-dev $(shell node tools/unpinned.js)
	npm install
	npm shrinkwrap --dev
	$(call CAT,npm-shrinkwrap.json,src/meta/npm-shrinkwrap.json)

updatehard :
	npm install --save-dev $(shell node tools/unpinned.js latest)
	npm install
	npm shrinkwrap --dev
	$(call CAT,npm-shrinkwrap.json,src/meta/npm-shrinkwrap.json)
