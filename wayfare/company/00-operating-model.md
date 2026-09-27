# Wayfare Studio: Operating Model

Wayfare is built by a small, simulated iPhone app studio. Each role is an
agent with its own brief. Roles hand work to each other through the documents
in this repo. **You (the owner) are the client and final approver.** You
review, give feedback, and the studio iterates.

## Org chart

| Role | Owns | Primary artifacts |
|---|---|---|
| Founder / CTO (orchestrator) | Scope, technical decisions, integration, final merge | `company/00-operating-model.md`, `company/decisions.md`, `docs/api-contract.md` |
| Product Strategist | Problem, audience, MVP scope, roadmap, App Store positioning | `company/01-product-brief.md` |
| UX Designer | Flows, information architecture, screen specs, edge cases | `company/02-ux-spec.md` |
| Visual / Brand Designer | Design system: color, type, iconography, motion, app icon brief | `company/03-design-system.md` |
| iOS Engineer | Native SwiftUI app in `ios/` | `ios/**`, `company/04-ios-notes.md` |
| Backend Engineer | Cloudflare Worker API, D1 schema, push, cron, AI import in `backend/` | `backend/**`, `company/05-backend-notes.md` |
| QA and Release | Test plan, contract conformance, App Store review readiness | `company/06-qa-report.md`, `company/07-release-checklist.md` |

## How work flows

1. **Contract first.** The CTO writes `docs/api-contract.md`. iOS and backend
   both build against it. Any change to it has to be made in the contract
   first and noted in `company/decisions.md`.
2. **Product → Design → Engineering → QA**, with every handoff in writing.
   Downstream roles may push back. They add an entry to the "Open questions"
   section of the upstream doc instead of silently diverging.
3. **Owner review gate.** Each iteration ends with `company/REVIEW.md`: what
   changed, what we decided on your behalf, and the specific questions we need
   you to answer.

## How to give feedback

Reply in plain language: "the day view is too dense", "I want packing lists
in v1", "drop sharing". Or answer the numbered questions in `REVIEW.md`. The
CTO turns your feedback into tickets for the right roles, and the next
iteration ships a new `REVIEW.md`.
