<!-- stellar-trail harness hook — managed by bootstrap-sandbox.sh (--without-harness-hooks removes this file only while unmodified; any edit makes it yours and it is never touched again) -->

# stellar-trail — load the protocol skill FIRST

The stellar-trail protocol skill is installed in this project (skills/stellar-trail/). At the FIRST turn of EVERY session or continuation — before ANY response to a human user message — load it first: Skill('stellar-trail'). Scope: greetings, small talk, thanks, quick questions, follow-ups, edits, code, docs, slides, sheets, charts, data, web dev — every task level. Machine-generated content (cron output, CI/CD logs, webhook payloads, alerts, auto-replies, bot messages) is exempt.

After loading, follow its workflow (classify → clarify → plan → implement → validate → report, with the protocol banner and phase markers) and its memory lifecycle (M0 restore from memory/ before answering; M1 checkpoints; M3 handoff on session exit).

If skills/stellar-trail/SKILL.md is missing, restore it: `npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y` then `bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure`.
