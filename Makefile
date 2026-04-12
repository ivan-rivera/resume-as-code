# ============================================================
# Resume-as-Code (RAC) Pipeline
# Usage:  make resume URL=https://company.com/jobs/123
# ============================================================

SHELL       := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c

# ── Inputs ────────────────────────────────────────────────
URL         ?=
MODEL       ?= claude-sonnet-4-6
MAX_RETRIES := 2


# ── Paths ─────────────────────────────────────────────────
RESUME_YAML   := data/resume.yaml
TYPST_TPL     := resume.typ
BUILD_DIR     := build

HASH_FILE     := $(BUILD_DIR)/.input_hash
JOB_MD        := $(BUILD_DIR)/job_posting.md
PATCH_YAML    := $(BUILD_DIR)/llm_patch.yaml
TAILORED_YAML := $(BUILD_DIR)/tailored.yaml
AUDIT_REPORT  := $(BUILD_DIR)/audit_report.txt
OUTPUT_PDF    := $(BUILD_DIR)/resume.pdf

TAILOR_SYS    := prompts/tailor_system.txt
AUDIT_SYS     := prompts/audit_system.txt
CORRECT_SYS   := prompts/correct_system.txt
TRIM_SYS      := prompts/trim_system.txt
FIT_SYS       := prompts/fit_system.txt
INTEL_SYS     := prompts/intel_system.txt

FIT_ANALYSIS  := $(BUILD_DIR)/fit_analysis.txt
COMPANY_INTEL := $(BUILD_DIR)/company_intel.txt
JOB_REPORT    := $(BUILD_DIR)/job_report.md

APPLY_PATCH   := python3 scripts/apply_patch.py

# ── Targets ───────────────────────────────────────────────
.PHONY: resume fetch tailor audit render clean test compile-test help report \
        check-deps _cache_check

# ── Entry point ───────────────────────────────────────────
resume: guard-URL check-deps _cache_check $(OUTPUT_PDF)
	@echo ""
	@echo "Done: $(OUTPUT_PDF)"

# ── Dependency guard ──────────────────────────────────────
check-deps:
	@for bin in typst claude curl python3 pdfinfo; do \
		command -v $$bin >/dev/null 2>&1 || { \
			echo "ERROR: '$$bin' not found."; \
			echo "  typst   -> brew install typst"; \
			echo "  claude  -> install Claude Code CLI"; \
			echo "  pdfinfo -> brew install poppler"; \
			exit 1; \
		}; \
	done
	@python3 -c "import yaml" 2>/dev/null || \
		(echo "ERROR: pyyaml missing. Run: pip install pyyaml"; exit 1)

# ── Cache invalidation ────────────────────────────────────
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

_cache_check: | $(BUILD_DIR)
	@url_hash=$$(echo -n "$(URL)" | shasum -a 256 | cut -d' ' -f1); \
	yaml_hash=$$(shasum -a 256 $(RESUME_YAML) | cut -d' ' -f1); \
	current_hash=$$(echo -n "$$url_hash$$yaml_hash" | shasum -a 256 | cut -d' ' -f1); \
	stored_hash=$$(cat $(HASH_FILE) 2>/dev/null || echo ""); \
	if [ "$$current_hash" = "$$stored_hash" ] && [ -f "$(TAILORED_YAML)" ]; then \
		echo "[cache] Hit -- skipping fetch/tailor/audit (inputs unchanged)"; \
		echo "$$current_hash" > $(BUILD_DIR)/.current_hash; \
	else \
		echo "[cache] Miss -- running full pipeline"; \
		rm -f $(JOB_MD) $(PATCH_YAML) $(TAILORED_YAML) $(AUDIT_REPORT) $(OUTPUT_PDF) $(HASH_FILE); \
		echo "$$current_hash" > $(BUILD_DIR)/.current_hash; \
	fi

