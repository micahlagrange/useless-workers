#!/usr/bin/env node
/**
 * epicpr.mjs -- the deploy half of an epic, run by the "epic-deploy" GitHub
 * Actions workflow after Micah moves the epic's card to `accepted` on the
 * game's project board. It is vendored into each game repo as tools/epicpr.mjs
 * by epicci.mjs (together with core.mjs, bodies.mjs and itchcheck.mjs, so it
 * imports nothing else from this repo).
 *
 * No network call here goes to any AI service, and nothing here reads or
 * writes the Jam Hub dashboard or the project board (the default Actions token
 * cannot reach a user-owned project; the local hub.mjs tick moves the cards).
 * Only git, gh (issues, pull requests, workflow runs), an itch page GET and
 * one Discord webhook POST.
 *
 *   resolve       read the epic issue and the pull requests recorded at review
 *   merge         merge each of those pull requests (head commit, checks, conflicts)
 *   ship          dispatch the repo's publish workflow on the default branch and wait
 *   verify-itch   wait until the itch page shows an update newer than --since
 *   announce      post the issue's "### Announcement" to the Discord webhook
 *   finish        comment the outcome on the issue (and close it when deployed)
 *
 * Every step is safe to run again after a failure: a merged PR is skipped, an
 * announced epic is not announced twice, a closed issue is not closed twice.
 * Exit codes: 0 ok, 1 failed, 2 usage, 3 merge conflict, 4 head moved since review, 5 checks not green.
 * Details of the whole flow: references/epic-workflow.md.
 */
import { appendFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { argv, flag, gh, ghJson, sleep } from './core.mjs';
import { checkUrl } from './itchcheck.mjs';
import { EPIC_PREFIX, markerOf, setMarker, parseReviewed, announcementOf } from './bodies.mjs';

export { EPIC_PREFIX };
const now = () => new Date().toISOString();
const log = (s) => console.error(s);

export const RESULT_MARKER = 'epic-result';
export const ISSUE_DEPLOY_FIELDS = 'number,title,state,body,comments';
export const PR_DEPLOY_FIELDS = 'number,title,state,body,headRefName,baseRefName,headRefOid,mergeable,mergedAt,mergeCommit';
/** The outcomes that mean the card goes back to claude-wip (the local tick reads them). */
export const FAILED_OUTCOMES = ['ship-failed', 'conflict', 'stale', 'checks-failed', 'refused', 'deploy-unverified'];

export class ShipError extends Error {
  constructor(message, code = 1) { super(message); this.code = code; }
}

// ------------------------------------------------------------------ issue helpers
/** Rewrite one hidden marker in an issue body, reading the body fresh so no other edit is lost. */
export function markIssue(repo, number, name, value) {
  const issue = ghJson(['issue', 'view', String(number), '--repo', repo, '--json', 'body']);
  if (!issue) throw new Error(`cannot read ${repo}#${number}`);
  const dir = mkdtempSync(join(tmpdir(), 'mark-'));
  try {
    const file = join(dir, 'body.md');
    writeFileSync(file, setMarker(issue.body, name, value));
    const r = gh(['issue', 'edit', String(number), '--repo', repo, '--body-file', file]);
    if (r.code) throw new Error(`gh issue edit #${number} failed: ${r.out.slice(0, 300)}`);
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

/** The epic issue a PR refers to: `<!-- epic-issue N -->` or `Refs #N` in its body. */
export const issueOf = (body = '') => {
  const m = String(body).match(/(?:epic-issue\s+|Refs\s+#)(\d+)/i);
  return m ? Number(m[1]) : null;
};

/** The newest `epic-result` comment of an issue as {outcome, at, ...}, or null. */
export function lastResult(comments = []) {
  const re = new RegExp(`<!--\\s*${RESULT_MARKER}\\s+(\\{.*?\\})\\s*-->`);
  const results = comments.flatMap((c) => {
    try { return [JSON.parse((String(c.body || '').match(re) || [])[1])]; } catch { return []; }
  });
  return results.sort((a, b) => Date.parse(a.at) - Date.parse(b.at)).pop() || null;
}

// ------------------------------------------------------------------ resolve
/** Pure: may this epic be deployed? {ok, reason} or {ok, issue, title, prs: [{number, sha}]}. */
export function decideDeploy(issue, prs, { defaultBranch }) {
  if (!issue) return { ok: false, reason: 'epic issue not found' };
  if (issue.state !== 'OPEN') return { ok: false, reason: `#${issue.number} is not open` };
  const reviewed = parseReviewed(markerOf(issue.body, 'reviewed'));
  if (!Object.keys(reviewed).length) return { ok: false, reason: `#${issue.number} has no recorded review: Claude moves a card to review with hub.mjs move, which records the commits` };
  const list = [];
  for (const [n, sha] of Object.entries(reviewed)) {
    const pr = prs.find((p) => p?.number === Number(n));
    if (!pr) return { ok: false, reason: `PR #${n} named at review was not found` };
    if (pr.state === 'CLOSED') return { ok: false, reason: `PR #${n} was closed unmerged` };
    if (pr.baseRefName !== defaultBranch) return { ok: false, reason: `PR #${n} targets ${pr.baseRefName}, not ${defaultBranch}` };
    if (issueOf(pr.body) !== issue.number) return { ok: false, reason: `PR #${n} does not say "Refs #${issue.number}"` };
    list.push({ number: pr.number, sha });
  }
  return { ok: true, issue: issue.number, title: issue.title, prs: list };
}

function cmdResolve() {
  const repo = need('--repo', process.env.GITHUB_REPOSITORY), base = need('--base', process.env.DEFAULT_BRANCH), number = need('--issue');
  const issue = ghJson(['issue', 'view', number, '--repo', repo, '--json', ISSUE_DEPLOY_FIELDS]);
  const named = Object.keys(parseReviewed(markerOf(issue?.body, 'reviewed')));
  const prs = named.map((n) => ghJson(['pr', 'view', n, '--repo', repo, '--json', PR_DEPLOY_FIELDS]));
  const verdict = decideDeploy(issue, prs, { defaultBranch: base });
  if (!verdict.ok) fail(verdict.reason);
  const prSpec = verdict.prs.map((p) => `${p.number}=${p.sha}`).join(',');
  for (const [k, v] of Object.entries({ issue: verdict.issue, title: verdict.title, prs: prSpec, since: now() })) setOutput(k, v);
  log(`deploying #${verdict.issue}: PR ${prSpec}`);
  console.log(JSON.stringify(verdict));
}

// ------------------------------------------------------------------ checks + merge
/** Pure: fold check runs + legacy statuses into pass | fail | pending | none. */
export function judge(runs = [], statuses = [], ignore = []) {
  const relevant = runs.filter((r) => !ignore.includes(r.name));
  const bad = ['failure', 'cancelled', 'timed_out', 'action_required', 'startup_failure', 'stale'];
  if (relevant.some((r) => r.status === 'completed' && bad.includes(r.conclusion))) return 'fail';
  if (statuses.some((s) => ['failure', 'error'].includes(s.state))) return 'fail';
  if (!relevant.length && !statuses.length) return 'none';
  if (relevant.some((r) => r.status !== 'completed') || statuses.some((s) => s.state === 'pending')) return 'pending';
  return 'pass';
}

/** Wait until every check on the commit passed. Throws ShipError 5 on a failure, no checks, or a timeout. */
export function waitChecks(repo, sha, { ignore = [], timeout = 1800000, grace = 180000 } = {}) {
  const start = Date.now();
  for (;;) {
    const runs = ghJson(['api', `repos/${repo}/commits/${sha}/check-runs?per_page=100`, '-q', '.check_runs']) || [];
    const statuses = ghJson(['api', `repos/${repo}/commits/${sha}/status`, '-q', '.statuses']) || [];
    const verdict = judge(runs, statuses, ignore);
    log(`checks on ${sha.slice(0, 7)}: ${verdict} (${runs.length} runs)`);
    if (verdict === 'pass') return;
    if (verdict === 'fail') throw new ShipError(`a check failed on ${sha.slice(0, 7)}`, 5);
    if (verdict === 'none' && Date.now() - start > grace) throw new ShipError(`no checks ran on ${sha.slice(0, 7)}; refusing to merge untested work`, 5);
    if (Date.now() - start > timeout) throw new ShipError(`checks still pending after ${timeout / 1000}s`, 5);
    sleep(20000);
  }
}

const viewPr = (repo, number) => {
  const pr = ghJson(['pr', 'view', String(number), '--repo', repo, '--json', PR_DEPLOY_FIELDS]);
  if (!pr) throw new ShipError(`cannot read PR #${number}`, 1);
  return pr;
};

/** Merge one reviewed PR: the head must still be the reviewed commit, it must not conflict and its checks must be green.
 *  An already merged PR is skipped. Returns {merged, note}. `wait` and `settle` are injectable for tests. */
export function mergePr(repo, { number, sha }, { wait = waitChecks, settle = () => sleep(3000) } = {}) {
  let pr = viewPr(repo, number);
  if (pr.state === 'MERGED') return { merged: false, note: `PR #${number} is already merged` };
  if (pr.state !== 'OPEN') throw new ShipError(`PR #${number} is ${pr.state.toLowerCase()}, not open`, 1);
  if (pr.headRefOid !== sha) throw new ShipError(`PR #${number} moved after review: reviewed ${sha.slice(0, 7)}, now ${pr.headRefOid.slice(0, 7)}`, 4);
  for (let i = 0; i < 5 && pr.mergeable === 'UNKNOWN'; i++) { settle(); pr = viewPr(repo, number); }
  if (pr.mergeable === 'CONFLICTING') throw new ShipError(`PR #${number} conflicts with the main line`, 3);
  wait(repo, sha, { ignore: [] });
  const m = gh(['pr', 'merge', String(number), '--repo', repo, '--merge', '--match-head-commit', sha]);
  if (m.code) throw new ShipError(`gh pr merge #${number} failed: ${m.out.slice(0, 300)}`, /head (branch|commit)|match/i.test(m.out) ? 4 : 1);
  return { merged: true, note: `merged PR #${number}` };
}

function cmdMerge() {
  const repo = need('--repo', process.env.GITHUB_REPOSITORY);
  const specs = need('--prs').split(',').filter(Boolean).map((p) => { const [number, sha] = p.split('='); return { number: Number(number), sha }; });
  for (const spec of specs) log(mergePr(repo, spec).note);
}

// ------------------------------------------------------------------ ship + verify
/** Pure: the dispatched run since the dispatch (for this commit when sha is given), newest first. */
export function pickRun(runs, { sha, since }) {
  return runs
    .filter((r) => (!sha || r.headSha === sha) && Date.parse(r.createdAt) >= Date.parse(since) - 5000)
    .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt))[0] || null;
}

function cmdShip() {
  const repo = need('--repo', process.env.GITHUB_REPOSITORY), wf = need('--workflow'), ref = need('--ref'), sha = flag('--sha');
  const since = now();
  const d = gh(['workflow', 'run', wf, '--repo', repo, '--ref', ref]);
  if (d.code) fail(`could not dispatch ${wf}: ${d.out}`);
  let run = null;
  for (let i = 0; i < 24 && !run; i++) {
    sleep(5000);
    const runs = ghJson(['run', 'list', '--repo', repo, '--workflow', wf, '--branch', ref, '--event', 'workflow_dispatch', '--limit', '10', '--json', 'databaseId,headSha,createdAt,url']) || [];
    run = pickRun(runs, { sha, since });
  }
  if (!run) fail(`${wf} was dispatched but no run ${sha ? `for ${sha.slice(0, 7)} ` : ''}appeared`);
  log(`publish run ${run.url}`);
  setOutput('run_url', run.url);
  const w = gh(['run', 'watch', String(run.databaseId), '--repo', repo, '--exit-status'], undefined, 1800000);
  if (w.code) fail(`publish run failed: ${run.url}`);
}

function cmdVerifyItch() {
  const url = need('--url'), since = Date.parse(need('--since')) - 60000;
  const password = flag('--password') || process.env.ITCH_PAGE_PASSWORD || null;
  const timeout = +(flag('--timeout') || 600) * 1000, start = Date.now();
  return (async () => {
    for (;;) {
      const page = await checkUrl(url, password).catch((e) => ({ unlocked: false, note: e.message }));
      const fresh = page.unlocked && page.updated && Date.parse(page.updated) >= since;
      log(`itch: unlocked=${page.unlocked} updated=${page.updated} fresh=${!!fresh}`);
      if (fresh) { console.log(JSON.stringify(page)); return; }
      if (Date.now() - start > timeout) fail(page.unlocked ? 'the itch page has not updated yet (it may still be processing)' : `the itch page did not unlock: ${page.note || page.status}`);
      sleep(15000);
    }
  })();
}

// ------------------------------------------------------------------ announce
export const DISCORD_LIMIT = 2000;

/** Pure: the Discord message: Claude's announcement prose, else a plain line, cut to Discord's limit. */
export function announcementText(issue, itchUrl = '') {
  const prose = announcementOf([issue.body, ...(issue.comments || []).map((c) => c.body)].join('\n\n'));
  const text = prose || `${issue.title} is live${itchUrl ? `: ${itchUrl}` : '.'}`;
  return text.length <= DISCORD_LIMIT ? text : `${text.slice(0, DISCORD_LIMIT - 1)}…`;
}

/** Post the announcement once. Returns {sent, why}; never posts without a webhook or twice. `post` is injectable for tests. */
export async function announce({ repo, number, webhook, itchUrl = '', post = defaultPost }) {
  const issue = ghJson(['issue', 'view', String(number), '--repo', repo, '--json', ISSUE_DEPLOY_FIELDS]);
  if (!issue) throw new Error(`cannot read ${repo}#${number}`);
  if (markerOf(issue.body, 'announced') !== null) return { sent: false, why: 'already announced' };
  if (!webhook) return { sent: false, why: 'no DISCORD_WEBHOOK_URL secret: nothing was posted' };
  await post(webhook, announcementText(issue, itchUrl));
  markIssue(repo, number, 'announced', now());
  return { sent: true, why: 'posted' };
}

async function defaultPost(webhook, content) {
  const res = await fetch(webhook, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ content, allowed_mentions: { parse: [] } }) });
  if (!res.ok) throw new Error(`Discord webhook answered ${res.status}`);
}

