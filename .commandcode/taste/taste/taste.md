# Taste
- Grants full access to the repo and the machine and expects the agent to act autonomously — run commands and make decisions without asking for confirmation. Confidence: 0.7
- When starting a build, prefers the agent to first explain/research how an existing comparable product works before diving into implementation. Confidence: 0.55
- Prefers compact, dense layouts — consolidates controls into shared horizontal rows (e.g., volume inline with transport buttons) instead of stacking separate rows, and calls out wasted vertical space as a problem. Confidence: 0.6
- Wants UI controls to fully do what their label says rather than an approximate workaround (e.g., "Lock" should show the real lock screen, not just blank the display). Confidence: 0.6
- Prefers progressive disclosure in interactions: a lightweight hover/preview state that stays stable while inspecting it, with a deliberate follow-up action to open the full view, rather than an immediate jump to the full UI. Confidence: 0.5
- After finishing a build, wants a written explanation covering (a) how it works, (b) what code was written, and (c) how to run it / keep it running on their own laptop. Confidence: 0.8
- Expects the agent to actually build and deploy the change so it is live on their machine (e.g., run `make install` and confirm the installed app is running/updated), not just leave source edits — will push back with "I can't see any changes" otherwise. Confidence: 0.65
- Prefers data/integrations sourced from native macOS/Apple apps already on the machine rather than third-party services or API keys ("use mac apps only"). Confidence: 0.8