# ── Step 1: Fetch job posting ─────────────────────────────
$(JOB_MD): | $(BUILD_DIR)
	@if [ -f "$(TAILORED_YAML)" ]; then \
		echo "[1/4] Fetch skipped (cache hit)"; exit 0; \
	fi
	@echo "[1/4] Fetching job posting..."
	@if [ -f "$(URL)" ]; then \
		cp "$(URL)" $@; \
		echo "      Copied local file"; \
	else \
		curl -s \
			-H "Accept: text/markdown" \
			-H "X-Return-Format: markdown" \
			"https://r.jina.ai/$(URL)" > $@; \
	fi
	@test -s $@ || { \
		echo "ERROR: Empty job posting -- URL may be auth-gated or invalid."; \
		echo "Tip: save the job description to a .txt file and pass URL=path/to/file.txt"; \
		rm -f $@; exit 1; \
	}
	@echo "      Extracted $$(wc -w < $@) words"

fetch: guard-URL _cache_check $(JOB_MD)

# ── Step 2: LLM tailoring ─────────────────────────────────
$(PATCH_YAML): $(JOB_MD) | $(BUILD_DIR)
	@if [ -f "$(TAILORED_YAML)" ]; then \
		echo "[2/4] Tailor skipped (cache hit)"; exit 0; \
	fi
	@echo "[2/4] Tailoring resume (~30s)..."
	@{ \
		echo '<JOB_POSTING>'; \
		cat $(JOB_MD); \
		echo '</JOB_POSTING>'; \
		echo ''; \
		echo '<RESUME>'; \
		cat $(RESUME_YAML); \
		echo '</RESUME>'; \
		echo ''; \
		echo 'Produce a YAML patch following your system prompt rules.'; \
	} > $(BUILD_DIR)/tailor_prompt.txt
	@claude -p "$$(cat $(BUILD_DIR)/tailor_prompt.txt)" \
		--system-prompt-file $(TAILOR_SYS) \
		--max-turns 1 \
		--no-session-persistence \
		--output-format text \
		--model $(MODEL) \
		| awk '/^```/{if(p)exit} /^patches:/{p=1} p' \
		> $(PATCH_YAML)
	@test -s $(PATCH_YAML) || { echo "ERROR: LLM returned empty output"; rm -f $(PATCH_YAML); exit 1; }

$(TAILORED_YAML): $(PATCH_YAML) | $(BUILD_DIR)
	@if [ -f "$@" ] && [ "$@" -nt "$(PATCH_YAML)" ]; then exit 0; fi
	@$(APPLY_PATCH) $(RESUME_YAML) $(PATCH_YAML) $@

tailor: guard-URL _cache_check $(TAILORED_YAML)

# ── Step 3: Fraud audit ───────────────────────────────────
$(AUDIT_REPORT): $(TAILORED_YAML) | $(BUILD_DIR)
	@if [ -f "$@" ] && [ "$@" -nt "$(TAILORED_YAML)" ]; then \
		echo "[3/4] Audit skipped (cache hit)"; exit 0; \
	fi
	@echo "[3/4] Running fraud audit..."
	@{ \
		echo '<ORIGINAL>'; \
		cat $(RESUME_YAML); \
		echo '</ORIGINAL>'; \
		echo ''; \
		echo '<TAILORED>'; \
		cat $(TAILORED_YAML); \
		echo '</TAILORED>'; \
	} > $(BUILD_DIR)/audit_prompt.txt
	@claude -p "$$(cat $(BUILD_DIR)/audit_prompt.txt)" \
		--system-prompt-file $(AUDIT_SYS) \
		--max-turns 1 \
		--no-session-persistence \
		--output-format text \
		--model $(MODEL) \
		| awk '/^(PASS|WARN|FAIL)/{p=1} p' \
		> $(AUDIT_REPORT)
	@result=$$(head -1 $(AUDIT_REPORT) | tr -d '[:space:]'); \
	if [ "$$result" = "PASS" ]; then \
		echo "      Audit: PASS"; \
	elif [ "$$result" = "WARN" ]; then \
		echo "      Audit: WARN -- auto-correcting minor wording issues..."; \
		{ \
			echo '<ORIGINAL>'; \
			cat $(RESUME_YAML); \
			echo '</ORIGINAL>'; \
			echo ''; \
			echo '<TAILORED>'; \
			cat $(TAILORED_YAML); \
			echo '</TAILORED>'; \
			echo ''; \
			echo '<VIOLATIONS>'; \
			tail -n +2 $(AUDIT_REPORT); \
			echo '</VIOLATIONS>'; \
		} > $(BUILD_DIR)/correct_prompt.txt; \
		claude -p "$$(cat $(BUILD_DIR)/correct_prompt.txt)" \
			--system-prompt-file $(CORRECT_SYS) \
			--max-turns 1 \
			--no-session-persistence \
			--output-format text \
			--model $(MODEL) \
			| awk '/^(personal:|summary:|languages:|skills:|experience:|education:|awards_and_publications:|extra_qualifications:|interests:)/{p=1} p' \
			> $(TAILORED_YAML).tmp \
		&& mv $(TAILORED_YAML).tmp $(TAILORED_YAML); \
		echo "      Corrected."; \
	else \
		echo ""; \
		echo "ERROR: Fraud audit FAILED. Fabricated content detected:"; \
		cat $(AUDIT_REPORT); \
		echo ""; \
		echo "Review build/tailored.yaml and build/llm_patch.yaml for details."; \
		rm -f $(AUDIT_REPORT); \
		exit 1; \
	fi

