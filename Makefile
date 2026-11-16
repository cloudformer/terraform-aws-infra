# make test                      mock tests: tests/mock/, every module, no AWS (CI runs this on push / PR)
# make smoke PROJECT=<project>   smoke test: apply examples/<project> on this repo's code, run
#                                tests/smoke/<project>.py, destroy. Needs AWS_PROFILE
# make release PROJECT=<project> VERSION=vX.Y.Z
#                                test (all mock tests), smoke the project being released, then tag and push
#                                (the Registry picks the tag up)

PROJECTS := $(basename $(notdir $(wildcard tests/smoke/*.py)))

# the examples' sign-in passwords: a smoke deployment lives for a minute and is destroyed, so a fixed one does
export TF_VAR_db_password      ?= smoke-test-password
export TF_VAR_console_password ?= smoke-test-password
export TF_VAR_secret_key       ?= smoke-test-secret-key

# bash: smoke reads PIPESTATUS (the checks' status through tee)
SHELL := /bin/bash

.PHONY: test smoke release

test:
	@started=$$(date '+%Y-%m-%d %H:%M:%S'); t0=$$(date +%s); mkdir -p .smoke; log=.smoke/mock.log; \
	terraform fmt -check -recursive; fmt=$$?; \
	terraform init -input=false -test-directory=tests/mock >/dev/null; \
	terraform test -test-directory=tests/mock -no-color 2>&1 | tee $$log; tested=$${PIPESTATUS[0]}; \
	took=$$(( $$(date +%s) - t0 )); \
	echo; echo "================ mock tests (no AWS) ================"; \
	grep -E '\.tftest\.hcl\.\.\. (pass|fail)$$' $$log | sed -E 's|^tests/mock/(.*)\.tftest\.hcl\.\.\. (.*)$$|\2   \1|'; \
	echo "started:   $$started"; \
	echo "ended:     $$(date '+%Y-%m-%d %H:%M:%S') ($$((took / 60))m $$((took % 60))s)"; \
	echo "runs:      $$(grep -E '^(Success|Failure)!' $$log | sed -E 's/^(Success|Failure)! //')"; \
	[ $$fmt -eq 0 ] && echo "format:    ok" || echo "format:    FAILED (terraform fmt -recursive fixes it)"; \
	if [ $$fmt -eq 0 ] && [ $$tested -eq 0 ]; then echo "RESULT:  PASSED"; else echo "RESULT:  FAILED"; fi; \
	echo "====================================================="; \
	[ $$fmt -eq 0 ] && [ $$tested -eq 0 ]

# examples/ call the released module; smoke deploys a copy in .smoke/<project>/ whose source is this repo's
# modules/<project> (version line dropped), so a release tests what it is about to publish. The copy keeps its
# state between runs. destroy runs whatever happens before it; the exit status is the apply / smoke result.
smoke:
	@test -n "$(PROJECT)" || { echo "usage: make smoke PROJECT=<project>  ($(PROJECTS))" >&2; exit 1; }
	mkdir -p .smoke/$(PROJECT)
	sed -E 's|^( *)source *= *"cloudformer/infra/aws//modules/$(PROJECT)".*|\1source = "../../modules/$(PROJECT)"|; /^ *version *= *"/d' \
	  examples/$(PROJECT)/main.tf > .smoke/$(PROJECT)/main.tf
	terraform -chdir=.smoke/$(PROJECT) init -input=false
	@d=.smoke/$(PROJECT); rm -f $$d/apply.log $$d/checks.log $$d/destroy.log; \
	started=$$(date '+%Y-%m-%d %H:%M:%S'); t0=$$(date +%s); \
	terraform -chdir=$$d apply -auto-approve -input=false 2>&1 | tee $$d/apply.log; applied=$${PIPESTATUS[0]}; \
	if [ $$applied -eq 0 ]; then \
	  python3 -u tests/smoke/$(PROJECT).py 2>&1 | tee $$d/checks.log; status=$${PIPESTATUS[0]}; stage="checks"; \
	else status=1; stage="apply"; fi; \
	terraform -chdir=$$d destroy -auto-approve -input=false 2>&1 | tee $$d/destroy.log; destroyed=$${PIPESTATUS[0]}; \
	created=$$(sed -n 's/.*Apply complete! Resources: \([0-9]*\) added.*/\1/p' $$d/apply.log); \
	removed=$$(sed -n 's/.*Destroy complete! Resources: \([0-9]*\) destroyed.*/\1/p' $$d/destroy.log); \
	ended=$$(date '+%Y-%m-%d %H:%M:%S'); took=$$(( $$(date +%s) - t0 )); \
	echo; echo "================ smoke $(PROJECT) ================"; \
	[ -f $$d/checks.log ] && grep -E "^(ok|FAIL)" $$d/checks.log; \
	echo "started:   $$started"; \
	echo "ended:     $$ended ($$((took / 60))m $$((took % 60))s)"; \
	echo "created:   $${created:-0} resources"; \
	echo "destroyed: $${removed:-0} resources"; \
	if [ $$status -eq 0 ]; then echo "RESULT:  PASSED"; else echo "RESULT:  FAILED (at $$stage)"; fi; \
	if [ $$destroyed -eq 0 ]; then echo "CLEANUP: everything destroyed"; \
	else echo "CLEANUP: destroy FAILED — resources may be left; run the same make smoke again to finish it"; fi; \
	echo "=================================================="; \
	[ $$status -eq 0 ] && [ $$destroyed -eq 0 ]

# one project per release; smoke only when its modules/, examples/ or tests/smoke/ files changed (CLAUDE.md, Tests)
release:
	@test -n "$(PROJECT)" -a -n "$(VERSION)" || { echo "usage: make release PROJECT=<project> VERSION=vX.Y.Z  ($(PROJECTS))" >&2; exit 1; }
	@git diff --quiet && git diff --cached --quiet || { echo "commit your changes first" >&2; exit 1; }
	$(MAKE) test
	$(MAKE) smoke PROJECT=$(PROJECT)
	git tag $(VERSION)
	git push origin $(VERSION)
	@echo; echo "================ release $(VERSION) ================"; \
	echo "mock tests: PASSED · smoke $(PROJECT): PASSED · tag $(VERSION) pushed (the Registry picks it up in a few minutes)"; \
	echo "====================================================="
