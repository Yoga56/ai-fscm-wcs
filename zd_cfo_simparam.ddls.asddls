@EndUserText.label: 'CFO Brief - what-if toggles'
define abstract entity ZD_CFO_SimParam
{
  @EndUserText.label: 'Receivables assumed late (comma-separated item ids)'
  LateItems     : abap.char(1000);
  @EndUserText.label: 'Payables held to the next run (comma-separated item ids)'
  HeldItems     : abap.char(1000);
  @EndUserText.label: 'Receivables factored today (comma-separated item ids)'
  FactorItems   : abap.char(1000);
  @EndUserText.label: 'Shift this week''s run by n days'
  RunDelayDays  : abap.int4;
  @EndUserText.label: 'Liquidity floor override (0 = configured)'
  FloorOverride : abap.dec(23,2);
}
