# What Drives Conversion in Quick Commerce?
## An End-to-End Product Analytics Investigation

**Tools:** Google BigQuery · SQL · Python
**Domain:** Quick Commerce · Product Analytics · Experimentation
**Author:** Harsha Narasimhe Gowda · [linkedin.com/in/harsha-ng](https://www.linkedin.com/in/harsha-ng)

---

## Why I Built This

Quick commerce is one of the most analytically interesting product categories in consumer tech. Users make decisions in seconds. Sessions are short, intent is high, and the margin between a great experience and a lost order is razor-thin.

I got access to a sample of anonymised quick commerce event data and decided to investigate a question that I kept coming back to: **what actually drives conversion in a quick delivery app, and why does it change?**

Not in theory. In the data.

This project is the result of that investigation — a full end-to-end analysis from raw event streams to strategic recommendations, structured around a central mystery: **a 14 percentage point improvement in funnel conversion that appeared mid-period with no obvious explanation.**

---

## The Dataset

Three anonymised event tables covering a three-week period (Aug 24 – Sep 14, 2025):

| Table | Description |
|---|---|
| `daily_events` | All user-generated app events — sessions, browsing, interactions |
| `cart_events` | Product add-to-cart events with placement metadata |
| `order_events` | Order placement events with nested product-level JSON |

**Scale:** ~380,000 inter-event gaps analysed · 15 product placement surfaces · 22 days of behaviour

---

## Data Preparation

Before any analysis, I ran a full validation pass.

### What I found
- **113 duplicate event IDs** in the daily events table
- **1 duplicate event ID** in the cart events table
- Root cause: the same events were ingested twice, consistent with a pipeline re-processing artifact

### How I resolved it
Retained the earliest occurrence of each duplicate event ID, ensuring correct event sequencing and no double-counting downstream.

### Structural transformation
The order events table stored product details as nested JSON. I flattened it to one row per product per order, retaining `order_id`, `anonymous_id`, and `event_timestamp` — enabling consistent user-product level joins across all three tables.

### A note on Sep 12–14
Order data for the final three days shows zero orders despite significant cart activity. This is almost certainly a data pipeline completeness issue, not real user behaviour. I have flagged it throughout the analysis and excluded affected dates from conversion calculations where relevant.

---

## Part 1 — Understanding the Audience

### Active Users per Day

I defined an active user as any `anonymous_id` generating at least one event on a given day — the broadest possible definition of engagement.

**Finding:** Peak activity hit 415 users on Aug 29 (Friday). Every weekend showed a consistent 30–40% drop:

| Weekend Day | Active Users | vs. Surrounding Weekdays |
|---|---|---|
| Aug 31 (Sun) | 274 | −34% |
| Sep 7 (Sun) | 187 | −43% |
| Sep 14 (Sun) | 176 | −47% |

**Interpretation:** Weekend users are a different audience. Lower volume, lower engagement. This has product implications — a weekend homepage optimised for discovery rather than efficiency could recover some of that drop.

---

## Part 2 — The Central Mystery

### The Funnel and the 14-Point Lift

I built a daily three-step funnel: Active → Cart → Order. Each step uses the same-day join — a user counts at a step only if they performed that action on the same calendar day.

**The numbers:**

| Period | Active → Cart | Cart → Order | Overall |
|---|---|---|---|
| Aug 24–31 | ~31–52% | ~57–74% | ~18–37% |
| Sep 1–11 | ~57–64% | ~59–73% | ~38–45% |

Cart-to-order conversion was stable throughout — 65 to 73% across the entire period. The checkout experience was not the problem.

**The bottleneck was always Active → Cart.** And then, starting September 1, it got dramatically better.

### Why did it improve?

I ruled out the obvious explanations:

- **Not a weekend effect.** The improvement holds consistently across weekdays in September, not just high-traffic days.
- **Not a volume effect.** September weekday traffic is actually slightly lower than August peaks, yet conversion is higher.
- **Not random noise.** The lift is consistent across 11 consecutive weekdays in September.

**That leaves two hypotheses:**

1. A product or UX change was shipped around September 1 that improved homepage relevance or search quality
2. The user cohort shifted — September brought a higher proportion of returning users who already knew what they wanted

**To distinguish between these, I would need:** deploy logs from around Sep 1, and cohort segmentation splitting new vs. returning users across both periods.

**What I would do:** Correlate the lift with any feature releases in that window. If a change is identified, design a holdback experiment to quantify its causal contribution to the conversion improvement.

---

## Part 3 — Where Users Convert (and Why)

### Product Placement Analysis

Not all surfaces are equal. I analysed conversion across 15 placement types — the locations within the app where users discover and add products to their cart.

**Methodology:** Last-touch attribution — the cart event closest in time before an order receives purchase credit. Cart events occurring after the order timestamp are excluded.

**Results:**

| Placement | Cart Adds | Purchased | Conversion | Volume Rank |
|---|---|---|---|---|
| Out-of-stock substitutes | 1,523 | 1,182 | **77.6%** | 8 |
| Last bought | 6,772 | 5,150 | **76.0%** | 5 |
| Search | 23,770 | 15,953 | 67.1% | 2 |
| Cart recommendations | 2,033 | 1,364 | 67.1% | 7 |
| Personalised recommendations | 8,173 | 4,889 | 59.8% | 3 |
| Category browse | 30,257 | 18,005 | 59.5% | 1 |
| Product detail page | 4,991 | 2,786 | 55.8% | 6 |
| Deals | 6,781 | 3,198 | 47.2% | 4 |

### The Intent vs. Discovery Trade-off

This data tells a clear story about user psychology:

**High-intent surfaces** (substitutes, last bought) convert at 76–78% because users already know what they want. They are replacing something or reordering a habit. There is almost nothing the product can do to improve these further — the intent is already there.

**Discovery surfaces** (category, search) drive 80%+ of total cart volume but convert at 59–67%. These users are browsing. They may or may not find what they are looking for.

**The implication:** The biggest revenue opportunity is not in high-intent surfaces. It is in closing the gap on discovery surfaces through better relevance, personalisation, and ranking.

### Where I Would Focus

**Personalised recommendations (59.8% conversion, 8K cart adds)** is the highest-ROI opportunity. It has meaningful volume and meaningful room to improve. A better algorithm — one that filters by past purchase behaviour rather than general popularity — could realistically push this to 65%+, generating hundreds of additional purchases per period.

**Proposed experiment:** A/B test a purchase-history-weighted recommendation algorithm vs. the current approach. Primary metric: recommendation-to-cart rate. Guardrail metrics: overall conversion rate and revenue per session.

---

## Part 4 — Which Products Drive Conversion?

### The 100% Conversion Problem

At product level, I calculated conversion as the share of users who added a product to cart and then purchased it (with the purchase confirmed as occurring after the cart event).

To filter noise, I required at least 10 distinct users per product.

**The result:** Eight products showed 100% conversion. Several more exceeded 90%.

**The catch:** These are all low-volume products (10–21 cart adds). A product with 100% conversion from 10 users is interesting but not impactful.

### A Better Definition of "Best"

Conversion rate × cart add volume = expected purchases per period. That is the metric that actually matters.

A product with 70% conversion and 1,000 cart adds generates 700 expected purchases. A product with 100% conversion and 10 cart adds generates 10.

The high-converting, low-volume products are almost certainly staple items — things users add to cart with full intent to buy (milk, eggs, a specific brand of coffee). They are important to stock reliably but not where the product growth story lives.

**The growth story** is in the mid-conversion, high-volume products — items that are frequently added but not always purchased. Understanding why those cart adds do not convert (price, stock availability, delivery fee friction) is where the real product work is.

---

## Part 5 — Defining a Session

### What Does a "Session" Mean in Quick Commerce?

Sessions are not defined in the raw event data — they need to be constructed from inter-event gaps. I analysed the gap distribution between consecutive events per user:

| Gap | Events | % of Total |
|---|---|---|
| Under 1 minute | 329,543 | 86.4% |
| 1–5 minutes | 27,387 | 7.2% |
| 5–15 minutes | 4,549 | 1.2% |
| 15–30 minutes | 2,690 | 0.7% |
| 30–60 minutes | 2,231 | 0.6% |
| Over 60 minutes | 15,057 | 3.9% |

**86.4% of gaps are under one minute.** User activity happens in short, intense bursts. After 30 minutes of inactivity, the behavioural signal is clear: the session is over.

**My definition:** A session is a continuous sequence of user events where no consecutive gap exceeds 30 minutes. A session also ends upon order placement, since that represents the completion of user intent.

**A note on threshold choice:** In a quick commerce context, 10–15 minutes might actually be more behaviourally accurate — most sessions are complete within that window. I chose 30 minutes as the industry standard, but I would test both thresholds against session-to-order rate to find the definition that best predicts conversion behaviour.

### What Sessions Unlock

With sessions defined, the next layer of analysis becomes possible:
- **Session-to-order rate** — a more precise conversion metric than daily active users
- **Events per session** — an engagement proxy that separates high and low intent visits
- **Entry point analysis** — do users who start from search convert differently than users who start from the homepage?
- **Re-engagement patterns** — how often do users browse in one session and order in a later one?

---

## Summary of Recommendations

| Priority | Action | Expected Impact |
|---|---|---|
| P1 | Investigate Sep 1 conversion lift — identify the driver and design a holdback test | Confirm and replicate the +14pp funnel improvement |
| P2 | A/B test personalised recommendation algorithm (purchase-history weighted) | Estimated 5–8pp lift in recommendation-to-cart rate |
| P3 | Diagnose mid-conversion, high-volume product drop-off | Identify stock, pricing, or friction issues hiding in the data |
| P4 | Weekend-specific homepage strategy | Recover 30–40% weekend engagement gap |
| P5 | Implement session-level analytics | Enable session-to-order rate as primary conversion KPI |

---

## Repository Structure

```
quick-commerce-product-analytics/
│
├── README.md                    # This file — full project narrative
├── queries.sql                  # All BigQuery SQL (Q1–Q5, fully commented)
└── analysis_report.pdf          # Supporting visualisations and detailed results
```

---

## SQL Overview

All queries are in [`queries.sql`](./queries.sql) — fully commented, structured as modular CTE chains.

| Query | What it answers |
|---|---|
| Q1 | Active users per day with deduplication |
| Q2 | Daily three-step funnel with conversion rates |
| Q3 | Placement performance with last-touch attribution |
| Q4 | Product-level conversion with volume threshold |
| Q5 | Inter-event gap distribution for session definition |

---

*This project was built independently using anonymised event data as a self-directed investigation into quick commerce product analytics. All findings and recommendations are my own.*
