@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'CFO Daily Brief'
@Metadata.ignorePropagatedAnnotations: true
define root view entity ZR_CFO_Brief
  as select from ztcfo_brief
  composition [0..*] of ZR_CFO_RunwayDay   as _RunwayDay
  composition [0..*] of ZR_CFO_Risk        as _Risk
  composition [0..*] of ZR_CFO_TradeOff    as _TradeOff
  composition [0..*] of ZR_CFO_ActionDraft as _ActionDraft
{
  key brief_uuid            as BriefUuid,

      company_code          as CompanyCode,
      brief_date            as BriefDate,
      data_mode             as DataMode,
      currency              as Currency,
      horizon_days          as HorizonDays,

      @Semantics.amount.currencyCode: 'Currency'
      cash_today            as CashToday,
      @Semantics.amount.currencyCode: 'Currency'
      liquidity_floor       as LiquidityFloor,
      run_date              as RunDate,
      next_run_date         as NextRunDate,
      @Semantics.amount.currencyCode: 'Currency'
      run_total             as RunTotal,
      run_invoice_count     as RunInvoiceCount,
      run_vendor_count      as RunVendorCount,
      @Semantics.amount.currencyCode: 'Currency'
      cash_after_run        as CashAfterRun,
      run_holds_floor       as RunHoldsFloor,
      @Semantics.amount.currencyCode: 'Currency'
      low_point             as LowPoint,
      low_point_day         as LowPointDay,
      low_point_date        as LowPointDate,
      @Semantics.amount.currencyCode: 'Currency'
      stressed_low_point    as StressedLowPoint,
      stressed_low_day      as StressedLowDay,
      @Semantics.amount.currencyCode: 'Currency'
      headroom              as Headroom,
      floor_breach          as FloorBreach,
      scheduled_breach      as ScheduledBreach,
      case
        when scheduled_breach = 'X' then 1
        when floor_breach     = 'X' then 2
        else 3
      end                   as LiquidityCriticality,

      @Semantics.amount.currencyCode: 'Currency'
      ar_total              as ArTotal,
      @Semantics.amount.currencyCode: 'Currency'
      ar_overdue            as ArOverdue,
      ar_overdue_chg_pct    as ArOverdueChangePct,
      @Semantics.amount.currencyCode: 'Currency'
      ap_total              as ApTotal,
      @Semantics.amount.currencyCode: 'Currency'
      ap_due_window         as ApDueWindow,
      @Semantics.amount.currencyCode: 'Currency'
      ap_overdue            as ApOverdue,
      ap_overdue_chg_pct    as ApOverdueChangePct,

      review_count          as ReviewCount,
      headline              as Headline,
      narrative             as Narrative,
      explain_text          as ExplainText,
      engine                as Engine,
      model_used            as ModelUsed,
      error_text            as ErrorText,
      generated_at          as GeneratedAt,

      @Semantics.user.createdBy: true
      created_by            as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at            as CreatedAt,
      @Semantics.user.lastChangedBy: true
      last_changed_by       as LastChangedBy,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at       as LastChangedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _RunwayDay,
      _Risk,
      _TradeOff,
      _ActionDraft
}
