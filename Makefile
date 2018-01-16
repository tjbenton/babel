MAKEFLAGS = -j1
FLOW_COMMIT = 622bbc4f07acb77eb1109830c70815f827401d90
TEST262_COMMIT = 1282e842febf418ca27df13fa4b32f7e5021b470

export NODE_ENV = test

# Fix color output until TravisCI fixes https://github.com/travis-ci/travis-ci/issues/7967
export FORCE_COLOR = true

SOURCES = packages codemods

.PHONY: build build-dist watch lint fix clean test-clean test-only test test-ci publish bootstrap

build: clean
	make clean-lib
  # Build babylon before building all other projects
	make build-babylon
	./node_modules/.bin/gulp build
	node ./packages/babel-types/scripts/generateTypeHelpers.js
	# call build again as the generated files might need to be compiled again.
	./node_modules/.bin/gulp build
ifneq ("$(BABEL_ENV)", "cov")
	make build-standalone
	make build-preset-env-standalone
endif

build-babylon:
	cd packages/babylon; \
	./node_modules/.bin/rollup -c

build-standalone:
	./node_modules/.bin/gulp build-babel-standalone

build-preset-env-standalone:
	./node_modules/.bin/gulp build-babel-preset-env-standalone

build-dist: build
	cd packages/babel-polyfill; \
	scripts/build-dist.sh
	cd packages/babel-runtime; \
	node scripts/build-dist.js
	node scripts/generate-babel-types-docs.js

watch: clean
	make clean-lib
	BABEL_ENV=development ./node_modules/.bin/gulp watch

watch-babylon:
	cd packages/babylon; \
	./node_modules/.bin/rollup -c -w

flow:
	./node_modules/.bin/flow check --strip-root

lint:
	./node_modules/.bin/eslint scripts $(SOURCES) *.js --format=codeframe --rulesdir="./scripts/eslint_rules"

fix:
	./node_modules/.bin/eslint scripts $(SOURCES) *.js --format=codeframe --fix --rulesdir="./scripts/eslint_rules"

clean: test-clean
	rm -rf packages/babel-polyfill/browser*
	rm -rf packages/babel-polyfill/dist
	rm -rf coverage
	rm -rf packages/*/npm-debug*

test-clean:
	$(foreach source, $(SOURCES), \
		$(call clean-source-test, $(source)))

test-only:
	./scripts/test.sh
	make test-clean

test: lint test-only

test-ci:
	make bootstrap
	make test-only

test-ci-coverage: SHELL:=/bin/bash
test-ci-coverage:
	BABEL_ENV=cov make bootstrap
	./scripts/test-cov.sh
	bash <(curl -s https://codecov.io/bash) -f coverage/coverage-final.json

bootstrap-flow:
	rm -rf ./build/flow
	mkdir -p ./build
	git clone --branch=master --single-branch --shallow-since=2017-01-01 https://github.com/facebook/flow.git ./build/flow
	cd build/flow && git checkout $(FLOW_COMMIT)

test-flow:
	node scripts/tests/flow/run_babylon_flow_tests.js

test-flow-ci:
	make bootstrap
	make test-flow

test-flow-update-whitelist:
	node scripts/tests/flow/run_babylon_flow_tests.js --update-whitelist

bootstrap-test262:
	rm -rf ./build/test262
	mkdir -p ./build
	git clone --branch=master --single-branch --shallow-since=2017-01-01 https://github.com/tc39/test262.git ./build/test262
	cd build/test262 && git checkout $(TEST262_COMMIT)

test-test262:
	node scripts/tests/test262/run_babylon_test262.js

test-test262-ci:
	make bootstrap
	make test-test262

test-test262-update-whitelist:
	node scripts/tests/test262/run_babylon_test262.js --update-whitelist

publish:
	git pull --rebase
	make clean-lib
	rm -rf packages/babel-runtime/helpers
	rm -rf packages/babel-runtime/core-js
	BABEL_ENV=production make build-dist
	make test
	# not using lerna independent mode atm, so only update packages that have changed since we use ^
	# --only-explicit-updates
	./node_modules/.bin/lerna publish --force-publish=* --exact --skip-temp-tag
	make clean

bootstrap:
	make clean-all
	yarn
	./node_modules/.bin/lerna bootstrap --hoist
	make build
	cd packages/babel-runtime; \
	node scripts/build-dist.js

clean-lib:
	$(foreach source, $(SOURCES), \
		$(call clean-source-lib, $(source)))

clean-all:
	rm -rf node_modules
	rm -rf package-lock.json

	$(foreach source, $(SOURCES), \
		$(call clean-source-all, $(source)))

	make clean

define clean-source-lib
	rm -rf $(1)/*/lib

endef

define clean-source-test
	rm -rf $(1)/*/test/tmp
	rm -rf $(1)/*/test-fixtures.json

endef

define clean-source-all
	rm -rf $(1)/*/lib
	rm -rf $(1)/*/node_modules
	rm -rf $(1)/*/package-lock.json

endef
