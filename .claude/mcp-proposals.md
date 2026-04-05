# MCP Proposals for Resume-as-Code

These MCPs would enhance the pipeline with richer company research and market data.
None are required for core resume tailoring — they extend the `/company-research` command.

## Immediately Useful (available today)

### Tavily MCP (already installed globally)
Already available in your Claude Code setup. Used by `/company-research`.
- `tavily_search` — quick factual lookup (Glassdoor scores, funding news)
- `tavily_research` — deep multi-source synthesis (company culture, interview prep)
- `tavily_extract` — extract content from a specific Glassdoor or Blind URL

No additional setup needed.

## High Value (worth adding)

### Brave Search MCP
- More coverage of Blind and niche tech community forums vs Tavily
- Install: `npx @modelcontextprotocol/server-brave-search`
- Requires: Brave Search API key (free tier: 2000 queries/month)
- Add to `.claude/settings.json` under `mcpServers`

### LinkedIn MCP (unofficial)
- Scrape job postings directly from LinkedIn URLs
- Useful when Jina Reader struggles with LinkedIn auth walls
- No official MCP — use `mcp-server-playwright` with a LinkedIn session cookie
- Caution: violates LinkedIn ToS; use only for personal job search

## Nice to Have

### Crunchbase MCP
- Authoritative funding data, investor lists, founding team history
- Relevant for: startup roles, assessing company financial health
- No public MCP — can be approximated with Tavily searching Crunchbase

### Levels.fyi Scraper
- Compensation data for specific companies and levels
- No MCP — use `tavily_extract` with a levels.fyi URL

## Glassdoor & Blind (No Official MCP)

Neither Glassdoor nor Blind has an official MCP or public API. The recommended approach:
1. Use Tavily to search `site:glassdoor.com <company> reviews` for aggregated sentiment
2. Use Tavily to search `site:teamblind.com <company>` for anonymous employee posts
3. For salary data, search `glassdoor <company> <role> salary` or `levels.fyi <company>`

These searches work reliably within `/company-research` without any additional MCP setup.

## Proposed `make research` Target

Add this to the Makefile for company research as a separate pipeline step:

```makefile
COMPANY ?=
ROLE    ?= ML Engineer

research: guard-COMPANY check-deps | $(BUILD_DIR)
	@echo "Researching: $(COMPANY) | Role: $(ROLE)"
	@claude \
		-p "Research $(COMPANY) thoroughly for a candidate applying for the role of $(ROLE). Cover: company overview, recent news (last 6 months), Glassdoor/Blind culture reviews, interview process, salary range, and any red flags. Search the web. Format as a concise report." \
		--max-turns 3 \
		--output-format text \
		--model $(MODEL) \
		> $(BUILD_DIR)/research_$(COMPANY).md
	@echo ""
	@echo "Research saved: $(BUILD_DIR)/research_$(COMPANY).md"
	@cat $(BUILD_DIR)/research_$(COMPANY).md
```

Usage: `make research COMPANY="Anthropic" ROLE="Senior ML Engineer"`
