# The demo scenario — the slide story, reconciled

`ZCL_CFO_DEMO_SEED` (ABAP) and `app/cfobrief/mock/engine/scenario.js` (JS) hold the same rows.
The anchor is a Tuesday (the slides use **Tue 4 Aug 2026**), so the weekly F110 run falls on
Thursday. Amounts in USD million, illustrative.

## Base data

| | Value | Where it comes from |
|---|---:|---|
| Cash today (bank) | 22.0 | `ZTCFO_DEMO_MISC` BANK row |
| Liquidity floor | 8.0 | `ZTCFO_CONFIG` |
| Total AP / due in 14 days / this week's proposal | 100.0 / 18.0 / 12.0 | open supplier items |
| Proposal | 180 invoices / 47 vendors | XYZ 3.0 + two blocked 1.5 + 177 small invoices (44 vendors) |
| Total AR / overdue | 85.0 / 9.0 | ABC 4.0 + Northwind 2.0 + Contoso 1.5 + Fabrikam 1.5 |
| Yesterday's overdue (baseline brief) | AR 8.04 / AP 2.0 | → AR **up 11.9 %**, AP **down 5.0 %** |
| Plant 1000 PO spend | 13.1 vs 11.1 average | → **up 18.0 % ($2.0M)** |

## Runway (days with cash movement)

| Day | Date | In | Out | Scheduled | If ABC is late | Note |
|---:|---|---:|---:|---:|---:|---|
| 0 | Tue 4 Aug | 0.0 | 0.0 | 22.0 | 22.0 | opening bank balance |
| 1 | Wed 5 Aug | 0.6 | 0.6 | 22.0 | 22.0 | |
| 2 | Thu 6 Aug | 0.5 | 12.5 | 10.0 | 10.0 | this week's F110 run $12.0M |
| 3 | Fri 7 Aug | 0.4 | 0.6 | 9.8 | 9.8 | |
| 6 | Mon 10 Aug | 4.5 | 0.8 | 13.5 | 9.5 | ABC $4.0M promised |
| 7 | Tue 11 Aug | 0.6 | 0.6 | 13.5 | 9.5 | |
| 8 | Wed 12 Aug | 0.5 | 0.5 | 13.5 | 9.5 | |
| 9 | Thu 13 Aug | 4.0 | 8.0 | **9.5** | **5.5** | next run: raw material $6.0M + spare parts $2.0M — low point |
| 10 | Fri 14 Aug | 1.8 | 0.3 | 11.0 | 7.0 | |
| 13 | Mon 17 Aug | 1.7 | 0.5 | 12.2 | 8.2 | |
| 14 | Tue 18 Aug | 4.0 | 0.2 | 16.0 | 12.0 | Northwind $2.0M + others |
| 15 | Wed 19 Aug | 0.8 | 0.4 | 16.4 | 16.4 | ABC arrives if late |
| 16 | Thu 20 Aug | 0.9 | 4.5 | 12.8 | 12.8 | run |
| 23 | Thu 27 Aug | 0.8 | 5.0 | 11.8 | 11.8 | run (incl. Delta Chemicals $1.0M) |
| 30 | Thu 3 Sep | 1.2 | 4.0 | 12.3 | 12.3 | run |

## How each slide statement is produced

| Slide statement | Rule |
|---|---|
| "ABC $4M likely to pay late (~75 %)" | 6 of ABC's 8 cleared invoices were late, 9 days on average → P(late) 0.75, shifted 9 days |
| "Low-point $9.5M Day 9 … → $5.5M below floor" | minimum of the scheduled / stressed paths |
| "decide by Mon 10 Aug: chase or factor (funds ~3 days, before Day 9)" | low-point day − 3 working days |
| "Vendor XYZ $3M off-pattern" | 18.4 standard deviations above XYZ's cleared invoices (mean $0.4M) |
| "2 invoices blocked $1.5M" | payment block `R` inside this week's run |
| "Raw-material PO $6M — approve by Fri **7** Aug (3-day lead)" | next run Thu 13 Aug − 1 working day (proposal) − 3 working days. **The slide says Fri 8 Aug; 4 Aug 2026 is a Tuesday, so the Friday is the 7th.** |
| "Pay raw material; a small late fee ≪ a stopped line" | spare part: fee $2.0M × 3 % × 7/365 = **$1,151**; raw material: `ZTCFO_CRIT` level H, $30M revenue at risk on Line 2 |
| Deferring alone is not enough | shortfall $2.5M → $0.5M; factoring ABC ($3.9M at 97.5 %) closes the rest |
| "If ABC pays, deposit ~$3M @ 4.2 % ≈ $1,700" | free cash Day 10–14 = $11.0M − $8.0M; $3M × 4.2 % × 5/365 = **$1,726**; held because the stressed path is below the floor |
| "early-payment discount ≈ 37 % p.a." | 2/10 net 30: 2/98 × 365/20 = **37.2 %** |
| "3 items to review" | XYZ + blocked invoices + raw-material approval |

## What-if checks (asserted in both test suites)

| Toggle | Result |
|---|---|
| ABC pays late | scheduled low point $5.5M → below floor |
| Factor ABC today | low point $9.4M on both paths → no breach |
| Hold XYZ to the next run | Day 3 $12.8M, Day 9 unchanged at $9.5M |
| Floor $10M | scheduled breach |
