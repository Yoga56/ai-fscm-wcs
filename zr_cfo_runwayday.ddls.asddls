@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'CFO Daily Brief - Runway day'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZR_CFO_RunwayDay
  as select from ztcfo_runway
  association to parent ZR_CFO_Brief as _Brief on $projection.BriefUuid = _Brief.BriefUuid
{
  key runway_uuid           as RunwayUuid,
      brief_uuid            as BriefUuid,
      day_index             as DayIndex,
      calendar_date         as CalendarDate,
      currency              as Currency,
      @Semantics.amount.currencyCode: 'Currency'
      inflow                as Inflow,
      @Semantics.amount.currencyCode: 'Currency'
      outflow               as Outflow,
      @Semantics.amount.currencyCode: 'Currency'
      closing_scheduled     as ClosingScheduled,
      @Semantics.amount.currencyCode: 'Currency'
      closing_stressed      as ClosingStressed,
      @Semantics.amount.currencyCode: 'Currency'
      closing_expected      as ClosingExpected,
      @Semantics.amount.currencyCode: 'Currency'
      floor_amount          as FloorAmount,
      @Semantics.amount.currencyCode: 'Currency'
      floor_delta           as FloorDelta,
      is_weekend            as IsWeekend,
      is_run_day            as IsRunDay,
      is_low_point          as IsLowPoint,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _Brief
}