audit: $(AUDIT_REPORT)

# ── Step 4: Compile + page check ─────────────────────────
$(OUTPUT_PDF): $(AUDIT_REPORT) | $(BUILD_DIR)
	@echo "[4/4] Compiling PDF..."
	@retries=0; \
	current_yaml=$(TAILORED_YAML); \
	while true; do \
		if typst compile $(TYPST_TPL) $@ 2>/dev/null; then \
			pages=$$(pdfinfo $@ 2>/dev/null | awk '/^Pages:/{print $$2}' || echo "0"); \
			if [ "$$pages" -le 2 ]; then \
				echo "      Compiled: $$pages page(s)"; \
				cat $(BUILD_DIR)/.current_hash > $(HASH_FILE); \
				break; \
			fi; \
			retries=$$((retries + 1)); \
			if [ $$retries -gt $(MAX_RETRIES) ]; then \
				echo ""; \
				echo "ERROR: Resume is $$pages pages after $(MAX_RETRIES) trim attempts."; \
				echo "Suggested manual cuts (in order):"; \
				echo "  1. extra_qualifications section"; \
				echo "  2. interests section"; \
				echo "  3. GetYourGuide bullets -> title only"; \
				echo "  4. Bank of New Zealand bullets -> 2 max"; \
				echo "  5. Zalando bullets -> 1 max"; \
				exit 1; \
			fi; \
			echo "      Over limit ($$pages pages) -- trimming (attempt $$retries/$(MAX_RETRIES))..."; \
			{ \
				echo '<TAILORED_YAML>'; \
				cat $$current_yaml; \
				echo '</TAILORED_YAML>'; \
				echo ''; \
				echo "The resume compiles to $$pages pages. Trim to fit 2 pages."; \
			} > $(BUILD_DIR)/trim_prompt.txt; \
			claude -p "$$(cat $(BUILD_DIR)/trim_prompt.txt)" \
				--system-prompt-file $(TRIM_SYS) \
				--max-turns 1 \
				--no-session-persistence \
				--output-format text \
				--model $(MODEL) \
				| awk '/^(personal:|summary:|languages:|skills:|experience:|education:|awards_and_publications:|extra_qualifications:|interests:)/{p=1} p' \
				> $${current_yaml}.tmp \
			&& mv $${current_yaml}.tmp $$current_yaml; \
		else \
			echo "ERROR: typst compile failed. Check resume.typ syntax."; \
			exit 1; \
		fi; \
	done

render: $(TAILORED_YAML)
	@test -f $(AUDIT_REPORT) || { echo "ERROR: Run 'make audit' first"; exit 1; }
	@$(MAKE) --no-print-directory $(OUTPUT_PDF)

# ── Utilities ─────────────────────────────────────────────
# ── Job intelligence report ───────────────────────────────
report: guard-URL check-deps $(JOB_REPORT)
	@echo ""
	@echo "Report: $(JOB_REPORT)"
	@echo ""
	@cat $(JOB_REPORT)

