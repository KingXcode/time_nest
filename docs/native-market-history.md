# Native market chart foundation (not enabled)

The live market page remains unchanged. `NativeMarketHistory` is a local Flutter
renderer awaiting an independently verified, free public-display data source.
It is **not** a finished replacement and has no built-in provider, network request,
production fixture, or inferred market score.

## Integration contract

Implement `MarketHistorySource.load(indexId, refresh:)` only after verifying:

- Permission to display the data publicly, including any caching/redistribution.
- HTTPS delivery usable by the deployed browser (CORS if a direct API), without
  credentials in the web bundle or an unapproved proxy/hosting service.
- Coverage of the selected index; its identifier must match one of
  `marketIndices`. Do not substitute a different index silently.
- Values are official daily **closing index points**, not intraday quotes,
  adjusted security prices, or projected/fabricated points.
- Actual exchange session dates in `Asia/Shanghai`, source attribution/link,
  retrieval timestamp, and a source-supported timeliness statement.

The adapter returns `MarketHistory`, optionally decoded via `fromRows`:
`[{"date": "YYYY-MM-DD", "close": <positive finite number>}, ...]`.
Rows must be strictly date-ascending, unique, no later than retrieval's Shanghai
calendar date, and at most 5,000. An empty list is an explicit no-data result.
Dates remain date-only; do not convert them using the user's local timezone.
Validation does not establish that a session was actually open or the close is
official: those remain the provider adapter's responsibility.

Freshness defaults to `unverified`. `verifiedThroughDate` requires a provider or
exchange-calendar guarantee through the displayed date. Never infer freshness
from weekdays, an HTTP 200 response, or a successful refresh. `stale` preserves
the original retrieval time. Transport errors must throw rather than fabricate
or relabel data. Switching index/source clears the previous plot; failed refresh
retains the previous plot with an explicit potentially-stale warning.

## Rendering and scope

The renderer is a daily-close line chart, not OHLC candles. Sessions are equally
spaced and the value range is auto-scaled, both disclosed in the UI. A single
record is a point, not a trend. Selection is available through touch and an
accessible slider. Current scope deliberately excludes weekly/monthly rollups,
indicators, ratings, and whole-market interpretation.

All synthetic examples live in `test/native_market_history_test.dart` only.
Before activating: add provider-specific transport and schema tests, verify a
real attributed historical series and failure states in the public build and
on the affected iPhone, then replace the embedded plot deliberately. Do not
publish a fixture-backed preview or call this foundation a working market feed.
