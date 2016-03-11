# Set an output prefix, which is the local directory if not specified.
PREFIX?=$(shell pwd)

# Used to populate version variable in main package.
VERSION=$(shell git describe --match 'v[0-9]*' --dirty='.m' --always)

# Project packages.
PACKAGES=$(shell go list ./... | grep -v /vendor/)

GO_LDFLAGS=-ldflags "-X `go list ./version`.Version=$(VERSION)"

.PHONY: clean all fmt vet lint errcheck complexity build binaries test setup checkprotos coverage ci check
.DEFAULT: default

check: fmt vet lint errcheck complexity

all: check build binaries test

ci: check build binaries checkprotos coverage

AUTHORS: .mailmap .git/HEAD
	git log --format='%aN <%aE>' | sort -fu > $@

# This only needs to be generated by hand when cutting full releases.
version/version.go:
	./version/version.sh > $@

${PREFIX}/bin/swarmctl: version/version.go $(shell find . -type f -name '*.go')
	@echo "🐳 $@"
	@go build  -o $@ ${GO_LDFLAGS}  ${GO_GCFLAGS} ./cmd/swarmctl

${PREFIX}/bin/swarmd: version/version.go $(shell find . -type f -name '*.go')
	@echo "🐳 $@"
	@go build  -o $@ ${GO_LDFLAGS}  ${GO_GCFLAGS} ./cmd/swarmd

${PREFIX}/bin/protoc-gen-gogoswarm: version/version.go $(shell find . -type f -name '*.go')
	@echo "🐳 $@"
	@go build  -o $@ ${GO_LDFLAGS}  ${GO_GCFLAGS} ./cmd/protoc-gen-gogoswarm

setup:
	@echo "🐳 $@"
	# TODO(stevvooe): Install these from the vendor directory
	@go get -u github.com/golang/lint/golint
	@go get -u github.com/fzipp/gocyclo
	@go get -u github.com/kisielk/errcheck
	@go get -u github.com/golang/mock/mockgen

generate: ${PREFIX}/bin/protoc-gen-gogoswarm
	@echo "🐳 $@"
	@PATH=${PREFIX}/bin:${PATH} go generate -x ${PACKAGES}

checkprotos: generate
	@echo "🐳 $@"
	@test -z "$$(git status --short | grep ".pb.go" | tee /dev/stderr)" || \
		(echo "👹 please run 'make generate' when making changes to proto files" && false)

# Depends on binaries because vet will silently fail if it can't load compiled
# imports
vet: binaries
	@echo "🐳 $@"
	@go vet ${PACKAGES}

fmt:
	@echo "🐳 $@"
	@test -z "$$(gofmt -s -l . | grep -v vendor/ | grep -v ".pb.go$$" | tee /dev/stderr)" || \
		(echo "👹 please format Go code with 'gofmt -s'" && false)
	@test -z "$$(find . -path ./vendor -prune -o -name '*.proto' -type f -exec grep -Hn -e "^ " {} \; | tee /dev/stderr)" || \
		(echo "👹 please indent proto files with tabs only" && false)
	@test -z "$$(find . -path ./vendor -prune -o -name '*.proto' -type f -exec grep -Hn "id = " {} \; | grep -v gogoproto.customname | tee /dev/stderr)" || \
		(echo "👹 id fields in proto files must have a gogoproto.customname set" && false)
	@test -z "$$(find . -path ./vendor -prune -o -name '*.proto' -type f -exec grep -Hn "Meta meta = " {} \; | grep -v '(gogoproto.nullable) = false' | tee /dev/stderr)" || \
		(echo "👹 meta fields in proto files must have option (gogoproto.nullable) = false" && false)


lint:
	@echo "🐳 $@"
	@test -z "$$(golint ./... | grep -v vendor/ | grep -v ".pb.go:" | grep -v ".mock.go" | tee /dev/stderr)"

errcheck:
	@echo "🐳 $@"
	@test -z "$$(golint ./... | grep -v vendor/ | grep -v ".pb.go:" | grep -v ".mock.go" | tee /dev/stderr)"

complexity:
	@echo "🐳 $@"
	@test -z "$$(gocyclo -over 15 . | grep -v vendor/ | grep -v ".pb.go:" | tee /dev/stderr)"

build:
	@echo "🐳 $@"
	@go build -tags "${DOCKER_BUILDTAGS}" -v ${GO_LDFLAGS} ${PACKAGES}

test:
	@echo "🐳 $@"
	@go test -parallel 8 -race -tags "${DOCKER_BUILDTAGS}" ${PACKAGES}

binaries: ${PREFIX}/bin/swarmctl ${PREFIX}/bin/swarmd ${PREFIX}/bin/protoc-gen-gogoswarm
	@echo "🐳 $@"

clean:
	@echo "🐳 $@"
	@rm -rf "${PREFIX}/bin/swarmctl" "${PREFIX}/bin/swarmd" "${PREFIX}/bin/protoc-gen-gogoswarm"

coverage: 
	@echo "🐳 $@"
	@for pkg in ${PACKAGES}; do \
		go test -tags "${DOCKER_BUILDTAGS}" -test.short -coverprofile="../../../$$pkg/coverage.txt" -covermode=count $$pkg; \
	done
