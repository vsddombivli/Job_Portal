# v1.1.2 — Vardhaman Sanskar Dham branding

For an existing v1.1/v1.1.1 deployment, replace **app.js**, **styles.css** and **index.html** from the branding ZIP. Keep **config.js**, **core.js**, other source files and all existing Supabase settings. Wait for GitHub Pages to deploy, then hard-refresh the site.

No SQL or Edge Function deployment is needed. This update adds the VSD name/purpose in English and Hindi, a text VSD mark, branded login/help/footer and mobile header. Your existing configured coordinator contact is preserved. An approved official logo can replace the text mark later. demo.html is optional for a standalone preview.

The earlier upgrade instructions below apply only if you have not already installed those versions.

---

# v1.1.1 popup and minimum-experience fix

If you have already installed v1.1 (including migration 002 and the Claude function), replace only **app.js** and **core.js** on GitHub. Keep config.js and all other deployed files. No SQL changes or Edge Function deployment are needed for this patch. Wait for GitHub Pages deployment, then hard-refresh the site. Cross buttons now close every popup. Minimum experience is required in the main job form; explicitly enter 0 for freshers.

The instructions below still apply only if you are upgrading from the original v1.0 installation.

---

# Update your existing website to v1.1

Your existing Supabase database, accounts and current `config.js` are kept. The job save error is a bug in the original SQL function; it is not an email/domain problem.

## 1. Fix SQL and add AI profile fields

Supabase → SQL Editor → New query. Paste and run:

`supabase/migrations/002_job_fix_and_resume_ai.sql`

**Do not rerun 001_initial.sql.** Migration 002 fixes the ambiguous `job_id` conflict target, keeps the RPC signature intact, adds separate skill fields and scan counters, and preserves existing jobs, candidates and application snapshots. It is safe to rerun. Run the entire file including BEGIN/COMMIT.

The SQL change alone fixes saving jobs with your existing frontend. It uses the named `job_contacts_pkey` constraint instead of `ON CONFLICT(job_id)`, and qualifies parameter references as `save_job.job_id`.

## 2. Add the Claude function

In Supabase → Edge Functions, create a new function named exactly:

`resume-analyse`

For the Dashboard editor, replace its starter code with the **entire contents** of:

`supabase/dashboard/resume-analyse.ts`

This file is self-contained. Do not paste only the modular `functions/resume-analyse/index.ts` into a single-file editor, since that version imports companion files.

Turn off the gateway's **Verify JWT / legacy JWT verification** toggle for this function. The code itself validates every JWT with Supabase Auth, checks account activity, mandatory password state and token session version, then checks the scan quota. Deploy.

Alternatively, CLI users can deploy the modular folder from the project root:

```sh
supabase functions deploy resume-analyse
```

## 3. Add secrets

Supabase → Edge Functions → Secrets:

| Secret | Value |
|---|---|
| `ANTHROPIC_API_KEY` | Your Anthropic Console API key |
| `ALLOWED_ORIGIN` | Your website's origin, e.g. `https://YOUR_USERNAME.github.io` |
| `ANTHROPIC_MODEL` | Optional. Defaults to `claude-haiku-4-5-20251001` |

For GitHub Pages, the origin excludes the repository path and has no trailing slash. Keep any origin already needed by account-admin; multiple origins can be comma separated. Supabase's built-in `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` remain server-side.

**Never put the Anthropic key into GitHub, config.js or chat.** No paid API request was made while preparing this update.

## 4. Update GitHub frontend files

Replace these four files in the same directory as your current index.html:

- `app.js`
- `core.js`
- `resume.js`
- `styles.css`

**Keep your existing `config.js` with your real Supabase URL and public anon key.** This update archive deliberately omits config.js and supplies config.example.js for new installations only. Keep index.html and demo.js from v1; equivalent copies are included for completeness. You may replace demo.html if you also publish the demonstration page.

After GitHub Pages finishes deployment, hard-refresh with Ctrl+Shift+R (or clear the site's cached files on mobile). Update all four files together because the new UI uses new exports from core.js/resume.js. The new frontend needs migration 002 before profiles can be saved.

## 5. Verify

- Save a Draft job, then edit it to Published: both must appear in the admin list. Published, unexpired jobs also appear in candidate search. Saving now clears search/location filters so a newly saved job is visible.
- Upload a text PDF, scanned PDF or DOCX; explicitly agree to send it to Anthropic and select Analyse with Claude.
- Check/edit primary skills, supporting skills, suggested roles and experience in the review dialog. Click Use these suggestions, then Save profile. Until Save profile is clicked, no profile update occurs.
- Confirm the revised profile still has its previous work preferences; existing legacy job restrictions and private contacts are retained during edits.
- Try without AI consent and as a temporary-password/paused account: analysis must be blocked. No API key should appear in browser source or network request bodies.
- Optionally run `tests/upgrade-permissions.sql` in SQL Editor. It creates rollback-only fixtures and checks job create/edit status changes, contact upsert, skill synchronisation and the scan quota. It requires both migrations.

## Short forms

Candidate: name, mobile, experience, preferred cities/roles, primary/supporting skills and sharing consent. CV upload is optional. Current/expected CTC are in a collapsed salary section. The private urgent-support checkbox remains available. Redundant current city, disabled email input and unused email frequency/settings inputs are removed; the login email is shown as text. Existing hidden preferences are not erased.

Job: title, company, location, skills, employer email, minimum experience, status, description and verified-source checkbox. Minimum experience is required (0 for freshers). Salary range and closing date are in a collapsed optional section. Category is derived from the title for new jobs; source defaults to company. New jobs default to Office/Full-time with no mandatory skill gate. Existing category, work mode, employment type, mandatory skills and source are preserved; legacy mandatory skill/maximum experience inputs appear in optional details when needed.

## AI limits and behaviour

- Claude API paid usage consumes your existing Anthropic credit. No subscription or domain is required for this feature.
- Max 3 attempts per account per India calendar day; max 100 attempts across the portal/day, enforced atomically in SQL. Failed upstream attempts count too, since usage may already have occurred. Change these limits only in the quota function after reviewing credit usage.
- Max CV upload 2 MB; browser PDF reader allows up to 30 pages. DOCX text sent to Claude is capped at 40,000 characters. Password-protected/malformed files may fail. The API also enforces byte limits; PDF page counting occurs in the browser.
- PDFs are sent to Claude as native PDF content, allowing readable scanned PDFs to be analysed. DOCX is converted to plain text in the browser. No URL-fetching or file lookup endpoints exist in the function.
- AI consent is separate from normal profile/application sharing consent. PDFs can contain personal information, so review Anthropic's applicable terms/retention and obtain candidate consent. DOCX email/phone text is reduced before sending; this is not complete anonymisation.
- Outputs are validated, bounded and explicitly reviewed. Skill names are normalised in English for matching; the summary follows English/Hindi UI selection. Experience is approximate, rounded to the nearest half-year and editable; ambiguous experience is left unknown.
- Primary skills contribute more to matching than supporting skills. Both enter the combined skills list used by existing search/application rules. AI does not approve/reject candidates or infer protected personal characteristics.
- No raw resume or model output is written to an AI log table. Resume storage follows the existing private upload workflow only when the user saves the profile. Saved profile skill lists and confirmed summary are retained. Scan counters store account/day/attempt count only.
- If Claude is unavailable, use Read without AI or manually enter details. Existing profiles and applications remain available.

45 automated checks passed, including mocked provider/auth/quota/error cases and confirmation-before-save flows. Live SQL, real Anthropic calls and browser end-to-end validation need your deployed project.
