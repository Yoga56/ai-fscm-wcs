@EndUserText.label: 'CFO Brief - what-if runway day'
define abstract entity ZD_CFO_SIMDAY
{
  DayIndex         : abap.int4;
  CalendarDate     : abap.dats;
  Currency         : abap.cuky;
  @Semantics.amount.currencyCode: 'Currency'
  Baseline         : abap.curr(23,2);
  @Semantics.amount.currencyCode: 'Currency'
  Scenario         : abap.curr(23,2);
  @Semantics.amount.currencyCode: 'Currency'
  Stressed         : abap.curr(23,2);
  @Semantics.amount.currencyCode: 'Currency'
  FloorAmount      : abap.curr(23,2);
  IsRunDay         : abap_boolean;
  IsLowPoint       : abap_boolean;
  @Semantics.amount.currencyCode: 'Currency'
  ScenarioLow      : abap.curr(23,2);
  ScenarioLowDay   : abap.int4;
  @Semantics.amount.currencyCode: 'Currency'
  StressedLow      : abap.curr(23,2);
  StressedLowDay   : abap.int4;
  ScenarioBreach   : abap_boolean;
  StressedBreach   : abap_boolean;
  Summary          : abap.char(255);
}
