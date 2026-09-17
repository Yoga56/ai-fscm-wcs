@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'CFO Daily Brief'
@Metadata.allowExtensions: true
define root view entity ZC_CFO_BRIEF
  provider contract transactional_query
  as projection on ZR_CFO_BRIEF
{
  key BriefUuid,
      CompanyCode,
      BriefDate,
      DataMode,
      Currency,
      HorizonDays,
      @Semantics.amount.currencyCode: 'Currency'
      CashToday,
      @Semantics.amount.currencyCode: 'Currency'
      LiquidityFloor,
      RunDate,
      NextRunDate,
      @Semantics.amount.currencyCode: 'Currency'
      RunTotal,
      RunInvoiceCount,
      RunVendorCount,
      @Semantics.amount.currencyCode: 'Currency'
      CashAfterRun,
      RunHoldsFloor,
      @Semantics.amount.currencyCode: 'Currency'
      LowPoint,
      LowPointDay,
      LowPointDate,
      @Semantics.amount.currencyCode: 'Currency'
      StressedLowPoint,
      StressedLowDay,
      @Semantics.amount.currencyCode: 'Currency'
      Headroom,
      FloorBreach,
      ScheduledBreach,
      LiquidityCriticality,
      @Semantics.amount.currencyCode: 'Currency'
      ArTotal,
      @Semantics.amount.currencyCode: 'Currency'
      ArOverdue,
      ArOverdueChangePct,
      @Semantics.amount.currencyCode: 'Currency'
      ApTotal,
      @Semantics.amount.currencyCode: 'Currency'
      ApDueWindow,
      @Semantics.amount.currencyCode: 'Currency'
      ApOverdue,
      ApOverdueChangePct,
      ReviewCount,
      Headline,
      Narrative,
      ExplainText,
      Engine,
      ModelUsed,
      ErrorText,
      GeneratedAt,
      CreatedBy,
      CreatedAt,
      LastChangedBy,
      LastChangedAt,
      LocalLastChangedAt,
      _RunwayDay : redirected to composition child ZC_CFO_RUNWAYDAY,
      _Risk : redirected to composition child ZC_CFO_RISK,
      _TradeOff : redirected to composition child ZC_CFO_TRADEOFF,
      _ActionDraft : redirected to composition child ZC_CFO_ACTIONDRAFT
}
