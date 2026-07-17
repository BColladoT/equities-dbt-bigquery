# INTERVIEW.md

> **Status: NOT YET WRITTEN. The answers below are deliberately blank.**
>
> This file exists so I can answer, in my own words, the questions I'll be asked about this
> project. It is the single most important file in the repo — a CV claim I can't defend is worse
> than no CV claim at all.
>
> **It must be written by me (Brian), not generated.** An answer I didn't write is an answer I
> can't deliver under follow-up questioning, which is the only place it matters.

---

## Honest record of how this was built

Required by the project brief, and recorded here rather than quietly omitted.

**I did not walk through the build myself.** The design phase was collaborative — I made the real
modelling calls, and I can point to them:

- **Session VWAP → `intermediate/`, not staging.** I chose the layer and gave the reasoning.
- **Scope → all 573 setup symbols, not the top 50.** I was shown that selecting the top 50 *by
  setup count* would inflate the win rate from 78.9% to 85.5% through selection bias, and I chose
  the unbiased scope.
- **Both marts, not just the funnel.** I was shown that a funnel-only design orphans
  `int_bars_session_vwap` and leaves a live DAG over 1,818 CSV rows while 20.4M bars sit unused.
  I chose to fix it.
- **The reimplementation framing.** When it turned out the tick backtest and this project use
  different input data, I chose "state it plainly" over minimising or hiding the divergence.

**But the implementation — the SQL, the tests, the macro, the README — was written while I was
away from the computer**, after I asked for it to be finished autonomously. I was pushed back on
once before that happened, and this note is the agreed consequence.

**What that means concretely, and what I owe this project before I put it on a CV:**

- [ ] Read every model in `models/` and be able to explain each one cold.
- [ ] Complete the four explain-back gates that were deferred (they're in
      `docs/superpowers/plans/`, Tasks 6, 7, 8, 9). They are deferred, not cancelled.
- [ ] Write the six answers below in my own words.
- [ ] Only then treat this as CV material.

Until those boxes are ticked, the honest description of this repo is *"a project I designed and
had built"*, not *"a project I built"*. The distinction will surface in the first follow-up
question, so I'd rather own it here than be caught by it there.

---

## The six questions

### 1. Walk me through your DAG.

> _Your answer here._
>
> Prompts, not answers — delete these when you write: What are the three layers and what belongs
> in each? Where does the DAG fork, and why? Which models are views, which are tables, and what
> decided that? Why are there two sources and not one?

---

### 2. Why is that model in `intermediate/` and not `marts/`?

> _Your answer here._
>
> The trap to be ready for: if you say "because it's business logic spanning many rows," a good
> interviewer will counter — *"but it's one row per bar in and one row out. Why isn't that
> staging?"* Row grain doesn't settle it. Have the better argument ready. Look at what
> `bar_vwap` and `session_vwap` each owe their existence to.

---

### 3. What tests did you write, and why those?

> _Your answer here._
>
> The trap: *"your tests are all green — what do they actually prove?"* The source was profiled
> clean (0 malformed bars in 20.4M rows) before any SQL was written, so most tests pass on day
> one. Why is that the point rather than a weakness? Which single test is most likely to fire in
> real life, and why? And why does the `relationships` test warn on dev but error on prod —
> is that gaming the test or encoding a real contract?

---

### 4. What breaks if the source schema changes?

> _Your answer here._
>
> Prompts: If Alpaca renames `vwap`, how many files do you touch? What if they change the
> timestamp from UTC to ET? What if they start sending `low > high`? Which of those does the
> project catch loudly, and which would slip through? Be honest about the third one — see
> "What this project does not do" in the README.

---

### 5. Why dbt instead of a folder of SQL scripts?

> _Your answer here._
>
> Prompts: You have a concrete answer most people don't — this project genuinely targets two
> engines from one codebase. What would `macros/to_et.sql` look like as a folder of scripts? What
> about `ref()` and the lineage graph? What about the 53 tests? Don't just recite dbt's marketing;
> point at something in this repo.

---

### 6. How does partitioning save you money here?

> _Your answer here._
>
> **This answer needs a real measured number, and you don't have one yet.** Task 4 Step 5 of the
> plan runs `bq query --dry_run` twice — once with a date filter, once without — and reports bytes
> billed without charging. Run it once BigQuery is live and put both numbers here. A guessed
> answer ("it scans less data") is worth nothing; "a filtered query scans X MB vs Y GB unfiltered,
> on my table" is worth a lot.
>
> Also be ready for: *"you said the whole thing is 1.26 GB and free — so why bother partitioning
> at all?"* That's the sharper question.

---

## Questions I should also expect

Not in the brief, but likely given what's in this repo:

- *"Your win rate is 78.9% — out of how many, and who selected them?"* (The funnel is the answer.
  909 → 327 → 258. Volunteer it before you're asked.)
- *"Is this validated?"* (No. In-sample. Walk-forward in progress. Say so immediately.)
- *"Does your SQL agree with your backtest?"* (No — 57.6% overlap on the sample. Know why, and know
  why you didn't tune the thresholds to close the gap. This is your strongest answer if you can
  deliver it calmly.)
- *"You've never run this on BigQuery, have you?"* (Not yet. The target is configured, not
  exercised. The README says so.)
- *"Why is `never_triggered` the biggest bucket?"* (582 of 909. Is that a bug or the strategy
  working as designed?)
