# Sadharmik Jobs — v1.1.1

A mobile-friendly English/Hindi portal for the Jain community, with admin-created accounts, private CVs, job matching and applications. Email delivery remains disabled by design.

**Already deployed v1? Follow UPGRADE.md. Do not rerun the base migration or replace your working config.js.**

## Preview and hosting

Open `demo.html` for a single-file interactive demo with fictional records. Changes last for the current tab; refresh resets them. Claude calls and password changes are disabled in the demo. Its local CV reader works without AI. Do not use personal documents in a shared demonstration.

The production frontend is plain HTML/CSS/JavaScript, needs no build step and runs on GitHub Pages or another static HTTPS host. Python is only an optional local web server:

```sh
python3 -m http.server 8080
```

Open http://localhost:8080. Copy config.example.js to config.js for a new installation. Do not open production index.html directly with file:// because it imports JavaScript modules.

## Features

- Admin-approved accounts with temporary passwords, mandatory change at first login, current-password verification, admin-assisted resets and pause/reactivate.
- Short candidate form: name, mobile, experience, preferred city/role, primary/supporting skills, optional current/expected CTC, private urgent-support flag and consent. Candidates without a CV can still apply.
- Short job form: title, company, location, skills, private employer email, status, description and verified-source confirmation. Minimum experience is required in the main job form (enter 0 for freshers); salary and closing date are collapsed optional fields. Existing advanced settings are preserved on edit.
- Claude résumé analysis through a protected Edge Function: primary/supporting skills, suitable titles, experience and a short summary, with explicit consent and editable review before saving. Native PDF support can read legible scanned pages; DOCX uses extracted text. Local keyword extraction remains a fallback.
- Matching considers skills (primary skills weighted more), roles, location/work mode, experience, salary and employment type. Age and employment gaps do not reduce scores. Candidates can browse every published, unexpired job; only explicit mandatory skills gate applying.
- Atomic, duplicate-protected applications retain submitted profile/job/CV snapshots. Later profile edits cannot alter submitted snapshots. Candidate withdrawal and admin review/status updates are supported.
- Private CV links, RLS, column privileges, backend-only role controls, rotated session versions, reset/pause session revocation and administrative activity logs.
- No employer account is required. Admin coordinates manually until email is enabled. Normal staff mailboxes and application email delivery are separate future work.

## New Supabase installation

1. Use a new Supabase project, separate from any donation-receipt app.
2. Run `supabase/migrations/001_initial.sql` once in SQL Editor.
3. Run `supabase/migrations/002_job_fix_and_resume_ai.sql`. It is the upgrade script and is rerunnable. It adds AI-related profile columns/counters and fixes the original ambiguous job_id SQL reference.
4. Enable email/password Auth, disable public sign-ups, and set minimum password length to 12. Do not use email invitations for the initial no-email workflow. Admin creates confirmed accounts after verifying ownership/eligibility externally.
5. In Authentication → Users, create (not invite) the first admin account with a temporary password and auto-confirm enabled. Promote that exact UUID:

```sql
update auth.users
set raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)
  || jsonb_build_object('approved',true,'access_version',gen_random_uuid()::text)
where id='YOUR-ADMIN-UUID';

update public.profiles p
set role='admin',active=true,must_change_password=true,
 full_name='Community Admin',access_version=u.raw_app_meta_data->>'access_version'
from auth.users u where p.id=u.id and p.id='YOUR-ADMIN-UUID';
```

