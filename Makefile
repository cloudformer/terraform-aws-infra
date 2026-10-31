# make test                      mock tests: tests/mock/, every module, no AWS (CI runs this on push / PR)
# make smoke PROJECT=<project>   smoke test: apply examples/<project> on this repo's code, run
#                                tests/smoke/<project>.py, destroy. Needs AWS_PROFILE and the example's
#                                TF_VAR_* (e.g. TF_VAR_db_password)
# make release PROJECT=<project> VERSION=vX.Y.Z
#                                test (all mock tests), smoke the project being released, then tag and push
#                                (the Registry picks the tag up)

PROJECTS := $(basename $(notdir $(wildcard tests/smoke/*.py)))

.PHONY: test smoke release

test:
	terraform fmt -check -recursive
	terraform init -input=false -test-directory=tests/mock
	terraform test -test-directory=tests/mock

# examples/ call the released module; smoke deploys a copy in .smoke/<project>/ whose source is this repo's
# modules/<project> (version line dropped), so a release tests what it is about to publish. The copy keeps its
# state between runs. destroy runs whatever happens before it; the exit status is the apply / smoke result.
smoke:
	@test -n "$(PROJECT)" || { echo "usage: make smoke PROJECT=<project>  ($(PROJECTS))" >&2; exit 1; }
	mkdir -p .smoke/$(PROJECT)
	sed -E 's|^( *)source *= *"cloudformer/infra/aws//modules/$(PROJECT)".*|\1source = "../../modules/$(PROJECT)"|; /^ *version *= *"/d' \
	  examples/$(PROJECT)/main.tf > .smoke/$(PROJECT)/main.tf
	terraform -chdir=.smoke/$(PROJECT) init -input=false
	terraform -chdir=.smoke/$(PROJECT) apply -auto-approve -input=false && python3 tests/smoke/$(PROJECT).py; \
	  status=$$?; terraform -chdir=.smoke/$(PROJECT) destroy -auto-approve -input=false; exit $$status

# one project per release; smoke only when its modules/, examples/ or tests/smoke/ files changed (CLAUDE.md, Tests)
release:
	@test -n "$(PROJECT)" -a -n "$(VERSION)" || { echo "usage: make release PROJECT=<project> VERSION=vX.Y.Z  ($(PROJECTS))" >&2; exit 1; }
	@git diff --quiet && git diff --cached --quiet || { echo "commit your changes first" >&2; exit 1; }
	$(MAKE) test
	$(MAKE) smoke PROJECT=$(PROJECT)
	git tag $(VERSION)
	git push origin $(VERSION)
