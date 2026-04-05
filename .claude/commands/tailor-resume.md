---
description: Tailor resume.yaml for a job posting URL and render a 2-page PDF
argument-hint: <job-url-or-file-path>
---

Run the full Resume-as-Code pipeline for the provided job posting.

Steps:
1. Run `make resume URL=$ARGUMENTS` and report the output.
2. If the audit fails, show the violations from `build/audit_report.txt` and ask whether to retry with a stricter prompt.
3. If compilation fails due to page overflow, show the suggested cuts and ask for confirmation before running `make render` again.
4. When complete, confirm the PDF is at `build/resume.pdf` and show the page count.

Do not modify `data/resume.yaml` without explicit user confirmation.