6. Deploy `account-admin` and `resume-analyse` from their Edge Function folders. CLI users can run:

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy account-admin
supabase functions deploy resume-analyse
```

Dashboard users: paste the complete `supabase/functions/account-admin/index.ts` into account-admin, and the complete **supabase/dashboard/resume-analyse.ts** into resume-analyse. The dashboard version of resume-analyse is self-contained; the modular index.ts alone is not. Disable gateway legacy JWT verification for these functions; both functions perform their own authenticated-user and account/session checks. supabase/config.toml specifies the same setting for CLI deployment.

7. In Supabase Secrets, set `ANTHROPIC_API_KEY` and `ALLOWED_ORIGIN` (e.g. https://YOUR_USERNAME.github.io, no repository path or trailing slash). The optional `ANTHROPIC_MODEL` defaults to claude-haiku-4-5-20251001. Multiple allowed origins may be comma-separated. Supabase supplies SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY inside hosted functions. Never put private keys in GitHub or frontend code.
8. Copy config.example.js to config.js and enter your Supabase URL, public legacy anon key and coordinator contact. The pinned SDK supports that public key; never use a service-role/secret key here.
9. Deploy only `index.html`, `styles.css`, `app.js`, `core.js`, `demo.js`, `resume.js` and your configured `config.js` to your public site. Source SQL, tests and backend setup files do not need to be published with the frontend.
10. Run the rollback SQL checks and complete live checks below before onboarding real candidates.

After promotion, log out and sign in fresh. The first admin and every new candidate must change the temporary password, then sign in with the new password. Admins can create candidates through the app once ready. Creating the account counts as community approval.

## Security and data

- Browser calls cannot edit role, active/approval/password/session flags. Candidate data is visible only to its owner and authorised admins. Employer contacts are stored in an admin-only table.
- Application creation checks consent, mobile, required skills, role and job state on the server, and uses a unique candidate/job constraint. Storage uploads use immutable UUID paths, and submitted CV references cannot be deleted through candidate permissions.
- Reset/pause actions rotate session metadata and revoke old refresh sessions. A partially failed reset stays restricted; repeat the reset with a different temporary password after resolving the error.
- CVs are private, at most 2 MB. Signed download links expire after 60 seconds; downloaded copies cannot be recalled.
- AI consent is explicit and separate. PDF files are sent to Anthropic, including any personal data in them. DOCX email/phone text is reduced before transmission, not fully anonymised. Confirm applicable provider terms and your retention policy. No CV contents or model responses are logged by the function.
- AI attempts are capped at 3 per account/day and 100 community-wide/day (India calendar days). Failed upstream attempts count too. Scan counters store only account/date/count, and remain until maintenance or account deletion. The 90-second provider timeout and validated request/output limits restrict usage.
- Candidate account deletion is assisted in v1. Verify identity, apply your retention policy, remove private CV objects with trusted administration and remove the Auth user. Profile/application rows cascade. Downloaded/shared data cannot be recalled.

## Dependencies and limitations

- Supabase JS 2.49.8, PDF.js 4.10.38, Mammoth 1.9.0 load from CDNs; fonts load from Google Fonts with local fallbacks. Production requires access to the CDNs and your Supabase project. Review pinned dependency/model versions periodically.
- Claude uses Anthropic Messages API with schema-constrained JSON, bounded server validation and no model tools. The default API model can be changed using a secret; availability depends on your Anthropic account. AI costs consume your Console credits. No live paid request was made during development.
- Local text extraction rejects unreadable scans; Claude native PDF analysis can handle legible scans after consent. Encrypted, corrupted or poor-quality documents may still fail. PDF page counting (30-page limit) is browser-side; server bounds the file to 2 MB. DOCX text sent to AI is limited to 40,000 characters. No malware scanner is provided.
- AI is a suggestion service, may miss or misclassify details, and never directly saves a profile. Candidates must review and click Use these suggestions, then Save profile. An uncertain experience total stays blank; otherwise it is rounded to half-years and editable.
- Manual inputs use comma-separated skill names. English normalised names currently match best; Hindi UI/job descriptions remain supported. Some provider/admin errors remain English.
- New jobs default to Office/Full-time, category=title, source=company and no hard skill gates. Existing hidden preferences/settings are preserved; advanced settings can be managed through trusted administration if needed. Current city is derived from the first preferred city only when no existing city is stored.
- Email alerts, email password recovery, self-registration, employer dashboards, exports, push/SMS/WhatsApp notifications and automatic deletion are not included. Stored legacy alert preferences are preserved but do not schedule messages. Applications remain in the portal for admin review.
- Lists load all accessible records for the intended 100–500-person pilot. Add server pagination before larger volumes. Free-tier capacity depends on file sizes/versions/downloads; 500 CVs at the 2 MB cap approximately fill 1 GB before versions. Monitor usage, establish backups and a retention process; free projects may pause when inactive.

## Validation and live checks

```sh
npm test
node --check app.js
node --check core.js
node --check resume.js
```

45 automated checks passed, including auth/session/consent/quota failures, provider refusal/truncated output, payload limits, candidate review before save, primary-skill weighting, short-form persistence, and original matching/UI checks. Provider responses and DOM are mocked. A live Supabase project, paid Anthropic request and real-browser end-to-end validation were unavailable in this workspace; these still require your deployment.

Run tests/supabase-permissions.sql and tests/upgrade-permissions.sql in SQL Editor after both migrations. Both are rollback-only fixtures. Verify:

- Draft, Published and Closed job saves; edit contact without duplicates; new job visible after filters clear.
- Admin bootstrap, candidate creation/reset/pause, mandatory-password change and invalidation of old sessions.
- Candidate A cannot access B's profile/CV/application or private employer contacts; temporary/paused accounts cannot scan/apply.
- Real PDF, scanned PDF and DOCX analysis; no-consent block; missing/wrong key/provider credit failure; 3/day quota.
- Review/cancel before saving; changed-file rejection; preserved old preferences; submitted application snapshots unaffected.
- Oversized/malformed files, no-CV manual entry, keyboard navigation, English/Hindi, mobile layout and CDN loading.
- No email marked sent; all delivery notices remain accurate.

## Change history

### 1.1.1 — 22 October 2026

Fixed all popup cross buttons by giving them an explicit button type and dispatching close actions before submit-button filtering. Minimum job experience is now visible and required, with explicit zero allowed for freshers and blank/non-finite/out-of-range values rejected. Existing records and backend schema are unchanged. Deploy app.js and core.js together; no SQL or Edge Function redeployment is required. 45 mocked automated checks pass, including actual delegated close-click handling and required-experience validation.


### 1.1.0 — 22 October 2026

Fixed the original save_job job_id ambiguity through qualified parameter references and a named conflict constraint. Added a rerunnable upgrade migration; Claude résumé analysis with server secrets, native PDF support, explicit consent, quotas, validated output and confirmation; separate primary/supporting skills and matching weights; short forms that preserve legacy data; reliable visibility after job save; compact mobile header; dashboard function bundle and upgrade guide. Config.js is deliberately excluded from this update archive so existing deployments keep their configuration.

### 1.0.0 — 21 October 2026

Initial bilingual portal, Supabase schema, protected account function, private CVs, basic text/keyword extraction, matching, applications/admin review and demo. Email disabled per agreed first-release workflow.
