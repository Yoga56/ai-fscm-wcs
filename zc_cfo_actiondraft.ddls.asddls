@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'CFO Daily Brief - Action draft'
@Metadata.allowExtensions: true
define view entity ZC_CFO_ACTIONDRAFT
  as projection on ZR_CFO_ACTIONDRAFT
{
  key ActionUuid,
      BriefUuid,
      ActionType,
      SourceKind,
      SourceUuid,
      Recipient,
      Subject,
      Body,
      InternalNote,
      Currency,
      @Semantics.amount.currencyCode: 'Currency'
      Amount,
      Status,
      StatusCriticality,
      Engine,
      RoutedTo,
      RoutedAt,
      DecidedBy,
      DecidedAt,
      DecisionNote,
      CreatedBy,
      CreatedAt,
      LastChangedBy,
      LastChangedAt,
      LocalLastChangedAt,
      _Brief : redirected to parent ZC_CFO_BRIEF
}
