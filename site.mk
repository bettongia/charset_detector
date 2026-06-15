# BEGIN: Documentation site tasks
SITE_DIR = site
DOCS_DIR = docs

# Extract fields from pubspec.yaml for header template substitution
PKG_NAME    := $(shell awk '/^name:/{print $$2}'        pubspec.yaml)
PKG_DESC    := $(shell awk '/^description:/{print $$2}' pubspec.yaml)
PKG_VERSION := $(shell awk '/^version:/{print $$2}'     pubspec.yaml)
REPO_URL    := $(shell awk '/^repository:/{print $$2}'  pubspec.yaml)
_HEADER := $(SITE_DIR)/_header.html
_INDEX  := $(SITE_DIR)/_index.md

doc_site: $(SITE_DIR)/favicon.ico $(SITE_DIR)/bettongia-$(DOCS_DIR).css $(SITE_DIR)/index.html $(SITE_DIR)/spec.html $(SITE_DIR)/roadmap.html  $(SITE_DIR)/api/index.html coverage
.PHONY: site

$(SITE_DIR):
	mkdir -p $@

# Generate header with $repo$ replaced by the pubspec.yaml repository URL.
# include-before-body content is verbatim in pandoc (not template-processed),
# so substitution must happen before pandoc runs.
$(_HEADER): $(DOCS_DIR)/template/header.html pubspec.yaml | $(SITE_DIR)
	sed -e 's|\$$name\$$|$(PKG_NAME)|g' \
	    -e 's|\$$version\$$|$(PKG_VERSION)|g' \
	    -e 's|\$$repo\$$|$(REPO_URL)|g' \
	    $< > $@

$(_INDEX): $(DOCS_DIR)/index.md pubspec.yaml | $(SITE_DIR)
	sed -e 's|\$$name\$$|$(PKG_NAME)|g' \
	    -e 's|\$$version\$$|$(PKG_VERSION)|g' \
	    -e 's|\$$repo\$$|$(REPO_URL)|g' \
		-e 's|\$$description\$$|$(REPO_DESC)|g' \
	    $< > $@

$(SITE_DIR)/bettongia-$(DOCS_DIR).css: | $(SITE_DIR)
	cp $(DOCS_DIR)/template/bettongia-$(DOCS_DIR).css $(SITE_DIR)/bettongia-$(DOCS_DIR).css

$(SITE_DIR)/favicon.ico: $(DOCS_DIR)/template/favicon.ico  | $(SITE_DIR)
	cp $(DOCS_DIR)/template/favicon.ico $(SITE_DIR)/favicon.ico

$(SITE_DIR)/index.html: $(_INDEX) $(DOCS_DIR)/.pandoc $(_HEADER) | $(SITE_DIR)
	pandoc --defaults="$(DOCS_DIR)/.pandoc" $(_INDEX) README.md -o "$(SITE_DIR)/index.html";

$(SITE_DIR)/spec.html: $(DOCS_DIR)/spec/*.md $(DOCS_DIR)/.pandoc $(_HEADER) | $(SITE_DIR)
	pandoc --defaults="$(DOCS_DIR)/.pandoc" --mathml $(DOCS_DIR)/spec/*.md -o "$(SITE_DIR)/spec.html";

$(SITE_DIR)/roadmap.html: $(DOCS_DIR)/roadmap/*.md $(DOCS_DIR)/.pandoc $(_HEADER) | $(SITE_DIR)
	pandoc --defaults="$(DOCS_DIR)/.pandoc" $(DOCS_DIR)/roadmap/v*.md -o "$(SITE_DIR)/roadmap.html";

$(SITE_DIR)/api/index.html: lib/** test/** | $(SITE_DIR)
	dart doc -o $(SITE_DIR)/api/index.html

# END: Documentation site tasks
