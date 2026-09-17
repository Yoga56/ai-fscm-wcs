@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'CFO Daily Brief - Runway day'
@Metadata.allowExtensions: true
define view entity ZC_CFO_RUNWAYDAY
  as projection on ZR_CFO_RUNWAYDAY
{
  key RunwayUuid,
      BriefUuid,
      DayIndex,
      CalendarDate,
      Currency,
      @Semantics.amount.currencyCode: 'Currency'
      Inflow,
      @Semantics.amount.currencyCode: 'Currency'
      Outflow,
      @Semantics.amount.currencyCode: 'Currency'
      ClosingScheduled,
      @Semantics.amount.currencyCode: 'Currency'
      ClosingStressed,
      @Semantics.amount.currencyCode: 'Currency'
      ClosingExpected,
      @Semantics.amount.currencyCode: 'Currency'
      FloorAmount,
      @Semantics.amount.currencyCode: 'Currency'
      FloorDelta,
      IsWeekend,
      IsRunDay,
      IsLowPoint,
      LocalLastChangedAt,
      _Brief : redirected to parent ZC_CFO_BRIEF
}