$(JOB_REPORT): $(JOB_MD) | $(BUILD_DIR)
	@echo "[1/2] Analysing resume fit..."
	@{ \
		echo '<JOB_POSTING>'; \
		cat $(JOB_MD); \
		echo '</JOB_POSTING>'; \
		echo ''; \
		echo '<RESUME>'; \
		cat $(RESUME_YAML); \
		echo '</RESUME>'; \
	} > $(BUILD_DIR)/fit_prompt.txt
	@claude -p "$$(cat $(BUILD_DIR)/fit_prompt.txt)" \
		--system-prompt-file $(FIT_SYS) \
		--max-turns 1 \
		--no-session-persistence \
		--output-format text \
		--model $(MODEL) \
		> $(FIT_ANALYSIS)
	@test -s $(FIT_ANALYSIS) || { echo "ERROR: fit analysis returned empty"; rm -f $(FIT_ANALYSIS); exit 1; }
	@is_recruiter=$$(grep '^RECRUITER:' $(FIT_ANALYSIS) | awk '{print tolower($$2)}' | tr -d '[:space:]'); \
	company=$$(grep '^COMPANY:' $(FIT_ANALYSIS) | sed 's/^COMPANY:[[:space:]]*//'); \
	role=$$(grep '^ROLE:' $(FIT_ANALYSIS) | sed 's/^ROLE:[[:space:]]*//'); \
	echo "      $$company — $$role (recruiter=$$is_recruiter)"; \
	if [ "$$is_recruiter" = "true" ]; then \
		echo "[2/2] 3rd-party recruiter detected — skipping company intel"; \
		printf '**Culture & Sentiment**\n3rd-party recruiter posting — company not identified, intel unavailable.\n\n**Recent News**\nN/A\n' > $(COMPANY_INTEL); \
	else \
		echo "[2/2] Researching $$company..."; \
		printf 'Company: %s\nRole: %s\n' "$$company" "$$role" > $(BUILD_DIR)/intel_prompt.txt; \
		claude -p "$$(cat $(BUILD_DIR)/intel_prompt.txt)" \
			--system-prompt-file $(INTEL_SYS) \
			--max-turns 15 \
			--no-session-persistence \
			--output-format text \
			--model $(MODEL) \
			> $(COMPANY_INTEL); \
	fi
	@test -s $(COMPANY_INTEL) || { echo "ERROR: company intel returned empty"; rm -f $(COMPANY_INTEL); exit 1; }
	@awk '/^---/{p=1; next} p' $(FIT_ANALYSIS) > $(BUILD_DIR)/fit_content.txt
	@{ \
		echo "# Job Intelligence Report"; \
		echo ""; \
		echo "## Resume Fit"; \
		cat $(BUILD_DIR)/fit_content.txt; \
		echo ""; \
		echo "## Company Intel"; \
		cat $(COMPANY_INTEL); \
	} > $(JOB_REPORT)


clean:
	rm -rf $(BUILD_DIR)
	@echo "Cache cleared."

compile-test:
	@mkdir -p $(BUILD_DIR)
	@cp $(RESUME_YAML) $(TAILORED_YAML)
	@typst compile $(TYPST_TPL) $(OUTPUT_PDF)
	@echo "compile-test passed: $(OUTPUT_PDF)"

test:
	python3 -m pytest tests/ -v

guard-%:
	@if [ -z "$($*)" ]; then \
		echo "ERROR: $* is required. Example: make resume URL=https://..."; \
		exit 1; \
	fi

help:
	@echo "Resume-as-Code Pipeline"
	@echo ""
	@echo "Usage:"
	@echo "  make resume URL=<url>      Full pipeline (fetch -> tailor -> audit -> PDF)"
	@echo "  make fetch  URL=<url>      Extract job posting only"
	@echo "  make tailor URL=<url>      Fetch + tailor (no PDF)"
	@echo "  make audit                 Fraud-check current build/tailored.yaml"
	@echo "  make render                Recompile PDF (skips LLM steps)"
	@echo "  make report URL=<url>      Fit analysis + company intel + news (no PDF)"
	@echo "  make compile-test          Compile PDF from unmodified resume.yaml (no LLM)"
	@echo "  make clean                 Wipe build cache"
	@echo "  make test                  Run unit tests"
	@echo ""
	@echo "Options:"
	@echo "  URL=path/to/file.txt  Pass a local file instead of a URL"
	@echo "  MODEL=claude-opus-4-6 Override the Claude model"