async function cmdAnnounce() {
  const r = await announce({ repo: need('--repo', process.env.GITHUB_REPOSITORY), number: need('--issue'), webhook: process.env.DISCORD_WEBHOOK_URL, itchUrl: flag('--itch-url') || process.env.ITCH_URL || '' });
  log(`announce: ${r.why}`);
  setOutput('announced', r.sent);
}

// ------------------------------------------------------------------ finish
const HEADLINES = {
  'deployed': 'Published and verified on itch. Closing this issue.',
  'deploy-unverified': 'Published, but the itch page is not confirmed. The card goes back to claude-wip; accept it again to retry.',
  'ship-failed': 'Not deployed. The card goes back to claude-wip.',
  'conflict': 'Not merged: a pull request conflicts with the main line. Claude resolves it on the branch; accept again afterwards.',
  'stale': 'Not merged: a pull request changed after review. Review the new commits; Claude moves the card to review again.',
  'checks-failed': 'Not merged: the checks did not pass.',
  'refused': 'Not deployed: the epic is not in a deployable state.',
};

/** Comment the outcome on the epic issue; when deployed, close it (once). A failed outcome leaves it open. */
export function finishIssue({ repo, issue, outcome, sha = null, url = null, detail = null }) {
  if (!HEADLINES[outcome]) throw new Error(`unknown outcome ${outcome}`);
  const result = { outcome, sha, runUrl: url, at: now() };
  const body = [`**${HEADLINES[outcome]}**`, detail ? `\n${detail}` : '', url ? `\n[Run](${url})` : '', `\n<!-- ${RESULT_MARKER} ${JSON.stringify(result)} -->`].join('\n');
  const c = gh(['issue', 'comment', String(issue), '--repo', repo, '--body', body]);
  if (c.code) throw new Error(`gh issue comment #${issue} failed: ${c.out.slice(0, 300)}`);
  if (outcome !== 'deployed') return;
  const state = ghJson(['issue', 'view', String(issue), '--repo', repo, '--json', 'state']);
  if (state?.state === 'OPEN') {
    const closed = gh(['issue', 'close', String(issue), '--repo', repo, '--reason', 'completed']);
    if (closed.code) throw new Error(`gh issue close #${issue} failed: ${closed.out.slice(0, 300)}`);
  }
}

function cmdFinish() {
  finishIssue({ repo: need('--repo', process.env.GITHUB_REPOSITORY), issue: need('--issue'), outcome: need('--outcome'), sha: flag('--sha'), url: flag('--url'), detail: flag('--detail') });
}

// ------------------------------------------------------------------ plumbing
function need(name, fallback = null) {
  const v = flag(name) || fallback;
  if (!v) { console.error(`missing ${name}`); process.exit(2); }
  return v;
}
function fail(message, code = 1) { throw new ShipError(message, code); }
function setOutput(k, v) {
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `${k}=${String(v ?? '').replace(/\r?\n/g, ' ')}\n`);
}

const COMMANDS = { resolve: cmdResolve, merge: cmdMerge, ship: cmdShip, 'verify-itch': cmdVerifyItch, announce: cmdAnnounce, finish: cmdFinish };

async function main() {
  const fn = COMMANDS[argv[0]];
  if (!fn) { console.error(`usage: epicpr.mjs ${Object.keys(COMMANDS).join('|')} [flags]  (see the header)`); process.exit(2); }
  try { await fn(); }
  catch (e) { console.error(`epicpr ${argv[0]}: ${e.message}`); process.exit(e instanceof ShipError ? e.code : 1); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
