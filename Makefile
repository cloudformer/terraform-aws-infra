# make test               mock tests: tests/mock/, every module, no AWS (CI runs this on push / PR)
# make smoke P=<project>  smoke test: apply examples/<project>, run tests/smoke/<project>.py, destroy
#                         needs AWS_PROFILE and the example's TF_VAR_* (e.g. TF_VAR_db_password)
# make release V=vX.Y.Z   test, smoke every project, then tag and push (the Registry picks the tag up)

PROJECTS := $(basename $(notdir $(wildcard tests/smoke/*.py)))

.PHONY: test smoke release

test:
	terraform fmt -check -recursive
	terraform init -input=false -test-directory=tests/mock
	terraform test -test-directory=tests/mock

# destroy runs whatever happens before it; the exit status is the apply / smoke result
smoke:
	@test -n "$(P)" || { echo "usage: make smoke P=<project>  ($(PROJECTS))" >&2; exit 1; }
	terraform -chdir=examples/$(P) init -input=false
	terraform -chdir=examples/$(P) apply -auto-approve -input=false && python3 tests/smoke/$(P).py; \
	  status=$$?; terraform -chdir=examples/$(P) destroy -auto-approve -input=false; exit $$status

# smoke: every project for now; once there are several, only the ones changed since the last tag
release:
	@test -n "$(V)" || { echo "usage: make release V=vX.Y.Z" >&2; exit 1; }
	@git diff --quiet && git diff --cached --quiet || { echo "commit your changes first" >&2; exit 1; }
	$(MAKE) test
	for p in $(PROJECTS); do $(MAKE) smoke P=$$p || exit 1; done
	git tag $(V)
	git push origin $(V)
