@EndUserText.label: 'CFO Brief - generate brief parameters'
define abstract entity ZD_CFO_GenParam
{
  @EndUserText.label: 'Company Code'
  CompanyCode : abap.char(4);
  @EndUserText.label: 'Brief Date (empty = today / demo anchor)'
  BriefDate   : abap.dats;
}
