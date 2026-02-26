# Week Navigation Design

## Goal

Add `<` `>` arrows to navigate the bar chart to past weeks. Hero and month row update contextually.

## Approach

Offset-based: `weekOffset: Int` (0 = current, -1 = last week, etc.). Rolling 7-day windows shifted by 7 per step.

## Changes

### Models.swift — `UsageData.from(response:weekOffset:)`

- offset 0: today-6..today (unchanged behavior)
- offset -1: today-13..today-7
- `periodCost`: today's cost when offset=0, week total otherwise
- `weekLabel`: "This Week" at 0, "Feb 17 – 23" otherwise
- `monthLabel`: "This Month" at 0, "January" otherwise
- `isCurrentWeek: Bool`

### UsageService.swift

- Store raw `CCUsageResponse` alongside computed `UsageData`
- `func usageData(weekOffset: Int) -> UsageData` for on-demand recompute

### MenuBarView.swift

- `@State private var weekOffset = 0`
- Chart header: `< dateRange >` with chevron buttons
- Hero: shows `periodCost` with contextual subtitle
- Month row: uses `monthLabel` and offset-aware month total
- Right arrow disabled at offset 0

### BarChartView.swift

No changes — still receives `[DailyUsage]`.
